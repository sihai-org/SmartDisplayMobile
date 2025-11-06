// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SmartDisplay';

  @override
  String get action_ok => 'OK';

  @override
  String get action_cancel => 'Cancel';

  @override
  String get nav_home => 'Home';

  @override
  String get nav_settings => 'Settings';

  @override
  String get login_title => 'Sign In';

  @override
  String get login_button => 'Log in';

  @override
  String get settings_title => 'Settings';

  @override
  String get app_info => 'App Info';

  @override
  String get app_name => 'App Name';

  @override
  String get version => 'Version';

  @override
  String get language => 'Language';

  @override
  String get language_system => 'Follow System';

  @override
  String get language_zh => 'Chinese';

  @override
  String get language_en => 'English';

  @override
  String get bluetooth_settings => 'Bluetooth Settings';

  @override
  String get manage_bluetooth => 'Manage Bluetooth connection and permissions';

  @override
  String get camera_permission => 'Camera Permission';

  @override
  String get manage_qr_permission => 'Manage QR scanning permission';

  @override
  String get about => 'About';

  @override
  String get help => 'Help';

  @override
  String get help_desc => 'View guide and FAQs';

  @override
  String get feedback => 'Feedback';

  @override
  String get feedback_desc => 'Report issues or suggestions';

  @override
  String get account_security => 'Account & Security';

  @override
  String get delete_account => 'Delete Account';

  @override
  String get profile_title => 'Profile';

  @override
  String get logout => 'Sign out';

  @override
  String get page_not_found => 'Page Not Found';

  @override
  String page_not_exist(Object path) {
    return 'Requested page does not exist: $path';
  }

  @override
  String get back_to_home => 'Back to Home';

  @override
  String get splash_loading => 'Loading...';

  @override
  String get splash_title => 'Hello';

  @override
  String get splash_subtitle => 'Datou SmartDisplay';

  @override
  String get login_email => 'Email';

  @override
  String get login_password => 'Password';

  @override
  String login_failed(Object error) {
    return 'Sign in failed: $error';
  }

  @override
  String get home_title => 'Home';

  @override
  String get devices_title => 'Devices';

  @override
  String get device_management => 'Switch Device';

  @override
  String get device_details => 'Device Details';

  @override
  String get current_device => 'Current Device';

  @override
  String get connect => 'Connect';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get scan_qr => 'Scan QR';

  @override
  String get provision => 'Provision';

  @override
  String get wifi_selection => 'Wi‑Fi Selection';

  @override
  String get qr_scanner_title => 'QR Scanner';

  @override
  String get no_data => 'No data';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get sending_otp => 'Sending verification code...';

  @override
  String otp_sent_to(Object email) {
    return 'Verification code sent to $email';
  }

  @override
  String send_failed(Object error) {
    return 'Send failed: $error';
  }

  @override
  String get signing_in => 'Signing in, please wait...';

  @override
  String get login_success => 'Signed in successfully';

  @override
  String get otp_invalid => 'Invalid code, please retry';

  @override
  String get email_signin => 'Email Sign In';

  @override
  String get email_invalid => 'Please enter a valid email';

  @override
  String get otp_code => 'Verification Code';

  @override
  String resend_in(Object seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get send_otp => 'Send Code';

  @override
  String get signin_with_google => 'Sign in with Google';

  @override
  String signout_failed(Object error) {
    return 'Sign out failed: $error';
  }

  @override
  String get google_signin_placeholder => 'Coming soon';

  @override
  String get login_expired => 'Login session expired';

  @override
  String get welcome_title => 'Welcome to SmartDisplay';

  @override
  String get welcome_hint => 'Scan the QR code on the display to provision Wi‑Fi';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get add_device => 'Add Device';

  @override
  String get wifi_not_connected => 'Device not connected to network. Select a Wi‑Fi to provision:';

  @override
  String get wifi_status_unknown => 'Unable to get network status. Showing available Wi‑Fi networks:';

  @override
  String get unknown_network => 'Unknown';

  @override
  String get band => 'Band';

  @override
  String get no_wifi_found => 'No Wi‑Fi networks found';

  @override
  String get scan_networks => 'Scan Networks';

  @override
  String get refresh_networks => 'Refresh Networks';

  @override
  String get enter_wifi_password => 'Enter Wi‑Fi password:';

  @override
  String get wifi_password_optional => 'Wi‑Fi password (leave empty for open network):';

  @override
  String get enter_password => 'Enter password';

  @override
  String get leave_empty_if_open => 'Leave empty if open';

  @override
  String get secure_network_need_password => 'Secure network detected; password required';

  @override
  String get open_network_may_need_password => 'Open network detected; enter password if required';

  @override
  String get signal_strength => 'Signal strength';

  @override
  String connecting_to(Object ssid) {
    return 'Connecting to $ssid...';
  }

  @override
  String wifi_credentials_sent(Object ssid) {
    return 'Wi‑Fi credentials sent to TV: $ssid';
  }

  @override
  String get wifi_credentials_failed => 'Failed to send Wi‑Fi credentials';

  @override
  String connect_failed(Object error) {
    return 'Connect failed: $error';
  }

  @override
  String get unknown_device => 'Unknown Device';

  @override
  String get current_selected => 'Selected';

  @override
  String get set_current_device => 'Set as current';

  @override
  String get check_update => 'Check Update';

  @override
  String get delete_device => 'Delete Device';

  @override
  String get device_id_label => 'ID';

  @override
  String get ble_label => 'BLE';

  @override
  String get last_connected_at => 'Last connected';

  @override
  String get empty_saved_devices => 'No saved devices';

  @override
  String get empty_hint_add_by_scan => 'Scan the QR on your device to add a new SmartDisplay';

  @override
  String get scan_qr_add_device => 'Scan QR to add device';

  @override
  String get device_switched => 'Switched to current device';

  @override
  String switch_device_failed(Object error) {
    return 'Failed to switch device: $error';
  }

  @override
  String get missing_ble_params => 'Missing Bluetooth parameters. Please rescan the device first.';

  @override
  String get no_device_title => 'No device added yet';

  @override
  String get no_device_subtitle => 'Power on the display, then scan the QR code shown to add a device';

  @override
  String get dark_env_hint => 'Try to scan under better lighting';

  @override
  String get turn_on => 'Turn on flashlight';

  @override
  String get user_fallback => 'Anonymous user';

  @override
  String devices_count(Object count) {
    return 'You have $count devices';
  }

  @override
  String get logout_confirm_title => 'Confirm logout';

  @override
  String get logout_confirm_ok => 'Logout';

  @override
  String get qr_content_title => 'QR Content';

  @override
  String get qr_unrecognized_hint => 'Unrecognized device QR. Raw content:';

  @override
  String get copied_to_clipboard => 'Copied to clipboard';

  @override
  String get copy_text => 'Copy Text';

  @override
  String get ble_disconnected_ephemeral => 'Disconnected BLE from unbound device';

  @override
  String get connect_success => 'Connected successfully';

  @override
  String get connect_failed_retry => 'Connection failed, please retry';

  @override
  String get device_bound_elsewhere => 'The user bound to the device does not match with you';

  @override
  String get connect_failed_move_closer => 'Connection failed, move closer and retry';

  @override
  String get error_title => 'Error';

  @override
  String get no_device_data_message => 'No device data found. Please rescan the QR code.';

  @override
  String get rescan => 'Rescan';

  @override
  String get connect_device_title => 'Connect Device';

  @override
  String get ble_connecting => 'Connecting via Bluetooth...';

  @override
  String get provision_success => 'Provisioning successful. Device is online';

  @override
  String selected_network(Object ssid) {
    return 'Selected network: $ssid';
  }

  @override
  String get manual_wifi_entry_title => 'Or enter Wi‑Fi info manually';

  @override
  String get wifi_name_label => 'Wi‑Fi Name (SSID)';

  @override
  String get wifi_password_label => 'Wi‑Fi Password';

  @override
  String get please_enter_wifi_name => 'Please enter Wi‑Fi name';

  @override
  String get provision_request_failed => 'Failed to send provisioning request';

  @override
  String get send_provision_request => 'Send Provisioning Request';

  @override
  String get provisioning_please_wait => 'Provisioning, please wait…';

  @override
  String get bind_device_title => 'Bind Device';

  @override
  String get no_device_info_message => 'No device info found. Please go back and rescan';

  @override
  String get back_to_scan => 'Back to Scan';

  @override
  String get confirm_binding_title => 'Confirm Binding';

  @override
  String get confirm_binding_question => 'Bind this device to your account?';

  @override
  String get bind_button => 'Bind';

  @override
  String fetch_otp_failed(Object error) {
    return 'Failed to fetch authorization code: $error';
  }

  @override
  String get otp_empty => 'Authorization code is empty';

  @override
  String get bind_failed => 'Binding failed';

  @override
  String get bind_success => 'Binding successful';

  @override
  String bind_failed_error(Object error) {
    return 'Binding failed: $error';
  }

  @override
  String get firmware_version_label => 'Firmware Version';

  @override
  String get manage_network => 'Manage Network';

  @override
  String get refresh => 'Refresh';

  @override
  String get confirm_delete_device => 'Are you sure you want to delete this device?';

  @override
  String get device_name_label => 'Device Name';

  @override
  String get delete_consequence_hint => 'After deletion, auto-connection will be disabled. You will need to rescan the QR code to add it again.';

  @override
  String get delete_success => 'Device deleted successfully';

  @override
  String get delete_failed => 'Failed to delete device';

  @override
  String delete_failed_error(Object error) {
    return 'Failed to delete device: $error';
  }

  @override
  String get ble_connected_text => 'Bluetooth connected';

  @override
  String get ble_connecting_text => 'Bluetooth connecting';

  @override
  String get ble_disconnected_text => 'Bluetooth not connected';

  @override
  String get relative_just_now => 'Just now';

  @override
  String relative_minutes_ago(Object count) {
    return '$count minutes ago';
  }

  @override
  String relative_hours_ago(Object count) {
    return '$count hours ago';
  }

  @override
  String relative_days_ago(Object count) {
    return '$count days ago';
  }

  @override
  String get sync_devices_in_progress => 'Syncing devices…';

  @override
  String get sync_devices_success => 'Devices synced';

  @override
  String get sync_devices_failed => 'Failed to sync devices';

  @override
  String get update_started => 'Device update started. Keep power and network on';

  @override
  String get already_latest_version => 'Already on the latest version';

  @override
  String get check_update_failed_retry => 'Check for update failed, please try again later';

  @override
  String check_update_failed_error(Object error) {
    return 'Check for update failed: $error';
  }

  @override
  String nearby_networks_count(Object count) {
    return 'Nearby networks ($count)';
  }

  @override
  String get no_scan_results_hint => 'No results yet. Tap refresh at top right.';

  @override
  String get last_updated => 'Last updated';

  @override
  String get network_not_connected => 'Network not connected';
}
