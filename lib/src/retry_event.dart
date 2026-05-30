/// Lifecycle events emitted by [SmartRetry] on the [SmartRetry.events] stream.
///
/// All events are subtypes of the **sealed** [RetryEvent] class, which means
/// you can exhaustively switch on them using Dart 3 pattern matching.
///
/// ### Listening example
/// ```dart
/// SmartRetry.events.listen((event) {
///   switch (event) {
///     case AttemptStarted(:final attemptNumber, :final maxAttempts):
///       print('▶ attempt $attemptNumber/$maxAttempts');
///
///     case AttemptFailed(:final attemptNumber, :final exception, :final nextDelay):
///       logger.warn('attempt $attemptNumber failed (${nextDelay.inMilliseconds}ms): $exception');
///
///     case AttemptSucceeded(:final attemptNumber, :final totalElapsed):
///       metrics.record('retry.success', tags: {'attempt': '$attemptNumber'});
///
///     case AllAttemptsFailed(:final totalAttempts, :final lastException):
///       crashReporter.capture(lastException);
///
///     case RetryAborted(:final exception):
///       logger.error('Non-retryable: $exception');
///   }
/// });
/// ```
///
/// The stream is a **broadcast** stream: multiple listeners are supported
/// simultaneously (useful for logging + metrics + UI all at once).
sealed class RetryEvent {
  const RetryEvent();
}

/// Emitted **just before** an attempt is executed.
///
/// This is the first event in every attempt's lifecycle, fired even before
/// the [fn] callable is invoked.
final class AttemptStarted extends RetryEvent {
  /// The 1-based attempt number about to execute.
  final int attemptNumber;

  /// Total attempts configured (from [RetryOptions.maxAttempts]).
  final int maxAttempts;

  /// Creates an [AttemptStarted] event.
  const AttemptStarted(this.attemptNumber, this.maxAttempts);

  @override
  String toString() =>
      'AttemptStarted(attempt: $attemptNumber/$maxAttempts)';
}

/// Emitted when an attempt throws an [Exception] and a retry will be made.
///
/// **Not** emitted on the final (exhausted) attempt — that fires
/// [AllAttemptsFailed] instead.
final class AttemptFailed extends RetryEvent {
  /// The 1-based attempt number that failed.
  final int attemptNumber;

  /// The exception thrown by this attempt.
  final Exception exception;

  /// How long [SmartRetry] will sleep before the next attempt.
  final Duration nextDelay;

  /// Creates an [AttemptFailed] event.
  const AttemptFailed(this.attemptNumber, this.exception, this.nextDelay);

  @override
  String toString() => 'AttemptFailed('
      'attempt: $attemptNumber, '
      'nextDelay: ${nextDelay.inMilliseconds}ms, '
      'error: ${exception.runtimeType}'
      ')';
}

/// Emitted when an attempt completes **successfully**.
///
/// After this event the [SmartRetry.run] / [SmartRetry.runWithOptions] future
/// resolves with the return value.
final class AttemptSucceeded extends RetryEvent {
  /// The 1-based attempt number that succeeded.
  final int attemptNumber;

  /// Total wall-clock time from the very first attempt to this success.
  final Duration totalElapsed;

  /// Creates an [AttemptSucceeded] event.
  const AttemptSucceeded(this.attemptNumber, this.totalElapsed);

  @override
  String toString() => 'AttemptSucceeded('
      'attempt: $attemptNumber, '
      'totalElapsed: ${totalElapsed.inMilliseconds}ms'
      ')';
}

/// Emitted when **all attempts have been exhausted**.
///
/// After this event [SmartRetry] throws [MaxAttemptsExceededException].
final class AllAttemptsFailed extends RetryEvent {
  /// Total number of attempts that were made.
  final int totalAttempts;

  /// The exception thrown by the last (final) attempt.
  final Exception lastException;

  /// Creates an [AllAttemptsFailed] event.
  const AllAttemptsFailed(this.totalAttempts, this.lastException);

  @override
  String toString() => 'AllAttemptsFailed('
      'totalAttempts: $totalAttempts, '
      'lastException: ${lastException.runtimeType}'
      ')';
}

/// Emitted when [RetryOptions.retryIf] returns `false`.
///
/// Signals that the error is non-transient (e.g. 404 Not Found, bad
/// credentials) and no further attempts will be made.
///
/// After this event [SmartRetry] throws [NonRetryableException].
final class RetryAborted extends RetryEvent {
  /// The exception that caused the abort.
  final Exception exception;

  /// Creates a [RetryAborted] event.
  const RetryAborted(this.exception);

  @override
  String toString() =>
      'RetryAborted(exception: ${exception.runtimeType})';
}
