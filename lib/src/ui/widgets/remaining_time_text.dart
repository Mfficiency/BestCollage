import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart' show RemainingTime;

/// A small "00:01:23 remaining" line for work that takes a while, shown below
/// its progress. Only for work that looks like taking more than 30 s in all
/// (and not in its first 3 s), and never while there is nothing to go on (no
/// [done] fraction and no [typical] duration). Refreshes every second
/// so the countdown moves even when the progress doesn't.
///
/// [eta] must already be started; the widget only reads it.
class RemainingTimeText extends StatefulWidget {
  const RemainingTimeText({
    super.key,
    required this.eta,
    this.done,
    this.typical,
    this.prefix,
    this.style,
    this.textAlign = TextAlign.center,
  });

  final RemainingTime eta;

  /// How far the work is, 0..1; null when it can't say.
  final double? done;

  /// How long the same work usually takes (e.g. last time), counted down
  /// when there is no [done].
  final Duration? typical;

  /// Put in front of the time, e.g. "Saving · ".
  final String? prefix;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  State<RemainingTimeText> createState() => _RemainingTimeTextState();
}

class _RemainingTimeTextState extends State<RemainingTimeText> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.eta.label(widget.done, typical: widget.typical);
    if (label == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        '${widget.prefix ?? ''}$label',
        key: const Key('remaining_time'),
        textAlign: widget.textAlign,
        style: widget.style ??
            theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
