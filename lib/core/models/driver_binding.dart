/// 龙虾驱动绑定记录（本地缓存）。
class DriverBinding {
  final String driverHwId;
  final String deviceId;
  final String? deviceName;
  final DateTime boundAt;

  const DriverBinding({
    required this.driverHwId,
    required this.deviceId,
    this.deviceName,
    required this.boundAt,
  });

  DriverBinding copyWith({
    String? driverHwId,
    String? deviceId,
    String? deviceName,
    DateTime? boundAt,
  }) => DriverBinding(
    driverHwId: driverHwId ?? this.driverHwId,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    boundAt: boundAt ?? this.boundAt,
  );

  Map<String, dynamic> toJson() => {
    'driver_hw_id': driverHwId,
    'device_id': deviceId,
    'device_name': deviceName,
    'bound_at': boundAt.toIso8601String(),
  };

  static DriverBinding fromJson(Map<String, dynamic> json) => DriverBinding(
    driverHwId: json['driver_hw_id'] as String,
    deviceId: json['device_id'] as String,
    deviceName: json['device_name'] as String?,
    boundAt:
        DateTime.tryParse(json['bound_at'] as String? ?? '') ?? DateTime.now(),
  );
}
