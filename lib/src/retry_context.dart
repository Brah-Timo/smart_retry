import 'package:meta/meta.dart';

/// An immutable snapshot of the retry state captured **after a failure and
/// before the next sleep**.
///
/// Instances are passed to [RetryOptions.onRetry] on every retry. They
/// are also embedded in [AttemptFailed] events on the [SmartRetry.events]
/// stream.
///
/// ### Usage
/// ```dart
/// onRetry: (ctx) {
///   print(
///     '[${ctx.attemptNumber}/${ctx.maxAttempts}] '
///     'Sleeping ${ctx.nextDelay.inMilliseconds}ms '
///     '(${ctx.remainingAttempts} left) — '
///     '${ctx.lastException.runtimeType}',
///   );
/// },
/// ```
@immutable
class RetryContext {
  // ── Attempt info ─────────────────────────────────────────────────────────────

  /// The **1-based** attempt number that just failed.
  ///
  /// `1` means the first call failed; `2` means the first *retry* failed, etc.
  final int attemptNumber;

  /// Total attempts configured via [RetryOptions.maxAttempts].
  final int maxAttempts;

  // ── Error info ───────────────────────────────────────────────────────────────

  /// The [Exception] thrown by the attempt that just completed.
  final Exception lastException;

  // ── Timing info ──────────────────────────────────────────────────────────────

  /// The delay [SmartRetry] will sleep **before the next attempt**.
  ///
  /// This is the post-jitter value — the actual duration the coroutine will
  /// be suspended.
  final Duration nextDelay;

  /// Wall-clock time elapsed since the very first attempt started.
  ///
  /// Includes all previous sleeps and execution times.
  final Duration elapsedTime;

  // ── Derived convenience getters ──────────────────────────────────────────────

  /// `true` if no further retries will be made after the current one
  /// (i.e. the **next** attempt is the last).
  ///
  /// Note: [onRetry] is *not* called after the final attempt, so
  /// [isFinalAttempt] being `true` means "the next attempt is the last one".
  bool get isFinalAttempt => attemptNumber >= maxAttempts - 1;

  /// Number of attempts still remaining, including the next one.
  ///
  /// `remainingAttempts == 1` means only one more chance after this sleep.
  int get remainingAttempts => maxAttempts - attemptNumber;

  /// Total time spent sleeping across all retries so far.
  ///
  /// Approximated as `elapsedTime - (attemptNumber × avgExecTime)`.
  /// In practice use [elapsedTime] for wall-clock measurements.
  Duration get totalSleepSoFar => elapsedTime;

  // ── Constructor ──────────────────────────────────────────────────────────────

  /// Creates an immutable [RetryContext].
  ///
  /// All fields are required. Instances are created exclusively by
  /// [SmartRetryRunner].
  const RetryContext({
    required this.attemptNumber,
    required this.maxAttempts,
    required this.lastException,
    required this.nextDelay,
    required this.elapsedTime,
  })  : assert(attemptNumber >= 1, 'attemptNumber must be >= 1'),
        assert(maxAttempts >= 1, 'maxAttempts must be >= 1');

  // ── toString ─────────────────────────────────────────────────────────────────

  @override
  String toString() => 'RetryContext('
      'attempt: $attemptNumber/$maxAttempts, '
      'remaining: $remainingAttempts, '
      'nextDelay: ${nextDelay.inMilliseconds}ms, '
      'elapsed: ${elapsedTime.inMilliseconds}ms, '
      'error: ${lastException.runtimeType}'
      ')';
}
