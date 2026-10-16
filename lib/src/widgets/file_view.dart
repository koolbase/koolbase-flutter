import 'package:flutter/material.dart';

import '../storage/files_controller.dart';
import '../storage/storage_client.dart';
import '../storage/storage_files.dart';
import 'load_error.dart';
import 'record_view.dart' show KoolbaseRecordStatus;

/// One file's details, by path, handed to [builder] (storage S4) -- a SCOPE,
/// not a screen: it adds no scrolling and no layout of its own, like
/// [KoolbaseRecordView]. Only a file the signed-in person may view is
/// shown; anything else is [notFound]. Loading, not found and error are
/// slotted. A change made through this SDK in the bucket shows by itself:
/// deleted or moved away, the file is [notFound]; replaced, its new size.
///
/// ```dart
/// KoolbaseFileView(
///   bucket: 'photos',
///   path: photoPath,
///   builder: (context, file) => Column(children: [
///     Text(file.name),
///     Text('${file.size} bytes'),
///   ]),
/// )
/// ```
///
/// A changed [bucket] or [path] starts a new load.
class KoolbaseFileView extends StatefulWidget {
  const KoolbaseFileView({
    super.key,
    required this.bucket,
    required this.path,
    required this.builder,
    this.loading,
    this.notFound,
    this.error,
    @visibleForTesting this.storage,
  });

  /// The bucket the file is in.
  final String bucket;

  /// The file's path. Null or empty shows [notFound] without a request.
  final String? path;

  /// Builds what shows the file. Appearance is entirely the caller's.
  final Widget Function(BuildContext context, KoolbaseFileInfo file) builder;

  /// Shown during the first load. Defaults to a centered spinner.
  final WidgetBuilder? loading;

  /// Shown when there is no file to show. Defaults to "Not available."
  final WidgetBuilder? notFound;

  /// Shown when the first load failed. Receives the error and a retry.
  final Widget Function(
      BuildContext context, Object error, Future<void> Function() retry)? error;

  /// Test seam only: the storage client to read from.
  final KoolbaseStorageClient? storage;

  @override
  State<KoolbaseFileView> createState() => _KoolbaseFileViewState();
}

class _KoolbaseFileViewState extends State<KoolbaseFileView> {
  late KoolbaseFileController _controller;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _controller = KoolbaseFileController(
      bucket: widget.bucket,
      path: widget.path ?? '',
      storage: widget.storage,
    )..addListener(_onChanged);
    _controller.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(KoolbaseFileView old) {
    super.didUpdateWidget(old);
    if (old.bucket != widget.bucket || old.path != widget.path) {
      _controller
        ..removeListener(_onChanged)
        ..dispose();
      _start();
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_controller.status) {
      case KoolbaseRecordStatus.loading:
        return widget.loading?.call(context) ??
            const Center(child: CircularProgressIndicator());
      case KoolbaseRecordStatus.notFound:
        return widget.notFound?.call(context) ?? const _NotAvailable();
      case KoolbaseRecordStatus.error:
        final err = _controller.error!;
        return widget.error?.call(context, err, _controller.refresh) ??
            KbLoadError(title: "Couldn't load this.", onRetry: _controller.refresh);
      case KoolbaseRecordStatus.loaded:
        return widget.builder(context, _controller.file!);
    }
  }
}

class _NotAvailable extends StatelessWidget {
  const _NotAvailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Not available.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
