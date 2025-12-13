// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'network_status.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

NetworkStatus _$NetworkStatusFromJson(Map<String, dynamic> json) {
  return _NetworkStatus.fromJson(json);
}

/// @nodoc
mixin _$NetworkStatus {
  bool get connected => throw _privateConstructorUsedError;
  String? get ssid => throw _privateConstructorUsedError;
  int? get rawRssi => throw _privateConstructorUsedError;

  /// Serializes this NetworkStatus to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of NetworkStatus
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NetworkStatusCopyWith<NetworkStatus> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NetworkStatusCopyWith<$Res> {
  factory $NetworkStatusCopyWith(
          NetworkStatus value, $Res Function(NetworkStatus) then) =
      _$NetworkStatusCopyWithImpl<$Res, NetworkStatus>;
  @useResult
  $Res call({bool connected, String? ssid, int? rawRssi});
}

/// @nodoc
class _$NetworkStatusCopyWithImpl<$Res, $Val extends NetworkStatus>
    implements $NetworkStatusCopyWith<$Res> {
  _$NetworkStatusCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NetworkStatus
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? connected = null,
    Object? ssid = freezed,
    Object? rawRssi = freezed,
  }) {
    return _then(_value.copyWith(
      connected: null == connected
          ? _value.connected
          : connected // ignore: cast_nullable_to_non_nullable
              as bool,
      ssid: freezed == ssid
          ? _value.ssid
          : ssid // ignore: cast_nullable_to_non_nullable
              as String?,
      rawRssi: freezed == rawRssi
          ? _value.rawRssi
          : rawRssi // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$NetworkStatusImplCopyWith<$Res>
    implements $NetworkStatusCopyWith<$Res> {
  factory _$$NetworkStatusImplCopyWith(
          _$NetworkStatusImpl value, $Res Function(_$NetworkStatusImpl) then) =
      __$$NetworkStatusImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({bool connected, String? ssid, int? rawRssi});
}

/// @nodoc
class __$$NetworkStatusImplCopyWithImpl<$Res>
    extends _$NetworkStatusCopyWithImpl<$Res, _$NetworkStatusImpl>
    implements _$$NetworkStatusImplCopyWith<$Res> {
  __$$NetworkStatusImplCopyWithImpl(
      _$NetworkStatusImpl _value, $Res Function(_$NetworkStatusImpl) _then)
      : super(_value, _then);

  /// Create a copy of NetworkStatus
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? connected = null,
    Object? ssid = freezed,
    Object? rawRssi = freezed,
  }) {
    return _then(_$NetworkStatusImpl(
      connected: null == connected
          ? _value.connected
          : connected // ignore: cast_nullable_to_non_nullable
              as bool,
      ssid: freezed == ssid
          ? _value.ssid
          : ssid // ignore: cast_nullable_to_non_nullable
              as String?,
      rawRssi: freezed == rawRssi
          ? _value.rawRssi
          : rawRssi // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$NetworkStatusImpl implements _NetworkStatus {
  const _$NetworkStatusImpl({this.connected = false, this.ssid, this.rawRssi});

  factory _$NetworkStatusImpl.fromJson(Map<String, dynamic> json) =>
      _$$NetworkStatusImplFromJson(json);

  @override
  @JsonKey()
  final bool connected;
  @override
  final String? ssid;
  @override
  final int? rawRssi;

  @override
  String toString() {
    return 'NetworkStatus(connected: $connected, ssid: $ssid, rawRssi: $rawRssi)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NetworkStatusImpl &&
            (identical(other.connected, connected) ||
                other.connected == connected) &&
            (identical(other.ssid, ssid) || other.ssid == ssid) &&
            (identical(other.rawRssi, rawRssi) || other.rawRssi == rawRssi));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, connected, ssid, rawRssi);

  /// Create a copy of NetworkStatus
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NetworkStatusImplCopyWith<_$NetworkStatusImpl> get copyWith =>
      __$$NetworkStatusImplCopyWithImpl<_$NetworkStatusImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$NetworkStatusImplToJson(
      this,
    );
  }
}

abstract class _NetworkStatus implements NetworkStatus {
  const factory _NetworkStatus(
      {final bool connected, final String? ssid, final int? rawRssi}) = _$NetworkStatusImpl;

  factory _NetworkStatus.fromJson(Map<String, dynamic> json) =
      _$NetworkStatusImpl.fromJson;

  @override
  bool get connected;
  @override
  String? get ssid;
  @override
  int? get rawRssi;

  /// Create a copy of NetworkStatus
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NetworkStatusImplCopyWith<_$NetworkStatusImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
