import 'package:flutter/material.dart';
import 'package:koolbase_flutter/koolbase_flutter.dart';

/// A collection rendered as a grid rather than a list.
///
/// Deliberately thin: [KoolbaseCollectionController] already owns fetching,
/// stale-while-revalidate and refresh, so this differs from
/// [KoolbaseCollectionList] only in how records are laid out. Sharing the
/// controller is what keeps the two from drifting on the hard parts.
class KoolbaseCollectionGrid extends StatefulWidget {
  const KoolbaseCollectionGrid({
    super.key,
    required this.collection,
    required this.itemBuilder,
    this.crossAxisCount = 2,
    this.spacing = 8,
    this.childAspectRatio = 1,
    this.query,
    this.empty,
    this.error,
    this.loading,
    this.padding,
    @visibleForTesting this.controller,
  });

  /// The collection to show.
  final String collection;

  /// Builds one record's tile. Appearance is entirely the caller's.
  final Widget Function(BuildContext context, KoolbaseRecord record)
      itemBuilder;

  /// Tiles across. Fixed rather than responsive — a caller who needs reflow
  /// can vary it from a LayoutBuilder.
  final int crossAxisCount;

  /// Gap between tiles, both directions.
  final double spacing;

  /// Tile width : height.
  final double childAspectRatio;

  /// Shapes each fresh query. Null lists the collection unfiltered.
  final KoolbaseQueryBuilder? query;

  /// Shown when the load succeeded and there are no records.
  final WidgetBuilder? empty;

  /// Shown when the FIRST load failed with nothing to show. Later refresh
  /// failures keep the records.
  final Widget Function(
      BuildContext context, Object error, Future<void> Function() retry)? error;

  /// Shown during the first load. Defaults to a centered spinner.
  final WidgetBuilder? loading;

  final EdgeInsetsGeometry? padding;

  /// Test seam only.
  final KoolbaseCollectionController? controller;

  @override
  State<KoolbaseCollectionGrid> createState() => _KoolbaseCollectionGridState();
}

class _KoolbaseCollectionGridState extends State<KoolbaseCollectionGrid> {
  late final KoolbaseCollectionController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        KoolbaseCollectionController(
          collection: widget.collection,
          queryBuilder: widget.query,
        );
    _controller.addListener(_onChanged);
    _controller.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    if (_ownsController) _controller.dispose();
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
            Center(child: Text('$err'));
      case KoolbaseListStatus.loaded:
        final records = _controller.records;
        if (records.isEmpty) {
          // Refreshable even when empty: the pull gesture needs something
          // scrollable over the empty slot.
          return RefreshIndicator(
            onRefresh: _controller.refresh,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: widget.empty?.call(context) ??
                      const Center(child: Text('Nothing here yet')),
                ),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _controller.refresh,
          child: GridView.builder(
            padding: widget.padding,
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: widget.crossAxisCount,
              mainAxisSpacing: widget.spacing,
              crossAxisSpacing: widget.spacing,
              childAspectRatio: widget.childAspectRatio,
            ),
            itemCount: records.length,
            itemBuilder: (context, i) =>
                widget.itemBuilder(context, records[i]),
          ),
        );
    }
  }
}
