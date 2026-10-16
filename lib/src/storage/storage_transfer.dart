// An upload's lifecycle, as an app watches it (S1).
//
// pending -> uploading (bytes sent of total) -> verifying -> completed, or
// failed / cancelled. Verifying is its own phase: the bytes have arrived and
// the server is checking them (size, type, the bucket's rules and cap) and
// putting them in place. Only completed means the file can be referenced
// from a record.

import 'dart:async';

import 'package:http/http.dart' as http;

import '../koolbase_exception.dart';
import 'storage_exceptions.dart';
import 'storage_models.dart';

/// Where an upload is.
enum KoolbaseUploadState {
  /// Not started: asking the server for an upload link.
  pending,

  /// Sending the file's bytes; see [KoolbaseUploadProgress.bytesSent].
  uploading,

  /// The bytes have arrived; the server is checking them and putting the
  /// file in place. It can no longer be cancelled.
  verifying,

  /// Done: the file is in the bucket.
  completed,

  /// It failed; [KoolbaseUploadProgress.error] says why.
  failed,

  /// Cancelled before the server began checking it. Nothing was stored.
  cancelled,
}

/// One moment of an upload.
class KoolbaseUploadProgress {
  final KoolbaseUploadState state;

  /// Bytes sent so far. On the web the browser sends the file in one piece,
  /// so this jumps from 0 to [bytesTotal] there.
  final int bytesSent;
  final int bytesTotal;

  /// Why it failed, when [state] is [KoolbaseUploadState.failed].
  final KoolbaseException? error;

  const KoolbaseUploadProgress({
    required this.state,
    required this.bytesSent,
    required this.bytesTotal,
    this.error,
  });

  /// 0.0 to 1.0: the share of bytes sent; 1.0 once verifying.
  double get fraction {
    if (state == KoolbaseUploadState.verifying || state == KoolbaseUploadState.completed) return 1;
    if (bytesTotal <= 0) return 0;
    return (bytesSent / bytesTotal).clamp(0, 1).toDouble();
  }

  /// Whether the upload has ended, one way or another.
  bool get isDone =>
      state == KoolbaseUploadState.completed ||
      state == KoolbaseUploadState.failed ||
      state == KoolbaseUploadState.cancelled;

  @override
  String toString() => 'KoolbaseUploadProgress(${state.name}, $bytesSent/$bytesTotal)';
}

/// A running upload: watch [progress], [cancel] it, await [result].
class KoolbaseUploadTask {
  KoolbaseUploadTask._(this._total) {
    _current = KoolbaseUploadProgress(state: KoolbaseUploadState.pending, bytesSent: 0, bytesTotal: _total);
    // An app that only follows progress is not left with an unhandled
    // error; awaiting [result] still sees it.
    _done.future.then((_) {}, onError: (Object _) {});
  }

  final int _total;
  final _controller = StreamController<KoolbaseUploadProgress>.broadcast(sync: true);
  final _done = Completer<UploadResult>();
  late KoolbaseUploadProgress _current;
  bool _cancelRequested = false;
  http.Client? _transfer;

  /// Every change of state and every chunk sent, as it happens.
  Stream<KoolbaseUploadProgress> get progress => _controller.stream;

  /// Where the upload is now.
  KoolbaseUploadProgress get current => _current;

  /// The uploaded file. Throws [KoolbaseUploadCancelledException] if it was
  /// cancelled, or the error that made it fail.
  Future<UploadResult> get result => _done.future;

  /// Stops the upload, if the server has not begun checking it yet. Returns
  /// whether it was stopped: false once verifying (the file will land, or
  /// fail on its own) or done.
  bool cancel() {
    if (_current.isDone || _current.state == KoolbaseUploadState.verifying) return false;
    _cancelRequested = true;
    _transfer?.close();
    return true;
  }

  bool get _cancelled => _cancelRequested;

