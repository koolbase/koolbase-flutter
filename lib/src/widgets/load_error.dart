// The default view for a first load that failed: a list's, a grid's, a
// record's. Its Retry shows that it is working (#97). Before, tapping it
// changed nothing on screen -- no progress, and a retry that failed again
// looked exactly like one that never ran. Now the button turns into
// "Retrying…" (for at least a moment, so a retry that fails at once is still
// seen), and one that failed again says so.

import 'dart:async';

import 'package:flutter/material.dart';

/// How long "Retrying…" shows at the least. A retry that succeeds sooner
/// shows the records at once: only a failure waits for it.
const kRetryMinShown = Duration(milliseconds: 600);

/// Said under the title once a retry has failed.
const kRetryFailedAgain =
    "Still couldn't load. Check your connection, then try again.";

class KbLoadError extends StatefulWidget {
  const KbLoadError({super.key, required this.title, required this.onRetry});

  final String title;

  /// Never throws: the controllers' refresh keeps its own failures.
  final Future<void> Function() onRetry;

  @override
  State<KbLoadError> createState() => _KbLoadErrorState();
}

class _KbLoadErrorState extends State<KbLoadError> {
  bool _busy = false;
  int _failed = 0;
  Timer? _shown;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    final shown = Completer<void>();
    _shown = Timer(kRetryMinShown, shown.complete);
    await widget.onRetry();
    // A retry that worked replaces this view: nothing more to show.
    if (!mounted) return;
    await shown.future;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed++;
    });
  }

  @override
  void dispose() {
    _shown?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            if (_failed > 0) ...[
              const SizedBox(height: 4),
              Text(
                kRetryFailedAgain,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _busy ? null : _retry,
              child: _busy
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Retrying…'),
                      ],
                    )
                  : const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
