import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/stopwatch.dart';
import 'package:wakey_alarm/presentation/providers/stopwatch_provider.dart';
import 'package:wakey_alarm/presentation/utils/stopwatch_format.dart';

/// The Stopwatch tab in the bottom-nav.
///
/// Pure in-memory, no native side, no persistence. See
/// `requirements.md` §5.3 and `workflow_plan.md` Iteration 2.
///
/// Layout:
/// * A large animated elapsed-time display wrapped in a progress
///   ring at the top. The ring sweeps around as the stopwatch
///   runs (one full revolution per minute) and the display
///   changes color/weight depending on state, so the user has a
///   strong visual cue that time is moving.
/// * A row of action buttons (Start/Pause, Reset, Lap) that swap
///   based on [StopwatchState.isRunning].
/// * A scrollable list of captured laps below. The list grows from
///   the top: lap 1 is at the bottom, the most recent lap is at
///   the top, matching what most sports stopwatches do.
class StopwatchScreen extends ConsumerWidget {
  const StopwatchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stopwatchProvider);
    final notifier = ref.read(stopwatchProvider.notifier);

    return Column(
      children: [
        _StopwatchDisplay(state: state),
        _StopwatchControls(state: state, notifier: notifier),
        const _LapListDivider(),
        Expanded(child: _LapsList(state: state)),
      ],
    );
  }
}

/// Visual container for the elapsed time. The display is wrapped in
/// a circular progress ring that:
///   * shows fractional progress through the current minute (or
///     hour, once we cross 1h) so the user has a peripheral cue
///     that time is moving even when they aren't reading the
///     digits;
///   * gently pulses (scale + opacity) when running, freezes when
///     paused, and is muted when idle;
///   * changes color depending on state (primary when running,
///     tertiary when paused, outline when idle).
///
/// We keep the actual elapsed text in a [FittedBox] so long
/// durations (multi-hour) don't overflow; the ring stays a
/// constant size regardless of text length.
class _StopwatchDisplay extends StatelessWidget {
  const _StopwatchDisplay({required this.state});

  final StopwatchState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use the with-hours formatter when we cross the hour mark so
    // the digits don't get scrunched; below an hour, the compact
    // MM:SS.hh form is easier to read at a glance.
    final showHours = state.elapsed.inHours >= 1;
    final text = showHours
        ? formatStopwatchWithHours(state.elapsed)
        : formatStopwatch(state.elapsed);

    // Sub-second progress: tick interval is 50 ms, so the ring
    // animates smoothly. Fraction is 0..1 across the current
    // sub-minute (or sub-hour, once past 1 h).
    final fraction = _fractionOfCurrentUnit(state.elapsed, showHours);

    // Color by state — strong color when running, accent on pause,
    // subtle on idle.
    final accent = _accentForState(theme.colorScheme, state);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Cap the ring at 240x240 so it doesn't dominate the
          // screen on small surfaces (e.g. 800x600 test viewports),
          // but let it grow up to 280 on a real phone width.
          final maxDim = constraints.maxWidth < 240
              ? constraints.maxWidth
              : (constraints.maxWidth < 320 ? 240.0 : 280.0);
          return Center(
            child: SizedBox(
              width: maxDim,
              height: maxDim,
              child: _PulsingRing(
                isPulsing: state.isRunning,
                child: _StopwatchRing(
                  fraction: fraction,
                  accent: accent,
                  trackColor: theme.colorScheme.surfaceContainerHighest,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              text,
                              maxLines: 1,
                              style: theme.textTheme.displayMedium?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                fontWeight: state.isRunning
                                    ? FontWeight.w300
                                    : FontWeight.w200,
                                color: state.isIdle
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _StatusLabel(state: state),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _accentForState(ColorScheme scheme, StopwatchState state) {
    if (state.isRunning) return scheme.primary;
    if (state.elapsed > Duration.zero) return scheme.tertiary;
    return scheme.outline;
  }

  /// Fraction (0..1) of the current time unit that has elapsed.
  /// For the MM:SS.hh view (under an hour) we wrap the ring every
  /// minute; for the with-hours view we wrap every hour. Wrapping
  /// at sub-unit cadence is what makes the ring feel like it's
  /// "ticking" in time with the stopwatch.
  double _fractionOfCurrentUnit(Duration elapsed, bool showHours) {
    final inUnit = showHours
        ? elapsed.inMinutes % 60
        : elapsed.inSeconds % 60;
    final unitMillis = showHours ? 60 * 1000 : 1000;
    final modMillis = elapsed.inMilliseconds % unitMillis;
    return modMillis / unitMillis + inUnit / 60.0;
  }
}

/// Small status label that sits under the elapsed time. Tells the
/// user at a glance whether the stopwatch is running, paused, or
/// ready to start — useful when the digit color alone is hard to
/// interpret (e.g. for colorblind users).
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.state});

  final StopwatchState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = switch (state) {
      _ when state.isRunning => (
          'RUNNING',
          theme.colorScheme.primary,
          Icons.fiber_manual_record,
        ),
      _ when state.elapsed > Duration.zero => (
          'PAUSED',
          theme.colorScheme.tertiary,
          Icons.pause_circle_outline,
        ),
      _ => ('READY', theme.colorScheme.onSurfaceVariant, Icons.timer_outlined),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

/// Subtle pulse animation: a 1.5 s ease-in-out cycle that scales
/// the child between 0.98 and 1.02 and dips the inner brightness.
/// Only animates while [isPulsing] is true; otherwise the child
/// renders at scale 1.0 with no animation (so a paused/idle
/// stopwatch is visually still).
class _PulsingRing extends StatefulWidget {
  const _PulsingRing({required this.isPulsing, required this.child});

  final bool isPulsing;
  final Widget child;

  @override
  State<_PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<_PulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _PulsingRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing != oldWidget.isPulsing) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.isPulsing) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // 0..1 -> -0.02..+0.02 around 1.0
        final scale = 1.0 + (t - 0.5) * 0.04;
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}

/// The circular progress ring + content. Uses [CustomPaint] so we
/// can:
///   * animate the ring smoothly via the [fraction] rebuild (driven
///     by the same 50 ms ticker that updates the elapsed time);
///   * add a soft outer "halo" stroke when the stopwatch is
///     running, which is what gives the screen its dynamic feel;
///   * keep the layout cheap (one CustomPaint, no extra layers).
class _StopwatchRing extends StatelessWidget {
  const _StopwatchRing({
    required this.fraction,
    required this.accent,
    required this.trackColor,
    required this.child,
  });

