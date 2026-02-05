import '../constants/enum.dart';

// v1 简单处理
DeviceUpdateVersionResult parseDeviceUpdateResult(dynamic data) {
  if (data is String) {
    switch (data) {
      case 'update_updating':
        return DeviceUpdateVersionResult.updating;
      case 'update_latest':
        return DeviceUpdateVersionResult.latest;
    }
  }
  return DeviceUpdateVersionResult.failed;
}

// v2 细分
DeviceUpdateVersionResult parseDeviceUpdateResultV2(dynamic data) {
  if (data is Map) {
    switch (data["ack"]) {
      case 'ACCEPTED':
        return DeviceUpdateVersionResult.updating;
      case 'ALREADY_IN_FLIGHT':
        return DeviceUpdateVersionResult.alreadyInFlight;
      case 'NO_UPDATE':
        return DeviceUpdateVersionResult.latest;
      case 'OPTIONAL_UPDATE':
        return DeviceUpdateVersionResult.optionalUpdate;
      case 'THROTTLED':
        return DeviceUpdateVersionResult.throttled;
      case 'REJECTED_LOW_STORAGE':
        return DeviceUpdateVersionResult.rejectedLowStorage;
      case 'REJECTED_ERROR':
        return DeviceUpdateVersionResult.failed;
    }
  }

  return DeviceUpdateVersionResult.failed;
}
