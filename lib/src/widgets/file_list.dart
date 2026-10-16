import 'package:flutter/material.dart';

import '../storage/files_controller.dart';
import '../storage/storage_files.dart';
import 'collection_list.dart' show KoolbaseListStatus;
import 'load_error.dart';

/// A bucket's files as a list (storage S4): only the files the signed-in
/// person may view, a page at a time, with pull to refresh and Load more.
/// It reloads by itself after an upload, delete, move, copy, metadata
/// change or restore made through this SDK in the bucket.
///
/// The same shape as [KoolbaseCollectionList]: a [ListView.separated]
/// inside a [RefreshIndicator], the rows entirely yours via [itemBuilder],
/// and loading, empty and error slotted. The data half is
/// [KoolbaseFilesController].
///
/// ```dart
/// KoolbaseFileList(
///   bucket: 'photos',
///   prefix: 'trips/',
///   sort: KoolbaseFileSort.createdAt,
///   descending: true,
///   itemBuilder: (context, file) => ListTile(title: Text(file.name)),
/// )
/// ```
class KoolbaseFileList extends StatefulWidget {
  const KoolbaseFileList({
    super.key,
    required this.bucket,
    required this.itemBuilder,
    this.prefix,
    this.sort = KoolbaseFileSort.path,
    this.descending = false,
    this.limit,
    this.empty,
    this.error,
    this.loading,
    this.separatorBuilder,
    this.padding,
    this.scrollsWithPage = false,
    @visibleForTesting this.controller,
  });

  /// The bucket to list.
  final String bucket;

  /// Only files whose path starts with this, taken literally.
  final String? prefix;

  /// The order, and which way.
  final KoolbaseFileSort sort;
  final bool descending;

  /// Files per page: 50 unless set, at most 100.
  final int? limit;

  /// One file's row.
  final Widget Function(BuildContext context, KoolbaseFileInfo file)
      itemBuilder;

  /// Shown when the bucket has no files you may view. Defaults to
  /// "Nothing here yet."
  final WidgetBuilder? empty;

  /// Shown when the first load fails, with the error and a retry. Defaults
  /// to [KbLoadError].
  final Widget Function(
    BuildContext context,
    Object error,
    Future<void> Function() retry,
  )? error;

  /// Shown during the first load. Defaults to a spinner.
  final WidgetBuilder? loading;

  final IndexedWidgetBuilder? separatorBuilder;
  final EdgeInsetsGeometry? padding;

  /// Inside a page that scrolls: the rows lay out at their own height, the
  /// page scrolls and refreshes, and Load more is a button.
  final bool scrollsWithPage;

  /// Test seam: a controller the test owns.
  final KoolbaseFilesController? controller;

  @override
  State<KoolbaseFileList> createState() => _KoolbaseFileListState();
}

class _KoolbaseFileListState extends State<KoolbaseFileList> {
  late KoolbaseFilesController _controller;
  late bool _owns;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _owns = widget.controller == null;
    _controller = widget.controller ??
        KoolbaseFilesController(
          bucket: widget.bucket,
          prefix: widget.prefix,
          sort: widget.sort,
          descending: widget.descending,
          limit: widget.limit,
        );
    _controller.addListener(_changed);
    _controller.load();
  }

  void _stop() {
    _controller.removeListener(_changed);
    if (_owns) _controller.dispose();
  }

  @override
  void didUpdateWidget(KoolbaseFileList old) {
    super.didUpdateWidget(old);
    // Another listing: start afresh, never showing the previous one's files.
    if (old.bucket != widget.bucket ||
        old.prefix != widget.prefix ||
        old.sort != widget.sort ||
        old.descending != widget.descending ||
        old.limit != widget.limit ||
        old.controller != widget.controller) {
      _stop();
      _start();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_controller.status) {
      case KoolbaseListStatus.loading:
        return widget.loading?.call(context) ??
            const Center(child: CircularProgressIndicator());
      case KoolbaseListStatus.error:
        final err = _controller.error!;
        return widget.error?.call(context, err, _controller.refresh) ??
            KbLoadError(
              title: "Couldn't load these files.",
              onRetry: _controller.refresh,
            );
      case KoolbaseListStatus.loaded:
        final files = _controller.files;
        if (files.isEmpty) {
          if (widget.scrollsWithPage) {
            return widget.empty?.call(context) ?? const _NothingYet();
          }
          // Refreshable even when empty; the empty slot fills the height
          // only when there is one to fill.
          return RefreshIndicator(
            onRefresh: _controller.refresh,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight.isFinite
                        ? constraints.maxHeight
                        : 0,
                  ),
                  child: widget.empty?.call(context) ?? const _NothingYet(),
                ),
              ),
            ),
          );
        }
        final list = ListView.separated(
          shrinkWrap: widget.scrollsWithPage,
          physics: widget.scrollsWithPage
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          padding: widget.padding,
          // One more row while there is more to load: the control that
          // says so.
          itemCount: files.length + (_controller.hasMore ? 1 : 0),
          separatorBuilder:
              widget.separatorBuilder ?? (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == files.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: _controller.loadingMore
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: _controller.loadMore,
                          child: const Text('Load more'),
                        ),
                ),
              );
            }
            return widget.itemBuilder(context, files[index]);
          },
        );
        if (widget.scrollsWithPage) return list;
        return RefreshIndicator(onRefresh: _controller.refresh, child: list);
    }
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nothing here yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
}
