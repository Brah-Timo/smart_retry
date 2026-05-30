import 'dart:math' as math;

import 'package:smart_retry/src/jitter_strategy.dart';
import 'package:test/test.dart';

void main() {
  const initial = Duration(milliseconds: 500);
  const maxDelay = Duration(seconds: 30);
  const base = Duration(seconds: 4);

  // Helper: run the jitter function [iterations] times with a seeded RNG and
  // return all results.
  List<Duration> sample({
    required JitterStrategy strategy,
    int iterations = 200,
    int seed = 12345,
    Duration? lastDelay,
  }) {
    final rng = math.Random(seed);
    return List.generate(
      iterations,
      (_) => applyJitter(
        strategy: strategy,
        baseDelay: base,
        initialDelay: initial,
        maxDelay: maxDelay,
        lastDelay: lastDelay,
        random: rng,
      ),
    );
  }

  // ── Full jitter ──────────────────────────────────────────────────────────────
  group('JitterStrategy.full', () {
    test('all results are in [0, baseDelay]', () {
      final results = sample(strategy: JitterStrategy.full);
      for (final d in results) {
        expect(d.inMicroseconds, greaterThanOrEqualTo(0));
        expect(d, lessThanOrEqualTo(base));
      }
    });

    test('results are not all identical (randomised)', () {
      final results = sample(strategy: JitterStrategy.full);
      final unique = results.map((d) => d.inMicroseconds).toSet();
      expect(unique.length, greaterThan(1));
    });

    test('average is roughly baseDelay / 2', () {
      final results = sample(strategy: JitterStrategy.full, iterations: 10000);
      final avg =
          results.fold(0, (s, d) => s + d.inMilliseconds) / results.length;
      // Allow ±25% tolerance for statistical noise
      expect(avg, closeTo(base.inMilliseconds / 2, base.inMilliseconds * 0.25));
    });

    test('never exceeds maxDelay', () {
      final results = sample(
        strategy: JitterStrategy.full,
        iterations: 1000,
      );
      for (final d in results) {
        expect(d, lessThanOrEqualTo(maxDelay));
      }
    });
  });

  // ── Equal jitter ─────────────────────────────────────────────────────────────
  group('JitterStrategy.equal', () {
    test('all results are in [baseDelay/2, baseDelay]', () {
      final results = sample(strategy: JitterStrategy.equal);
      final half = Duration(microseconds: base.inMicroseconds ~/ 2);
      for (final d in results) {
        expect(
          d,
          greaterThanOrEqualTo(half),
          reason: '${d.inMilliseconds}ms < half (${half.inMilliseconds}ms)',
        );
        expect(d, lessThanOrEqualTo(base));
      }
    });

    test('results are randomised (not all identical)', () {
      final results = sample(strategy: JitterStrategy.equal);
      final unique = results.map((d) => d.inMicroseconds).toSet();
      expect(unique.length, greaterThan(1));
    });

    test('never exceeds maxDelay', () {
      final results = sample(strategy: JitterStrategy.equal, iterations: 1000);
      for (final d in results) {
        expect(d, lessThanOrEqualTo(maxDelay));
      }
    });
  });

  // ── Decorrelated jitter ──────────────────────────────────────────────────────
  group('JitterStrategy.decorrelated', () {
    test('all results are in [initialDelay, maxDelay]', () {
      final results = sample(
        strategy: JitterStrategy.decorrelated,
        lastDelay: initial,
      );
      for (final d in results) {
        expect(d, greaterThanOrEqualTo(initial));
        expect(d, lessThanOrEqualTo(maxDelay));
      }
    });

    test('never exceeds maxDelay with large lastDelay', () {
      // If lastDelay is huge, upper = min(maxDelay, last*3) keeps it bounded.
      final results = sample(
        strategy: JitterStrategy.decorrelated,
        lastDelay: const Duration(hours: 1),
      );
      for (final d in results) {
        expect(d, lessThanOrEqualTo(maxDelay));
      }
    });

    test('defaults to initialDelay when lastDelay is null', () {
      // Without lastDelay, results should still be in [initial, maxDelay].
      final rng = math.Random(99);
      for (var i = 0; i < 100; i++) {
        final d = applyJitter(
          strategy: JitterStrategy.decorrelated,
          baseDelay: base,
          initialDelay: initial,
          maxDelay: maxDelay,
          lastDelay: null, // triggers default → initialDelay
          random: rng,
        );
        expect(d, greaterThanOrEqualTo(initial));
        expect(d, lessThanOrEqualTo(maxDelay));
      }
    });
  });

  // ── None jitter ───────────────────────────────────────────────────────────────
  group('JitterStrategy.none', () {
    test('returns exactly baseDelay every time', () {
      final results = sample(strategy: JitterStrategy.none);
      for (final d in results) {
        expect(d, equals(base));
      }
    });

    test('is deterministic across different seeds', () {
      final r1 = applyJitter(
        strategy: JitterStrategy.none,
        baseDelay: base,
        initialDelay: initial,
        maxDelay: maxDelay,
        random: math.Random(1),
      );
      final r2 = applyJitter(
        strategy: JitterStrategy.none,
        baseDelay: base,
        initialDelay: initial,
        maxDelay: maxDelay,
        random: math.Random(9999),
      );
      expect(r1, equals(r2));
    });
  });

  // ── Edge cases ────────────────────────────────────────────────────────────────
  group('Edge cases', () {
    test('zero baseDelay returns Duration.zero for all strategies', () {
      for (final strategy in JitterStrategy.values) {
        final d = applyJitter(
          strategy: strategy,
          baseDelay: Duration.zero,
          initialDelay: Duration.zero,
          maxDelay: maxDelay,
          random: math.Random(0),
        );
        expect(d, equals(Duration.zero),
            reason: '$strategy with zero base should return zero');
      }
    });

    test('result is always <= maxDelay for all strategies', () {
      final caps = [
        Duration.zero,
        const Duration(milliseconds: 1),
        const Duration(seconds: 1),
      ];
      for (final cap in caps) {
        for (final strategy in JitterStrategy.values) {
          final d = applyJitter(
            strategy: strategy,
            baseDelay: const Duration(hours: 1), // huge base
            initialDelay: Duration.zero,
            maxDelay: cap,
            random: math.Random(42),
          );
          expect(d, lessThanOrEqualTo(cap),
              reason: '$strategy exceeded cap $cap');
        }
      }
    });
  });
}
