/// Base class for all exceptions in the application
abstract class AppException implements Exception {
  const AppException({required this.message, this.code, this.details});

  final String message;
  final String? code;
  final Map<String, dynamic>? details;

  @override
  String toString() =>
      'AppException: $message ${code != null ? '($code)' : ''}';
}

/// BLE related exceptions
class BleException extends AppException {
  const BleException({required super.message, super.code, super.details});

  @override
  String toString() =>
      'BleException: $message ${code != null ? '($code)' : ''}';
}
