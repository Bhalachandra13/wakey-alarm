import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/stopwatch.dart';
import 'package:wakey_alarm/presentation/providers/stopwatch_provider.dart';
import 'package:wakey_alarm/presentation/screens/stopwatch_screen.dart';

void main() {
  group('StopwatchScreen', () {
    testWidgets('renders 00:00.00 and a Start button when idle', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: StopwatchScreen())),
        ),
      );

      expect(find.text('00:00.00'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Lap'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);
      expect(find.text('No laps yet'), findsOneWidget);
    });

    testWidgets('tapping Start flips the primary button to Pause', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: StopwatchScreen())),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pump();

      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Start'), findsNothing);
    });

    testWidgets('tapping Lap on a running stopwatch adds a lap row', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: StopwatchScreen())),
        ),
      );

      // Start the stopwatch.
      await tester.tap(find.text('Start'));
      await tester.pump();
      // Tap Lap; the screen rebuilds to show a new lap row.
      await tester.tap(find.text('Lap'));
      await tester.pump();

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('No laps yet'), findsNothing);
    });

    testWidgets('tapping Reset clears the elapsed display and the lap list', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: StopwatchScreen())),
        ),
      );

      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.tap(find.text('Lap'));
      await tester.pump();
      expect(find.text('#1'), findsOneWidget);

      // Pause so Reset is the primary action; Reset is still
      // enabled while running too.
      await tester.tap(find.text('Pause'));
      await tester.pump();

      await tester.tap(find.text('Reset'));
      await tester.pump();

      expect(find.text('00:00.00'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('#1'), findsNothing);
      expect(find.text('No laps yet'), findsOneWidget);
    });

    testWidgets('Lap button is disabled when stopwatch is idle', (
      tester,
    ) async {
      // The CircleButton widget renders a disabled button as a
      // filled-grey circle with a desaturated icon. We can't read
      // the disabled color from the test environment easily, so we
      // assert on the *behavior*: tapping the disabled Lap button
      // does not add a lap row.
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: StopwatchScreen())),
        ),
      );

      // Try to tap Lap; should be a no-op.
      await tester.tap(find.text('Lap'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('#1'), findsNothing);
      expect(find.text('No laps yet'), findsOneWidget);
    });

    testWidgets('Reset button is disabled on a fresh stopwatch', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: StopwatchScreen())),
        ),
      );

      // Tapping Reset when idle does nothing.
      await tester.tap(find.text('Reset'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('00:00.00'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('Laps list shows most-recent lap at the top', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StopwatchScreen())),
        ),
      );

      // Record three laps directly through the notifier, no real
      // time elapses. This keeps the test deterministic.
      final notifier = container.read(stopwatchProvider.notifier);
      notifier.debugSetTickInterval(const Duration(milliseconds: 10));
      notifier.start();
      notifier.recordLap();
      notifier.recordLap();
      notifier.recordLap();
      notifier.pause();
      await tester.pump();

      final lapLabels = tester.widgetList<Text>(find.byType(Text));
      final lapTexts = lapLabels.map((w) => w.data ?? '').toList();
      final lap1Index = lapTexts.indexOf('#1');
      final lap2Index = lapTexts.indexOf('#2');
      final lap3Index = lapTexts.indexOf('#3');
      expect(lap1Index, isNonNegative);
      expect(lap2Index, isNonNegative);
      expect(lap3Index, isNonNegative);
      // The list is reversed: #3 is the most recent and should be
      // visually higher (smaller index) than #1.
      expect(lap3Index, lessThan(lap2Index));
      expect(lap2Index, lessThan(lap1Index));
    });

    testWidgets(
        'scales down a long elapsed display with a FittedBox to avoid overflow', (
      tester,
    ) async {
      final state = StopwatchState(
        elapsed: const Duration(
          hours: 12,
          minutes: 34,
          seconds: 56,
          milliseconds: 789,
        ),
        isRunning: false,
        laps: const [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stopwatchProvider.overrideWith(() => _FixedStopwatchNotifier(state)),
          ],
          child: const MaterialApp(home: Scaffold(body: StopwatchScreen())),
        ),
      );
      await tester.pumpAndSettle();

      final displayText = find.text('12:34:56.78');
      expect(displayText, findsOneWidget);
      expect(
        find.ancestor(of: displayText, matching: find.byType(FittedBox)),
        findsOneWidget,
        reason: 'Elapsed time should be wrapped in a FittedBox',
      );
    });
  });
}

class _FixedStopwatchNotifier extends StopwatchNotifier {
  _FixedStopwatchNotifier(this._state);
  final StopwatchState _state;

  @override
  StopwatchState build() => _state;
}
