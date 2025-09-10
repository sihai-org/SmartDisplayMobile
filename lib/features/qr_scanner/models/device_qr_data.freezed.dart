// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_qr_data.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

DeviceQrData _$DeviceQrDataFromJson(Map<String, dynamic> json) {
  return _DeviceQrData.fromJson(json);
}

/// @nodoc
mixin _$DeviceQrData {
  /// 设备ID
  String get deviceId => throw _privateConstructorUsedError;

  /// 设备名称
  String get deviceName => throw _privateConstructorUsedError;

  /// BLE设备MAC地址
  String get bleAddress => throw _privateConstructorUsedError;

  /// 设备公钥（用于加密握手）
  String get publicKey => throw _privateConstructorUsedError;

  /// 设备类型
  String get deviceType => throw _privateConstructorUsedError;

  /// 固件版本
  String? get firmwareVersion => throw _privateConstructorUsedError;

  /// 生成时间戳
  int? get timestamp => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DeviceQrDataCopyWith<DeviceQrData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeviceQrDataCopyWith<$Res> {
  factory $DeviceQrDataCopyWith(
          DeviceQrData value, $Res Function(DeviceQrData) then) =
      _$DeviceQrDataCopyWithImpl<$Res, DeviceQrData>;
  @useResult
  $Res call(
      {String deviceId,
      String deviceName,
      String bleAddress,
      String publicKey,
      String deviceType,
      String? firmwareVersion,
      int? timestamp});
}

/// @nodoc
class _$DeviceQrDataCopyWithImpl<$Res, $Val extends DeviceQrData>
    implements $DeviceQrDataCopyWith<$Res> {
  _$DeviceQrDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? deviceId = null,
    Object? deviceName = null,
    Object? bleAddress = null,
    Object? publicKey = null,
    Object? deviceType = null,
    Object? firmwareVersion = freezed,
    Object? timestamp = freezed,
  }) {
    return _then(_value.copyWith(
      deviceId: null == deviceId
          ? _value.deviceId
          : deviceId // ignore: cast_nullable_to_non_nullable
              as String,
      deviceName: null == deviceName
          ? _value.deviceName
          : deviceName // ignore: cast_nullable_to_non_nullable
              as String,
      bleAddress: null == bleAddress
          ? _value.bleAddress
          : bleAddress // ignore: cast_nullable_to_non_nullable
              as String,
      publicKey: null == publicKey
          ? _value.publicKey
          : publicKey // ignore: cast_nullable_to_non_nullable
              as String,
      deviceType: null == deviceType
          ? _value.deviceType
          : deviceType // ignore: cast_nullable_to_non_nullable
              as String,
      firmwareVersion: freezed == firmwareVersion
          ? _value.firmwareVersion
          : firmwareVersion // ignore: cast_nullable_to_non_nullable
              as String?,
      timestamp: freezed == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DeviceQrDataImplCopyWith<$Res>
    implements $DeviceQrDataCopyWith<$Res> {
  factory _$$DeviceQrDataImplCopyWith(
          _$DeviceQrDataImpl value, $Res Function(_$DeviceQrDataImpl) then) =
      __$$DeviceQrDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String deviceId,
      String deviceName,
      String bleAddress,
      String publicKey,
      String deviceType,
      String? firmwareVersion,
      int? timestamp});
}

/// @nodoc
class __$$DeviceQrDataImplCopyWithImpl<$Res>
    extends _$DeviceQrDataCopyWithImpl<$Res, _$DeviceQrDataImpl>
    implements _$$DeviceQrDataImplCopyWith<$Res> {
  __$$DeviceQrDataImplCopyWithImpl(
      _$DeviceQrDataImpl _value, $Res Function(_$DeviceQrDataImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? deviceId = null,
    Object? deviceName = null,
    Object? bleAddress = null,
    Object? publicKey = null,
    Object? deviceType = null,
    Object? firmwareVersion = freezed,
    Object? timestamp = freezed,
  }) {
    return _then(_$DeviceQrDataImpl(
      deviceId: null == deviceId
          ? _value.deviceId
          : deviceId // ignore: cast_nullable_to_non_nullable
              as String,
      deviceName: null == deviceName
          ? _value.deviceName
          : deviceName // ignore: cast_nullable_to_non_nullable
              as String,
      bleAddress: null == bleAddress
          ? _value.bleAddress
          : bleAddress // ignore: cast_nullable_to_non_nullable
              as String,
      publicKey: null == publicKey
          ? _value.publicKey
          : publicKey // ignore: cast_nullable_to_non_nullable
              as String,
      deviceType: null == deviceType
          ? _value.deviceType
          : deviceType // ignore: cast_nullable_to_non_nullable
              as String,
      firmwareVersion: freezed == firmwareVersion
          ? _value.firmwareVersion
          : firmwareVersion // ignore: cast_nullable_to_non_nullable
              as String?,
      timestamp: freezed == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DeviceQrDataImpl implements _DeviceQrData {
  const _$DeviceQrDataImpl(
      {required this.deviceId,
      required this.deviceName,
      required this.bleAddress,
      required this.publicKey,
      this.deviceType = 'smart_display',
      this.firmwareVersion,
      this.timestamp});

  factory _$DeviceQrDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$DeviceQrDataImplFromJson(json);

  /// 设备ID
  @override
  final String deviceId;

  /// 设备名称
  @override
  final String deviceName;

  /// BLE设备MAC地址
  @override
  final String bleAddress;

  /// 设备公钥（用于加密握手）
  @override
  final String publicKey;

  /// 设备类型
  @override
  @JsonKey()
  final String deviceType;

  /// 固件版本
  @override
  final String? firmwareVersion;

  /// 生成时间戳
  @override
  final int? timestamp;

  @override
  String toString() {
    return 'DeviceQrData(deviceId: $deviceId, deviceName: $deviceName, bleAddress: $bleAddress, publicKey: $publicKey, deviceType: $deviceType, firmwareVersion: $firmwareVersion, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceQrDataImpl &&
            (identical(other.deviceId, deviceId) ||
                other.deviceId == deviceId) &&
            (identical(other.deviceName, deviceName) ||
                other.deviceName == deviceName) &&
            (identical(other.bleAddress, bleAddress) ||
                other.bleAddress == bleAddress) &&
            (identical(other.publicKey, publicKey) ||
                other.publicKey == publicKey) &&
            (identical(other.deviceType, deviceType) ||
                other.deviceType == deviceType) &&
            (identical(other.firmwareVersion, firmwareVersion) ||
                other.firmwareVersion == firmwareVersion) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, deviceId, deviceName, bleAddress,
      publicKey, deviceType, firmwareVersion, timestamp);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DeviceQrDataImplCopyWith<_$DeviceQrDataImpl> get copyWith =>
      __$$DeviceQrDataImplCopyWithImpl<_$DeviceQrDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DeviceQrDataImplToJson(
      this,
    );
  }
}

abstract class _DeviceQrData implements DeviceQrData {
  const factory _DeviceQrData(
      {required final String deviceId,
      required final String deviceName,
      required final String bleAddress,
      required final String publicKey,
      final String deviceType,
      final String? firmwareVersion,
      final int? timestamp}) = _$DeviceQrDataImpl;

  factory _DeviceQrData.fromJson(Map<String, dynamic> json) =
      _$DeviceQrDataImpl.fromJson;

  @override

  /// 设备ID
  String get deviceId;
  @override

  /// 设备名称
  String get deviceName;
  @override

  /// BLE设备MAC地址
  String get bleAddress;
  @override

  /// 设备公钥（用于加密握手）
  String get publicKey;
  @override

  /// 设备类型
  String get deviceType;
  @override

  /// 固件版本
  String? get firmwareVersion;
  @override

  /// 生成时间戳
  int? get timestamp;
  @override
  @JsonKey(ignore: true)
  _$$DeviceQrDataImplCopyWith<_$DeviceQrDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$QrScanResult {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(DeviceQrData deviceData) success,
    required TResult Function(String message) error,
    required TResult Function() cancelled,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(DeviceQrData deviceData)? success,
    TResult? Function(String message)? error,
    TResult? Function()? cancelled,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(DeviceQrData deviceData)? success,
    TResult Function(String message)? error,
    TResult Function()? cancelled,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Success value) success,
    required TResult Function(_Error value) error,
    required TResult Function(_Cancelled value) cancelled,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Success value)? success,
    TResult? Function(_Error value)? error,
    TResult? Function(_Cancelled value)? cancelled,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Success value)? success,
    TResult Function(_Error value)? error,
    TResult Function(_Cancelled value)? cancelled,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $QrScanResultCopyWith<$Res> {
  factory $QrScanResultCopyWith(
          QrScanResult value, $Res Function(QrScanResult) then) =
      _$QrScanResultCopyWithImpl<$Res, QrScanResult>;
}

/// @nodoc
class _$QrScanResultCopyWithImpl<$Res, $Val extends QrScanResult>
    implements $QrScanResultCopyWith<$Res> {
  _$QrScanResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$SuccessImplCopyWith<$Res> {
  factory _$$SuccessImplCopyWith(
          _$SuccessImpl value, $Res Function(_$SuccessImpl) then) =
      __$$SuccessImplCopyWithImpl<$Res>;
  @useResult
  $Res call({DeviceQrData deviceData});

  $DeviceQrDataCopyWith<$Res> get deviceData;
}

/// @nodoc
class __$$SuccessImplCopyWithImpl<$Res>
    extends _$QrScanResultCopyWithImpl<$Res, _$SuccessImpl>
    implements _$$SuccessImplCopyWith<$Res> {
  __$$SuccessImplCopyWithImpl(
      _$SuccessImpl _value, $Res Function(_$SuccessImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? deviceData = null,
  }) {
    return _then(_$SuccessImpl(
      null == deviceData
          ? _value.deviceData
          : deviceData // ignore: cast_nullable_to_non_nullable
              as DeviceQrData,
    ));
  }

  @override
  @pragma('vm:prefer-inline')
  $DeviceQrDataCopyWith<$Res> get deviceData {
    return $DeviceQrDataCopyWith<$Res>(_value.deviceData, (value) {
      return _then(_value.copyWith(deviceData: value));
    });
  }
}

/// @nodoc

class _$SuccessImpl implements _Success {
  const _$SuccessImpl(this.deviceData);

  @override
  final DeviceQrData deviceData;

  @override
  String toString() {
    return 'QrScanResult.success(deviceData: $deviceData)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SuccessImpl &&
            (identical(other.deviceData, deviceData) ||
                other.deviceData == deviceData));
  }

  @override
  int get hashCode => Object.hash(runtimeType, deviceData);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SuccessImplCopyWith<_$SuccessImpl> get copyWith =>
      __$$SuccessImplCopyWithImpl<_$SuccessImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(DeviceQrData deviceData) success,
    required TResult Function(String message) error,
    required TResult Function() cancelled,
  }) {
    return success(deviceData);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(DeviceQrData deviceData)? success,
    TResult? Function(String message)? error,
    TResult? Function()? cancelled,
  }) {
    return success?.call(deviceData);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(DeviceQrData deviceData)? success,
    TResult Function(String message)? error,
    TResult Function()? cancelled,
    required TResult orElse(),
  }) {
    if (success != null) {
      return success(deviceData);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Success value) success,
    required TResult Function(_Error value) error,
    required TResult Function(_Cancelled value) cancelled,
  }) {
    return success(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Success value)? success,
    TResult? Function(_Error value)? error,
    TResult? Function(_Cancelled value)? cancelled,
  }) {
    return success?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Success value)? success,
    TResult Function(_Error value)? error,
    TResult Function(_Cancelled value)? cancelled,
    required TResult orElse(),
  }) {
    if (success != null) {
      return success(this);
    }
    return orElse();
  }
}

