import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/timer_record.dart';
import 'package:wakey_alarm/presentation/providers/timers_provider.dart';

/// Full-screen countdown for a single timer.
///
/// Opened by tapping a tile in the [TimerScreen]. The big
/// time-remaining text pulses with a *heartbeat* — a quick
/// double-beat (lub-dub) followed by a longer rest — so the user can
/// feel the timer counting down even at a glance. The tile's
/// pause/resume/cancel controls are mirrored here as larger
/// primary actions; whichever surface the user is on, they can act
/// on the timer without going back to the list.
class TimerDetailScreen extends ConsumerStatefulWidget {
  const TimerDetailScreen({super.key, required this.timerId});

  final int timerId;

  @override
  ConsumerState<TimerDetailScreen> createState() => _TimerDetailScreenState();
}

class _TimerDetailScreenState extends ConsumerState<TimerDetailScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // The heartbeat loop: ~1.2s per cycle. The curve itself encodes
    // the lub-dub shape via a [TweenSequence] in [_HeartbeatText]
    // below; here we just keep the controller repeating forever.
    // We start it on the first build; subsequent rebuilds driven
    // by `ref.watch` (e.g. when the user pauses) flip a flag in
    // [_HeartbeatText] that swaps the ScaleTransition's animation
    // for a static pose, but we keep the controller running so a
    // resume returns to the pulse without an extra frame of
    // setup.
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // We pull the full list so the screen can show the current
    // record's label/state and pop automatically if the timer
    // disappears (cancelled, fired, dismissed from the ringing UI).
    final timersAsync = ref.watch(timersProvider);
    final liveRemaining = ref.watch(
      liveTimerRemainingForIdProvider(widget.timerId),
    );
    final timer = timersAsync.maybeWhen(
      data: (list) => list.where((t) => t.id == widget.timerId).firstOrNull,
      orElse: () => null,
    );

    // If the timer was cancelled or fired while this screen was
    // open, the row will be gone. Pop back to the list rather than
    // render an empty state.
    if (timer == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final remainingSeconds = liveRemaining ?? timer.remainingSeconds;
    final isRunning = timer.state == TimerState.running;

    return Scaffold(
      appBar: AppBar(
        title: Text(timer.label),
        actions: [
          if (timer.id != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete timer',
              onPressed: () async {
                await ref.read(timersProvider.notifier).cancel(timer.id!);
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 24),
              // State pill so the user knows whether the countdown
              // is live or frozen.
              _StatePill(state: timer.state),
              const SizedBox(height: 32),
              // The pulsing countdown inside a circular progress
              // ring. The ring's filled arc spans
              // `remaining / duration` of the circumference, so it
              // visibly depletes second by second in lockstep with
              // the digits (both are driven by the same live
              // remaining value). Only pulses while running — a
              // paused timer sits still so the frozen value is
              // unambiguous.
              Expanded(
                child: Center(
                  child: _CountdownRing(
                    remaining: remainingSeconds,
                    total: timer.durationSeconds,
                    color: isRunning
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    child: _HeartbeatText(
                      controller: _pulse,
                      enabled: isRunning,
                      text: _formatRemaining(remainingSeconds),
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: isRunning
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ActionButton(
                    icon: Icons.close,
                    label: 'Cancel',
                    color: theme.colorScheme.error,
                    onTap: () async {
                      if (timer.id == null) return;
                      await ref.read(timersProvider.notifier).cancel(timer.id!);
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
                  ),
                  _ActionButton(
                    icon: isRunning ? Icons.pause : Icons.play_arrow,
                    label: isRunning ? 'Pause' : 'Resume',
                    color: theme.colorScheme.primary,
                    onTap: () async {
                      if (timer.id == null) return;
                      final notifier = ref.read(timersProvider.notifier);
                      if (isRunning) {
                        await notifier.pause(timer.id!);
                      } else {
                        final ok = await notifier.resume(timer.id!);
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not resume the timer. Grant the '
                                '"Alarms & reminders" permission, then try again.',
                              ),
                              duration: Duration(seconds: 5),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatRemaining(int seconds) {
    if (seconds < 0) seconds = 0;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// The state pill shown above the countdown. Makes "running" vs
/// "paused" obvious at a glance.
class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});
  final TimerState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = switch (state) {
      TimerState.running => (
        'Running',
        theme.colorScheme.primary,
        Icons.fiber_manual_record,
      ),
      TimerState.paused => (
        'Paused',
        theme.colorScheme.tertiary,
        Icons.pause_circle_outline,
      ),
      _ => ('Done', theme.colorScheme.outline, Icons.check_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// A text widget that pulses with a *heartbeat* rhythm: a quick
/// lub, a slightly stronger dub, then a long rest. Implemented with
/// a [TweenSequence] of scale values, weighted so a single repeat
/// of the parent [AnimationController] covers one full heartbeat
/// cycle.
///
/// The visual is intentionally subtle — the digits are huge so a
/// 1.0 → 1.10 → 1.15 scale ramp is enough to read as a "beat" from
/// across the room without making the text unstable.
class _HeartbeatText extends StatelessWidget {
  const _HeartbeatText({
    required this.controller,
    required this.enabled,
    required this.text,
    required this.style,
  });

  final AnimationController controller;
  final bool enabled;
  final String text;
  final TextStyle? style;

  // A "heartbeat" is a quick double pulse followed by a long rest.
  // The weights below add up to 100 (one controller cycle = 1 beat).
  // Tuned to feel like lub-dub-rest on the eye.
  static final _tween = TweenSequence<double>(<TweenSequenceItem<double>>[
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.10,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 8,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.10,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 8,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.15,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 8,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.15,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 16,
    ),
    TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 60),
  ]);

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      // While paused, freeze the animation at the rest pose (1.0)
      // so the user sees a stable number. We do this by rewinding
      // the controller rather than skipping the ScaleTransition —
      // cheaper and avoids the widget tree rebuilding.
      scale: enabled
          ? _tween.animate(controller)
          : const AlwaysStoppedAnimation<double>(1.0),
      child: Text(text, style: style, textAlign: TextAlign.center),
    );
  }
}

/// A circular countdown ring with [child] (the digits) centered
/// inside it. The filled arc spans `remaining / total` of the
/// circumference — full at the start, empty when the timer reaches
/// zero — and redraws every second as the live remaining value
/// flips. For a paused timer the fraction is frozen, matching the
/// frozen digits.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.remaining,
    required this.total,
    required this.color,
    required this.child,
  });

  final int remaining;
  final int total;
  final Color color;
  final Widget child;

  static const double _strokeWidth = 10;

  @override
  Widget build(BuildContext context) {
    // Clamped to [0, 1] so a negative remaining (shouldn't happen,
    // but defensive) doesn't produce a NaN sweep angle.
    final fraction = total <= 0
        ? 0.0
        : (remaining / total).clamp(0.0, 1.0).toDouble();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit the biggest square the parent offers, capped so the
        // ring doesn't dominate a tablet screen.
        final side = math.min(
          constraints.maxWidth,
          math.min(constraints.maxHeight, 320.0),
        );
        return SizedBox(
          width: side,
          height: side,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _RingPainter(
                    fraction: fraction,
                    color: color,
                    strokeWidth: _strokeWidth,
                  ),
                ),
              ),
              // Inset the digits well past the stroke so the
              // heartbeat scale-up never clips the ring, and let
              // the FittedBox shrink long "H:MM:SS" values to fit.
              Padding(
                padding: const EdgeInsets.all(_strokeWidth * 2.5),
                child: FittedBox(fit: BoxFit.scaleDown, child: child),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Paints the ring track plus the filled arc for [fraction] of the
/// circumference, starting at 12 o'clock and sweeping clockwise.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.strokeWidth,
  });

  final double fraction;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withValues(alpha: 0.15);
    canvas.drawCircle(center, radius, trackPaint);
    if (fraction <= 0) return;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withValues(alpha: 0.10),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
