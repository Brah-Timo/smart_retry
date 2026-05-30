// ignore_for_file: avoid_print
import 'dart:io';

import 'package:smart_retry/smart_retry.dart';

// ════════════════════════════════════════════════════════════════════════════
// smart_retry — Runnable Examples
// ════════════════════════════════════════════════════════════════════════════
//
// Run with:  dart run example/main.dart
// ════════════════════════════════════════════════════════════════════════════

Future<void> main() async {
  print('╔══════════════════════════════════════════════════════════╗');
  print('║           smart_retry  —  runnable examples             ║');
  print('╚══════════════════════════════════════════════════════════╝\n');

  await example1SimpleRetry();
  await example2CustomOptions();
  await example3RetryIf();
  await example4OnRetryCallback();
  await example5ReusableOptions();
  await example6EventStream();
  await example7PreviewSchedule();
  await example8NonRetryableHandling();
  await example9ExhaustedHandling();

  SmartRetry.dispose();
  print('\n✅  All examples completed.');
}

// ────────────────────────────────────────────────────────────────────────────
// Example 1 — Simplest possible call
// ────────────────────────────────────────────────────────────────────────────
Future<void> example1SimpleRetry() async {
  _header('1', 'Simple retry — succeeds on 3rd attempt');

  var calls = 0;
  final result = await SmartRetry.run<String>(
    () async {
      calls++;
      if (calls < 3) throw SocketException('transient error (call $calls)');
      return 'user_data_42';
    },
    maxAttempts: 5,
    initialDelay: const Duration(milliseconds: 50),
    jitterStrategy: JitterStrategy.none, // deterministic for demo
  );

  print('  Result  : $result');
  print('  Calls   : $calls');
}

