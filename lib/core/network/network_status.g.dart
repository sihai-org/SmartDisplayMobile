// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$NetworkStatusImpl _$$NetworkStatusImplFromJson(Map<String, dynamic> json) =>
    _$NetworkStatusImpl(
      connected: json['connected'] as bool? ?? false,
      ssid: json['ssid'] as String?,
      ip: json['ip'] as String?,
      signal: (json['signal'] as num?)?.toInt(),
      frequency: (json['frequency'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$NetworkStatusImplToJson(
        _$NetworkStatusImpl instance) =>
    <String, dynamic>{
      'connected': instance.connected,
      'ssid': instance.ssid,
      'ip': instance.ip,
      'signal': instance.signal,
      'frequency': instance.frequency,
    };

