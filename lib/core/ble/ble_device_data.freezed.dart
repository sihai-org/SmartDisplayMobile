// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ble_device_data.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

BleDeviceData _$BleDeviceDataFromJson(Map<String, dynamic> json) {
  return _BleDeviceData.fromJson(json);
}

/// @nodoc
mixin _$BleDeviceData {
  /// 业务ID
  String get displayDeviceId => throw _privateConstructorUsedError;

  /// 蓝牙ID
  String get bleDeviceId => throw _privateConstructorUsedError;

  /// 设备名称
  String get deviceName => throw _privateConstructorUsedError;

  /// 设备公钥
  String get publicKey => throw _privateConstructorUsedError;

  /// 连接状态
  BleDeviceStatus get status => throw _privateConstructorUsedError;

  /// RSSI信号强度
  int? get rssi => throw _privateConstructorUsedError;

  /// MTU大小
  int get mtu => throw _privateConstructorUsedError;

  /// 连接时间戳
  DateTime? get connectedAt => throw _privateConstructorUsedError;

  /// 错误信息
  String? get errorMessage => throw _privateConstructorUsedError;

  /// Serializes this BleDeviceData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of BleDeviceData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BleDeviceDataCopyWith<BleDeviceData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BleDeviceDataCopyWith<$Res> {
  factory $BleDeviceDataCopyWith(
          BleDeviceData value, $Res Function(BleDeviceData) then) =
      _$BleDeviceDataCopyWithImpl<$Res, BleDeviceData>;
  @useResult
  $Res call(
      {String displayDeviceId,
      String bleDeviceId,
      String deviceName,
      String publicKey,
      BleDeviceStatus status,
      int? rssi,
      int mtu,
      DateTime? connectedAt,
      String? errorMessage});
}

