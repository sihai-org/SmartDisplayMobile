// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$NetworkStatusImpl _$$NetworkStatusImplFromJson(Map<String, dynamic> json) =>
    _$NetworkStatusImpl(
      connected: json['connected'] as bool? ?? false,
      ssid: json['ssid'] as String?,
      rawRssi: json['rawRssi'] as int?,
    );

Map<String, dynamic> _$$NetworkStatusImplToJson(_$NetworkStatusImpl instance) =>
    <String, dynamic>{
      'connected': instance.connected,
      'ssid': instance.ssid,
      'rawRssi': instance.rawRssi,
    };