  final double fraction;
  final Color accent;
  final Color trackColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingPainter(
        fraction: fraction.clamp(0.0, 1.0),
        accent: accent,
        trackColor: trackColor,
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: child,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.accent,
    required this.trackColor,
  });

  final double fraction;
  final Color accent;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final strokeWidth = 6.0;

    // Track (faint full circle).
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Outer halo: a softer, wider stroke under the main progress
    // arc, only when there is some progress to show. Gives the
    // running stopwatch a "lit-up" feel.
    if (fraction > 0) {
      final haloPaint = Paint()
        ..color = accent.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      final haloRect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        haloRect,
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
        haloPaint,
      );
    }

    // Progress arc.
    if (fraction > 0) {
      final progressPaint = Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * fraction,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) {
    return old.fraction != fraction ||
        old.accent != accent ||
        old.trackColor != trackColor;
  }
}

class _StopwatchControls extends StatelessWidget {
  const _StopwatchControls({required this.state, required this.notifier});

  final StopwatchState state;
  final StopwatchNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Three control slots: [primary action][secondary action][tertiary]
    // — primary is Start/Resume or Pause; secondary is Lap (only when
    // running) or invisible when idle/paused; tertiary is Reset
    // (only when the elapsed time or lap list is non-empty).
    final canLap = state.isRunning;
    final canReset = !state.isIdle || state.laps.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CircleButton(
            label: state.isRunning ? 'Pause' : 'Start',
            icon: state.isRunning ? Icons.pause : Icons.play_arrow,
            color: state.isRunning
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
            onPressed: () {
              if (state.isRunning) {
                notifier.pause();
              } else {
                notifier.start();
              }
            },
          ),
          _CircleButton(
            label: 'Lap',
            icon: Icons.flag,
            color: theme.colorScheme.tertiary,
            onPressed: canLap ? notifier.recordLap : null,
          ),
          _CircleButton(
            label: 'Reset',
            icon: Icons.refresh,
            color: theme.colorScheme.secondary,
            onPressed: canReset ? notifier.reset : null,
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onPressed == null;
    // The InkWell wraps the entire button (icon + label) so taps
    // anywhere in the button — including the label text below the
    // round icon — trigger [onPressed]. Tapping just the Icon via a
    // 64x64 hit target would force the user to be precise; tapping
    // the label is a natural fallback for stock-clock stopwatches.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Material(
                  color: disabled
                      ? theme.colorScheme.surfaceContainerHighest
                      : color,
                  shape: const CircleBorder(),
                  child: Icon(
                    icon,
                    size: 32,
                    color: disabled
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: disabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LapListDivider extends StatelessWidget {
  const _LapListDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'LAPS',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LapsList extends StatelessWidget {
  const _LapsList({required this.state});

  final StopwatchState state;

  @override
  Widget build(BuildContext context) {
    if (state.laps.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.flag_outlined,
              size: 32,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              'No laps yet',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap the flag while running to record a split',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    // Reverse so the newest lap is at the top, like a sports
    // stopwatch. Build a local reversed list (cheap — typical lap
    // counts are < 100).
    final ordered = state.laps.reversed.toList(growable: false);
    return ListView.separated(
      itemCount: ordered.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final lap = ordered[index];
        // Highlight the most recent lap (first in the reversed
        // list) — gives an immediate "you just lapped" feedback.
        final isLatest = index == 0;
        return _LapRow(lap: lap, highlight: isLatest);
      },
    );
  }
}

class _LapRow extends StatelessWidget {
  const _LapRow({required this.lap, required this.highlight});

  final StopwatchLap lap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Format both fields via the with-hours formatter so a 1h+ lap
    // doesn't truncate the minutes digit.
    final lapText = formatStopwatchWithHours(lap.lapTime);
    final totalText = formatStopwatchWithHours(lap.totalTime);
    return Container(
      color: highlight
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
          : null,
      child: ListTile(
        dense: true,
        leading: SizedBox(
          width: 40,
          child: Text(
            '#${lap.number}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: highlight
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withValues(alpha: 0.7),
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
        title: Text(
          lapText,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        trailing: Text(
          totalText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