/// @nodoc
class _$BleDeviceDataCopyWithImpl<$Res, $Val extends BleDeviceData>
    implements $BleDeviceDataCopyWith<$Res> {
  _$BleDeviceDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BleDeviceData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? displayDeviceId = null,
    Object? bleDeviceId = null,
    Object? deviceName = null,
    Object? publicKey = null,
    Object? status = null,
    Object? rssi = freezed,
    Object? mtu = null,
    Object? connectedAt = freezed,
    Object? errorMessage = freezed,
  }) {
    return _then(_value.copyWith(
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
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as BleDeviceStatus,
      rssi: freezed == rssi
          ? _value.rssi
          : rssi // ignore: cast_nullable_to_non_nullable
              as int?,
      mtu: null == mtu
          ? _value.mtu
          : mtu // ignore: cast_nullable_to_non_nullable
              as int,
      connectedAt: freezed == connectedAt
          ? _value.connectedAt
          : connectedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BleDeviceDataImplCopyWith<$Res>
    implements $BleDeviceDataCopyWith<$Res> {
  factory _$$BleDeviceDataImplCopyWith(
          _$BleDeviceDataImpl value, $Res Function(_$BleDeviceDataImpl) then) =
      __$$BleDeviceDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String displayDeviceId,
      String bleDeviceId,
      String deviceName,
      String publicKey,
      BleDeviceStatus status,
      int? rssi,
      int mtu,
      DateTime? connectedAt,
      String? errorMessage});
}

/// @nodoc
class __$$BleDeviceDataImplCopyWithImpl<$Res>
    extends _$BleDeviceDataCopyWithImpl<$Res, _$BleDeviceDataImpl>
    implements _$$BleDeviceDataImplCopyWith<$Res> {
  __$$BleDeviceDataImplCopyWithImpl(
      _$BleDeviceDataImpl _value, $Res Function(_$BleDeviceDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of BleDeviceData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? displayDeviceId = null,
    Object? bleDeviceId = null,
    Object? deviceName = null,
    Object? publicKey = null,
    Object? status = null,
    Object? rssi = freezed,
    Object? mtu = null,
    Object? connectedAt = freezed,
    Object? errorMessage = freezed,
  }) {
    return _then(_$BleDeviceDataImpl(
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
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as BleDeviceStatus,
      rssi: freezed == rssi
          ? _value.rssi
          : rssi // ignore: cast_nullable_to_non_nullable
              as int?,
      mtu: null == mtu
          ? _value.mtu
          : mtu // ignore: cast_nullable_to_non_nullable
              as int,
      connectedAt: freezed == connectedAt
          ? _value.connectedAt
          : connectedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BleDeviceDataImpl implements _BleDeviceData {
  const _$BleDeviceDataImpl(
      {required this.displayDeviceId,
      required this.bleDeviceId,
      required this.deviceName,
      required this.publicKey,
      this.status = BleDeviceStatus.disconnected,
      this.rssi,
      this.mtu = 23,
      this.connectedAt,
      this.errorMessage});

  factory _$BleDeviceDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$BleDeviceDataImplFromJson(json);

  /// 业务ID
  @override
  final String displayDeviceId;

  /// 蓝牙ID
  @override
  final String bleDeviceId;

  /// 设备名称
  @override
  final String deviceName;

  /// 设备公钥
  @override
  final String publicKey;

  /// 连接状态
  @override
  @JsonKey()
  final BleDeviceStatus status;

  /// RSSI信号强度
  @override
  final int? rssi;

  /// MTU大小
  @override
  @JsonKey()
  final int mtu;

  /// 连接时间戳
  @override
  final DateTime? connectedAt;

  /// 错误信息
  @override
  final String? errorMessage;

  @override
  String toString() {
    return 'BleDeviceData(displayDeviceId: $displayDeviceId, bleDeviceId: $bleDeviceId, deviceName: $deviceName, publicKey: $publicKey, status: $status, rssi: $rssi, mtu: $mtu, connectedAt: $connectedAt, errorMessage: $errorMessage)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BleDeviceDataImpl &&
            (identical(other.displayDeviceId, displayDeviceId) ||
                other.displayDeviceId == displayDeviceId) &&
            (identical(other.bleDeviceId, bleDeviceId) ||
                other.bleDeviceId == bleDeviceId) &&
            (identical(other.deviceName, deviceName) ||
                other.deviceName == deviceName) &&
            (identical(other.publicKey, publicKey) ||
                other.publicKey == publicKey) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.rssi, rssi) || other.rssi == rssi) &&
            (identical(other.mtu, mtu) || other.mtu == mtu) &&
            (identical(other.connectedAt, connectedAt) ||
                other.connectedAt == connectedAt) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, displayDeviceId, bleDeviceId,
      deviceName, publicKey, status, rssi, mtu, connectedAt, errorMessage);

  /// Create a copy of BleDeviceData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BleDeviceDataImplCopyWith<_$BleDeviceDataImpl> get copyWith =>
      __$$BleDeviceDataImplCopyWithImpl<_$BleDeviceDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BleDeviceDataImplToJson(
      this,
    );
  }
}

abstract class _BleDeviceData implements BleDeviceData {
  const factory _BleDeviceData(
      {required final String displayDeviceId,
      required final String bleDeviceId,
      required final String deviceName,
      required final String publicKey,
      final BleDeviceStatus status,
      final int? rssi,
      final int mtu,
      final DateTime? connectedAt,
      final String? errorMessage}) = _$BleDeviceDataImpl;

  factory _BleDeviceData.fromJson(Map<String, dynamic> json) =
      _$BleDeviceDataImpl.fromJson;

  /// 业务ID
  @override
  String get displayDeviceId;

  /// 蓝牙ID
  @override
  String get bleDeviceId;

  /// 设备名称
  @override
  String get deviceName;

  /// 设备公钥
  @override
  String get publicKey;

  /// 连接状态
  @override
  BleDeviceStatus get status;

  /// RSSI信号强度
  @override
  int? get rssi;

  /// MTU大小
  @override
  int get mtu;

  /// 连接时间戳
  @override
  DateTime? get connectedAt;

  /// 错误信息
  @override
  String? get errorMessage;

  /// Create a copy of BleDeviceData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BleDeviceDataImplCopyWith<_$BleDeviceDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$BleConnectionResult {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(BleDeviceData device) success,
    required TResult Function(String message) error,
    required TResult Function() timeout,
    required TResult Function() cancelled,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(BleDeviceData device)? success,
    TResult? Function(String message)? error,
    TResult? Function()? timeout,
    TResult? Function()? cancelled,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(BleDeviceData device)? success,
    TResult Function(String message)? error,
    TResult Function()? timeout,
    TResult Function()? cancelled,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Success value) success,
    required TResult Function(_Error value) error,
    required TResult Function(_Timeout value) timeout,
    required TResult Function(_Cancelled value) cancelled,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Success value)? success,
    TResult? Function(_Error value)? error,
    TResult? Function(_Timeout value)? timeout,
    TResult? Function(_Cancelled value)? cancelled,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Success value)? success,
    TResult Function(_Error value)? error,
    TResult Function(_Timeout value)? timeout,
    TResult Function(_Cancelled value)? cancelled,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BleConnectionResultCopyWith<$Res> {
  factory $BleConnectionResultCopyWith(
          BleConnectionResult value, $Res Function(BleConnectionResult) then) =
      _$BleConnectionResultCopyWithImpl<$Res, BleConnectionResult>;
}

