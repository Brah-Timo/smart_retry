import 'package:smart_retry/src/backoff_strategy.dart';
import 'package:test/test.dart';

void main() {
  const initial = Duration(milliseconds: 100);
  const max = Duration(seconds: 60);

  // ── Exponential ─────────────────────────────────────────────────────────────
  group('BackoffStrategy.exponential', () {
    test('attempt 0 returns initialDelay', () {
      final d = calculateBaseDelay(
        strategy: BackoffStrategy.exponential,
        attemptIndex: 0,
        initialDelay: initial,
        factor: 2.0,
        maxDelay: max,
      );
      expect(d, equals(initial));
    });

    test('doubles on each attempt with factor 2', () {
      final delays = List.generate(
        5,
        (i) => calculateBaseDelay(
          strategy: BackoffStrategy.exponential,
          attemptIndex: i,
          initialDelay: initial,
          factor: 2.0,
          maxDelay: max,
        ),
      );
      // 100 → 200 → 400 → 800 → 1600
      expect(delays[0].inMilliseconds, equals(100));
      expect(delays[1].inMilliseconds, equals(200));
      expect(delays[2].inMilliseconds, equals(400));
      expect(delays[3].inMilliseconds, equals(800));
      expect(delays[4].inMilliseconds, equals(1600));
    });

    test('triples on each attempt with factor 3', () {
      final d0 = calculateBaseDelay(
        strategy: BackoffStrategy.exponential,
        attemptIndex: 0,
        initialDelay: const Duration(milliseconds: 100),
        factor: 3.0,
        maxDelay: max,
      );
      final d1 = calculateBaseDelay(
        strategy: BackoffStrategy.exponential,
        attemptIndex: 1,
        initialDelay: const Duration(milliseconds: 100),
        factor: 3.0,
        maxDelay: max,
      );
      expect(d1.inMilliseconds, equals(d0.inMilliseconds * 3));
    });

    test('never exceeds maxDelay regardless of attempt index', () {
      const cap = Duration(seconds: 5);
      for (var i = 0; i < 50; i++) {
        final d = calculateBaseDelay(
          strategy: BackoffStrategy.exponential,
          attemptIndex: i,
          initialDelay: initial,
          factor: 2.0,
          maxDelay: cap,
        );
        expect(
          d,
          lessThanOrEqualTo(cap),
          reason: 'attempt $i exceeded maxDelay',
        );
      }
    });

    test('returns Duration.zero when initialDelay is zero', () {
      final d = calculateBaseDelay(
        strategy: BackoffStrategy.exponential,
        attemptIndex: 5,
        initialDelay: Duration.zero,
        factor: 2.0,
        maxDelay: max,
      );
      expect(d, equals(Duration.zero));
    });

    test('handles very large attemptIndex without overflow', () {
      expect(
        () => calculateBaseDelay(
          strategy: BackoffStrategy.exponential,
          attemptIndex: 1000,
          initialDelay: initial,
          factor: 2.0,
          maxDelay: max,
        ),
        returnsNormally,
      );
    });
  });

  // ── Linear ──────────────────────────────────────────────────────────────────
  group('BackoffStrategy.linear', () {
    test('grows linearly: initial × (n+1)', () {
      final delays = List.generate(
        4,
        (i) => calculateBaseDelay(
          strategy: BackoffStrategy.linear,
          attemptIndex: i,
          initialDelay: initial,
          factor: 2.0, // ignored by linear
          maxDelay: max,
        ),
      );
      // 100 × 1 = 100, × 2 = 200, × 3 = 300, × 4 = 400
      expect(delays[0].inMilliseconds, equals(100));
      expect(delays[1].inMilliseconds, equals(200));
      expect(delays[2].inMilliseconds, equals(300));
      expect(delays[3].inMilliseconds, equals(400));
    });

    test('never exceeds maxDelay', () {
      const cap = Duration(milliseconds: 250);
      for (var i = 0; i < 20; i++) {
        final d = calculateBaseDelay(
          strategy: BackoffStrategy.linear,
          attemptIndex: i,
          initialDelay: initial,
          factor: 1.0,
          maxDelay: cap,
        );
        expect(d, lessThanOrEqualTo(cap));
      }
    });
  });

  // ── Constant ─────────────────────────────────────────────────────────────────
  group('BackoffStrategy.constant', () {
    test('always returns initialDelay regardless of attempt index', () {
      for (var i = 0; i < 20; i++) {
        final d = calculateBaseDelay(
          strategy: BackoffStrategy.constant,
          attemptIndex: i,
          initialDelay: initial,
          factor: 2.0,
          maxDelay: max,
        );
        expect(d, equals(initial), reason: 'failed at attempt $i');
      }
    });

    test('ignores factor completely', () {
      final d1 = calculateBaseDelay(
        strategy: BackoffStrategy.constant,
        attemptIndex: 3,
        initialDelay: initial,
        factor: 100.0,
        maxDelay: max,
      );
      final d2 = calculateBaseDelay(
        strategy: BackoffStrategy.constant,
        attemptIndex: 3,
        initialDelay: initial,
        factor: 1.0,
        maxDelay: max,
      );
      expect(d1, equals(d2));
    });
  });
}
