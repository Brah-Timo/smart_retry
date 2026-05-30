import 'dart:async';
import 'dart:math' as math;

import 'package:smart_retry/src/backoff_strategy.dart';
import 'package:smart_retry/src/exceptions/max_attempts_exceeded.dart';
import 'package:smart_retry/src/exceptions/non_retryable_exception.dart';
import 'package:smart_retry/src/jitter_strategy.dart';
import 'package:smart_retry/src/retry_context.dart';
import 'package:smart_retry/src/retry_event.dart';
import 'package:smart_retry/src/retry_options.dart';
import 'package:smart_retry/src/utils/duration_calculator.dart';

/// The primary entry point for **smart_retry**.
///
/// [SmartRetry] is a pure-static, side-effect-free class (all state is
/// localised to each [run] / [runWithOptions] call), except for the shared
/// broadcast [events] stream.
///
/// ---
///
/// ## Core API
///
/// ### One-off call with inline parameters
/// ```dart
/// final user = await SmartRetry.run(
///   () => api.getUser(id: 42),
///   maxAttempts: 5,
///   retryIf: (e) => e is SocketException,
///   onRetry: (ctx) => print('Retry ${ctx.attemptNumber}: ${ctx.nextDelay}'),
/// );
/// ```
///
/// ### Reusable shared configuration
/// ```dart
/// const _opts = RetryOptions(
///   maxAttempts: 4,
///   jitterStrategy: JitterStrategy.equal,
///   retryIf: _isTransient,
/// );
///
/// final user  = await SmartRetry.runWithOptions(() => api.getUser(),  options: _opts);
/// final posts = await SmartRetry.runWithOptions(() => api.getPosts(), options: _opts);
/// ```
///
/// ### Centralized event monitoring
/// ```dart
/// SmartRetry.events.listen((e) {
///   if (e is AllAttemptsFailed) crashlytics.record(e.lastException);
/// });
/// ```
///
/// ---
///
/// ## Exception contract
///
/// | Situation | Thrown |
/// |-----------|--------|
/// | All attempts exhausted | [MaxAttemptsExceededException] |
/// | `retryIf` returns `false` | [NonRetryableException] |
/// | Success | — (returns `T`) |
///
/// ---
///
/// ## Thread / Isolate safety
///
/// Each [run] invocation maintains its own local state (stopwatch, lastDelay,
/// Random seed). The [events] stream is a broadcast stream safe for multiple
/// concurrent listeners. [SmartRetry] does **not** use any global mutable
/// state beyond the stream controller.
abstract final class SmartRetry {
  SmartRetry._(); // Prevent instantiation

  // ── Event stream ─────────────────────────────────────────────────────────────

  static final StreamController<RetryEvent> _events =
      StreamController<RetryEvent>.broadcast();

  /// A **broadcast** stream of [RetryEvent]s covering the full lifecycle of
  /// every retry operation.
  ///
  /// Events (in emission order per attempt):
  /// 1. [AttemptStarted] — before executing [fn]
  /// 2. [AttemptFailed]  — after a retryable failure (not on final attempt)
  ///    OR [RetryAborted] — if `retryIf` returns `false`
  ///    OR [AllAttemptsFailed] — if all attempts are exhausted
  /// 3. [AttemptSucceeded] — on success
  ///
  /// Multiple concurrent listeners are supported. The stream stays open for
  /// the lifetime of the process; call [dispose] during app shutdown if you
  /// need to release resources.
  ///
  /// ### Example — plug in to a logging framework
  /// ```dart
  /// SmartRetry.events.where((e) => e is AttemptFailed).listen((e) {
  ///   final f = e as AttemptFailed;
  ///   Sentry.addBreadcrumb(
  ///     Breadcrumb(message: 'Retry attempt ${f.attemptNumber} failed: ${f.exception}'),
  ///   );
  /// });
  /// ```
  static Stream<RetryEvent> get events => _events.stream;

  // ── Primary API: run ─────────────────────────────────────────────────────────

