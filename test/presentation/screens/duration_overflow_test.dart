import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/presentation/screens/timer_screen.dart';

/// Phone-shaped test surface (Pixel 8 physical pixels: 1080 x 2400,
/// dpr 2.625 → 411 x 914 logical). The previous implementation's
/// Duration row overflowed by 26dp on this width.
const _phonePhysical = Size(1080, 2400);
const _phoneDpr = 2.625;

void main() {
  testWidgets(
    'Add Timer Duration row does not overflow on Pixel-8-width surface',
    (tester) async {
      tester.view.physicalSize = _phonePhysical;
      tester.view.devicePixelRatio = _phoneDpr;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            // Render the production DurationStepper widget inside
            // a 3-column row inside the form's padding, to exactly
            // mirror the layout used by CreateTimerScreen on
            // device. No Riverpod or sqflite needed.
            body: _DurationRowPreview(),
          ),
        ),
      );
      await tester.pump();

      // If any RenderFlex overflowed, flutter_test reports it as
      // an exception. This expect() will fail before the others
      // run if the layout is still broken.
      expect(tester.takeException(), isNull);
      // Sanity: all three stepper labels should be present.
      expect(find.text('Hours'), findsOneWidget);
      expect(find.text('Minutes'), findsOneWidget);
      expect(find.text('Seconds'), findsOneWidget);
    },
  );
}

/// Mirrors the row-of-three-steppers used in `CreateTimerScreen.build`.
class _DurationRowPreview extends StatelessWidget {
  const _DurationRowPreview();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: const [
          Expanded(
            child: DurationStepper(
              label: 'Hours',
              value: 0,
              min: 0,
              max: 23,
              onChanged: _noop,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: DurationStepper(
              label: 'Minutes',
              value: 0,
              min: 0,
              max: 59,
              onChanged: _noop,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: DurationStepper(
              label: 'Seconds',
              value: 0,
              min: 0,
              max: 59,
              onChanged: _noop,
            ),
          ),
        ],
      ),
    );
  }
}

void _noop(int _) {}
