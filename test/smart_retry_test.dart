import 'dart:io';

import 'package:smart_retry/smart_retry.dart';
import 'package:test/test.dart';

import 'helpers/mock_function.dart';

void main() {
  // ── Basic behaviour ──────────────────────────────────────────────────────────
  group('SmartRetry.run — basic behaviour', () {
    test('succeeds on the first attempt (no retry needed)', () async {
      final fn = AlwaysSucceedFunction('hello');
      final result = await SmartRetry.run(
        fn.call,
        initialDelay: Duration.zero,
      );
      expect(result, equals('hello'));
      expect(fn.callCount, equals(1));
    });

    test('retries and succeeds on the second attempt', () async {
      final fn = MockFunction<int>(failTimes: 1, successValue: 42);
      final result = await SmartRetry.run(
        fn.call,
        maxAttempts: 3,
        initialDelay: Duration.zero,
      );
      expect(result, equals(42));
      expect(fn.callCount, equals(2));
    });

    test('retries and succeeds on the third attempt', () async {
      final fn = MockFunction<String>(failTimes: 2, successValue: 'done');
      final result = await SmartRetry.run(
        fn.call,
        maxAttempts: 5,
        initialDelay: Duration.zero,
      );
      expect(result, equals('done'));
      expect(fn.callCount, equals(3));
    });

    test('uses exactly maxAttempts calls before giving up', () async {
      final fn = AlwaysFailFunction();
      try {
        await SmartRetry.run(
          fn.call,
          maxAttempts: 4,
          initialDelay: Duration.zero,
        );
      } on MaxAttemptsExceededException {
        // expected
      }
      expect(fn.callCount, equals(4));
    });
  });

  // ── MaxAttemptsExceededException ────────────────────────────────────────────
  group('MaxAttemptsExceededException', () {
    test('is thrown when all attempts are exhausted', () async {
      expect(
        () => SmartRetry.run<void>(
          AlwaysFailFunction().call,
          maxAttempts: 3,
          initialDelay: Duration.zero,
        ),
        throwsA(isA<MaxAttemptsExceededException>()),
      );
    });

    test('carries correct attempts count', () async {
      MaxAttemptsExceededException? caught;
      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction().call,
          maxAttempts: 3,
          initialDelay: Duration.zero,
        );
      } on MaxAttemptsExceededException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught!.attempts, equals(3));
    });

    test('carries the last exception as lastException', () async {
      const error = SocketException('custom message');
      MaxAttemptsExceededException? caught;
      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction(exception: error).call,
          maxAttempts: 2,
          initialDelay: Duration.zero,
        );
      } on MaxAttemptsExceededException catch (e) {
        caught = e;
      }
      expect(caught?.lastException, equals(error));
    });

    test('totalElapsed is a non-negative duration', () async {
      MaxAttemptsExceededException? caught;
      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction().call,
          maxAttempts: 2,
          initialDelay: Duration.zero,
        );
      } on MaxAttemptsExceededException catch (e) {
        caught = e;
      }
      expect(caught?.totalElapsed.isNegative, isFalse);
    });
  });

  // ── NonRetryableException ───────────────────────────────────────────────────
  group('NonRetryableException (retryIf predicate)', () {
    test('is thrown immediately when retryIf returns false', () async {
      final fn = AlwaysFailFunction(
        exception: const FormatException('bad json'),
      );
      expect(
        () => SmartRetry.run<void>(
          fn.call,
          maxAttempts: 10,
          initialDelay: Duration.zero,
          // Only SocketException is retryable; FormatException is not
          retryIf: (e) => e is SocketException,
        ),
        throwsA(isA<NonRetryableException>()),
      );
      // Slight delay to allow the async operation to settle
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fn.callCount, equals(1)); // Only tried once
    });

    test('retries when retryIf returns true', () async {
      final fn = MockFunction<String>(
        failTimes: 2,
        successValue: 'ok',
        exception: const SocketException('network'),
      );
      final result = await SmartRetry.run(
        fn.call,
        maxAttempts: 5,
        initialDelay: Duration.zero,
        retryIf: (e) => e is SocketException,
      );
      expect(result, equals('ok'));
      expect(fn.callCount, equals(3));
    });

    test('async retryIf predicate is supported', () async {
      final fn = MockFunction<int>(
        failTimes: 1,
        successValue: 99,
        exception: const SocketException('x'),
      );
      final result = await SmartRetry.run(
        fn.call,
        maxAttempts: 3,
        initialDelay: Duration.zero,
        retryIf: (e) async {
          await Future<void>.delayed(Duration.zero);
          return e is SocketException;
        },
      );
      expect(result, equals(99));
      expect(fn.callCount, equals(2));
    });

    test('wraps the original cause correctly', () async {
      const original = FormatException('oops');
      NonRetryableException? caught;
      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction(exception: original).call,
          maxAttempts: 5,
          initialDelay: Duration.zero,
          retryIf: (e) => false,
        );
      } on NonRetryableException catch (e) {
        caught = e;
      }
      expect(caught?.cause, equals(original));
    });
  });

  // ── onRetry callback ────────────────────────────────────────────────────────
  group('onRetry callback', () {
    test('is called once per retry (not after final attempt)', () async {
      final contexts = <RetryContext>[];
      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction().call,
          maxAttempts: 4,
          initialDelay: Duration.zero,
          onRetry: contexts.add,
        );
      } on MaxAttemptsExceededException {
        // expected
      }
      // Called before attempts 2, 3, 4 — NOT after the final failure
      expect(contexts.length, equals(3));
    });

    test('context carries correct attemptNumber', () async {
      final contexts = <RetryContext>[];
      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction().call,
          maxAttempts: 3,
          initialDelay: Duration.zero,
          onRetry: contexts.add,
        );
      } on MaxAttemptsExceededException {
        // expected
      }
      expect(contexts[0].attemptNumber, equals(1));
      expect(contexts[1].attemptNumber, equals(2));
    });

    test('context.remainingAttempts decrements correctly', () async {
      final remaining = <int>[];
      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction().call,
          maxAttempts: 4,
          initialDelay: Duration.zero,
          onRetry: (ctx) => remaining.add(ctx.remainingAttempts),
        );
      } on MaxAttemptsExceededException {
        // expected
      }
      expect(remaining, equals([3, 2, 1]));
    });

    test('context.lastException matches thrown exception', () async {
      const err = SocketException('boom');
      Exception? captured;
      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction(exception: err).call,
          maxAttempts: 2,
          initialDelay: Duration.zero,
          onRetry: (ctx) => captured = ctx.lastException,
        );
      } on MaxAttemptsExceededException {
        // expected
      }
      expect(captured, equals(err));
    });

    test('context.nextDelay is non-negative', () async {
      final delays = <Duration>[];
      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction().call,
          maxAttempts: 3,
          initialDelay: const Duration(milliseconds: 50),
          jitterStrategy: JitterStrategy.none,
          onRetry: (ctx) => delays.add(ctx.nextDelay),
        );
      } on MaxAttemptsExceededException {
        // expected
      }
      for (final d in delays) {
        expect(d.isNegative, isFalse);
      }
    });
  });

  // ── runWithOptions ───────────────────────────────────────────────────────────
  group('SmartRetry.runWithOptions', () {
    test('behaves identically to run with the same parameters', () async {
      final fn1 = MockFunction<int>(failTimes: 1, successValue: 7);
      final fn2 = MockFunction<int>(failTimes: 1, successValue: 7);

      final r1 = await SmartRetry.run(
        fn1.call,
        maxAttempts: 3,
        initialDelay: Duration.zero,
        jitterStrategy: JitterStrategy.none,
      );

      final r2 = await SmartRetry.runWithOptions(
        fn2.call,
        options: const RetryOptions(
          maxAttempts: 3,
          initialDelay: Duration.zero,
          jitterStrategy: JitterStrategy.none,
        ),
      );

      expect(r1, equals(r2));
      expect(fn1.callCount, equals(fn2.callCount));
    });

    test('shared RetryOptions instance can be reused across multiple calls',
        () async {
      const opts = RetryOptions(
        maxAttempts: 3,
        initialDelay: Duration.zero,
        jitterStrategy: JitterStrategy.none,
      );

      final fn1 = MockFunction<String>(failTimes: 1, successValue: 'a');
      final fn2 = MockFunction<String>(failTimes: 2, successValue: 'b');

      final r1 = await SmartRetry.runWithOptions(fn1.call, options: opts);
      final r2 = await SmartRetry.runWithOptions(fn2.call, options: opts);

      expect(r1, equals('a'));
      expect(r2, equals('b'));
    });
  });

  // ── RetryOptions.copyWith ────────────────────────────────────────────────────
  group('RetryOptions.copyWith', () {
    const base = RetryOptions(maxAttempts: 3, initialDelay: Duration.zero);

    test('produces a new instance', () {
      final copy = base.copyWith(maxAttempts: 5);
      expect(identical(base, copy), isFalse);
    });

    test('overrides only the specified field', () {
      final copy = base.copyWith(maxAttempts: 7);
      expect(copy.maxAttempts, equals(7));
      expect(copy.initialDelay, equals(base.initialDelay));
      expect(copy.factor, equals(base.factor));
    });

    test('preserves all other fields when only one is changed', () {
      const original = RetryOptions(
        maxAttempts: 5,
        initialDelay: Duration(milliseconds: 200),
        maxDelay: Duration(seconds: 10),
        factor: 3.0,
        backoffStrategy: BackoffStrategy.linear,
        jitterStrategy: JitterStrategy.equal,
        debugMode: true,
      );
      final copy = original.copyWith(maxAttempts: 8);

      expect(copy.maxAttempts, equals(8));
      expect(copy.initialDelay, equals(original.initialDelay));
      expect(copy.maxDelay, equals(original.maxDelay));
      expect(copy.factor, equals(original.factor));
      expect(copy.backoffStrategy, equals(original.backoffStrategy));
      expect(copy.jitterStrategy, equals(original.jitterStrategy));
      expect(copy.debugMode, equals(original.debugMode));
    });
  });

  // ── previewSchedule ──────────────────────────────────────────────────────────
  group('SmartRetry.previewSchedule', () {
    test('returns maxAttempts - 1 rows', () {
      const opts = RetryOptions(
        maxAttempts: 5,
        jitterStrategy: JitterStrategy.none,
      );
      final schedule = SmartRetry.previewSchedule(options: opts);
      expect(schedule.length, equals(4));
    });

    test('rows have increasing attempt numbers', () {
      const opts = RetryOptions(
        maxAttempts: 4,
        jitterStrategy: JitterStrategy.none,
      );
      final schedule = SmartRetry.previewSchedule(options: opts);
      for (var i = 0; i < schedule.length; i++) {
        expect(schedule[i].attempt, equals(i + 1));
      }
    });

    test('delays grow with exponential backoff + no jitter', () {
      const opts = RetryOptions(
        maxAttempts: 4,
        initialDelay: Duration(milliseconds: 100),
        factor: 2.0,
        backoffStrategy: BackoffStrategy.exponential,
        jitterStrategy: JitterStrategy.none,
      );
      final schedule = SmartRetry.previewSchedule(options: opts);
      // 100ms → 200ms → 400ms
      expect(schedule[0].actualDelay.inMilliseconds, equals(100));
      expect(schedule[1].actualDelay.inMilliseconds, equals(200));
      expect(schedule[2].actualDelay.inMilliseconds, equals(400));
    });
  });

  // ── Event stream ─────────────────────────────────────────────────────────────
  group('SmartRetry.events stream', () {
    test('emits AttemptStarted before each attempt', () async {
      final events = <RetryEvent>[];
      final sub = SmartRetry.events.listen(events.add);

      final fn = MockFunction<int>(failTimes: 1, successValue: 1);
      await SmartRetry.run(fn.call, maxAttempts: 3, initialDelay: Duration.zero);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      final started = events.whereType<AttemptStarted>().toList();
      expect(started.length, equals(2)); // attempt 1 (fail) + attempt 2 (ok)
    });

    test('emits AttemptSucceeded on success', () async {
      final events = <RetryEvent>[];
      final sub = SmartRetry.events.listen(events.add);

      await SmartRetry.run(
        AlwaysSucceedFunction(42).call,
        initialDelay: Duration.zero,
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(events.whereType<AttemptSucceeded>(), isNotEmpty);
    });

    test('emits AllAttemptsFailed when exhausted', () async {
      final events = <RetryEvent>[];
      final sub = SmartRetry.events.listen(events.add);

      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction().call,
          maxAttempts: 2,
          initialDelay: Duration.zero,
        );
      } on MaxAttemptsExceededException {
        // expected
      }

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(events.whereType<AllAttemptsFailed>(), isNotEmpty);
    });

    test('emits RetryAborted when retryIf returns false', () async {
      final events = <RetryEvent>[];
      final sub = SmartRetry.events.listen(events.add);

      try {
        await SmartRetry.run<void>(
          AlwaysFailFunction(exception: const FormatException()).call,
          maxAttempts: 5,
          initialDelay: Duration.zero,
          retryIf: (e) => false,
        );
      } on NonRetryableException {
        // expected
      }

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(events.whereType<RetryAborted>(), isNotEmpty);
    });
  });

  // ── debugMode ────────────────────────────────────────────────────────────────
  group('debugMode', () {
    test('does not throw when enabled', () async {
      expect(
        () async {
          final fn = MockFunction<int>(failTimes: 1, successValue: 0);
          await SmartRetry.run(
            fn.call,
            maxAttempts: 3,
            initialDelay: Duration.zero,
            debugMode: true,
          );
        },
        returnsNormally,
      );
    });
  });
}