  /// Executes [fn] with automatic retry on failure.
  ///
  /// This is the **primary convenience API**. All parameters are optional and
  /// default to sensible production values.
  ///
  /// ### Parameters
  ///
  /// | Parameter | Type | Default | Description |
  /// |-----------|------|---------|-------------|
  /// | `fn` | `Future<T> Function()` | — | The async callable to execute and retry. |
  /// | `maxAttempts` | `int` | `3` | Total tries including the first. |
  /// | `initialDelay` | `Duration` | `500ms` | Base delay before the 2nd attempt. |
  /// | `maxDelay` | `Duration` | `30s` | Hard cap on any single delay. |
  /// | `factor` | `double` | `2.0` | Exponential growth multiplier. |
  /// | `backoffStrategy` | [BackoffStrategy] | `exponential` | Delay growth curve. |
  /// | `jitterStrategy` | [JitterStrategy] | `full` | Randomisation mode. |
  /// | `retryIf` | `FutureOr<bool> Function(Exception)?` | `null` | Per-exception retry gate. |
  /// | `onRetry` | `void Function(RetryContext)?` | `null` | Pre-sleep callback. |
  /// | `debugMode` | `bool` | `false` | Print debug output. |
  ///
  /// ### Returns
  /// The value returned by [fn] on the first successful execution.
  ///
  /// ### Throws
  /// - [MaxAttemptsExceededException] — if all [maxAttempts] attempts throw.
  /// - [NonRetryableException] — if [retryIf] returns `false`.
  ///
  /// ### Example
  /// ```dart
  /// final data = await SmartRetry.run(
  ///   () => http.get(Uri.parse('https://api.example.com/data')),
  ///   maxAttempts: 5,
  ///   initialDelay: const Duration(milliseconds: 300),
  ///   retryIf: (e) => e is SocketException || e is TimeoutException,
  ///   onRetry: (ctx) => print('[${ctx.attemptNumber}] Retrying in ${ctx.nextDelay}'),
  /// );
  /// ```
  static Future<T> run<T>(
    Future<T> Function() fn, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
    Duration maxDelay = const Duration(seconds: 30),
    double factor = 2.0,
    BackoffStrategy backoffStrategy = BackoffStrategy.exponential,
    JitterStrategy jitterStrategy = JitterStrategy.full,
    FutureOr<bool> Function(Exception e)? retryIf,
    void Function(RetryContext context)? onRetry,
    bool debugMode = false,
  }) =>
      runWithOptions(
        fn,
        options: RetryOptions(
          maxAttempts: maxAttempts,
          initialDelay: initialDelay,
          maxDelay: maxDelay,
          factor: factor,
          backoffStrategy: backoffStrategy,
          jitterStrategy: jitterStrategy,
          retryIf: retryIf,
          onRetry: onRetry,
          debugMode: debugMode,
        ),
      );

  // ── Secondary API: runWithOptions ────────────────────────────────────────────

  /// Executes [fn] using a pre-built [RetryOptions] configuration.
  ///
  /// Prefer this overload when the same options are reused across multiple
  /// call-sites — it avoids recreating the [RetryOptions] object on every
  /// call.
  ///
  /// ```dart
  /// final _retry = RetryOptions(
  ///   maxAttempts: 5,
  ///   retryIf: (e) => e is SocketException,
  /// );
  ///
  /// // Shared config, different functions:
  /// final user  = await SmartRetry.runWithOptions(() => api.getUser(),  options: _retry);
  /// final posts = await SmartRetry.runWithOptions(() => api.getPosts(), options: _retry);
  /// ```
  ///
  /// ### Throws
  /// Same as [run].
  static Future<T> runWithOptions<T>(
    Future<T> Function() fn, {
    required RetryOptions options,
  }) async {
    final stopwatch = Stopwatch()..start();
    final rng = math.Random();
    Duration? lastDelay;

    for (var attempt = 1; attempt <= options.maxAttempts; attempt++) {
      // ── PRE-ATTEMPT ──────────────────────────────────────────────────────────
      _emit(AttemptStarted(attempt, options.maxAttempts));
      _debug(options, '▶ attempt $attempt/${options.maxAttempts}');

      // ── EXECUTE ──────────────────────────────────────────────────────────────
      try {
        final result = await fn();

        // ✅ SUCCESS
        stopwatch.stop();
        _emit(AttemptSucceeded(attempt, stopwatch.elapsed));
        _debug(
          options,
          '✅ succeeded on attempt $attempt '
          '(total: ${formatDuration(stopwatch.elapsed)})',
        );
        return result;

        // ── FAILURE ────────────────────────────────────────────────────────────
      } on Exception catch (e) {
        final isLastAttempt = attempt >= options.maxAttempts;

        // ── Check retryIf predicate ──────────────────────────────────────────
        if (options.retryIf != null) {
          final shouldRetry = await options.retryIf!(e);
          if (!shouldRetry) {
            // ❌ NON-RETRYABLE
            _emit(RetryAborted(e));
            _debug(
              options,
              '🚫 aborted — ${e.runtimeType} is non-retryable',
            );
            throw NonRetryableException(
              cause: e,
              message: 'retryIf predicate returned false for '
                  '${e.runtimeType}: $e',
            );
          }
        }

        // ── Exhausted ────────────────────────────────────────────────────────
        if (isLastAttempt) {
          stopwatch.stop();
          _emit(AllAttemptsFailed(attempt, e));
          _debug(
            options,
            '💀 all $attempt attempts failed '
            '(total: ${formatDuration(stopwatch.elapsed)})',
          );
          throw MaxAttemptsExceededException(
            attempts: attempt,
            lastException: e,
            totalElapsed: stopwatch.elapsed,
          );
        }

        // ── Compute sleep duration ───────────────────────────────────────────
        final sleep = computeDelay(
          backoff: options.backoffStrategy,
          jitter: options.jitterStrategy,
          // attemptIndex is 0-based: first retry = index 0
          attemptIndex: attempt - 1,
          initialDelay: options.initialDelay,
          factor: options.factor,
          maxDelay: options.maxDelay,
          lastDelay: lastDelay,
          random: rng,
        );
        lastDelay = sleep;

        // ── Build context & fire callbacks ───────────────────────────────────
        final ctx = RetryContext(
          attemptNumber: attempt,
          maxAttempts: options.maxAttempts,
          lastException: e,
          nextDelay: sleep,
          elapsedTime: stopwatch.elapsed,
        );

        options.onRetry?.call(ctx);
        _emit(AttemptFailed(attempt, e, sleep));

        _debug(
          options,
          '⚠ attempt $attempt failed (${e.runtimeType}). '
          'Sleeping ${formatDuration(sleep)}…',
        );

        // ── Sleep ────────────────────────────────────────────────────────────
        await Future<void>.delayed(sleep);
      }
    }

    // Unreachable — the loop always returns or throws inside the body.
    // Dart's control-flow analysis doesn't prove it, so we satisfy the
    // compiler with an assertion-style error.
    throw StateError(
      'SmartRetry: reached unreachable code after retry loop. '
      'This is a bug — please file an issue.',
    );
  }

  // ── Static helpers ───────────────────────────────────────────────────────────

  /// Previews the delay schedule (without actually sleeping) for the given
  /// [options] using a fixed [seed] for reproducibility.
  ///
  /// Useful for documentation, debugging, or explaining retry behaviour to
  /// users in a UI.
  ///
  /// ```dart
  /// final schedule = SmartRetry.previewSchedule(
  ///   options: RetryOptions(maxAttempts: 5, jitterStrategy: JitterStrategy.none),
  /// );
  /// for (final row in schedule) {
  ///   print('Retry ${row.attempt}: ${row.actualDelay.inMilliseconds}ms');
  /// }
  /// ```
  static List<({int attempt, Duration baseDelay, Duration actualDelay})>
      previewSchedule({
    required RetryOptions options,
    int seed = 42,
  }) =>
          buildDelaySchedule(
            maxAttempts: options.maxAttempts,
            initialDelay: options.initialDelay,
            factor: options.factor,
            maxDelay: options.maxDelay,
            backoff: options.backoffStrategy,
            jitter: options.jitterStrategy,
            seed: seed,
          );

  /// Releases the internal [events] stream controller.
  ///
  /// Call this **once** during application shutdown if you need to cleanly
  /// release resources. After [dispose] is called, [events] will be a closed
  /// stream and adding further events will throw.
  ///
  /// In most applications this is **not required** — Dart's garbage collector
  /// handles it when the process exits.
  static void dispose() => _events.close();

  // ── Internal helpers ─────────────────────────────────────────────────────────

  static void _emit(RetryEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  static void _debug(RetryOptions opts, String msg) {
    if (opts.debugMode) {
      // ignore: avoid_print
      print('[SmartRetry] $msg');
    }
  }
}
