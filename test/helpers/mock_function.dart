import 'dart:io';

/// A simple stateful callable that fails for the first [failTimes] calls
/// and then returns [successValue].
///
/// Used across tests to control exactly how many attempts are needed.
///
/// ```dart
/// final fn = MockFunction<String>(failTimes: 2, successValue: 'ok');
/// // call 1 → throws SocketException
/// // call 2 → throws SocketException
/// // call 3 → returns 'ok'
/// ```
class MockFunction<T> {
  /// Number of leading calls that should throw [exception].
  final int failTimes;

  /// The value returned after [failTimes] have been exhausted.
  final T successValue;

  /// The exception thrown on failing calls.
  /// Defaults to `SocketException('mock network error')`.
  final Exception exception;

  int _callCount = 0;

  MockFunction({
    required this.failTimes,
    required this.successValue,
    Exception? exception,
  }) : exception = exception ?? const SocketException('mock network error');

  /// Total number of times this callable has been invoked.
  int get callCount => _callCount;

  /// Executes the mock: throws [exception] for the first [failTimes] calls,
  /// then returns [successValue].
  Future<T> call() async {
    _callCount++;
    if (_callCount <= failTimes) throw exception;
    return successValue;
  }

  /// Resets the call counter — useful for reusing the same mock across
  /// multiple test scenarios.
  void reset() => _callCount = 0;
}

/// A callable that **always** throws [exception].
class AlwaysFailFunction {
  final Exception exception;
  int _callCount = 0;

  AlwaysFailFunction({Exception? exception})
      : exception = exception ?? const SocketException('always fails');

  int get callCount => _callCount;

  Future<Never> call() async {
    _callCount++;
    throw exception;
  }
}

/// A callable that **always** succeeds immediately, returning [value].
class AlwaysSucceedFunction<T> {
  final T value;
  int _callCount = 0;

  AlwaysSucceedFunction(this.value);

  int get callCount => _callCount;

  Future<T> call() async {
    _callCount++;
    return value;
  }
}

/// Simulates a service that is unavailable for [downFor] calls then recovers.
/// The returned [Exception] cycles through [exceptions] (or defaults to
/// [SocketException]) during the down period.
class FlakeyService<T> {
  final int downFor;
  final T successValue;
  final List<Exception>? exceptions;

  int _callCount = 0;

  FlakeyService({
    required this.downFor,
    required this.successValue,
    this.exceptions,
  });

  int get callCount => _callCount;

  Future<T> call() async {
    final n = _callCount++;
    if (n < downFor) {
      final exList = exceptions;
      if (exList != null && exList.isNotEmpty) {
        throw exList[n % exList.length];
      }
      throw SocketException('service down (call ${n + 1})');
    }
    return successValue;
  }
}
