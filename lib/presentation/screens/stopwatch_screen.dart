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
/// * A large elapsed-time display at the top.
/// * A row of action buttons (Start/Pause, Reset, Lap) that swap
///   based on [StopwatchState.isRunning].
/// * A scrollable list of captured laps below. The list grows from
///   the top: lap 1 is at the bottom, the most recent lap is at the
///   top, matching what most sports stopwatches do. The list
///   auto-scrolls to keep the newest lap visible.
class StopwatchScreen extends ConsumerWidget {
  const StopwatchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stopwatchProvider);
    final notifier = ref.read(stopwatchProvider.notifier);

    return Column(
      children: [
        _StopwatchDisplay(elapsed: state.elapsed),
        _StopwatchControls(state: state, notifier: notifier),
        const _LapListDivider(),
        Expanded(child: _LapsList(state: state)),
      ],
    );
  }
}

class _StopwatchDisplay extends StatelessWidget {
  const _StopwatchDisplay({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use the with-hours formatter when we cross the hour mark so
    // the digits don't get scrunched; below an hour, the compact
    // MM:SS.hh form is easier to read at a glance.
    final showHours = elapsed.inHours >= 1;
    final text = showHours
        ? formatStopwatchWithHours(elapsed)
        : formatStopwatch(elapsed);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Text(
        text,
        style: theme.textTheme.displayLarge?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontWeight: FontWeight.w200,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
        child: Text(
          'No laps yet',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
        return _LapRow(lap: lap);
      },
    );
  }
}

class _LapRow extends StatelessWidget {
  const _LapRow({required this.lap});

  final StopwatchLap lap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Format both fields via the with-hours formatter so a 1h+ lap
    // doesn't truncate the minutes digit.
    final lapText = formatStopwatchWithHours(lap.lapTime);
    final totalText = formatStopwatchWithHours(lap.totalTime);
    return ListTile(
      leading: SizedBox(
        width: 40,
        child: Text(
          '#${lap.number}',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(lapText, style: theme.textTheme.titleMedium),
      trailing: Text(
        totalText,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
