import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:ezvenera/src/lifecycle/app_shutdown.dart';

/// Covers the teardown ordering guarantees that keep the Windows process from
/// being killed while native subsystems still hold live work (fast-fail
/// 0xC0000409 on exit).
void main() {
  ShutdownStep step(String name, Future<void> Function() body) {
    return ShutdownStep(name: name, run: body);
  }

  test('steps run in registration order', () async {
    final order = <String>[];
    final shutdown = AppShutdown(
      steps: [
        step('a', () async => order.add('a')),
        step('b', () async => order.add('b')),
        step('c', () async => order.add('c')),
      ],
    );

    final results = await shutdown.run();

    expect(order, ['a', 'b', 'c']);
    expect(results.map((result) => result.name), ['a', 'b', 'c']);
    expect(results.every((result) => result.isClean), isTrue);
  });

  test('a throwing step does not stop the later steps', () async {
    var reachedLast = false;
    final shutdown = AppShutdown(
      steps: [
        step('boom', () async => throw StateError('native handle busy')),
        step('last', () async => reachedLast = true),
      ],
    );

    final results = await shutdown.run();

    expect(reachedLast, isTrue);
    expect(results.first.error, isA<StateError>());
    expect(results.last.isClean, isTrue);
  });

  test('a hung step is given up on after the step timeout', () async {
    var reachedLast = false;
    final never = Completer<void>();
    final shutdown = AppShutdown(
      stepTimeout: const Duration(milliseconds: 30),
      steps: [
        step('hangs', () => never.future),
        step('last', () async => reachedLast = true),
      ],
    );

    final results = await shutdown.run();

    expect(reachedLast, isTrue);
    expect(results.first.timedOut, isTrue);
    expect(results.first.isClean, isFalse);
  });

  test('run() performs the teardown once and is safe to await twice', () async {
    var runs = 0;
    final shutdown = AppShutdown(steps: [step('count', () async => runs++)]);

    final first = shutdown.run();
    final second = shutdown.run();
    await Future.wait([first, second]);

    expect(runs, 1);
    expect(shutdown.hasRun, isTrue);
  });

  test('reports each result through the progress callback', () async {
    final reported = <String>[];
    final shutdown = AppShutdown(
      steps: [
        step('ok', () async {}),
        step('bad', () async => throw Exception('nope')),
      ],
    );

    await shutdown.run(
      onStepResult: (result) =>
          reported.add('${result.name}:${result.isClean ? "clean" : "dirty"}'),
    );

    expect(reported, ['ok:clean', 'bad:dirty']);
  });
}
