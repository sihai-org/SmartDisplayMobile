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
  /// 生成时间戳
  int? get timestamp => throw _privateConstructorUsedError;

  /// 业务ID
  String get displayDeviceId => throw _privateConstructorUsedError;

  /// 蓝牙ID
  String get bleDeviceId => throw _privateConstructorUsedError;

  /// 设备名称
  String get deviceName => throw _privateConstructorUsedError;

  /// 设备公钥（用于加密握手）
  String get publicKey => throw _privateConstructorUsedError;

  /// Serializes this DeviceQrData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DeviceQrData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
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
      {int? timestamp,
      String displayDeviceId,
      String bleDeviceId,
      String deviceName,
      String publicKey});
}

/// @nodoc
class _$DeviceQrDataCopyWithImpl<$Res, $Val extends DeviceQrData>
    implements $DeviceQrDataCopyWith<$Res> {
  _$DeviceQrDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DeviceQrData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = freezed,
    Object? displayDeviceId = null,
    Object? bleDeviceId = null,
    Object? deviceName = null,
    Object? publicKey = null,
  }) {
    return _then(_value.copyWith(
      timestamp: freezed == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as int?,
      displayDeviceId: null == displayDeviceId
          ? _value.displayDeviceId
          : displayDeviceId // ignore: cast_nullable_to_non_nullable
              as String,
      bleDeviceId: null == bleDeviceId
          ? _value.bleDeviceId
          : bleDeviceId // ignore: cast_nullable_to_non_nullable
              as String,
      deviceName: null == deviceName
          ? _value.deviceName
          : deviceName // ignore: cast_nullable_to_non_nullable
              as String,
      publicKey: null == publicKey
          ? _value.publicKey
          : publicKey // ignore: cast_nullable_to_non_nullable
              as String,
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
      {int? timestamp,
      String displayDeviceId,
      String bleDeviceId,
      String deviceName,
      String publicKey});
}

/// @nodoc
class __$$DeviceQrDataImplCopyWithImpl<$Res>
    extends _$DeviceQrDataCopyWithImpl<$Res, _$DeviceQrDataImpl>
    implements _$$DeviceQrDataImplCopyWith<$Res> {
  __$$DeviceQrDataImplCopyWithImpl(
      _$DeviceQrDataImpl _value, $Res Function(_$DeviceQrDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of DeviceQrData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = freezed,
    Object? displayDeviceId = null,
    Object? bleDeviceId = null,
    Object? deviceName = null,
    Object? publicKey = null,
  }) {
    return _then(_$DeviceQrDataImpl(
      timestamp: freezed == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as int?,
      displayDeviceId: null == displayDeviceId
          ? _value.displayDeviceId
          : displayDeviceId // ignore: cast_nullable_to_non_nullable
              as String,
      bleDeviceId: null == bleDeviceId
          ? _value.bleDeviceId
          : bleDeviceId // ignore: cast_nullable_to_non_nullable
              as String,
      deviceName: null == deviceName
          ? _value.deviceName
          : deviceName // ignore: cast_nullable_to_non_nullable
              as String,
      publicKey: null == publicKey
          ? _value.publicKey
          : publicKey // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DeviceQrDataImpl implements _DeviceQrData {
  const _$DeviceQrDataImpl(
      {this.timestamp,
      required this.displayDeviceId,
      required this.bleDeviceId,
      required this.deviceName,
      required this.publicKey});

  factory _$DeviceQrDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$DeviceQrDataImplFromJson(json);

  /// 生成时间戳
  @override
  final int? timestamp;

  /// 业务ID
  @override
  final String displayDeviceId;

  /// 蓝牙ID
  @override
  final String bleDeviceId;

  /// 设备名称
  @override
  final String deviceName;

  /// 设备公钥（用于加密握手）
  @override
  final String publicKey;

  @override
  String toString() {
    return 'DeviceQrData(timestamp: $timestamp, displayDeviceId: $displayDeviceId, bleDeviceId: $bleDeviceId, deviceName: $deviceName, publicKey: $publicKey)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceQrDataImpl &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.displayDeviceId, displayDeviceId) ||
                other.displayDeviceId == displayDeviceId) &&
            (identical(other.bleDeviceId, bleDeviceId) ||
                other.bleDeviceId == bleDeviceId) &&
            (identical(other.deviceName, deviceName) ||
                other.deviceName == deviceName) &&
            (identical(other.publicKey, publicKey) ||
                other.publicKey == publicKey));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, timestamp, displayDeviceId,
      bleDeviceId, deviceName, publicKey);

  /// Create a copy of DeviceQrData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
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
      {final int? timestamp,
      required final String displayDeviceId,
      required final String bleDeviceId,
      required final String deviceName,
      required final String publicKey}) = _$DeviceQrDataImpl;

  factory _DeviceQrData.fromJson(Map<String, dynamic> json) =
      _$DeviceQrDataImpl.fromJson;

  /// 生成时间戳
  @override
  int? get timestamp;

  /// 业务ID
  @override
  String get displayDeviceId;

  /// 蓝牙ID
  @override
  String get bleDeviceId;

  /// 设备名称
  @override
  String get deviceName;

  /// 设备公钥（用于加密握手）
  @override
  String get publicKey;

  /// Create a copy of DeviceQrData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
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

  /// Create a copy of QrScanResult
  /// with the given fields replaced by the non-null parameter values.
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

  /// Create a copy of QrScanResult
  /// with the given fields replaced by the non-null parameter values.
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

  /// Create a copy of QrScanResult
  /// with the given fields replaced by the non-null parameter values.
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

  /// Create a copy of QrScanResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
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

  /// Create a copy of QrScanResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
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

  /// Create a copy of QrScanResult
  /// with the given fields replaced by the non-null parameter values.
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

  /// Create a copy of QrScanResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
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

  /// Create a copy of QrScanResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
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

  /// Create a copy of QrScanResult
  /// with the given fields replaced by the non-null parameter values.
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
