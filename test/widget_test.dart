import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/presentation/app.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';

class MockAlarmsNotifier extends AlarmsNotifier {
  @override
  Future<List<Alarm>> build() async {
    return const [];
  }
}

void main() {
  testWidgets('app shell renders primary tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmsNotifierProvider.overrideWith(() => MockAlarmsNotifier()),
        ],
        child: const WakeyAlarmApp(),
      ),
    );

    expect(find.text('Alarms'), findsWidgets);
    expect(find.text('Stopwatch'), findsOneWidget);
    expect(find.text('Timer'), findsOneWidget);

    // AlarmsScreen shows empty state immediately as build completes sync/mocked
    await tester.pumpAndSettle();
    expect(
      find.text('No alarms yet'),
      findsOneWidget,
      reason: 'Alarms screen should display empty state',
    );

    await tester.tap(find.text('Timer'));
    await tester.pumpAndSettle();

    expect(find.text('No timers yet'), findsOneWidget);
  });
}



