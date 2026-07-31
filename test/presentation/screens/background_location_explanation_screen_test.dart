import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/presentation/screens/background_location_explanation_screen.dart';

void main() {
  group('BackgroundLocationExplanationScreen', () {
    testWidgets('renders explanation text and action buttons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BackgroundLocationExplanationScreen(),
        ),
      );

      expect(
        find.text('Background location'),
        findsOneWidget,
      );
      expect(
        find.text('Wakey-Wakey needs background location'),
        findsOneWidget,
      );
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });

    testWidgets('body is scrollable and buttons are pinned at the bottom', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BackgroundLocationExplanationScreen(),
        ),
      );

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.byType(BottomAppBar), findsNothing);
      // The action buttons live inside the Scaffold's bottomNavigationBar.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.bottomNavigationBar, isA<SafeArea>());
    });

    testWidgets('tapping "Open Settings" pops with true', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        const BackgroundLocationExplanationScreen(),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('tapping "Not now" pops with false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        const BackgroundLocationExplanationScreen(),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });
}
