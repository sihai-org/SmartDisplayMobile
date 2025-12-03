/// 本地持久化所使用的 key 统一入口，方便版本升级与清理。
class StorageKeys {
  /// WifiCredentialsRepository：当前用户的 Wi-Fi 凭据字典。
  static const wifiCredentialsBase = 'wifi_credentials_v1';

  /// SavedDevicesRepository：当前用户的已绑定设备列表。
  static const savedDevicesBase = 'saved_devices_v1';

  /// SavedDevicesRepository：当前用户最近一次选中的设备 ID。
  static const savedDevicesLastSelectedBase = 'saved_devices_last_selected_v1';

  /// DeviceCustomizationRepository：当前用户的设备自定义配置。
  static const deviceCustomizationBase = 'device_customization_v1';
}
