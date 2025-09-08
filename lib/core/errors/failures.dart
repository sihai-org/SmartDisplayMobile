import 'package:equatable/equatable.dart';

/// Base class for all failures in the application
abstract class Failure extends Equatable {
  const Failure({
    required this.message,
    this.code,
    this.details,
  });
  
  final String message;
  final String? code;
  final Map<String, dynamic>? details;
  
  @override
  List<Object?> get props => [message, code, details];
}

/// BLE related failures
class BleFailure extends Failure {
  const BleFailure({
    required super.message,
    super.code,
    super.details,
  });
}

/// Network/WiFi related failures  
class NetworkFailure extends Failure {
  const NetworkFailure({
    required super.message,
    super.code,
    super.details,
  });
}

/// Cryptography related failures
class CryptoFailure extends Failure {
  const CryptoFailure({
    required super.message,
    super.code,
    super.details,
  });
}

/// QR Code related failures
class QrFailure extends Failure {
  const QrFailure({
    required super.message,
    super.code,
    super.details,
  });
}

/// Device provisioning related failures
class ProvisioningFailure extends Failure {
  const ProvisioningFailure({
    required super.message,
    super.code,
    super.details,
  });
}

/// Permission related failures
class PermissionFailure extends Failure {
  const PermissionFailure({
    required super.message,
    super.code,
    super.details,
  });
}

/// Storage related failures
class StorageFailure extends Failure {
  const StorageFailure({
    required super.message,
    super.code,
    super.details,
  });
}

/// General application failures
class AppFailure extends Failure {
  const AppFailure({
    required super.message,
    super.code,
    super.details,
  });
}