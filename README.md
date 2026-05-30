# smart_retry 🔄

> **Stop writing the same `try/catch/for-loop` boilerplate in every project.**

[![pub.dev](https://img.shields.io/badge/pub.dev-smart__retry-blue)](https://pub.dev/packages/smart_retry)
[![Dart SDK](https://img.shields.io/badge/dart-%3E%3D3.0.0-blue)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![style: lints](https://img.shields.io/badge/style-lints-blue)](https://pub.dev/packages/lints)

A **production-ready, pure-Dart** package for intelligent async retry logic:

- ✅ **Exponential / linear / constant backoff** — grows delay between retries
- ✅ **Full / equal / decorrelated jitter** — prevents thundering herd problems
- ✅ **`retryIf` predicate** — only retry transient errors, abort on permanent ones
- ✅ **`onRetry` callback** — rich [RetryContext] before each sleep
- ✅ **Lifecycle event stream** — plug in any logger / crash reporter
- ✅ **`previewSchedule`** — inspect the delay table without executing
- ✅ **Typed exceptions** — `MaxAttemptsExceededException` & `NonRetryableException`
- ✅ **Zero runtime dependencies** (only `meta`)
- ✅ **100% Pure Dart** — Flutter, Dart CLI, server-side

---

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [API Reference](#api-reference)
   - [SmartRetry.run](#smartretryrun)
   - [SmartRetry.runWithOptions](#smartretryrunwithoptions)
   - [RetryOptions](#retryoptions)
   - [BackoffStrategy](#backoffstrategy)
   - [JitterStrategy](#jitterstrategy)
   - [RetryContext](#retrycontext)
   - [Event Stream](#event-stream)
   - [previewSchedule](#previewschedule)
4. [Exception Handling](#exception-handling)
5. [Delay Schedule Reference](#delay-schedule-reference)
6. [Strategy Comparison](#strategy-comparison)
7. [Advanced Recipes](#advanced-recipes)
8. [Contributing](#contributing)
9. [License](#license)

---

## Installation

```yaml
# pubspec.yaml
dependencies:
  smart_retry: ^1.0.0
```

```bash
dart pub get
# or
flutter pub get
```

---

## Quick Start

```dart
import 'dart:io';
import 'package:smart_retry/smart_retry.dart';

// ── Minimal ──────────────────────────────────────────────────────────────────
final data = await SmartRetry.run(
  () => api.fetchUser(id: 42),
  maxAttempts: 5,
  retryIf: (e) => e is SocketException,
);

// ── With logging ──────────────────────────────────────────────────────────────
final data = await SmartRetry.run(
  () => api.fetchUser(id: 42),
  maxAttempts: 5,
  retryIf: (e) => e is SocketException || e is TimeoutException,
  onRetry: (ctx) => print(
    '[${ctx.attemptNumber}/${ctx.maxAttempts}] '
    'Retry in ${ctx.nextDelay.inMilliseconds}ms — ${ctx.lastException}',
  ),
);

// ── Handle errors explicitly ─────────────────────────────────────────────────
try {
  final data = await SmartRetry.run(() => api.fetchUser(id: 42));
} on MaxAttemptsExceededException catch (e) {
  print('Failed after ${e.attempts} tries: ${e.lastException}');
} on NonRetryableException catch (e) {
  print('Permanent error, not retrying: ${e.cause}');
}
```

---

## API Reference

### SmartRetry.run

The **primary API**. All parameters are optional with production-ready defaults.

```dart
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
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fn` | `Future<T> Function()` | — | The async callable to execute and retry. |
| `maxAttempts` | `int` | `3` | Total tries including the first. |
| `initialDelay` | `Duration` | `500ms` | Base delay before the 2nd attempt. |
| `maxDelay` | `Duration` | `30s` | Hard cap on any single delay. |
| `factor` | `double` | `2.0` | Exponential growth multiplier. |
| `backoffStrategy` | `BackoffStrategy` | `exponential` | Delay growth curve. |
| `jitterStrategy` | `JitterStrategy` | `full` | Randomisation mode. |
| `retryIf` | `FutureOr<bool> Function(Exception)?` | `null` | Per-exception retry gate. Returns `true` → retry, `false` → abort. |
| `onRetry` | `void Function(RetryContext)?` | `null` | Callback invoked before each retry sleep. |
| `debugMode` | `bool` | `false` | Print structured debug output. |

---

### SmartRetry.runWithOptions

Preferred for **shared configuration** across multiple call-sites.

```dart
static Future<T> runWithOptions<T>(
  Future<T> Function() fn, {
  required RetryOptions options,
})
```

```dart
// Define once
final _retry = RetryOptions(
  maxAttempts: 4,
  retryIf: (e) => e is SocketException,
);

// Reuse everywhere
final user  = await SmartRetry.runWithOptions(() => api.getUser(),  options: _retry);
final posts = await SmartRetry.runWithOptions(() => api.getPosts(), options: _retry);
```

---

### RetryOptions

Immutable configuration value object. Supports `copyWith` for derivation.

```dart
const RetryOptions({
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 500),
  Duration maxDelay = const Duration(seconds: 30),
  double factor = 2.0,
  BackoffStrategy backoffStrategy = BackoffStrategy.exponential,
  JitterStrategy jitterStrategy = JitterStrategy.full,
  FutureOr<bool> Function(Exception e)? retryIf,
  void Function(RetryContext context)? onRetry,
  bool debugMode = false,
})
```

```dart
// Base config
const base = RetryOptions(maxAttempts: 4, retryIf: _isTransient);

// Derived config — inherits base, overrides specific fields
final upload = base.copyWith(maxAttempts: 8, maxDelay: Duration(minutes: 2));
```

---

### BackoffStrategy

Controls **how the base delay grows** between attempts.

| Strategy | Formula | Example (initial=500ms, factor=2) |
|----------|---------|-----------------------------------|
| `exponential` | `min(cap, initial × factorⁿ)` | 500 → 1000 → 2000 → 4000ms |
| `linear` | `min(cap, initial × (n+1))` | 500 → 1000 → 1500 → 2000ms |
| `constant` | `initial` (always) | 500 → 500 → 500 → 500ms |

---

### JitterStrategy

Controls **randomisation** applied on top of the base delay.

| Strategy | Formula | Notes |
|----------|---------|-------|
| `full` | `random(0, base)` | Best total throughput under load |
| `equal` | `base/2 + random(0, base/2)` | Guarantees minimum half delay |
| `decorrelated` | `random(initial, min(cap, last×3))` | Best under high contention |
| `none` | `base` (no randomisation) | Tests / single-client jobs only |

---

### RetryContext

Passed to `onRetry` before every retry sleep.

| Field | Type | Description |
|-------|------|-------------|
| `attemptNumber` | `int` | 1-based number of the attempt that just failed. |
| `maxAttempts` | `int` | Total configured attempts. |
| `lastException` | `Exception` | Exception thrown by the last attempt. |
| `nextDelay` | `Duration` | Actual sleep duration (post-jitter). |
| `elapsedTime` | `Duration` | Wall-clock time since the first attempt. |
| `remainingAttempts` | `int` | Computed: `maxAttempts - attemptNumber`. |
| `isFinalAttempt` | `bool` | True if the next attempt is the last. |

---

### Event Stream

`SmartRetry.events` is a **broadcast stream** of [RetryEvent] instances.

```dart
SmartRetry.events.listen((event) {
  switch (event) {
    case AttemptStarted(:final attemptNumber, :final maxAttempts):
      print('▶ $attemptNumber/$maxAttempts');

    case AttemptFailed(:final attemptNumber, :final exception, :final nextDelay):
      logger.warn('Attempt $attemptNumber failed (${nextDelay.inMilliseconds}ms): $exception');

    case AttemptSucceeded(:final attemptNumber, :final totalElapsed):
      metrics.increment('retry.success', tags: {'attempt': '$attemptNumber'});

    case AllAttemptsFailed(:final totalAttempts, :final lastException):
      Sentry.captureException(lastException);

    case RetryAborted(:final exception):
      logger.error('Non-retryable: $exception');
  }
});
```

Available event types: `AttemptStarted`, `AttemptFailed`, `AttemptSucceeded`,
`AllAttemptsFailed`, `RetryAborted`.

---

### previewSchedule

Inspect the full delay table **without executing** any code.

```dart
final schedule = SmartRetry.previewSchedule(
  options: RetryOptions(
    maxAttempts: 5,
    initialDelay: Duration(milliseconds: 500),
    factor: 2.0,
    backoffStrategy: BackoffStrategy.exponential,
    jitterStrategy: JitterStrategy.none,
  ),
);

for (final row in schedule) {
  print('Retry #${row.attempt}: ${row.actualDelay.inMilliseconds}ms');
}
// Retry #1: 500ms
// Retry #2: 1000ms
// Retry #3: 2000ms
// Retry #4: 4000ms
```

---

## Exception Handling

```dart
try {
  final result = await SmartRetry.run(() => api.getData());
} on MaxAttemptsExceededException catch (e) {
  // All attempts failed — transient problem persisted too long
  print('Gave up after ${e.attempts} attempts in ${e.totalElapsed.inSeconds}s');
  print('Last error: ${e.lastException}');
} on NonRetryableException catch (e) {
  // retryIf returned false — permanent error, no point retrying
  print('Permanent failure: ${e.cause}');
  print('Reason: ${e.message}');
}
```

---

## Delay Schedule Reference

Default configuration (`maxAttempts: 5`, `initialDelay: 500ms`, `factor: 2.0`, `jitter: full`):

| Retry | Base Delay | After Full Jitter |
|-------|-----------|-------------------|
| 1st | 500ms | 0 – 500ms |
| 2nd | 1 000ms | 0 – 1 000ms |
| 3rd | 2 000ms | 0 – 2 000ms |
| 4th | 4 000ms | 0 – 4 000ms |

---

## Strategy Comparison

| BackoffStrategy | JitterStrategy | Best for |
|----------------|----------------|---------|
| `exponential` | `full` | **Default** — general network calls |
| `exponential` | `equal` | When a minimum wait is required |
| `exponential` | `decorrelated` | High-concurrency, many clients |
| `constant` | `none` | Tests, deterministic queue consumers |
| `linear` | `full` | APIs with linear rate-limit windows |

---

## Advanced Recipes

### Async retryIf predicate

```dart
await SmartRetry.run(
  () => api.upload(file),
  retryIf: (e) async {
    // Check connectivity before deciding to retry
    final connected = await connectivity.checkConnectivity();
    return connected && e is SocketException;
  },
);
```

### Shared config across a service class

```dart
class ApiService {
  static final _opts = RetryOptions(
    maxAttempts: 4,
    initialDelay: const Duration(milliseconds: 300),
    retryIf: (e) => e is SocketException || e is TimeoutException,
    onRetry: (ctx) => log.warn('[API] retry ${ctx.attemptNumber}'),
  );

  Future<User> getUser(int id) =>
      SmartRetry.runWithOptions(() => _http.get('/users/$id'), options: _opts);

  Future<List<Post>> getPosts() =>
      SmartRetry.runWithOptions(() => _http.get('/posts'), options: _opts);
}
```

### Plug in Sentry / Firebase Crashlytics

```dart
void setupRetryMonitoring() {
  SmartRetry.events.listen((event) {
    if (event is AllAttemptsFailed) {
      Sentry.captureException(event.lastException, hint: Hint.withMap({
        'attempts': '${event.totalAttempts}',
      }));
    }
  });
}
```

---

## Contributing

Pull requests and issues are welcome at
[github.com/Brah-Timo/smart_retry](https://github.com/Brah-Timo/smart_retry).

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Run tests: `dart test`
4. Run the linter: `dart analyze`
5. Submit a PR

---

## License

[MIT](LICENSE) © 2026 
