import 'dart:math' as math;

/// Defines **how the base delay grows** between successive retry attempts.
///
/// The jitter strategy is applied on top of the value produced here.
/// See [JitterStrategy] for the randomisation layer.
///
/// ### Formulas
/// Let `b = initialDelay`, `f = factor`, `n = attemptIndex` (0-based),
/// and `cap = maxDelay`.
///
/// | Strategy    | Formula                                      |
/// |-------------|----------------------------------------------|
/// | exponential | `min(cap, b × fⁿ)`                           |
/// | linear      | `min(cap, b × (n + 1))`                      |
/// | constant    | `b`  (always, ignores n and factor)          |
enum BackoffStrategy {
  /// **Exponential backoff** — delay doubles (or multiplies by [factor]) on
  /// each attempt.
  ///
  /// ```
  /// factor=2, initial=500ms:
  ///   n=0 →  500ms
  ///   n=1 → 1 000ms
  ///   n=2 → 2 000ms
  ///   n=3 → 4 000ms
  ///   n=4 → 8 000ms  (or maxDelay if lower)
  /// ```
  ///
  /// **Best for**: most network retries — gives the server time to recover
  /// without overwhelming it.
  exponential,

  /// **Linear backoff** — delay increases by [initialDelay] on each attempt.
  ///
  /// ```
  /// initial=500ms:
  ///   n=0 →  500ms
  ///   n=1 → 1 000ms
  ///   n=2 → 1 500ms
  ///   n=3 → 2 000ms
  /// ```
  ///
  /// **Best for**: APIs with a predictable rate-limit recovery window.
  linear,

  /// **Constant backoff** — delay is always exactly [initialDelay].
  ///
  /// ```
  /// initial=500ms:
  ///   n=0 → 500ms
  ///   n=1 → 500ms
  ///   n=2 → 500ms
  /// ```
  ///
  /// **Best for**: tests, queue consumers, or when even spacing is required.
  constant,
}

/// Calculates the **base delay** (before jitter) for a given [strategy].
///
/// ### Parameters
/// - [strategy] — which growth formula to apply.
/// - [attemptIndex] — **zero-based** retry index (0 = after first failure).
/// - [initialDelay] — the starting / minimum duration.
/// - [factor] — multiplicative growth rate (only used by [BackoffStrategy.exponential]).
/// - [maxDelay] — hard cap; result is always `≤ maxDelay`.
///
/// ### Example
/// ```dart
/// final delay = calculateBaseDelay(
///   strategy: BackoffStrategy.exponential,
///   attemptIndex: 2,        // third retry
///   initialDelay: const Duration(milliseconds: 500),
///   factor: 2.0,
///   maxDelay: const Duration(seconds: 30),
/// ); // → Duration(milliseconds: 2000)
/// ```
Duration calculateBaseDelay({
  required BackoffStrategy strategy,
  required int attemptIndex,
  required Duration initialDelay,
  required double factor,
  required Duration maxDelay,
}) {
  assert(attemptIndex >= 0, 'attemptIndex must be non-negative');
  assert(factor >= 1.0, 'factor must be >= 1.0');

  final baseUs = initialDelay.inMicroseconds;
  final maxUs = maxDelay.inMicroseconds;

  if (baseUs <= 0) return Duration.zero;

  final int rawUs;

  switch (strategy) {
    case BackoffStrategy.exponential:
      // b × f^n  — clamp intermediate double before converting to int
      // to avoid overflow on very large attemptIndex values.
      final multiplier = math.pow(factor, attemptIndex).toDouble();
      final raw = baseUs * multiplier;
      rawUs = raw >= maxUs ? maxUs : raw.round();

    case BackoffStrategy.linear:
      // b × (n + 1)
      rawUs = baseUs * (attemptIndex + 1);

    case BackoffStrategy.constant:
      rawUs = baseUs;
  }

  return Duration(microseconds: math.min(rawUs, maxUs));
}
