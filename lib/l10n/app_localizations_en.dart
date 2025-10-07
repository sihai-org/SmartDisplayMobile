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
  String get device_management => 'Device Management';

  @override
  String get device_details => 'Device Details';

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
  String get google_signin_placeholder => 'Google sign-in (not implemented)';

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
  String get connected => 'Connected';

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
}