  void _emit(KoolbaseUploadState state, {int? sent, KoolbaseException? error}) {
    if (_current.isDone) return;
    _current = KoolbaseUploadProgress(
      state: state,
      bytesSent: sent ?? _current.bytesSent,
      bytesTotal: _total,
      error: error,
    );
    if (!_controller.isClosed) _controller.add(_current);
  }

  void _finish(UploadResult result) {
    _emit(KoolbaseUploadState.completed, sent: _total);
    _done.complete(result);
    _controller.close();
  }

  void _fail(Object error, StackTrace stack) {
    if (_cancelRequested) {
      _emit(KoolbaseUploadState.cancelled);
      _done.completeError(const KoolbaseUploadCancelledException(), stack);
    } else {
      final e = error is KoolbaseException ? error : KoolbaseStorageNetworkException(error.toString());
      _emit(KoolbaseUploadState.failed, error: e);
      _done.completeError(e, stack);
    }
    _controller.close();
  }
}

/// Runs [body] as [task]'s upload: its steps report through [step].
KoolbaseUploadTask runUploadTask(
  int total,
  Future<UploadResult> Function(KoolbaseUploadTaskControl step) body,
) {
  final task = KoolbaseUploadTask._(total);
  // Started on the next turn, so a caller can listen to every event.
  scheduleMicrotask(() async {
    try {
      final result = await body(KoolbaseUploadTaskControl._(task));
      task._finish(result);
    } catch (e, st) {
      task._fail(e, st);
    }
  });
  return task;
}

/// What an upload's steps report through, and how they learn of a cancel.
class KoolbaseUploadTaskControl {
  KoolbaseUploadTaskControl._(this._task);
  final KoolbaseUploadTask _task;

  /// Throws if the upload was cancelled, between steps.
  void checkCancelled() {
    if (_task._cancelled) throw const KoolbaseUploadCancelledException();
  }

  void uploading(int sent) => _task._emit(KoolbaseUploadState.uploading, sent: sent);

  /// Marks the bytes sent: from here the upload cannot be cancelled.
  void verifying() {
    checkCancelled();
    _task._emit(KoolbaseUploadState.verifying, sent: _task._total);
  }

  /// Sends [bytes] to a presigned [url] with PUT, reporting each chunk as
  /// it is taken; a cancel aborts it. Returns the response, read in full
  /// before the connection is let go.
  /// A transfer still going after [timeout] is stopped.
  Future<http.Response> put(Uri url, List<int> bytes, String contentType, {required Duration timeout}) async {
    checkCancelled();
    final client = http.Client();
    _task._transfer = client;
    try {
      final req = _ProgressRequest(url, bytes, (sent) {
        if (!_task._cancelled) uploading(sent);
      }, () => _task._cancelled)
        ..headers['Content-Type'] = contentType;
      final res = await client.send(req).timeout(timeout, onTimeout: () {
        client.close();
        throw const KoolbaseStorageNetworkException('The upload took too long and was stopped');
      });
      final full = await http.Response.fromStream(res);
      checkCancelled();
      return full;
    } finally {
      _task._transfer = null;
      client.close();
    }
  }
}

/// A PUT whose body is handed over a chunk at a time, as the connection
/// takes it, so the bytes sent can be reported.
class _ProgressRequest extends http.BaseRequest {
  _ProgressRequest(Uri url, this._bytes, this._onSent, this._stopped) : super('PUT', url) {
    contentLength = _bytes.length;
  }

  static const _chunk = 64 * 1024;
  final List<int> _bytes;
  final void Function(int sent) _onSent;
  final bool Function() _stopped;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_chunks());
  }

  Stream<List<int>> _chunks() async* {
    var sent = 0;
    _onSent(0);
    while (sent < _bytes.length) {
      if (_stopped()) throw const KoolbaseUploadCancelledException();
      final end = (sent + _chunk) < _bytes.length ? sent + _chunk : _bytes.length;
      yield _bytes.sublist(sent, end);
      sent = end;
      _onSent(sent);
    }
  }
}