/// @nodoc
class _$BleConnectionResultCopyWithImpl<$Res, $Val extends BleConnectionResult>
    implements $BleConnectionResultCopyWith<$Res> {
  _$BleConnectionResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BleConnectionResult
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$SuccessImplCopyWith<$Res> {
  factory _$$SuccessImplCopyWith(
          _$SuccessImpl value, $Res Function(_$SuccessImpl) then) =
      __$$SuccessImplCopyWithImpl<$Res>;
  @useResult
  $Res call({BleDeviceData device});

  $BleDeviceDataCopyWith<$Res> get device;
}

/// @nodoc
class __$$SuccessImplCopyWithImpl<$Res>
    extends _$BleConnectionResultCopyWithImpl<$Res, _$SuccessImpl>
    implements _$$SuccessImplCopyWith<$Res> {
  __$$SuccessImplCopyWithImpl(
      _$SuccessImpl _value, $Res Function(_$SuccessImpl) _then)
      : super(_value, _then);

  /// Create a copy of BleConnectionResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? device = null,
  }) {
    return _then(_$SuccessImpl(
      null == device
          ? _value.device
          : device // ignore: cast_nullable_to_non_nullable
              as BleDeviceData,
    ));
  }

  /// Create a copy of BleConnectionResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $BleDeviceDataCopyWith<$Res> get device {
    return $BleDeviceDataCopyWith<$Res>(_value.device, (value) {
      return _then(_value.copyWith(device: value));
    });
  }
}

/// @nodoc

class _$SuccessImpl implements _Success {
  const _$SuccessImpl(this.device);

  @override
  final BleDeviceData device;

  @override
  String toString() {
    return 'BleConnectionResult.success(device: $device)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SuccessImpl &&
            (identical(other.device, device) || other.device == device));
  }

  @override
  int get hashCode => Object.hash(runtimeType, device);

  /// Create a copy of BleConnectionResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SuccessImplCopyWith<_$SuccessImpl> get copyWith =>
      __$$SuccessImplCopyWithImpl<_$SuccessImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(BleDeviceData device) success,
    required TResult Function(String message) error,
    required TResult Function() timeout,
    required TResult Function() cancelled,
  }) {
    return success(device);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(BleDeviceData device)? success,
    TResult? Function(String message)? error,
    TResult? Function()? timeout,
    TResult? Function()? cancelled,
  }) {
    return success?.call(device);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(BleDeviceData device)? success,
    TResult Function(String message)? error,
    TResult Function()? timeout,
    TResult Function()? cancelled,
    required TResult orElse(),
  }) {
    if (success != null) {
      return success(device);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Success value) success,
    required TResult Function(_Error value) error,
    required TResult Function(_Timeout value) timeout,
    required TResult Function(_Cancelled value) cancelled,
  }) {
    return success(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Success value)? success,
    TResult? Function(_Error value)? error,
    TResult? Function(_Timeout value)? timeout,
    TResult? Function(_Cancelled value)? cancelled,
  }) {
    return success?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Success value)? success,
    TResult Function(_Error value)? error,
    TResult Function(_Timeout value)? timeout,
    TResult Function(_Cancelled value)? cancelled,
    required TResult orElse(),
  }) {
    if (success != null) {
      return success(this);
    }
    return orElse();
  }
}

abstract class _Success implements BleConnectionResult {
  const factory _Success(final BleDeviceData device) = _$SuccessImpl;

  BleDeviceData get device;