// ────────────────────────────────────────────────────────────────────────────
// Example 2 — Custom full options
// ────────────────────────────────────────────────────────────────────────────
Future<void> example2CustomOptions() async {
  _header('2', 'Custom options — exponential + equal jitter');

  var callCount2 = 0;
  try {
    await SmartRetry.run<void>(
      () async {
        callCount2++;
        if (callCount2 > 4) return; // satisfy unused-local-variable
        throw const SocketException('server overloaded');
      },
      maxAttempts: 4,
      initialDelay: const Duration(milliseconds: 20),
      maxDelay: const Duration(milliseconds: 200),
      factor: 2.0,
      backoffStrategy: BackoffStrategy.exponential,
      jitterStrategy: JitterStrategy.equal,
      debugMode: true, // ← prints each attempt to stdout
    );
  } on MaxAttemptsExceededException catch (e) {
    print('  Gave up : ${e.attempts} attempts, '
        '${e.totalElapsed.inMilliseconds}ms elapsed');
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Example 3 — retryIf: only retry specific exceptions
// ────────────────────────────────────────────────────────────────────────────
Future<void> example3RetryIf() async {
  _header('3', 'retryIf — skip retry for non-transient errors');

  // Scenario A: SocketException → retryable
  var callsA = 0;
  try {
    await SmartRetry.run<void>(
      () async {
        callsA++;
        throw const SocketException('network blip');
      },
      maxAttempts: 3,
      initialDelay: Duration.zero,
      retryIf: (e) => e is SocketException,
    );
  } on MaxAttemptsExceededException catch (e) {
    print('  Scenario A — exhausted after ${e.attempts} attempts '
        '(SocketException is retryable)');
  }

  // Scenario B: FormatException → NOT retryable → abort on first try
  var callsB = 0;
  try {
    await SmartRetry.run<void>(
      () async {
        callsB++;
        throw const FormatException('invalid JSON from server');
      },
      maxAttempts: 10, // high maxAttempts — but retryIf will block them
      initialDelay: Duration.zero,
      retryIf: (e) => e is SocketException, // FormatException won't match
    );
  } on NonRetryableException catch (e) {
    print('  Scenario B — aborted immediately on attempt 1: ${e.cause}');
  }

  print('  callsA=$callsA (all used), callsB=$callsB (only 1 used)');
}

// ────────────────────────────────────────────────────────────────────────────
// Example 4 — onRetry callback for rich logging
// ────────────────────────────────────────────────────────────────────────────
Future<void> example4OnRetryCallback() async {
  _header('4', 'onRetry callback — full RetryContext');

  var callCount4 = 0;
  try {
    await SmartRetry.run<void>(
      () async {
        callCount4++;
        if (callCount4 > 4) return; // satisfy unused-local-variable
        throw const SocketException('temporary failure');
      },
      maxAttempts: 4,
      initialDelay: const Duration(milliseconds: 30),
      jitterStrategy: JitterStrategy.none,
      onRetry: (ctx) {
        print(
          '  [retry ${ctx.attemptNumber}/${ctx.maxAttempts}] '
          'next in ${ctx.nextDelay.inMilliseconds}ms | '
          'elapsed ${ctx.elapsedTime.inMilliseconds}ms | '
          '${ctx.remainingAttempts} left | '
          'error: ${ctx.lastException.runtimeType}',
        );
      },
    );
  } on MaxAttemptsExceededException {
    // silently expected
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Example 5 — Shared RetryOptions across multiple API calls
// ────────────────────────────────────────────────────────────────────────────
Future<void> example5ReusableOptions() async {
  _header('5', 'Shared RetryOptions — reused across call-sites');

  final networkOpts = RetryOptions(
    maxAttempts: 4,
    initialDelay: const Duration(milliseconds: 30),
    maxDelay: const Duration(milliseconds: 300),
    factor: 2.0,
    jitterStrategy: JitterStrategy.full,
    retryIf: (e) => e is SocketException || e is HttpException,
    onRetry: (ctx) =>
        print('  [shared] retry ${ctx.attemptNumber}: ${ctx.lastException}'),
  );

  // Override only what's needed for a specific endpoint
  final uploadOpts = networkOpts.copyWith(
    maxAttempts: 6, // uploads may need more attempts
    maxDelay: const Duration(seconds: 1),
  );

  var userCalls = 0;
  final user = await SmartRetry.runWithOptions(
    () async {
      userCalls++;
      if (userCalls < 2) throw const SocketException('blip');
      return {'id': 1, 'name': 'Alice'};
    },
    options: networkOpts,
  );
  print('  User fetched: $user ($userCalls calls)');
  print('  Upload opts : $uploadOpts');
}

// ────────────────────────────────────────────────────────────────────────────
// Example 6 — Event stream for centralised monitoring
// ────────────────────────────────────────────────────────────────────────────
Future<void> example6EventStream() async {
  _header('6', 'Event stream — centralised monitoring');

  final log = <String>[];
  final sub = SmartRetry.events.listen((event) {
    switch (event) {
      case AttemptStarted(:final attemptNumber, :final maxAttempts):
        log.add('▶ start  $attemptNumber/$maxAttempts');
      case AttemptFailed(
          :final attemptNumber,
          :final exception,
          :final nextDelay
        ):
        log.add('⚠ failed $attemptNumber — '
            '${exception.runtimeType} — '
            'next: ${nextDelay.inMilliseconds}ms');
      case AttemptSucceeded(:final attemptNumber, :final totalElapsed):
        log.add('✅ ok     $attemptNumber — ${totalElapsed.inMilliseconds}ms');
      case AllAttemptsFailed(:final totalAttempts, :final lastException):
        log.add('💀 dead   $totalAttempts — ${lastException.runtimeType}');
      case RetryAborted(:final exception):
        log.add('🚫 abort  ${exception.runtimeType}');
    }
  });

  var calls = 0;
  await SmartRetry.run<int>(
    () async {
      calls++;
      if (calls < 3) throw const SocketException('x');
      return 0;
    },
    maxAttempts: 5,
    initialDelay: Duration.zero,
    retryIf: (e) => e is SocketException,
  );

  await Future<void>.delayed(const Duration(milliseconds: 20));
  await sub.cancel();

  for (final entry in log) {
    print('  $entry');
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Example 7 — previewSchedule: see delays without running
// ────────────────────────────────────────────────────────────────────────────
Future<void> example7PreviewSchedule() async {
  _header('7', 'previewSchedule — inspect delay table');

  const opts = RetryOptions(
    maxAttempts: 6,
    initialDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 20),
    factor: 2.0,
    backoffStrategy: BackoffStrategy.exponential,
    jitterStrategy: JitterStrategy.none, // deterministic for preview
  );

  final schedule = SmartRetry.previewSchedule(options: opts);

  print('  Retry | Base delay | Actual delay');
  print('  ------+------------+-------------');
  for (final row in schedule) {
    print(
      '   #${row.attempt.toString().padRight(4)}'
      '| ${_padMs(row.baseDelay)}  '
      '| ${_padMs(row.actualDelay)}',
    );
  }
}

String _padMs(Duration d) => '${d.inMilliseconds}ms'.padLeft(8);

// ────────────────────────────────────────────────────────────────────────────
// Example 8 — Handling NonRetryableException gracefully
// ────────────────────────────────────────────────────────────────────────────
Future<void> example8NonRetryableHandling() async {
  _header('8', 'NonRetryableException — graceful degradation');

  Future<String> fetchProfile(int userId) =>
      SmartRetry.run<String>(
        () async {
          // FormatException extends IOException → extends Exception — safe to catch
          if (userId == 0) throw const FormatException('userId must be > 0');
          throw const SocketException('server down');
        },
        maxAttempts: 3,
        initialDelay: Duration.zero,
        retryIf: (e) => e is SocketException, // FormatException → non-retryable
      );

  // Case A: programming error → NonRetryableException (abort immediately)
  try {
    await fetchProfile(0);
  } on NonRetryableException catch (e) {
    print('  ✋ Validation error, not retrying: ${e.cause}');
  } on MaxAttemptsExceededException {
    print('  This should not happen for userId=0');
  }

  // Case B: transient error → MaxAttemptsExceededException (retried 3 times)
  try {
    await fetchProfile(99);
  } on MaxAttemptsExceededException catch (e) {
    print('  🌐 Network down, gave up after ${e.attempts} attempts.');
  } on NonRetryableException {
    print('  This should not happen for userId=99');
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Example 9 — Full exhaustion with detailed error reporting
// ────────────────────────────────────────────────────────────────────────────
Future<void> example9ExhaustedHandling() async {
  _header('9', 'Full exhaustion — detailed reporting');

  final retries = <RetryContext>[];

  try {
    await SmartRetry.run<void>(
      () async => throw const SocketException('backend unreachable'),
      maxAttempts: 3,
      initialDelay: const Duration(milliseconds: 10),
      jitterStrategy: JitterStrategy.none,
      onRetry: retries.add,
    );
  } on MaxAttemptsExceededException catch (e) {
    print('  Final report:');
    print('    • Attempts     : ${e.attempts}');
    print('    • Total time   : ${e.totalElapsed.inMilliseconds}ms');
    print('    • Last error   : ${e.lastException}');
    print('    • Retry delays : ${retries.map((c) => '${c.nextDelay.inMilliseconds}ms').join(', ')}');
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────
void _header(String n, String title) {
  print('─── Example $n: $title');
}
