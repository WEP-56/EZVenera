import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/shell/main_shell.dart';

void main() {
  testWidgets('app shell renders main destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MainShell()));

    expect(find.text('Search'), findsWidgets);
    expect(find.text('Category'), findsWidgets);
    expect(find.text('Local'), findsWidgets);
    expect(find.text('Sources'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
  });
}
