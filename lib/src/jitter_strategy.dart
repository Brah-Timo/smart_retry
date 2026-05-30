import 'dart:math' as math;

/// Defines the **randomisation** applied on top of the base backoff delay.
///
/// Jitter is the key ingredient that prevents the *thundering herd* problem:
/// without it, all clients that fail at the same time retry at the same moment,
/// creating a spike that can crash the recovering server.
///
/// Based on the seminal AWS Architecture Blog post:
/// https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
///
/// ### Summary of formulas
///
/// Let `b = baseDelay`, `init = initialDelay`, `cap = maxDelay`,
/// `last = lastDelay` (previous sleep).
///
/// | Strategy    | Formula                                                    |
/// |-------------|-------------------------------------------------------------|
/// | full        | `random(0, b)`                                             |
/// | equal       | `b/2 + random(0, b/2)`                                     |
/// | decorrelated| `random(init, min(cap, last × 3))`                         |
/// | none        | `b` (no randomisation)                                     |
enum JitterStrategy {
  /// **Full jitter** — sleep = `random(0, baseDelay)`.
  ///
  /// The most aggressive randomisation. Completely replaces the backoff value
  /// with a uniform random in `[0, base]`. AWS research shows this produces
  /// the best aggregate throughput under high contention.
  ///
  /// ⚠️ Can produce very short delays (near zero) — acceptable on average.
  ///
  /// **Best for**: reducing total server load when many clients retry
  /// simultaneously.
  full,

  /// **Equal jitter** — sleep = `baseDelay/2 + random(0, baseDelay/2)`.
  ///
  /// Guarantees a minimum sleep of `baseDelay/2` while still randomising
  /// the second half. A good middle ground between spacing and load
  /// distribution.
  ///
  /// **Best for**: when you want a meaningful minimum delay but still
  /// spread retries.
  equal,

  /// **Decorrelated jitter** — sleep = `random(initialDelay, min(cap, last×3))`.
  ///
  /// Each delay is derived from the *previous* delay rather than the attempt
  /// index, producing a correlated random walk. AWS research demonstrates this
  /// achieves the lowest total aggregate wait time under high contention.
  ///
  /// Requires [applyJitter] to be called with `lastDelay` on every attempt
  /// (handled automatically by [SmartRetry]).
  ///
  /// **Best for**: high-concurrency scenarios where many clients retry at once.
  decorrelated,

  /// **No jitter** — sleep = `baseDelay` (pure deterministic backoff).
  ///
  /// Not recommended for production with multiple concurrent clients.
  /// Useful for tests or single-client background jobs.
  none,
}

/// Applies [strategy] randomisation to [baseDelay] and returns the actual
/// sleep [Duration].
///
/// ### Parameters
/// - [strategy] — which jitter algorithm to apply.
/// - [baseDelay] — the deterministic delay from [calculateBaseDelay].
/// - [initialDelay] — used as the lower bound for [JitterStrategy.decorrelated].
/// - [maxDelay] — hard cap; result is always `≤ maxDelay`.
/// - [lastDelay] — previous sleep duration; required for [JitterStrategy.decorrelated],
///   defaults to [initialDelay] if not provided.
/// - [random] — optional [math.Random] instance for deterministic testing.
///
/// ### Example
/// ```dart
/// final sleep = applyJitter(
///   strategy: JitterStrategy.full,
///   baseDelay: const Duration(seconds: 4),
///   initialDelay: const Duration(milliseconds: 500),
///   maxDelay: const Duration(seconds: 30),
/// ); // → somewhere in [0ms, 4000ms]
/// ```
Duration applyJitter({
  required JitterStrategy strategy,
  required Duration baseDelay,
  required Duration initialDelay,
  required Duration maxDelay,
  Duration? lastDelay,
  math.Random? random,
}) {
  final rng = random ?? math.Random();
  final baseUs = baseDelay.inMicroseconds;
  final maxUs = maxDelay.inMicroseconds;
  final initUs = initialDelay.inMicroseconds;

  // Guard: zero base → return zero immediately
  if (baseUs <= 0) return Duration.zero;

  final int resultUs;

  switch (strategy) {
    case JitterStrategy.full:
      // random(0, base)
      resultUs = _randInt(rng, 0, baseUs);

    case JitterStrategy.equal:
      // base/2 + random(0, base/2)
      final half = baseUs ~/ 2;
      resultUs = half + _randInt(rng, 0, math.max(half, 1));

    case JitterStrategy.decorrelated:
      // random(init, min(cap, last × 3))
      final lastUs = (lastDelay ?? initialDelay).inMicroseconds;
      final upper = math.min(maxUs, lastUs * 3);
      final lo = math.min(initUs, upper);
      resultUs = _randInt(rng, lo, math.max(upper, lo + 1));

    case JitterStrategy.none:
      resultUs = baseUs;
  }

  return Duration(microseconds: math.min(resultUs, maxUs));
}

/// Returns a random integer in the range `[lo, hi)`.
/// Handles the edge case where `hi <= lo` by returning `lo`.
int _randInt(math.Random rng, int lo, int hi) {
  if (hi <= lo) return lo;
  return lo + rng.nextInt(hi - lo);
}