  /// Create a copy of BleConnectionResult
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
    extends _$BleConnectionResultCopyWithImpl<$Res, _$ErrorImpl>
    implements _$$ErrorImplCopyWith<$Res> {
  __$$ErrorImplCopyWithImpl(
      _$ErrorImpl _value, $Res Function(_$ErrorImpl) _then)
      : super(_value, _then);

  /// Create a copy of BleConnectionResult
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
    return 'BleConnectionResult.error(message: $message)';
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

  /// Create a copy of BleConnectionResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ErrorImplCopyWith<_$ErrorImpl> get copyWith =>
      __$$ErrorImplCopyWithImpl<_$ErrorImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(BleDeviceData device) success,
    required TResult Function(String message) error,
    required TResult Function() timeout,
    required TResult Function() cancelled,
  }) {
    return error(message);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(BleDeviceData device)? success,
    TResult? Function(String message)? error,
    TResult? Function()? timeout,
    TResult? Function()? cancelled,
  }) {
    return error?.call(message);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(BleDeviceData device)? success,
    TResult Function(String message)? error,
    TResult Function()? timeout,
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
    required TResult Function(_Timeout value) timeout,
    required TResult Function(_Cancelled value) cancelled,
  }) {
    return error(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Success value)? success,
    TResult? Function(_Error value)? error,
    TResult? Function(_Timeout value)? timeout,
    TResult? Function(_Cancelled value)? cancelled,
  }) {
    return error?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Success value)? success,
    TResult Function(_Error value)? error,
    TResult Function(_Timeout value)? timeout,
    TResult Function(_Cancelled value)? cancelled,
    required TResult orElse(),
  }) {
    if (error != null) {
      return error(this);
    }
    return orElse();
  }
}

abstract class _Error implements BleConnectionResult {
  const factory _Error(final String message) = _$ErrorImpl;

  String get message;

  /// Create a copy of BleConnectionResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ErrorImplCopyWith<_$ErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$TimeoutImplCopyWith<$Res> {
  factory _$$TimeoutImplCopyWith(
          _$TimeoutImpl value, $Res Function(_$TimeoutImpl) then) =
      __$$TimeoutImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$TimeoutImplCopyWithImpl<$Res>
    extends _$BleConnectionResultCopyWithImpl<$Res, _$TimeoutImpl>
    implements _$$TimeoutImplCopyWith<$Res> {
  __$$TimeoutImplCopyWithImpl(
      _$TimeoutImpl _value, $Res Function(_$TimeoutImpl) _then)
      : super(_value, _then);

  /// Create a copy of BleConnectionResult
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$TimeoutImpl implements _Timeout {
  const _$TimeoutImpl();

  @override
  String toString() {
    return 'BleConnectionResult.timeout()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$TimeoutImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(BleDeviceData device) success,
    required TResult Function(String message) error,
    required TResult Function() timeout,
    required TResult Function() cancelled,
  }) {
    return timeout();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(BleDeviceData device)? success,
    TResult? Function(String message)? error,
    TResult? Function()? timeout,
    TResult? Function()? cancelled,
  }) {
    return timeout?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(BleDeviceData device)? success,
    TResult Function(String message)? error,
    TResult Function()? timeout,
    TResult Function()? cancelled,
    required TResult orElse(),
  }) {
    if (timeout != null) {
      return timeout();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_Success value) success,
    required TResult Function(_Error value) error,
    required TResult Function(_Timeout value) timeout,
    required TResult Function(_Cancelled value) cancelled,
  }) {
    return timeout(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Success value)? success,
    TResult? Function(_Error value)? error,
    TResult? Function(_Timeout value)? timeout,
    TResult? Function(_Cancelled value)? cancelled,
  }) {
    return timeout?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Success value)? success,
    TResult Function(_Error value)? error,
    TResult Function(_Timeout value)? timeout,
    TResult Function(_Cancelled value)? cancelled,
    required TResult orElse(),
  }) {
    if (timeout != null) {
      return timeout(this);
    }
    return orElse();
  }
}

abstract class _Timeout implements BleConnectionResult {
  const factory _Timeout() = _$TimeoutImpl;
}

