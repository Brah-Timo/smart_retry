# Changelog

All notable changes to **smart_retry** will be documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-05-30 🎉 Initial stable release

### Added

#### Core API
- `SmartRetry.run<T>()` — one-shot async retry with inline parameters and
  sensible defaults (`maxAttempts: 3`, `initialDelay: 500ms`, `factor: 2.0`,
  `jitter: full`).
- `SmartRetry.runWithOptions<T>()` — reusable `RetryOptions` variant.
- `SmartRetry.events` — broadcast `Stream<RetryEvent>` for lifecycle monitoring.
- `SmartRetry.previewSchedule()` — inspect the delay schedule without executing.
- `SmartRetry.dispose()` — optional cleanup of the event stream controller.

#### Configuration
- `RetryOptions` — immutable, `@immutable` configuration value object with
  `copyWith`, `==`, `hashCode`, and `toString`.

#### Backoff strategies (`BackoffStrategy`)
- `exponential` — delay = `min(cap, initial × factorⁿ)`
- `linear` — delay = `min(cap, initial × (n+1))`
- `constant` — delay = `initial` (always)

#### Jitter strategies (`JitterStrategy`)
- `full` — `random(0, base)` — best aggregate throughput
- `equal` — `base/2 + random(0, base/2)` — guaranteed minimum
- `decorrelated` — `random(initial, min(cap, last×3))` — best under contention
- `none` — no randomisation (deterministic; tests / single-client)

#### Context & Events
- `RetryContext` — immutable snapshot with `attemptNumber`, `maxAttempts`,
  `lastException`, `nextDelay`, `elapsedTime`, `remainingAttempts`,
  `isFinalAttempt`.
- `RetryEvent` sealed class with subtypes: `AttemptStarted`, `AttemptFailed`,
  `AttemptSucceeded`, `AllAttemptsFailed`, `RetryAborted`.

#### Typed Exceptions
- `MaxAttemptsExceededException` — carries `attempts`, `lastException`,
  `totalElapsed`.
- `NonRetryableException` — carries `cause` and human-readable `message`.

#### Utilities
- `calculateBaseDelay()` — public helper for custom wrapper authors.
- `applyJitter()` — public helper for custom wrapper authors.
- `computeDelay()` — combines backoff + jitter in a single call.
- `buildDelaySchedule()` — generates a reproducible delay table (used by
  `previewSchedule`).
- `formatDuration()` — adaptive human-readable duration string.

### Developer experience
- `debugMode: true` prints structured per-attempt output to stdout.
- Strict `analysis_options.yaml` with `lints/recommended` + extra safety rules.
- 100% documentation coverage on all public symbols.
- Full unit test suite: 40+ assertions covering all strategies, predicates,
  callbacks, events, and edge cases.
- Zero runtime dependencies (only `meta` for `@immutable`).

---

## [1.0.0-beta.1] — 2026-05-15

### Added
- Initial beta release for community feedback.
- Core `SmartRetry.run` with exponential backoff + full jitter.
- Basic `retryIf` predicate support.
- `onRetry` callback.

### Changed
- n/a (initial release)

### Fixed
- n/a (initial release)
