// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_qr_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DeviceQrDataImpl _$$DeviceQrDataImplFromJson(Map<String, dynamic> json) =>
    _$DeviceQrDataImpl(
      timestamp: (json['timestamp'] as num?)?.toInt(),
      displayDeviceId: json['displayDeviceId'] as String,
      bleDeviceId: json['bleDeviceId'] as String,
      deviceName: json['deviceName'] as String,
      publicKey: json['publicKey'] as String,
    );

Map<String, dynamic> _$$DeviceQrDataImplToJson(_$DeviceQrDataImpl instance) =>
    <String, dynamic>{
      'timestamp': instance.timestamp,
      'displayDeviceId': instance.displayDeviceId,
      'bleDeviceId': instance.bleDeviceId,
      'deviceName': instance.deviceName,
      'publicKey': instance.publicKey,
    };
