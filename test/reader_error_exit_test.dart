import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/pages/reader_page.dart';

/// A chapter that fails to load used to offer exactly one button. The reader
/// hides its system AppBar at zero height and keeps its back button in a top
/// bar that only the image viewport reveals on tap, so the error screen had no
/// way out: a source answering HTTP 410 meant killing the window.
void main() {
  Future<void> pumpError(
    WidgetTester tester, {
    required VoidCallback onRetry,
    required VoidCallback onBack,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderError(
            message: 'Bad state: invalid status code:410',
            onRetry: onRetry,
            onBack: onBack,
          ),
        ),
      ),
    );
  }

  testWidgets('the chapter error offers a way out besides retry', (
    tester,
  ) async {
    var retries = 0;
    var backs = 0;
    await pumpError(tester, onRetry: () => retries++, onBack: () => backs++);

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(backs, 1);
    expect(retries, 1);
  });

  testWidgets('both buttons stay reachable on a narrow screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(300, 420);
    addTearDown(tester.view.reset);

    await pumpError(tester, onRetry: () {}, onBack: () {});

    expect(tester.takeException(), isNull);
    for (final label in ['Retry', 'Back']) {
      expect(
        tester.getRect(find.text(label)),
        predicate<Rect>((rect) => rect.left >= 0 && rect.right <= 300),
        reason: '$label is off screen',
      );
    }
  });
}
