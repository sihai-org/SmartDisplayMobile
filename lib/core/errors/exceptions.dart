/// Base class for all exceptions in the application
abstract class AppException implements Exception {
  const AppException({
    required this.message,
    this.code,
    this.details,
  });
  
  final String message;
  final String? code;
  final Map<String, dynamic>? details;
  
  @override
  String toString() => 'AppException: $message ${code != null ? '($code)' : ''}';
}

/// BLE related exceptions
class BleException extends AppException {
  const BleException({
    required super.message,
    super.code,
    super.details,
  });
  
  @override
  String toString() => 'BleException: $message ${code != null ? '($code)' : ''}';
}

/// Network/WiFi related exceptions
class NetworkException extends AppException {
  const NetworkException({
    required super.message,
    super.code,
    super.details,
  });
  
  @override
  String toString() => 'NetworkException: $message ${code != null ? '($code)' : ''}';
}

/// Cryptography related exceptions
class CryptoException extends AppException {
  const CryptoException({
    required super.message,
    super.code,
    super.details,
  });
  
  @override
  String toString() => 'CryptoException: $message ${code != null ? '($code)' : ''}';
}

/// QR Code related exceptions
class QrException extends AppException {
  const QrException({
    required super.message,
    super.code,
    super.details,
  });
  
  @override
  String toString() => 'QrException: $message ${code != null ? '($code)' : ''}';
}

/// Device provisioning related exceptions
class ProvisioningException extends AppException {
  const ProvisioningException({
    required super.message,
    super.code,
    super.details,
  });
  
  @override
  String toString() => 'ProvisioningException: $message ${code != null ? '($code)' : ''}';
}

/// Permission related exceptions
class PermissionException extends AppException {
  const PermissionException({
    required super.message,
    super.code,
    super.details,
  });
  
  @override
  String toString() => 'PermissionException: $message ${code != null ? '($code)' : ''}';
}

/// Storage related exceptions
class StorageException extends AppException {
  const StorageException({
    required super.message,
    super.code,
    super.details,
  });
  
  @override
  String toString() => 'StorageException: $message ${code != null ? '($code)' : ''}';
}