import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/timer_record.dart';
import 'package:wakey_alarm/presentation/providers/timers_provider.dart';

/// The Timer tab. Lists all active (RUNNING/PAUSED) timers and
/// offers a FAB to create a new one. Mirrors the layout of the
/// Alarms tab so users get a consistent mental model across the two
/// features.
class TimerScreen extends ConsumerWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timersAsync = ref.watch(timersProvider);
    final liveRemaining = ref.watch(liveTimerRemainingProvider);

    return Stack(
      children: [
        timersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load timers',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    // Show the error's `toString()` but cap its
                    // length to a single line so a multi-kilobyte
                    // stack trace doesn't blow up the layout in
                    // the 800x600 default test surface.
                    e.toString().split('\n').first,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          data: (timers) {
            if (timers.isEmpty) {
              return const _EmptyTimersView();
            }
            return _TimersList(timers: timers, liveRemaining: liveRemaining);
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CreateTimerScreen()),
              );
            },
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class _EmptyTimersView extends StatelessWidget {
  const _EmptyTimersView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('No timers yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to create your first timer',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TimersList extends ConsumerWidget {
  const _TimersList({required this.timers, required this.liveRemaining});

  final List<TimerRecord> timers;
  final int? liveRemaining;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show the actively-counting-down timer first. Subsequent timers
    // follow in insertion order. We only show one `liveRemaining`
    // per screen (the first active running timer); the rest are
    // rendered from their DB value.
    final sorted = [...timers];
    sorted.sort((a, b) {
      final aRunning = a.state == TimerState.running ? 0 : 1;
      final bRunning = b.state == TimerState.running ? 0 : 1;
      if (aRunning != bRunning) return aRunning - bRunning;
      return 0;
    });
    return ListView.builder(
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final t = sorted[index];
        return _TimerCard(
          timer: t,
          liveRemaining: index == 0 && t.state == TimerState.running
              ? liveRemaining
              : null,
        );
      },
    );
  }
}

class _TimerCard extends ConsumerWidget {
  const _TimerCard({required this.timer, required this.liveRemaining});

  final TimerRecord timer;
  final int? liveRemaining;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final remaining = liveRemaining ?? timer.remainingSeconds;
    final isRunning = timer.state == TimerState.running;
    return Dismissible(
      key: ValueKey(timer.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        if (timer.id != null) {
          ref.read(timersProvider.notifier).cancel(timer.id!);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Timer cancelled')));
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: ListTile(
          leading: Icon(
            isRunning ? Icons.timer : Icons.timer_off,
            color: isRunning
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            size: 32,
          ),
          title: Text(timer.label, style: theme.textTheme.titleMedium),
          subtitle: Text(_formatRemaining(remaining)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(isRunning ? Icons.pause : Icons.play_arrow),
                tooltip: isRunning ? 'Pause' : 'Resume',
                onPressed: () {
                  if (timer.id == null) return;
                  final notifier = ref.read(timersProvider.notifier);
                  if (isRunning) {
                    notifier.pause(timer.id!);
                  } else {
                    notifier.resume(timer.id!);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel',
                onPressed: () {
                  if (timer.id != null) {
                    ref.read(timersProvider.notifier).cancel(timer.id!);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRemaining(int seconds) {
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

/// Form for creating a new timer.
class CreateTimerScreen extends ConsumerStatefulWidget {
  const CreateTimerScreen({super.key});

  @override
  ConsumerState<CreateTimerScreen> createState() => _CreateTimerScreenState();
}

class _CreateTimerScreenState extends ConsumerState<CreateTimerScreen> {
  final _labelController = TextEditingController(text: 'Timer');
  int _hours = 0;
  int _minutes = 5;
  int _seconds = 0;
  bool _vibrate = true;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  int get _totalSeconds => _hours * 3600 + _minutes * 60 + _seconds;

  Future<void> _start() async {
    if (_totalSeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a duration greater than zero')),
      );
      return;
    }
    final notifier = ref.read(timersProvider.notifier);
    await notifier.create(
      label: _labelController.text.trim().isEmpty
          ? 'Timer'
          : _labelController.text.trim(),
      durationSeconds: _totalSeconds,
      vibrate: _vibrate,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Timer'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _start)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label
            Text(
              'LABEL',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _labelController,
              decoration: InputDecoration(
                hintText: 'e.g. Boil eggs',
                prefixIcon: const Icon(Icons.label_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Duration pickers
            Text(
              'DURATION',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DurationStepper(
                    label: 'Hours',
                    value: _hours,
                    min: 0,
                    max: 23,
                    onChanged: (v) => setState(() => _hours = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DurationStepper(
                    label: 'Minutes',
                    value: _minutes,
                    min: 0,
                    max: 59,
                    onChanged: (v) => setState(() => _minutes = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DurationStepper(
                    label: 'Seconds',
                    value: _seconds,
                    min: 0,
                    max: 59,
                    onChanged: (v) => setState(() => _seconds = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Vibrate toggle
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text('Vibrate'),
                value: _vibrate,
                onChanged: (v) => setState(() => _vibrate = v),
              ),
            ),
            const SizedBox(height: 32),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _start,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Start'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationStepper extends StatelessWidget {
  const _DurationStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 48,
              child: Text(
                value.toString().padLeft(2, '0'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}
