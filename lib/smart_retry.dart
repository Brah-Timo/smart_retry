/// smart_retry — Intelligent async retry with exponential backoff & jitter.
///
/// ## Quick start
/// ```dart
/// import 'package:smart_retry/smart_retry.dart';
///
/// final data = await SmartRetry.run(
///   () => api.fetchUser(id: 42),
///   maxAttempts: 5,
///   retryIf: (e) => e is SocketException,
///   onRetry: (ctx) => print('Retry #${ctx.attemptNumber}: ${ctx.nextDelay}'),
/// );
/// ```
///
/// ## Reusable options
/// ```dart
/// final opts = RetryOptions(
///   maxAttempts: 4,
///   jitterStrategy: JitterStrategy.equal,
///   retryIf: (e) => e is SocketException || e is TimeoutException,
/// );
/// final user  = await SmartRetry.runWithOptions(() => api.getUser(),  options: opts);
/// final posts = await SmartRetry.runWithOptions(() => api.getPosts(), options: opts);
/// ```
///
/// ## Event stream
/// ```dart
/// SmartRetry.events.listen((event) {
///   if (event is AttemptFailed) logger.warn(event.exception.toString());
/// });
/// ```
library smart_retry;

// ── Core runner ──────────────────────────────────────────────────────────────
export 'src/smart_retry_runner.dart';

// ── Configuration ────────────────────────────────────────────────────────────
export 'src/retry_options.dart';

// ── Strategies ───────────────────────────────────────────────────────────────
export 'src/backoff_strategy.dart';
export 'src/jitter_strategy.dart';

// ── Context & Events ─────────────────────────────────────────────────────────
export 'src/retry_context.dart';
export 'src/retry_event.dart';

// ── Typed Exceptions ─────────────────────────────────────────────────────────
export 'src/exceptions/max_attempts_exceeded.dart';
export 'src/exceptions/non_retryable_exception.dart';
