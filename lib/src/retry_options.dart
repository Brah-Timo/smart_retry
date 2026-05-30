import 'dart:async';

import 'package:meta/meta.dart';

import 'package:smart_retry/src/backoff_strategy.dart';
import 'package:smart_retry/src/jitter_strategy.dart';
import 'package:smart_retry/src/retry_context.dart';

/// Immutable configuration object that governs every aspect of [SmartRetry].
///
/// All fields are validated at construction time via `assert`. Use [copyWith]
/// to derive adjusted configurations from a shared base.
///
/// ### Example — shared base config
/// ```dart
/// const kNetworkRetry = RetryOptions(
///   maxAttempts: 4,
///   initialDelay: Duration(milliseconds: 300),
///   jitterStrategy: JitterStrategy.full,
/// );
///
/// // Per-endpoint override
/// final uploadRetry = kNetworkRetry.copyWith(maxAttempts: 6);
/// ```
@immutable
class RetryOptions {
  // ── Core limits ─────────────────────────────────────────────────────────────

  /// Total number of attempts, including the very first try.
  ///
  /// Must be ≥ 1. With `maxAttempts: 3`, the function is executed at most
  /// three times: one initial call + two retries.
  ///
  /// Default: `3`.
  final int maxAttempts;

  // ── Timing ──────────────────────────────────────────────────────────────────

  /// Delay applied **before the second attempt** (i.e. after the first failure).
  ///
  /// Serves as the base unit for exponential and linear growth strategies.
  ///
  /// Default: `500 ms`.
  final Duration initialDelay;

  /// Hard upper cap on any single inter-retry delay.
  ///
  /// Regardless of how many retries have occurred or how large the backoff
  /// calculation grows, the actual sleep never exceeds this value.
  ///
  /// Default: `30 s`.
  final Duration maxDelay;

  /// Multiplicative growth factor for [BackoffStrategy.exponential].
  ///
  /// With `factor: 2.0` and `initialDelay: 500ms` the base delays are:
  /// `500ms → 1 000ms → 2 000ms → 4 000ms → …`
  ///
  /// Must be ≥ 1.0. Default: `2.0`.
  final double factor;

  // ── Strategies ──────────────────────────────────────────────────────────────

  /// Controls **how the base delay grows** between attempts.
  ///
  /// See [BackoffStrategy] for available options and their formulas.
  ///
  /// Default: [BackoffStrategy.exponential].
  final BackoffStrategy backoffStrategy;

  /// Controls **randomisation** applied on top of the base delay.
  ///
  /// Jitter prevents simultaneous retries from multiple clients hammering
  /// the same server (*thundering herd*).
  ///
  /// See [JitterStrategy] for available options.
  ///
  /// Default: [JitterStrategy.full].
  final JitterStrategy jitterStrategy;

  // ── Predicates & Hooks ──────────────────────────────────────────────────────

  /// Decides whether a given [Exception] is **retryable**.
  ///
  /// Return `true` → retry. Return `false` → rethrow immediately as
  /// [NonRetryableException] without further attempts.
  ///
  /// If `null`, **every** exception triggers a retry.
  ///
  /// The callback may be asynchronous (returns `FutureOr<bool>`), allowing
  /// e.g. a check against a connectivity service.
  ///
  /// ### Example
  /// ```dart
  /// retryIf: (e) =>
  ///   e is SocketException ||
  ///   e is TimeoutException ||
  ///   (e is HttpException && e.message.startsWith('5')),
  /// ```
  final FutureOr<bool> Function(Exception e)? retryIf;

  /// Callback invoked **just before each retry sleep**.
  ///
  /// The [RetryContext] provides the attempt number, elapsed time, next delay,
  /// and the exception that triggered this retry. Ideal for logging, analytics,
  /// or surfacing progress to the UI.
  ///
  /// Not called after the final (exhausted) attempt.
  ///
  /// ### Example
  /// ```dart
  /// onRetry: (ctx) {
  ///   logger.warn(
  ///     '[${ctx.attemptNumber}/${ctx.maxAttempts}] '
  ///     'Retry in ${ctx.nextDelay.inMilliseconds}ms — ${ctx.lastException}',
  ///   );
  /// },
  /// ```
  final void Function(RetryContext context)? onRetry;

  // ── Developer ergonomics ────────────────────────────────────────────────────

  /// When `true`, prints structured debug information to stdout on every
  /// attempt start, failure, and success.
  ///
  /// **Should be `false` in production.** Default: `false`.
  final bool debugMode;

  // ── Constructor ─────────────────────────────────────────────────────────────

  /// Creates an immutable [RetryOptions] configuration.
  ///
  /// All parameters are optional; sensible production defaults are applied.
  const RetryOptions({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.factor = 2.0,
    this.backoffStrategy = BackoffStrategy.exponential,
    this.jitterStrategy = JitterStrategy.full,
    this.retryIf,
    this.onRetry,
    this.debugMode = false,
  })  : assert(maxAttempts >= 1, 'maxAttempts must be at least 1'),
        assert(factor >= 1.0, 'factor must be >= 1.0');

  // ── copyWith ─────────────────────────────────────────────────────────────────

  /// Returns a copy of this configuration with the specified fields replaced.
  ///
  /// All unspecified fields retain their current values.
  ///
  /// ```dart
  /// final aggressive = kNetworkRetry.copyWith(maxAttempts: 8, factor: 3.0);
  /// ```
  RetryOptions copyWith({
    int? maxAttempts,
    Duration? initialDelay,
    Duration? maxDelay,
    double? factor,
    BackoffStrategy? backoffStrategy,
    JitterStrategy? jitterStrategy,
    FutureOr<bool> Function(Exception e)? retryIf,
    void Function(RetryContext context)? onRetry,
    bool? debugMode,
  }) =>
      RetryOptions(
        maxAttempts: maxAttempts ?? this.maxAttempts,
        initialDelay: initialDelay ?? this.initialDelay,
        maxDelay: maxDelay ?? this.maxDelay,
        factor: factor ?? this.factor,
        backoffStrategy: backoffStrategy ?? this.backoffStrategy,
        jitterStrategy: jitterStrategy ?? this.jitterStrategy,
        retryIf: retryIf ?? this.retryIf,
        onRetry: onRetry ?? this.onRetry,
        debugMode: debugMode ?? this.debugMode,
      );

  // ── Equality & hashing ───────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetryOptions &&
          runtimeType == other.runtimeType &&
          maxAttempts == other.maxAttempts &&
          initialDelay == other.initialDelay &&
          maxDelay == other.maxDelay &&
          factor == other.factor &&
          backoffStrategy == other.backoffStrategy &&
          jitterStrategy == other.jitterStrategy &&
          debugMode == other.debugMode;

  @override
  int get hashCode => Object.hash(
        maxAttempts,
        initialDelay,
        maxDelay,
        factor,
        backoffStrategy,
        jitterStrategy,
        debugMode,
      );

  @override
  String toString() => 'RetryOptions('
      'maxAttempts: $maxAttempts, '
      'initialDelay: ${initialDelay.inMilliseconds}ms, '
      'maxDelay: ${maxDelay.inSeconds}s, '
      'factor: $factor, '
      'backoff: $backoffStrategy, '
      'jitter: $jitterStrategy, '
      'debugMode: $debugMode'
      ')';
}