/// @nodoc
abstract class _$$CancelledImplCopyWith<$Res> {
  factory _$$CancelledImplCopyWith(
          _$CancelledImpl value, $Res Function(_$CancelledImpl) then) =
      __$$CancelledImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$CancelledImplCopyWithImpl<$Res>
    extends _$BleConnectionResultCopyWithImpl<$Res, _$CancelledImpl>
    implements _$$CancelledImplCopyWith<$Res> {
  __$$CancelledImplCopyWithImpl(
      _$CancelledImpl _value, $Res Function(_$CancelledImpl) _then)
      : super(_value, _then);

  /// Create a copy of BleConnectionResult
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$CancelledImpl implements _Cancelled {
  const _$CancelledImpl();

  @override
  String toString() {
    return 'BleConnectionResult.cancelled()';
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
    required TResult Function(BleDeviceData device) success,
    required TResult Function(String message) error,
    required TResult Function() timeout,
    required TResult Function() cancelled,
  }) {
    return cancelled();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(BleDeviceData device)? success,
    TResult? Function(String message)? error,
    TResult? Function()? timeout,
    TResult? Function()? cancelled,
  }) {
    return cancelled?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(BleDeviceData device)? success,
    TResult Function(String message)? error,
    TResult Function()? timeout,
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
    required TResult Function(_Timeout value) timeout,
    required TResult Function(_Cancelled value) cancelled,
  }) {
    return cancelled(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Success value)? success,
    TResult? Function(_Error value)? error,
    TResult? Function(_Timeout value)? timeout,
    TResult? Function(_Cancelled value)? cancelled,
  }) {
    return cancelled?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Success value)? success,
    TResult Function(_Error value)? error,
    TResult Function(_Timeout value)? timeout,
    TResult Function(_Cancelled value)? cancelled,
    required TResult orElse(),
  }) {
    if (cancelled != null) {
      return cancelled(this);
    }
    return orElse();
  }
}

abstract class _Cancelled implements BleConnectionResult {
  const factory _Cancelled() = _$CancelledImpl;
}

/// @nodoc
mixin _$BleScanResult {
  String get deviceId => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get address => throw _privateConstructorUsedError;
  int get rssi => throw _privateConstructorUsedError;
  DateTime get timestamp => throw _privateConstructorUsedError;
  Map<String, dynamic>? get advertisementData =>
      throw _privateConstructorUsedError;

  /// Create a copy of BleScanResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BleScanResultCopyWith<BleScanResult> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BleScanResultCopyWith<$Res> {
  factory $BleScanResultCopyWith(
          BleScanResult value, $Res Function(BleScanResult) then) =
      _$BleScanResultCopyWithImpl<$Res, BleScanResult>;
  @useResult
  $Res call(
      {String deviceId,
      String name,
      String address,
      int rssi,
      DateTime timestamp,
      Map<String, dynamic>? advertisementData});
}

/// @nodoc
class _$BleScanResultCopyWithImpl<$Res, $Val extends BleScanResult>
    implements $BleScanResultCopyWith<$Res> {
  _$BleScanResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BleScanResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? deviceId = null,
    Object? name = null,
    Object? address = null,
    Object? rssi = null,
    Object? timestamp = null,
    Object? advertisementData = freezed,
  }) {
    return _then(_value.copyWith(
      deviceId: null == deviceId
          ? _value.deviceId
          : deviceId // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      address: null == address
          ? _value.address
          : address // ignore: cast_nullable_to_non_nullable
              as String,
      rssi: null == rssi
          ? _value.rssi
          : rssi // ignore: cast_nullable_to_non_nullable
              as int,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      advertisementData: freezed == advertisementData
          ? _value.advertisementData
          : advertisementData // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BleScanResultImplCopyWith<$Res>
    implements $BleScanResultCopyWith<$Res> {
  factory _$$BleScanResultImplCopyWith(
          _$BleScanResultImpl value, $Res Function(_$BleScanResultImpl) then) =
      __$$BleScanResultImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String deviceId,
      String name,
      String address,
      int rssi,
      DateTime timestamp,
      Map<String, dynamic>? advertisementData});
}

/// @nodoc
class __$$BleScanResultImplCopyWithImpl<$Res>
    extends _$BleScanResultCopyWithImpl<$Res, _$BleScanResultImpl>
    implements _$$BleScanResultImplCopyWith<$Res> {
  __$$BleScanResultImplCopyWithImpl(
      _$BleScanResultImpl _value, $Res Function(_$BleScanResultImpl) _then)
      : super(_value, _then);

  /// Create a copy of BleScanResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? deviceId = null,
    Object? name = null,
    Object? address = null,
    Object? rssi = null,
    Object? timestamp = null,
    Object? advertisementData = freezed,
  }) {
    return _then(_$BleScanResultImpl(
      deviceId: null == deviceId
          ? _value.deviceId
          : deviceId // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      address: null == address
          ? _value.address
          : address // ignore: cast_nullable_to_non_nullable
              as String,
      rssi: null == rssi
          ? _value.rssi
          : rssi // ignore: cast_nullable_to_non_nullable
              as int,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
      advertisementData: freezed == advertisementData
          ? _value._advertisementData
          : advertisementData // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc

class _$BleScanResultImpl implements _BleScanResult {
  const _$BleScanResultImpl(
      {required this.deviceId,
      required this.name,
      required this.address,
      required this.rssi,
      required this.timestamp,
      final Map<String, dynamic>? advertisementData})
      : _advertisementData = advertisementData;

  @override
  final String deviceId;
  @override
  final String name;
  @override
  final String address;
  @override
  final int rssi;
  @override
  final DateTime timestamp;
  final Map<String, dynamic>? _advertisementData;
  @override
  Map<String, dynamic>? get advertisementData {
    final value = _advertisementData;
    if (value == null) return null;
    if (_advertisementData is EqualUnmodifiableMapView)
      return _advertisementData;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'BleScanResult(deviceId: $deviceId, name: $name, address: $address, rssi: $rssi, timestamp: $timestamp, advertisementData: $advertisementData)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BleScanResultImpl &&
            (identical(other.deviceId, deviceId) ||
                other.deviceId == deviceId) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.address, address) || other.address == address) &&
            (identical(other.rssi, rssi) || other.rssi == rssi) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            const DeepCollectionEquality()
                .equals(other._advertisementData, _advertisementData));
  }

  @override
  int get hashCode => Object.hash(runtimeType, deviceId, name, address, rssi,
      timestamp, const DeepCollectionEquality().hash(_advertisementData));

  /// Create a copy of BleScanResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BleScanResultImplCopyWith<_$BleScanResultImpl> get copyWith =>
      __$$BleScanResultImplCopyWithImpl<_$BleScanResultImpl>(this, _$identity);
}

