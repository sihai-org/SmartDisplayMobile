import '../errors/failures.dart';

/// Result type for handling success and failure states
sealed class Result<T> {
  const Result();
  
  /// Create a success result
  const factory Result.success(T data) = Success<T>;
  
  /// Create a failure result
  const factory Result.failure(Failure failure) = ResultFailure<T>;
  
  /// Check if result is success
  bool get isSuccess => this is Success<T>;
  
  /// Check if result is failure
  bool get isFailure => this is ResultFailure<T>;
  
  /// Get data if success, null otherwise
  T? get data => switch (this) {
    Success<T>(:final data) => data,
    ResultFailure<T>() => null,
  };
  
  /// Get failure if failure, null otherwise
  Failure? get failure => switch (this) {
    Success<T>() => null,
    ResultFailure<T>(:final failure) => failure,
  };
  
  /// Transform the data if success
  Result<U> map<U>(U Function(T) transform) {
    return switch (this) {
      Success<T>(:final data) => Result.success(transform(data)),
      ResultFailure<T>(:final failure) => Result.failure(failure),
    };
  }
  
  /// Chain operations that return Result
  Result<U> flatMap<U>(Result<U> Function(T) transform) {
    return switch (this) {
      Success<T>(:final data) => transform(data),
      ResultFailure<T>(:final failure) => Result.failure(failure),
    };
  }
  
  /// Handle both success and failure cases
  U fold<U>({
    required U Function(T) onSuccess,
    required U Function(Failure) onFailure,
  }) {
    return switch (this) {
      Success<T>(:final data) => onSuccess(data),
      ResultFailure<T>(:final failure) => onFailure(failure),
    };
  }
}

/// Success result implementation
class Success<T> extends Result<T> {
  const Success(this.data);
  
  @override
  final T data;
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T> && 
      runtimeType == other.runtimeType &&
      data == other.data;
  
  @override
  int get hashCode => data.hashCode;
  
  @override
  String toString() => 'Success($data)';
}

/// Failure result implementation
class ResultFailure<T> extends Result<T> {
  const ResultFailure(this.failure);
  
  @override
  final Failure failure;
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultFailure<T> && 
      runtimeType == other.runtimeType &&
      failure == other.failure;
  
  @override
  int get hashCode => failure.hashCode;
  
  @override
  String toString() => 'Failure($failure)';
}

/// Convenience extensions for Future<Result<T>>
extension FutureResultExtension<T> on Future<Result<T>> {
  /// Map the success value asynchronously
  Future<Result<U>> mapAsync<U>(Future<U> Function(T) transform) async {
    final result = await this;
    return switch (result) {
      Success<T>(:final data) => Result.success(await transform(data)),
      ResultFailure<T>(:final failure) => Result.failure(failure),
    };
  }
  
  /// Chain async operations that return Future<Result<U>>
  Future<Result<U>> flatMapAsync<U>(Future<Result<U>> Function(T) transform) async {
    final result = await this;
    return switch (result) {
      Success<T>(:final data) => await transform(data),
      ResultFailure<T>(:final failure) => Result.failure(failure),
    };
  }
}