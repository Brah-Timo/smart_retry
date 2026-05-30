/// Thrown by [SmartRetry] when [RetryOptions.retryIf] returns `false`,
/// indicating that the error is **not transient** and retrying would
/// serve no purpose.
///
/// Common non-retryable scenarios:
/// - HTTP 400 Bad Request (invalid payload — retrying won't fix it)
/// - HTTP 401 Unauthorized (bad credentials — need re-authentication)
/// - HTTP 403 Forbidden (permission denied)
/// - HTTP 404 Not Found (resource does not exist)
/// - [FormatException] (malformed server response)
/// - [ArgumentError] (programming error in the caller)
///
/// ### Catching example
/// ```dart
/// try {
///   await SmartRetry.run(
///     () => api.deletePost(id),
///     retryIf: (e) => e is SocketException,  // 404 won't match → abort
///   );
/// } on NonRetryableException catch (e) {
///   // Handle permanent errors differently from transient ones.
///   showErrorDialog('This action cannot be completed: ${e.cause}');
/// } on MaxAttemptsExceededException catch (e) {
///   // Handle transient exhaustion (network down, server overloaded, …).
///   showRetrySnackbar();
/// }
/// ```
class NonRetryableException implements Exception {
  // ── Fields ──────────────────────────────────────────────────────────────────

  /// The original [Exception] that triggered the non-retryable check.
  ///
  /// Inspect [cause.runtimeType] to understand why retrying was skipped.
  final Exception cause;

  /// Human-readable explanation of why this exception is non-retryable.
  final String message;

  // ── Constructor ─────────────────────────────────────────────────────────────

  /// Creates a [NonRetryableException] wrapping [cause].
  const NonRetryableException({
    required this.cause,
    required this.message,
  });

  // ── toString ─────────────────────────────────────────────────────────────────

  @override
  String toString() => 'NonRetryableException: $message\n'
      '  Caused by: $cause';
}