abstract class _BleScanResult implements BleScanResult {
  const factory _BleScanResult(
      {required final String deviceId,
      required final String name,
      required final String address,
      required final int rssi,
      required final DateTime timestamp,
      final Map<String, dynamic>? advertisementData}) = _$BleScanResultImpl;

  @override
  String get deviceId;
  @override
  String get name;
  @override
  String get address;
  @override
  int get rssi;
  @override
  DateTime get timestamp;
  @override
  Map<String, dynamic>? get advertisementData;

  /// Create a copy of BleScanResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BleScanResultImplCopyWith<_$BleScanResultImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$BleServiceInfo {
  String get serviceUuid => throw _privateConstructorUsedError;
  List<BleCharacteristicInfo> get characteristics =>
      throw _privateConstructorUsedError;

  /// Create a copy of BleServiceInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BleServiceInfoCopyWith<BleServiceInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BleServiceInfoCopyWith<$Res> {
  factory $BleServiceInfoCopyWith(
          BleServiceInfo value, $Res Function(BleServiceInfo) then) =
      _$BleServiceInfoCopyWithImpl<$Res, BleServiceInfo>;
  @useResult
  $Res call({String serviceUuid, List<BleCharacteristicInfo> characteristics});
}

/// @nodoc
class _$BleServiceInfoCopyWithImpl<$Res, $Val extends BleServiceInfo>
    implements $BleServiceInfoCopyWith<$Res> {
  _$BleServiceInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BleServiceInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? serviceUuid = null,
    Object? characteristics = null,
  }) {
    return _then(_value.copyWith(
      serviceUuid: null == serviceUuid
          ? _value.serviceUuid
          : serviceUuid // ignore: cast_nullable_to_non_nullable
              as String,
      characteristics: null == characteristics
          ? _value.characteristics
          : characteristics // ignore: cast_nullable_to_non_nullable
              as List<BleCharacteristicInfo>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BleServiceInfoImplCopyWith<$Res>
    implements $BleServiceInfoCopyWith<$Res> {
  factory _$$BleServiceInfoImplCopyWith(_$BleServiceInfoImpl value,
          $Res Function(_$BleServiceInfoImpl) then) =
      __$$BleServiceInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String serviceUuid, List<BleCharacteristicInfo> characteristics});
}

/// @nodoc
class __$$BleServiceInfoImplCopyWithImpl<$Res>
    extends _$BleServiceInfoCopyWithImpl<$Res, _$BleServiceInfoImpl>
    implements _$$BleServiceInfoImplCopyWith<$Res> {
  __$$BleServiceInfoImplCopyWithImpl(
      _$BleServiceInfoImpl _value, $Res Function(_$BleServiceInfoImpl) _then)
      : super(_value, _then);

  /// Create a copy of BleServiceInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? serviceUuid = null,
    Object? characteristics = null,
  }) {
    return _then(_$BleServiceInfoImpl(
      serviceUuid: null == serviceUuid
          ? _value.serviceUuid
          : serviceUuid // ignore: cast_nullable_to_non_nullable
              as String,
      characteristics: null == characteristics
          ? _value._characteristics
          : characteristics // ignore: cast_nullable_to_non_nullable
              as List<BleCharacteristicInfo>,
    ));
  }
}

