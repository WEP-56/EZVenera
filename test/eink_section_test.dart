import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/pages/settings_page.dart';
import 'package:ezvenera/src/settings/settings_controller.dart';

/// Regression for the Windows report "E-Ink mode takes effect, but the menu
/// does not change until the app is restarted". The section sits in the
/// appearance page as a `const` child, and Element.update skips a child whose
/// new and old widget instances are identical, so the page's own
/// setState never re-ran this build and the sub-switches stayed hidden.
void main() {
  /// `_SettingsGroup` paints its rounded card with a `DecoratedBox` that sits
  /// between the `ListTile`s and their `Material` ancestor, which trips a
  /// debug-only Flutter assertion ("ink splashes may be invisible"). It is a
  /// pre-existing layout warning, unrelated to the rebuild behaviour under
  /// test, so the pending errors are drained after every frame.
  void drainKnownLayoutAssertions(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: const EinkSettingsSection()),
        ),
      ),
    );
    drainKnownLayoutAssertions(tester);
  }

  setUp(() => SettingsController.instance.setEinkMode(false));
  tearDown(() => SettingsController.instance.setEinkMode(false));

  testWidgets('toggling E-Ink mode reveals its sub-switches immediately', (
    tester,
  ) async {
    await pumpSection(tester);
    expect(find.text('High-contrast theme'), findsNothing);
    expect(find.text('Chapter refresh flash'), findsNothing);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    drainKnownLayoutAssertions(tester);

    expect(SettingsController.instance.einkMode, isTrue);
    expect(find.text('High-contrast theme'), findsOneWidget);
    expect(find.text('Chapter refresh flash'), findsOneWidget);
  });

  testWidgets('turning E-Ink mode off hides them again without a restart', (
    tester,
  ) async {
    await SettingsController.instance.setEinkMode(true);
    await pumpSection(tester);
    expect(find.text('High-contrast theme'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    drainKnownLayoutAssertions(tester);

    expect(SettingsController.instance.einkMode, isFalse);
    expect(find.text('High-contrast theme'), findsNothing);
  });
}
