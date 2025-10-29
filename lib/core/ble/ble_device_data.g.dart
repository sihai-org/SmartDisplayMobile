// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ble_device_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$BleDeviceDataImpl _$$BleDeviceDataImplFromJson(Map<String, dynamic> json) =>
    _$BleDeviceDataImpl(
      displayDeviceId: json['displayDeviceId'] as String,
      bleDeviceId: json['bleDeviceId'] as String,
      deviceName: json['deviceName'] as String,
      publicKey: json['publicKey'] as String,
      status: $enumDecodeNullable(_$BleDeviceStatusEnumMap, json['status']) ??
          BleDeviceStatus.disconnected,
      rssi: (json['rssi'] as num?)?.toInt(),
      mtu: (json['mtu'] as num?)?.toInt() ?? 23,
      connectedAt: json['connectedAt'] == null
          ? null
          : DateTime.parse(json['connectedAt'] as String),
      errorMessage: json['errorMessage'] as String?,
    );

Map<String, dynamic> _$$BleDeviceDataImplToJson(_$BleDeviceDataImpl instance) =>
    <String, dynamic>{
      'displayDeviceId': instance.displayDeviceId,
      'bleDeviceId': instance.bleDeviceId,
      'deviceName': instance.deviceName,
      'publicKey': instance.publicKey,
      'status': _$BleDeviceStatusEnumMap[instance.status]!,
      'rssi': instance.rssi,
      'mtu': instance.mtu,
      'connectedAt': instance.connectedAt?.toIso8601String(),
      'errorMessage': instance.errorMessage,
    };

const _$BleDeviceStatusEnumMap = {
  BleDeviceStatus.disconnected: 'disconnected',
  BleDeviceStatus.scanning: 'scanning',
  BleDeviceStatus.connecting: 'connecting',
  BleDeviceStatus.connected: 'connected',
  BleDeviceStatus.authenticating: 'authenticating',
  BleDeviceStatus.authenticated: 'authenticated',
  BleDeviceStatus.error: 'error',
  BleDeviceStatus.timeout: 'timeout',
};
