// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_qr_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DeviceQrDataImpl _$$DeviceQrDataImplFromJson(Map<String, dynamic> json) =>
    _$DeviceQrDataImpl(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      bleAddress: json['bleAddress'] as String,
      publicKey: json['publicKey'] as String,
      deviceType: json['deviceType'] as String? ?? 'smart_display',
      firmwareVersion: json['firmwareVersion'] as String?,
      timestamp: (json['timestamp'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$DeviceQrDataImplToJson(_$DeviceQrDataImpl instance) =>
    <String, dynamic>{
      'deviceId': instance.deviceId,
      'deviceName': instance.deviceName,
      'bleAddress': instance.bleAddress,
      'publicKey': instance.publicKey,
      'deviceType': instance.deviceType,
      'firmwareVersion': instance.firmwareVersion,
      'timestamp': instance.timestamp,
    };