abstract class _Success implements QrScanResult {
  const factory _Success(final DeviceQrData deviceData) = _$SuccessImpl;

  DeviceQrData get deviceData;
  @JsonKey(ignore: true)
  _$$SuccessImplCopyWith<_$SuccessImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ErrorImplCopyWith<$Res> {
  factory _$$ErrorImplCopyWith(
          _$ErrorImpl value, $Res Function(_$ErrorImpl) then) =
      __$$ErrorImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$$ErrorImplCopyWithImpl<$Res>
    extends _$QrScanResultCopyWithImpl<$Res, _$ErrorImpl>
    implements _$$ErrorImplCopyWith<$Res> {
  __$$ErrorImplCopyWithImpl(
      _$ErrorImpl _value, $Res Function(_$ErrorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? message = null,
  }) {
    return _then(_$ErrorImpl(
      null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$ErrorImpl implements _Error {
  const _$ErrorImpl(this.message);

  @override
  final String message;

  @override
  String toString() {
    return 'QrScanResult.error(message: $message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ErrorImpl &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ErrorImplCopyWith<_$ErrorImpl> get copyWith =>
      __$$ErrorImplCopyWithImpl<_$ErrorImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(DeviceQrData deviceData) success,
    required TResult Function(String message) error,
    required TResult Function() cancelled,
  }) {
    return error(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(DeviceQrData deviceData)? success,
    TResult? Function(String message)? error,
    TResult? Function()? cancelled,
  }) {
    return error?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(DeviceQrData deviceData)? success,
    TResult Function(String message)? error,
    TResult Function()? cancelled,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(message);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Success value) success,
    required TResult Function(_Error value) error,
    required TResult Function(_Cancelled value) cancelled,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Success value)? success,
    TResult? Function(_Error value)? error,
    TResult? Function(_Cancelled value)? cancelled,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Success value)? success,
    TResult Function(_Error value)? error,
    TResult Function(_Cancelled value)? cancelled,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class _Error implements QrScanResult {
  const factory _Error(final String message) = _$ErrorImpl;

  String get message;
  @JsonKey(ignore: true)
  _$$ErrorImplCopyWith<_$ErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$CancelledImplCopyWith<$Res> {
  factory _$$CancelledImplCopyWith(
          _$CancelledImpl value, $Res Function(_$CancelledImpl) then) =
      __$$CancelledImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$CancelledImplCopyWithImpl<$Res>
    extends _$QrScanResultCopyWithImpl<$Res, _$CancelledImpl>
    implements _$$CancelledImplCopyWith<$Res> {
  __$$CancelledImplCopyWithImpl(
      _$CancelledImpl _value, $Res Function(_$CancelledImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$CancelledImpl implements _Cancelled {
  const _$CancelledImpl();

  @override
  String toString() {
    return 'QrScanResult.cancelled()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$CancelledImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(DeviceQrData deviceData) success,
    required TResult Function(String message) error,
    required TResult Function() cancelled,
  }) {
    return cancelled();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(DeviceQrData deviceData)? success,
    TResult? Function(String message)? error,
    TResult? Function()? cancelled,
  }) {
    return cancelled?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(DeviceQrData deviceData)? success,
    TResult Function(String message)? error,
    TResult Function()? cancelled,
    required TResult orElse(),
  }) {
    if (cancelled != null) {
      return cancelled();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Success value) success,
    required TResult Function(_Error value) error,
    required TResult Function(_Cancelled value) cancelled,
  }) {
    return cancelled(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Success value)? success,
    TResult? Function(_Error value)? error,
    TResult? Function(_Cancelled value)? cancelled,
  }) {
    return cancelled?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Success value)? success,
    TResult Function(_Error value)? error,
    TResult Function(_Cancelled value)? cancelled,
    required TResult orElse(),
  }) {
    if (cancelled != null) {
      return cancelled(this);
    }
    return orElse();
  }
}

abstract class _Cancelled implements QrScanResult {
  const factory _Cancelled() = _$CancelledImpl;
}
