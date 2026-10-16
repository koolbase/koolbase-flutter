// A large file's upload, in parts (S3).
//
// Each part goes straight to storage on its own signed link, three at a time.
// A part that fails for a passing reason -- the network, storage busy -- is
// sent again, up to four times, waiting longer each time; one whose link has
// expired gets a new link. A failed upload is not abandoned: its id
// ([KoolbaseUploadTask.uploadId]) resumes it, sending only the parts that did
// not arrive. Cancelling abandons it.

import 'dart:math' as math;

import 'storage_exceptions.dart';
import 'storage_transfer.dart';

/// The server's plan for an upload in parts, and which parts arrived.
class KoolbaseMultipartPlan {
  final String uploadId;
  final String path;
  final int size;
  final int partSize;
  final int partCount;
  final String contentType;
  final Set<int> uploaded;

  const KoolbaseMultipartPlan({
    required this.uploadId,
    required this.path,
    required this.size,
    required this.partSize,
    required this.partCount,
    required this.contentType,
    this.uploaded = const {},
  });

  factory KoolbaseMultipartPlan.fromJson(Map<String, dynamic> j) => KoolbaseMultipartPlan(
        uploadId: j['upload_id'] as String,
        path: j['path'] as String? ?? '',
        size: (j['size'] as num).toInt(),
        partSize: (j['part_size'] as num).toInt(),
        partCount: (j['part_count'] as num).toInt(),
        contentType: j['content_type'] as String? ?? '',
        uploaded: {for (final n in (j['uploaded'] as List? ?? const [])) (n as num).toInt()},
      );
}

/// Parts in flight at once.
const koolbasePartsAtOnce = 3;

/// Tries per part.
const koolbasePartTries = 4;

/// How long to wait before try [n] (1-based) of a part. Tests shorten it.
Duration Function(int n) koolbasePartRetryDelay = (n) => Duration(milliseconds: 500 * (1 << (n - 1)));

bool _passing(int status) => status == 408 || status == 429 || status >= 500;

/// Sends the parts of [bytes] not yet in [plan.uploaded], reporting the bytes
/// of the whole file; completes once every part has arrived. [links] signs
/// links for the parts asked.
Future<void> koolbaseSendParts(
  KoolbaseUploadTaskControl step,
  KoolbaseMultipartPlan plan,
  List<int> bytes,
  Future<Map<int, String>> Function(List<int> parts) links,
) async {
  final sent = <int, int>{};
  (int, int) bounds(int n) => ((n - 1) * plan.partSize, math.min(n * plan.partSize, plan.size));
  for (final n in plan.uploaded) {
    final (a, b) = bounds(n);
    sent[n] = b - a;
  }
  void report() {
    if (step.cancelled) return;
    step.uploading(math.min(sent.values.fold<int>(0, (a, b) => a + b), plan.size));
  }

  report();
  final todo = [for (var n = 1; n <= plan.partCount; n++) if (!plan.uploaded.contains(n)) n];

  // Links, asked for a few at a time -- one request for parts in flight at
  // once, not one each -- and renewed when one has expired.
  final known = <int, String>{};
  final asking = <int, Future<void>>{};
  Future<void> ask(List<int> parts) {
    final f = links(parts).then((got) => known.addAll(got));
    for (final n in parts) {
      asking[n] = f;
    }
    return f.whenComplete(() {
      for (final n in parts) {
        if (identical(asking[n], f)) asking.remove(n);
      }
    });
  }

  Future<String> linkFor(int n, {bool fresh = false}) async {
    if (fresh) {
      known.remove(n);
      await ask([n]);
    } else if (!known.containsKey(n)) {
      final pending = asking[n];
      if (pending != null) {
        await pending;
      } else {
        final from = math.max(todo.indexOf(n), 0);
        await ask([
          for (final p in todo.skip(from).take(50))
            if (p == n || (!known.containsKey(p) && !asking.containsKey(p))) p,
        ]);
      }
    }
    final url = known[n];
    if (url == null) throw KoolbaseStorageException('No upload link for part $n');
    return url;
  }

  final client = step.openClient();
  // Set once the upload stops: the parts still going give up.
  var stopped = false;
  Future<void> sendOne(int n) async {
    final (a, b) = bounds(n);
    final body = bytes.sublist(a, b);
    var fresh = false;
    for (var attempt = 1;; attempt++) {
      step.checkCancelled();
      if (stopped) return;
      final url = await linkFor(n, fresh: fresh);
      fresh = false;
      step.checkCancelled();
      sent[n] = 0;
      report();
      int status = 0;
      Object? failure;
      try {
        status = await step.putPart(client, Uri.parse(url), body, (s) {
          sent[n] = s;
          report();
        }, timeout: Duration(seconds: 60 + body.length ~/ (32 * 1024)));
      } on KoolbaseUploadCancelledException {
        rethrow;
      } catch (e) {
        if (step.cancelled) throw const KoolbaseUploadCancelledException();
        failure = e;
      }
      if (failure == null && status >= 200 && status < 300) {
        sent[n] = b - a;
        report();
        return;
      }
      sent[n] = 0;
      report();
      final again = failure != null || _passing(status) || status == 403;
      if (!again || attempt >= koolbasePartTries) {
        if (failure is KoolbaseStorageException) throw failure;
        throw failure == null
            ? KoolbaseStorageException('Upload of part $n failed: $status', code: 'upload_failed')
            : KoolbaseStorageNetworkException(failure.toString());
      }
      if (status == 403) {
        fresh = true;
      } else {
        await Future<void>.delayed(koolbasePartRetryDelay(attempt));
      }
    }
  }

  try {
    var next = 0;
    Future<void> worker() async {
      while (!stopped && next < todo.length) {
        final n = todo[next++];
        await sendOne(n);
      }
    }

    await Future.wait(
      [for (var i = 0; i < math.min(koolbasePartsAtOnce, todo.length); i++) worker()],
      eagerError: true,
    );
  } finally {
    stopped = true;
    step.closeClient(client);
  }
}