/// @nodoc

class _$BleServiceInfoImpl implements _BleServiceInfo {
  const _$BleServiceInfoImpl(
      {required this.serviceUuid,
      required final List<BleCharacteristicInfo> characteristics})
      : _characteristics = characteristics;

  @override
  final String serviceUuid;
  final List<BleCharacteristicInfo> _characteristics;
  @override
  List<BleCharacteristicInfo> get characteristics {
    if (_characteristics is EqualUnmodifiableListView) return _characteristics;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_characteristics);
  }

  @override
  String toString() {
    return 'BleServiceInfo(serviceUuid: $serviceUuid, characteristics: $characteristics)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BleServiceInfoImpl &&
            (identical(other.serviceUuid, serviceUuid) ||
                other.serviceUuid == serviceUuid) &&
            const DeepCollectionEquality()
                .equals(other._characteristics, _characteristics));
  }

  @override
  int get hashCode => Object.hash(runtimeType, serviceUuid,
      const DeepCollectionEquality().hash(_characteristics));

  /// Create a copy of BleServiceInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BleServiceInfoImplCopyWith<_$BleServiceInfoImpl> get copyWith =>
      __$$BleServiceInfoImplCopyWithImpl<_$BleServiceInfoImpl>(
          this, _$identity);
}

abstract class _BleServiceInfo implements BleServiceInfo {
  const factory _BleServiceInfo(
          {required final String serviceUuid,
          required final List<BleCharacteristicInfo> characteristics}) =
      _$BleServiceInfoImpl;

  @override
  String get serviceUuid;
  @override
  List<BleCharacteristicInfo> get characteristics;

  /// Create a copy of BleServiceInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BleServiceInfoImplCopyWith<_$BleServiceInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$BleCharacteristicInfo {
  String get characteristicUuid => throw _privateConstructorUsedError;
  bool get canRead => throw _privateConstructorUsedError;
  bool get canWrite => throw _privateConstructorUsedError;
  bool get canNotify => throw _privateConstructorUsedError;
  bool get canIndicate => throw _privateConstructorUsedError;

  /// Create a copy of BleCharacteristicInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BleCharacteristicInfoCopyWith<BleCharacteristicInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BleCharacteristicInfoCopyWith<$Res> {
  factory $BleCharacteristicInfoCopyWith(BleCharacteristicInfo value,
          $Res Function(BleCharacteristicInfo) then) =
      _$BleCharacteristicInfoCopyWithImpl<$Res, BleCharacteristicInfo>;
  @useResult
  $Res call(
      {String characteristicUuid,
      bool canRead,
      bool canWrite,
      bool canNotify,
      bool canIndicate});
}

