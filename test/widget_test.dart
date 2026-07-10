import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/presentation/app.dart';

void main() {
  testWidgets('app shell renders primary tabs', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: WakeyAlarmApp()));

    expect(find.text('Alarms'), findsWidgets);
    expect(find.text('Stopwatch'), findsOneWidget);
    expect(find.text('Timer'), findsOneWidget);
    expect(find.text('No alarms yet'), findsOneWidget);

    await tester.tap(find.text('Timer'));
    await tester.pump();

    expect(find.text('No timers yet'), findsOneWidget);
  });
}
