import 'dart:math' as math;

import 'package:smart_retry/src/backoff_strategy.dart';
import 'package:smart_retry/src/jitter_strategy.dart';

/// Computes the **final sleep duration** for a retry attempt by combining
/// the backoff formula and the jitter randomisation in one call.
///
/// This is a convenience wrapper used internally by [SmartRetryRunner].
/// You can also use it directly when building custom retry wrappers.
///
/// ### Parameters
/// - [backoff] — which growth formula to use.
/// - [jitter] — which randomisation to apply.
/// - [attemptIndex] — zero-based retry index (0 = after 1st failure).
/// - [initialDelay] — base delay unit.
/// - [factor] — growth multiplier (for exponential strategy).
/// - [maxDelay] — hard cap.
/// - [lastDelay] — previous sleep (only relevant for decorrelated jitter).
/// - [random] — injectable [math.Random] for deterministic tests.
///
/// ### Returns
/// The [Duration] the caller should `await Future.delayed(...)` before the
/// next attempt.
///
/// ### Example
/// ```dart
/// final sleep = computeDelay(
///   backoff: BackoffStrategy.exponential,
///   jitter: JitterStrategy.full,
///   attemptIndex: 2,
///   initialDelay: const Duration(milliseconds: 500),
///   factor: 2.0,
///   maxDelay: const Duration(seconds: 30),
/// );
/// await Future.delayed(sleep);
/// ```
Duration computeDelay({
  required BackoffStrategy backoff,
  required JitterStrategy jitter,
  required int attemptIndex,
  required Duration initialDelay,
  required double factor,
  required Duration maxDelay,
  Duration? lastDelay,
  math.Random? random,
}) {
  final base = calculateBaseDelay(
    strategy: backoff,
    attemptIndex: attemptIndex,
    initialDelay: initialDelay,
    factor: factor,
    maxDelay: maxDelay,
  );

  return applyJitter(
    strategy: jitter,
    baseDelay: base,
    initialDelay: initialDelay,
    maxDelay: maxDelay,
    lastDelay: lastDelay,
    random: random,
  );
}

/// Formats a [Duration] as a human-readable string with adaptive units.
///
/// - `< 1 ms` → `"0ms"`
/// - `< 1 000 ms` → `"42ms"`
/// - `>= 1 000 ms` → `"4.2s"`
///
/// Used by [SmartRetry] debug output.
String formatDuration(Duration d) {
  final ms = d.inMilliseconds;
  if (ms < 1) return '0ms';
  if (ms < 1000) return '${ms}ms';
  return '${(ms / 1000).toStringAsFixed(1)}s';
}

/// Returns a pretty table row showing the delay schedule for [maxAttempts]
/// retries given [backoff] + [jitter] settings and a fixed [seed] for
/// reproducibility (useful in documentation / tests).
///
/// ```dart
/// // Print a deterministic schedule for documentation:
/// print(buildDelaySchedule(
///   maxAttempts: 5,
///   initialDelay: const Duration(milliseconds: 500),
///   factor: 2.0,
///   maxDelay: const Duration(seconds: 30),
///   backoff: BackoffStrategy.exponential,
///   jitter: JitterStrategy.none,  // none = deterministic, good for docs
/// ));
/// ```
List<({int attempt, Duration baseDelay, Duration actualDelay})> buildDelaySchedule({
  required int maxAttempts,
  required Duration initialDelay,
  required double factor,
  required Duration maxDelay,
  required BackoffStrategy backoff,
  required JitterStrategy jitter,
  int seed = 42,
}) {
  final rng = math.Random(seed);
  Duration? last;
  final schedule = <({int attempt, Duration baseDelay, Duration actualDelay})>[];

  for (var i = 0; i < maxAttempts - 1; i++) {
    final base = calculateBaseDelay(
      strategy: backoff,
      attemptIndex: i,
      initialDelay: initialDelay,
      factor: factor,
      maxDelay: maxDelay,
    );
    final actual = applyJitter(
      strategy: jitter,
      baseDelay: base,
      initialDelay: initialDelay,
      maxDelay: maxDelay,
      lastDelay: last,
      random: rng,
    );
    last = actual;
    schedule.add((attempt: i + 1, baseDelay: base, actualDelay: actual));
  }
  return schedule;
}