/// @nodoc
class _$BleCharacteristicInfoCopyWithImpl<$Res,
        $Val extends BleCharacteristicInfo>
    implements $BleCharacteristicInfoCopyWith<$Res> {
  _$BleCharacteristicInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BleCharacteristicInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? characteristicUuid = null,
    Object? canRead = null,
    Object? canWrite = null,
    Object? canNotify = null,
    Object? canIndicate = null,
  }) {
    return _then(_value.copyWith(
      characteristicUuid: null == characteristicUuid
          ? _value.characteristicUuid
          : characteristicUuid // ignore: cast_nullable_to_non_nullable
              as String,
      canRead: null == canRead
          ? _value.canRead
          : canRead // ignore: cast_nullable_to_non_nullable
              as bool,
      canWrite: null == canWrite
          ? _value.canWrite
          : canWrite // ignore: cast_nullable_to_non_nullable
              as bool,
      canNotify: null == canNotify
          ? _value.canNotify
          : canNotify // ignore: cast_nullable_to_non_nullable
              as bool,
      canIndicate: null == canIndicate
          ? _value.canIndicate
          : canIndicate // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BleCharacteristicInfoImplCopyWith<$Res>
    implements $BleCharacteristicInfoCopyWith<$Res> {
  factory _$$BleCharacteristicInfoImplCopyWith(
          _$BleCharacteristicInfoImpl value,
          $Res Function(_$BleCharacteristicInfoImpl) then) =
      __$$BleCharacteristicInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String characteristicUuid,
      bool canRead,
      bool canWrite,
      bool canNotify,
      bool canIndicate});
}

/// @nodoc
class __$$BleCharacteristicInfoImplCopyWithImpl<$Res>
    extends _$BleCharacteristicInfoCopyWithImpl<$Res,
        _$BleCharacteristicInfoImpl>
    implements _$$BleCharacteristicInfoImplCopyWith<$Res> {
  __$$BleCharacteristicInfoImplCopyWithImpl(_$BleCharacteristicInfoImpl _value,
      $Res Function(_$BleCharacteristicInfoImpl) _then)
      : super(_value, _then);

  /// Create a copy of BleCharacteristicInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? characteristicUuid = null,
    Object? canRead = null,
    Object? canWrite = null,
    Object? canNotify = null,
    Object? canIndicate = null,
  }) {
    return _then(_$BleCharacteristicInfoImpl(
      characteristicUuid: null == characteristicUuid
          ? _value.characteristicUuid
          : characteristicUuid // ignore: cast_nullable_to_non_nullable
              as String,
      canRead: null == canRead
          ? _value.canRead
          : canRead // ignore: cast_nullable_to_non_nullable
              as bool,
      canWrite: null == canWrite
          ? _value.canWrite
          : canWrite // ignore: cast_nullable_to_non_nullable
              as bool,
      canNotify: null == canNotify
          ? _value.canNotify
          : canNotify // ignore: cast_nullable_to_non_nullable
              as bool,
      canIndicate: null == canIndicate
          ? _value.canIndicate
          : canIndicate // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc

class _$BleCharacteristicInfoImpl implements _BleCharacteristicInfo {
  const _$BleCharacteristicInfoImpl(
      {required this.characteristicUuid,
      required this.canRead,
      required this.canWrite,
      required this.canNotify,
      required this.canIndicate});

  @override
  final String characteristicUuid;
  @override
  final bool canRead;
  @override
  final bool canWrite;
  @override
  final bool canNotify;
  @override
  final bool canIndicate;

  @override
  String toString() {
    return 'BleCharacteristicInfo(characteristicUuid: $characteristicUuid, canRead: $canRead, canWrite: $canWrite, canNotify: $canNotify, canIndicate: $canIndicate)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BleCharacteristicInfoImpl &&
            (identical(other.characteristicUuid, characteristicUuid) ||
                other.characteristicUuid == characteristicUuid) &&
            (identical(other.canRead, canRead) || other.canRead == canRead) &&
            (identical(other.canWrite, canWrite) ||
                other.canWrite == canWrite) &&
            (identical(other.canNotify, canNotify) ||
                other.canNotify == canNotify) &&
            (identical(other.canIndicate, canIndicate) ||
                other.canIndicate == canIndicate));
  }

  @override
  int get hashCode => Object.hash(runtimeType, characteristicUuid, canRead,
      canWrite, canNotify, canIndicate);

  /// Create a copy of BleCharacteristicInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BleCharacteristicInfoImplCopyWith<_$BleCharacteristicInfoImpl>
      get copyWith => __$$BleCharacteristicInfoImplCopyWithImpl<
          _$BleCharacteristicInfoImpl>(this, _$identity);
}

abstract class _BleCharacteristicInfo implements BleCharacteristicInfo {
  const factory _BleCharacteristicInfo(
      {required final String characteristicUuid,
      required final bool canRead,
      required final bool canWrite,
      required final bool canNotify,
      required final bool canIndicate}) = _$BleCharacteristicInfoImpl;

  @override
  String get characteristicUuid;
  @override
  bool get canRead;
  @override
  bool get canWrite;
  @override
  bool get canNotify;
  @override
  bool get canIndicate;

  /// Create a copy of BleCharacteristicInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BleCharacteristicInfoImplCopyWith<_$BleCharacteristicInfoImpl>
      get copyWith => throw _privateConstructorUsedError;
}
