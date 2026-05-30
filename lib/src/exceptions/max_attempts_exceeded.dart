/// Thrown by [SmartRetry.run] / [SmartRetry.runWithOptions] when **all
/// configured attempts have been exhausted** and none succeeded.
///
/// ### Catching example
/// ```dart
/// try {
///   final data = await SmartRetry.run(
///     () => api.fetchData(),
///     maxAttempts: 4,
///   );
/// } on MaxAttemptsExceededException catch (e) {
///   print('Gave up after ${e.attempts} tries in ${e.totalElapsed.inSeconds}s');
///   print('Last error: ${e.lastException}');
///   rethrow; // or return a fallback value
/// }
/// ```
class MaxAttemptsExceededException implements Exception {
  // ── Fields ──────────────────────────────────────────────────────────────────

  /// Total number of attempts that were executed (equal to
  /// [RetryOptions.maxAttempts]).
  final int attempts;

  /// The [Exception] thrown by the **last** attempt.
  ///
  /// Inspect this to understand the root cause.
  final Exception lastException;

  /// Total wall-clock time from the first attempt to the final failure,
  /// including all sleep delays between retries.
  final Duration totalElapsed;

  // ── Constructor ─────────────────────────────────────────────────────────────

  /// Creates a [MaxAttemptsExceededException].
  const MaxAttemptsExceededException({
    required this.attempts,
    required this.lastException,
    required this.totalElapsed,
  }) : assert(attempts >= 1, 'attempts must be >= 1');

  // ── toString ─────────────────────────────────────────────────────────────────

  @override
  String toString() => 'MaxAttemptsExceededException: '
      'Failed after $attempts attempt${attempts == 1 ? '' : 's'} '
      'over ${totalElapsed.inMilliseconds}ms. '
      'Last error: $lastException';
}
