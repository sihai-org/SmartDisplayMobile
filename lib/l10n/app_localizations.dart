import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'VznGPT'**
  String get appTitle;

  /// No description provided for @action_ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get action_ok;

  /// No description provided for @action_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get action_cancel;

  /// No description provided for @nav_home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get nav_home;

  /// No description provided for @nav_settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get nav_settings;

  /// No description provided for @login_title.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get login_title;

  /// No description provided for @login_button.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get login_button;

  /// No description provided for @settings_title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings_title;

  /// No description provided for @app_info.
  ///
  /// In en, this message translates to:
  /// **'App Info'**
  String get app_info;

  /// No description provided for @app_name.
  ///
  /// In en, this message translates to:
  /// **'App Name'**
  String get app_name;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @language_system.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get language_system;

  /// No description provided for @language_zh.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get language_zh;

  /// No description provided for @language_en.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get language_en;

  /// No description provided for @bluetooth_settings.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth Settings'**
  String get bluetooth_settings;

  /// No description provided for @manage_bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Manage Bluetooth connection and permissions'**
  String get manage_bluetooth;

  /// No description provided for @camera_permission.
  ///
  /// In en, this message translates to:
  /// **'Camera Permission'**
  String get camera_permission;

  /// No description provided for @camera_permission_denied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission denied. Please enable it in Settings.'**
  String get camera_permission_denied;

  /// No description provided for @manage_qr_permission.
  ///
  /// In en, this message translates to:
  /// **'Manage QR scanning permission'**
  String get manage_qr_permission;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// No description provided for @help_desc.
  ///
  /// In en, this message translates to:
  /// **'View guide and FAQs'**
  String get help_desc;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// No description provided for @feedback_desc.
  ///
  /// In en, this message translates to:
  /// **'Report issues or suggestions'**
  String get feedback_desc;

  /// No description provided for @account_security.
  ///
  /// In en, this message translates to:
  /// **'Account & Security'**
  String get account_security;

  /// No description provided for @billing_title.
  ///
  /// In en, this message translates to:
  /// **'Billing'**
  String get billing_title;

  /// No description provided for @billing_available_credits.
  ///
  /// In en, this message translates to:
  /// **'Available Credits'**
  String get billing_available_credits;

  /// No description provided for @billing_credits_label.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get billing_credits_label;

  /// No description provided for @billing_recent_activity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get billing_recent_activity;

  /// No description provided for @billing_recent_activity_empty.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get billing_recent_activity_empty;

  /// No description provided for @billing_view_all.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get billing_view_all;

  /// No description provided for @billing_transactions_title.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get billing_transactions_title;

  /// No description provided for @billing_load_failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load billing data. Please try again later.'**
  String get billing_load_failed;

  /// No description provided for @serial_number_stats.
  ///
  /// In en, this message translates to:
  /// **'Serial Number Stats'**
  String get serial_number_stats;

  /// No description provided for @serial_number.
  ///
  /// In en, this message translates to:
  /// **'Serial number'**
  String get serial_number;

  /// No description provided for @positive_integer_hint.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive integer'**
  String get positive_integer_hint;

  /// No description provided for @original_link.
  ///
  /// In en, this message translates to:
  /// **'Original link'**
  String get original_link;

  /// No description provided for @device_name.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get device_name;

  /// No description provided for @device_id.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get device_id;

  /// No description provided for @copy_link.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copy_link;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @reported_success.
  ///
  /// In en, this message translates to:
  /// **'Reported successfully'**
  String get reported_success;

  /// No description provided for @report_failed.
  ///
  /// In en, this message translates to:
  /// **'Report failed. Please try again.'**
  String get report_failed;

  /// No description provided for @reported_mock.
  ///
  /// In en, this message translates to:
  /// **'Reported (mock)'**
  String get reported_mock;

  /// No description provided for @parse_failed.
  ///
  /// In en, this message translates to:
  /// **'Parse failed'**
  String get parse_failed;

  /// No description provided for @delete_account.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get delete_account;

  /// No description provided for @profile_title.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile_title;

  /// No description provided for @meeting_minutes.
  ///
  /// In en, this message translates to:
  /// **'Meeting Minutes'**
  String get meeting_minutes;

  /// No description provided for @meeting_minutes_list.
  ///
  /// In en, this message translates to:
  /// **'Meeting Minutes List'**
  String get meeting_minutes_list;

  /// No description provided for @meeting_minutes_empty.
  ///
  /// In en, this message translates to:
  /// **'No meeting minutes yet'**
  String get meeting_minutes_empty;

  /// No description provided for @meeting_minutes_detail.
  ///
  /// In en, this message translates to:
  /// **'Meeting Minutes Detail'**
  String get meeting_minutes_detail;

  /// No description provided for @meeting_minutes_loading.
  ///
  /// In en, this message translates to:
  /// **'Loading meeting minutes...'**
  String get meeting_minutes_loading;

  /// No description provided for @meeting_minutes_detail_empty.
  ///
  /// In en, this message translates to:
  /// **'No content'**
  String get meeting_minutes_detail_empty;

  /// No description provided for @meeting_minutes_generating.
  ///
  /// In en, this message translates to:
  /// **'Generating meeting minutes...'**
  String get meeting_minutes_generating;

  /// No description provided for @meeting_minutes_failed.
  ///
  /// In en, this message translates to:
  /// **'Generation failed'**
  String get meeting_minutes_failed;

  /// No description provided for @meeting_minutes_mock_title_1.
  ///
  /// In en, this message translates to:
  /// **'Project Weekly Sync Minutes'**
  String get meeting_minutes_mock_title_1;

  /// No description provided for @meeting_minutes_mock_title_2.
  ///
  /// In en, this message translates to:
  /// **'Requirements Review Minutes'**
  String get meeting_minutes_mock_title_2;

  /// No description provided for @meeting_minutes_mock_title_3.
  ///
  /// In en, this message translates to:
  /// **'Customer Feedback Summary'**
  String get meeting_minutes_mock_title_3;

  /// No description provided for @meeting_minutes_mock_content_1.
  ///
  /// In en, this message translates to:
  /// **'# Project Weekly Sync Minutes\n\n## Attendees\n- Product\n- Design\n- Engineering\n\n## Key Takeaways\n1. Prioritize completing the meeting minutes list page.\n2. Finish the detail page API next week.\n\n## To-Do\n- [ ] Review list page styling\n- [ ] API integration'**
  String get meeting_minutes_mock_content_1;

  /// No description provided for @meeting_minutes_mock_content_2.
  ///
  /// In en, this message translates to:
  /// **'# Requirements Review Minutes\n\n## Goals\n- Clarify the release scope\n- Align delivery cadence\n\n## Decisions\n- This release only includes the basic list and detail.\n- Data uses mock.\n\n## Risks\n- Detail content must support Markdown rendering.'**
  String get meeting_minutes_mock_content_2;

  /// No description provided for @meeting_minutes_mock_content_3.
  ///
  /// In en, this message translates to:
  /// **'# Customer Feedback Summary\n\n## Main Issues\n- List item information hierarchy is unclear\n- Detail content readability is average\n\n## Suggestions\n- Align date/time left-right on the second line\n- Bold the title to improve hierarchy'**
  String get meeting_minutes_mock_content_3;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get logout;

  /// No description provided for @page_not_found.
  ///
  /// In en, this message translates to:
  /// **'Page Not Found'**
  String get page_not_found;

  /// No description provided for @page_not_exist.
  ///
  /// In en, this message translates to:
  /// **'Requested page does not exist: {path}'**
  String page_not_exist(Object path);

  /// No description provided for @back_to_home.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get back_to_home;

  /// No description provided for @splash_loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get splash_loading;

  /// No description provided for @splash_title.
  ///
  /// In en, this message translates to:
  /// **'Hello'**
  String get splash_title;

  /// No description provided for @splash_subtitle.
  ///
  /// In en, this message translates to:
  /// **'VznGPT'**
  String get splash_subtitle;

  /// No description provided for @login_email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get login_email;

  /// No description provided for @login_password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get login_password;

  /// No description provided for @login_failed.
  ///
  /// In en, this message translates to:
  /// **'Sign in failed. Please try again.'**
  String get login_failed;

  /// No description provided for @home_title.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home_title;

  /// No description provided for @devices_title.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices_title;

  /// No description provided for @device_management.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get device_management;

  /// No description provided for @device_details.
  ///
  /// In en, this message translates to:
  /// **'Device Details'**
  String get device_details;

  /// No description provided for @current_device.
  ///
  /// In en, this message translates to:
  /// **'Current Device'**
  String get current_device;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @scan_qr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scan_qr;

  /// No description provided for @tap_to_scan.
  ///
  /// In en, this message translates to:
  /// **'Tap to scan'**
  String get tap_to_scan;

  /// No description provided for @provision.
  ///
  /// In en, this message translates to:
  /// **'Provision'**
  String get provision;

  /// No description provided for @wifi_selection.
  ///
  /// In en, this message translates to:
  /// **'Wi‑Fi Selection'**
  String get wifi_selection;

  /// No description provided for @qr_scanner_title.
  ///
  /// In en, this message translates to:
  /// **'QR Scanner'**
  String get qr_scanner_title;

  /// No description provided for @no_data.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get no_data;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @otp_sent_to.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent to {email}'**
  String otp_sent_to(Object email);

  /// No description provided for @login_success.
  ///
  /// In en, this message translates to:
  /// **'Signed in successfully'**
  String get login_success;

  /// No description provided for @otp_invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid code, please retry'**
  String get otp_invalid;

  /// No description provided for @login_failed_generic.
  ///
  /// In en, this message translates to:
  /// **'Sign in failed. Please try again later.'**
  String get login_failed_generic;

  /// No description provided for @login_failed_otp_invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid code, please retry'**
  String get login_failed_otp_invalid;

  /// No description provided for @login_failed_otp_expired.
  ///
  /// In en, this message translates to:
  /// **'Invalid or expired code. Please try again.'**
  String get login_failed_otp_expired;

  /// No description provided for @login_failed_rate_limited.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later.'**
  String get login_failed_rate_limited;

  /// No description provided for @email_signin.
  ///
  /// In en, this message translates to:
  /// **'Sign in with email'**
  String get email_signin;

  /// No description provided for @otp_code.
  ///
  /// In en, this message translates to:
  /// **'Verification Code'**
  String get otp_code;

  /// No description provided for @otp_spam_hint.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t receive the code? Please check Spam or Promotions.'**
  String get otp_spam_hint;

  /// No description provided for @resend_in.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String resend_in(Object seconds);

  /// No description provided for @send_otp.
  ///
  /// In en, this message translates to:
  /// **'Send Code'**
  String get send_otp;

  /// No description provided for @signout_failed.
  ///
  /// In en, this message translates to:
  /// **'Sign out failed. Please try again.'**
  String get signout_failed;

  /// No description provided for @google_signin_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get google_signin_placeholder;

  /// No description provided for @audit_mode_enabled.
  ///
  /// In en, this message translates to:
  /// **'Audit mode enabled'**
  String get audit_mode_enabled;

  /// No description provided for @login_expired.
  ///
  /// In en, this message translates to:
  /// **'Login session expired'**
  String get login_expired;

  /// No description provided for @welcome_title.
  ///
  /// In en, this message translates to:
  /// **'Welcome to VznGPT'**
  String get welcome_title;

  /// No description provided for @welcome_hint.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR code on the display to provision Wi‑Fi'**
  String get welcome_hint;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @add_device.
  ///
  /// In en, this message translates to:
  /// **'Add Device'**
  String get add_device;

  /// No description provided for @wifi_not_connected.
  ///
  /// In en, this message translates to:
  /// **'Device not connected to network. Select a Wi‑Fi to provision:'**
  String get wifi_not_connected;

  /// No description provided for @wifi_status_unknown.
  ///
  /// In en, this message translates to:
  /// **'Unable to get network status. Showing available Wi‑Fi networks:'**
  String get wifi_status_unknown;

  /// No description provided for @network_status_loading.
  ///
  /// In en, this message translates to:
  /// **'Fetching network status…'**
  String get network_status_loading;

  /// No description provided for @unknown_network.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown_network;

  /// No description provided for @band.
  ///
  /// In en, this message translates to:
  /// **'Band'**
  String get band;

  /// No description provided for @no_wifi_found.
  ///
  /// In en, this message translates to:
  /// **'No Wi‑Fi networks found'**
  String get no_wifi_found;

  /// No description provided for @scan_networks.
  ///
  /// In en, this message translates to:
  /// **'Scan Networks'**
  String get scan_networks;

  /// No description provided for @refresh_networks.
  ///
  /// In en, this message translates to:
  /// **'Refresh Networks'**
  String get refresh_networks;

  /// No description provided for @enter_wifi_password.
  ///
  /// In en, this message translates to:
  /// **'Enter Wi‑Fi password:'**
  String get enter_wifi_password;

  /// No description provided for @wifi_password_optional.
  ///
  /// In en, this message translates to:
  /// **'Wi‑Fi password (leave empty for open network):'**
  String get wifi_password_optional;

  /// No description provided for @enter_password.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get enter_password;

  /// No description provided for @leave_empty_if_open.
  ///
  /// In en, this message translates to:
  /// **'Leave empty if open'**
  String get leave_empty_if_open;

  /// No description provided for @secure_network_need_password.
  ///
  /// In en, this message translates to:
  /// **'Secure network detected; password required'**
  String get secure_network_need_password;

  /// No description provided for @open_network_may_need_password.
  ///
  /// In en, this message translates to:
  /// **'Open network detected; enter password if required'**
  String get open_network_may_need_password;

  /// No description provided for @signal_strength.
  ///
  /// In en, this message translates to:
  /// **'Signal strength'**
  String get signal_strength;

  /// No description provided for @connecting_to.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {ssid}...'**
  String connecting_to(Object ssid);

  /// No description provided for @wifi_credentials_sent.
  ///
  /// In en, this message translates to:
  /// **'Wi‑Fi credentials sent: {ssid}'**
  String wifi_credentials_sent(Object ssid);

  /// No description provided for @wifi_credentials_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send Wi‑Fi credentials'**
  String get wifi_credentials_failed;

  /// No description provided for @unknown_device.
  ///
  /// In en, this message translates to:
  /// **'Unknown Device'**
  String get unknown_device;

  /// No description provided for @current_selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get current_selected;

  /// No description provided for @set_current_device.
  ///
  /// In en, this message translates to:
  /// **'Set as current'**
  String get set_current_device;

  /// No description provided for @check_update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get check_update;

  /// No description provided for @delete_device.
  ///
  /// In en, this message translates to:
  /// **'Unbind Device'**
  String get delete_device;

  /// No description provided for @unbind_action.
  ///
  /// In en, this message translates to:
  /// **'Unbind'**
  String get unbind_action;

  /// No description provided for @device_id_label.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get device_id_label;

  /// No description provided for @ble_label.
  ///
  /// In en, this message translates to:
  /// **'BLE'**
  String get ble_label;

  /// No description provided for @last_connected_at.
  ///
  /// In en, this message translates to:
  /// **'Last connected'**
  String get last_connected_at;

  /// No description provided for @empty_saved_devices.
  ///
  /// In en, this message translates to:
  /// **'No saved devices'**
  String get empty_saved_devices;

  /// No description provided for @empty_hint_add_by_scan.
  ///
  /// In en, this message translates to:
  /// **'Scan the QR on your device to add a new smart display'**
  String get empty_hint_add_by_scan;

  /// No description provided for @scan_qr_add_device.
  ///
  /// In en, this message translates to:
  /// **'Scan QR to add device'**
  String get scan_qr_add_device;

  /// No description provided for @device_switched.
  ///
  /// In en, this message translates to:
  /// **'Switched to this device'**
  String get device_switched;

  /// No description provided for @switch_device_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to switch device. Please try again.'**
  String get switch_device_failed;

  /// No description provided for @missing_ble_params.
  ///
  /// In en, this message translates to:
  /// **'Missing Bluetooth parameters. Please rescan the device first.'**
  String get missing_ble_params;

  /// No description provided for @no_device_title.
  ///
  /// In en, this message translates to:
  /// **'No device added yet'**
  String get no_device_title;

  /// No description provided for @no_device_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Power on the display, then scan the QR code shown to add a device'**
  String get no_device_subtitle;

  /// No description provided for @dark_env_hint.
  ///
  /// In en, this message translates to:
  /// **'Try to scan under better lighting'**
  String get dark_env_hint;

  /// No description provided for @turn_on.
  ///
  /// In en, this message translates to:
  /// **'Turn on flashlight'**
  String get turn_on;

  /// No description provided for @user_fallback.
  ///
  /// In en, this message translates to:
  /// **'Anonymous user'**
  String get user_fallback;

  /// No description provided for @devices_count.
  ///
  /// In en, this message translates to:
  /// **'You have {count} devices'**
  String devices_count(Object count);

  /// No description provided for @logout_confirm_title.
  ///
  /// In en, this message translates to:
  /// **'Confirm logout'**
  String get logout_confirm_title;

  /// No description provided for @logout_confirm_ok.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout_confirm_ok;

  /// No description provided for @qr_content_title.
  ///
  /// In en, this message translates to:
  /// **'QR Content'**
  String get qr_content_title;

  /// No description provided for @qr_unrecognized_hint.
  ///
  /// In en, this message translates to:
  /// **'Unrecognized device QR. Raw content:'**
  String get qr_unrecognized_hint;

  /// No description provided for @copied_to_clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied_to_clipboard;

  /// No description provided for @copy_text.
  ///
  /// In en, this message translates to:
  /// **'Copy Text'**
  String get copy_text;

  /// No description provided for @qr_scan_success.
  ///
  /// In en, this message translates to:
  /// **'Scan successful, navigating...'**
  String get qr_scan_success;

  /// No description provided for @ble_disconnected_on_exit.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth disconnected because you exited the binding flow'**
  String get ble_disconnected_on_exit;

  /// No description provided for @connect_success.
  ///
  /// In en, this message translates to:
  /// **'Connected successfully'**
  String get connect_success;

  /// No description provided for @connect_failed_retry.
  ///
  /// In en, this message translates to:
  /// **'Connection failed, please retry'**
  String get connect_failed_retry;

  /// No description provided for @ble_disconnected_rescan_bind.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth disconnected. Please rescan the QR code.'**
  String get ble_disconnected_rescan_bind;

  /// No description provided for @device_bound_elsewhere.
  ///
  /// In en, this message translates to:
  /// **'This device is linked to a different account'**
  String get device_bound_elsewhere;

  /// No description provided for @ble_connect_timeout_relaunch_toast.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out. Please fully close the app and reopen it to try again.'**
  String get ble_connect_timeout_relaunch_toast;

  /// No description provided for @ble_scan_timeout_device_not_found.
  ///
  /// In en, this message translates to:
  /// **'Connection failed. The device may not be nearby.'**
  String get ble_scan_timeout_device_not_found;

  /// No description provided for @ble_not_ready_enable_bluetooth_check_permission.
  ///
  /// In en, this message translates to:
  /// **'Please enable Bluetooth and check permissions'**
  String get ble_not_ready_enable_bluetooth_check_permission;

  /// No description provided for @error_title.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error_title;

  /// No description provided for @no_device_data_message.
  ///
  /// In en, this message translates to:
  /// **'No device data found. Please rescan the QR code.'**
  String get no_device_data_message;

  /// No description provided for @rescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get rescan;

  /// No description provided for @connect_device_title.
  ///
  /// In en, this message translates to:
  /// **'Connect Device'**
  String get connect_device_title;

  /// No description provided for @ble_connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting via Bluetooth...'**
  String get ble_connecting;

  /// No description provided for @provision_success.
  ///
  /// In en, this message translates to:
  /// **'Wi‑Fi setup complete. Device is online'**
  String get provision_success;

  /// No description provided for @selected_network.
  ///
  /// In en, this message translates to:
  /// **'Selected network: {ssid}'**
  String selected_network(Object ssid);

  /// No description provided for @manual_wifi_entry_title.
  ///
  /// In en, this message translates to:
  /// **'Or enter Wi‑Fi info manually'**
  String get manual_wifi_entry_title;

  /// No description provided for @wifi_name_label.
  ///
  /// In en, this message translates to:
  /// **'Wi‑Fi Name (SSID)'**
  String get wifi_name_label;

  /// No description provided for @wifi_password_label.
  ///
  /// In en, this message translates to:
  /// **'Wi‑Fi Password'**
  String get wifi_password_label;

  /// No description provided for @please_enter_wifi_name.
  ///
  /// In en, this message translates to:
  /// **'Please enter Wi‑Fi name'**
  String get please_enter_wifi_name;

  /// No description provided for @wifi_bssid_label.
  ///
  /// In en, this message translates to:
  /// **'BSSID: {bssid}'**
  String wifi_bssid_label(Object bssid);

  /// No description provided for @wifi_frequency_mhz_label.
  ///
  /// In en, this message translates to:
  /// **'Frequency: {mhz} MHz'**
  String wifi_frequency_mhz_label(Object mhz);

  /// No description provided for @wifi_rssi_dbm_label.
  ///
  /// In en, this message translates to:
  /// **'RSSI: {dbm} dBm'**
  String wifi_rssi_dbm_label(Object dbm);

  /// No description provided for @wifi_signal_strong.
  ///
  /// In en, this message translates to:
  /// **'Strong signal'**
  String get wifi_signal_strong;

  /// No description provided for @wifi_signal_good.
  ///
  /// In en, this message translates to:
  /// **'Good signal'**
  String get wifi_signal_good;

  /// No description provided for @wifi_signal_weak.
  ///
  /// In en, this message translates to:
  /// **'Weak signal'**
  String get wifi_signal_weak;

  /// No description provided for @wifi_signal_unknown.
  ///
  /// In en, this message translates to:
  /// **'Signal unknown'**
  String get wifi_signal_unknown;

  /// No description provided for @provision_request_failed.
  ///
  /// In en, this message translates to:
  /// **'Network connection failed, please try again'**
  String get provision_request_failed;

  /// No description provided for @send_provision_request.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get send_provision_request;

  /// No description provided for @provisioning_please_wait.
  ///
  /// In en, this message translates to:
  /// **'Provisioning, please wait…'**
  String get provisioning_please_wait;

  /// No description provided for @wifi_scanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning Wi‑Fi…'**
  String get wifi_scanning;

  /// No description provided for @last_wifi_scan_time.
  ///
  /// In en, this message translates to:
  /// **'Last scan: {time}'**
  String last_wifi_scan_time(Object time);

  /// No description provided for @bind_device_title.
  ///
  /// In en, this message translates to:
  /// **'Bind Device'**
  String get bind_device_title;

  /// No description provided for @no_device_info_message.
  ///
  /// In en, this message translates to:
  /// **'No device info found. Please go back and rescan'**
  String get no_device_info_message;

  /// No description provided for @back_to_scan.
  ///
  /// In en, this message translates to:
  /// **'Back to Scan'**
  String get back_to_scan;

  /// No description provided for @confirm_binding_title.
  ///
  /// In en, this message translates to:
  /// **'Confirm Binding'**
  String get confirm_binding_title;

  /// No description provided for @confirm_binding_question.
  ///
  /// In en, this message translates to:
  /// **'Bind this device to your account?'**
  String get confirm_binding_question;

  /// No description provided for @bind_button.
  ///
  /// In en, this message translates to:
  /// **'Bind'**
  String get bind_button;

  /// No description provided for @bind_failed.
  ///
  /// In en, this message translates to:
  /// **'Binding failed. Please try again later.'**
  String get bind_failed;

  /// No description provided for @bind_timeout_check_network_and_retry.
  ///
  /// In en, this message translates to:
  /// **'Binding timed out. Please confirm network access and stay near the device before retrying.'**
  String get bind_timeout_check_network_and_retry;

  /// No description provided for @bind_mobile_network_error.
  ///
  /// In en, this message translates to:
  /// **'Mobile network connection failed. Please check and retry.'**
  String get bind_mobile_network_error;

  /// No description provided for @bind_device_network_timeout.
  ///
  /// In en, this message translates to:
  /// **'Device network timeout. Please check and retry.'**
  String get bind_device_network_timeout;

  /// No description provided for @bind_success.
  ///
  /// In en, this message translates to:
  /// **'Device linked successfully'**
  String get bind_success;

  /// No description provided for @firmware_version_label.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get firmware_version_label;

  /// No description provided for @manage_network.
  ///
  /// In en, this message translates to:
  /// **'Manage Network'**
  String get manage_network;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @confirm_delete_device.
  ///
  /// In en, this message translates to:
  /// **'Unbind this device?'**
  String get confirm_delete_device;

  /// No description provided for @device_name_label.
  ///
  /// In en, this message translates to:
  /// **'Device Name'**
  String get device_name_label;

  /// No description provided for @delete_consequence_hint.
  ///
  /// In en, this message translates to:
  /// **'After unbinding, you\'ll need to scan the QR code on the device screen to bind it again.'**
  String get delete_consequence_hint;

  /// No description provided for @delete_success.
  ///
  /// In en, this message translates to:
  /// **'Device unbound successfully'**
  String get delete_success;

  /// No description provided for @delete_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to unbind device'**
  String get delete_failed;

  /// No description provided for @delete_failed_error.
  ///
  /// In en, this message translates to:
  /// **'Failed to unbind device. Please try again.'**
  String get delete_failed_error;

  /// No description provided for @ble_connected_text.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth connected'**
  String get ble_connected_text;

  /// No description provided for @ble_connecting_text.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth connecting'**
  String get ble_connecting_text;

  /// No description provided for @ble_disconnected_text.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth not connected'**
  String get ble_disconnected_text;

  /// No description provided for @relative_just_now.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get relative_just_now;

  /// No description provided for @relative_minutes_ago.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes ago'**
  String relative_minutes_ago(Object count);

  /// No description provided for @relative_hours_ago.
  ///
  /// In en, this message translates to:
  /// **'{count} hours ago'**
  String relative_hours_ago(Object count);

  /// No description provided for @relative_days_ago.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String relative_days_ago(Object count);

  /// No description provided for @sync_devices_in_progress.
  ///
  /// In en, this message translates to:
  /// **'Syncing devices…'**
  String get sync_devices_in_progress;

  /// No description provided for @sync_devices_success.
  ///
  /// In en, this message translates to:
  /// **'Devices synced'**
  String get sync_devices_success;

  /// No description provided for @sync_devices_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to sync devices'**
  String get sync_devices_failed;

  /// No description provided for @update_started.
  ///
  /// In en, this message translates to:
  /// **'Device update started. Keep power and network on'**
  String get update_started;

  /// No description provided for @update_in_progress.
  ///
  /// In en, this message translates to:
  /// **'Update already in progress'**
  String get update_in_progress;

  /// No description provided for @already_latest_version.
  ///
  /// In en, this message translates to:
  /// **'Already on the latest version'**
  String get already_latest_version;

  /// No description provided for @optional_update_available.
  ///
  /// In en, this message translates to:
  /// **'Optional update available'**
  String get optional_update_available;

  /// No description provided for @update_throttled_retry.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please try again later'**
  String get update_throttled_retry;

  /// No description provided for @update_low_storage_retry.
  ///
  /// In en, this message translates to:
  /// **'Insufficient storage. Restart the device and try again'**
  String get update_low_storage_retry;

  /// No description provided for @check_update_failed_retry.
  ///
  /// In en, this message translates to:
  /// **'Check for update failed, please try again later'**
  String get check_update_failed_retry;

  /// No description provided for @check_update_failed_error.
  ///
  /// In en, this message translates to:
  /// **'Unable to check for updates right now. Please try again later.'**
  String get check_update_failed_error;

  /// No description provided for @nearby_networks_count.
  ///
  /// In en, this message translates to:
  /// **'Nearby networks ({count})'**
  String nearby_networks_count(Object count);

  /// No description provided for @no_scan_results_hint.
  ///
  /// In en, this message translates to:
  /// **'No results yet. Tap refresh at top right.'**
  String get no_scan_results_hint;

  /// No description provided for @last_updated.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get last_updated;

  /// No description provided for @network_not_connected.
  ///
  /// In en, this message translates to:
  /// **'Network not connected'**
  String get network_not_connected;

  /// No description provided for @device_settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get device_settings;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @wallpaper_section_title.
  ///
  /// In en, this message translates to:
  /// **'Set Wallpaper'**
  String get wallpaper_section_title;

  /// No description provided for @wallpaper_aspect_ratio_hint.
  ///
  /// In en, this message translates to:
  /// **'16:9 aspect ratio recommended'**
  String get wallpaper_aspect_ratio_hint;

  /// No description provided for @wallpaper_default.
  ///
  /// In en, this message translates to:
  /// **'Default wallpaper'**
  String get wallpaper_default;

  /// No description provided for @wallpaper_default_hint.
  ///
  /// In en, this message translates to:
  /// **'Use the built-in wallpaper'**
  String get wallpaper_default_hint;

  /// No description provided for @wallpaper_custom_upload.
  ///
  /// In en, this message translates to:
  /// **'Custom upload'**
  String get wallpaper_custom_upload;

  /// No description provided for @wallpaper_custom_hint.
  ///
  /// In en, this message translates to:
  /// **'Upload an image as the wallpaper'**
  String get wallpaper_custom_hint;

  /// No description provided for @layout_section_title.
  ///
  /// In en, this message translates to:
  /// **'Choose Layout'**
  String get layout_section_title;

  /// No description provided for @layout_default.
  ///
  /// In en, this message translates to:
  /// **'Default layout'**
  String get layout_default;

  /// No description provided for @layout_default_hint.
  ///
  /// In en, this message translates to:
  /// **'Standard content arrangement'**
  String get layout_default_hint;

  /// No description provided for @layout_frame.
  ///
  /// In en, this message translates to:
  /// **'Frame layout'**
  String get layout_frame;

  /// No description provided for @layout_frame_hint.
  ///
  /// In en, this message translates to:
  /// **'Photo-forward layout like a frame'**
  String get layout_frame_hint;

  /// No description provided for @wake_word_section_title.
  ///
  /// In en, this message translates to:
  /// **'Wake Word'**
  String get wake_word_section_title;

  /// No description provided for @wake_word_default.
  ///
  /// In en, this message translates to:
  /// **'Use device default'**
  String get wake_word_default;

  /// No description provided for @wake_word_default_hint.
  ///
  /// In en, this message translates to:
  /// **'Changing this restarts the device immediately'**
  String get wake_word_default_hint;

  /// No description provided for @wake_word_confirm_title.
  ///
  /// In en, this message translates to:
  /// **'Change wake word?'**
  String get wake_word_confirm_title;

  /// No description provided for @wake_word_confirm_message.
  ///
  /// In en, this message translates to:
  /// **'The device will restart immediately to apply this change.'**
  String get wake_word_confirm_message;

  /// No description provided for @wake_word_confirm_action.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get wake_word_confirm_action;

  /// No description provided for @save_settings.
  ///
  /// In en, this message translates to:
  /// **'Save settings'**
  String get save_settings;

  /// No description provided for @reset_to_default.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get reset_to_default;

  /// No description provided for @device_edit_load_failed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load device settings. Please try again.'**
  String get device_edit_load_failed;

  /// No description provided for @missing_device_id_save.
  ///
  /// In en, this message translates to:
  /// **'Missing device ID. Unable to save.'**
  String get missing_device_id_save;

  /// No description provided for @settings_saved.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully'**
  String get settings_saved;

  /// No description provided for @settings_save_failed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save settings. Please try again.'**
  String get settings_save_failed;

  /// No description provided for @saving_ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving_ellipsis;

  /// No description provided for @processing_ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processing_ellipsis;

  /// No description provided for @reading_ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Reading...'**
  String get reading_ellipsis;

  /// No description provided for @wallpaper_uploading_ellipsis.
  ///
  /// In en, this message translates to:
  /// **'Uploading...'**
  String get wallpaper_uploading_ellipsis;

  /// No description provided for @wallpaper_processing_index_total.
  ///
  /// In en, this message translates to:
  /// **'Processing {current}/{total}...'**
  String wallpaper_processing_index_total(Object current, Object total);

  /// No description provided for @current_label.
  ///
  /// In en, this message translates to:
  /// **'Current wallpaper'**
  String get current_label;

  /// No description provided for @set_as_current.
  ///
  /// In en, this message translates to:
  /// **'Set as current'**
  String get set_as_current;

  /// No description provided for @wallpaper_count.
  ///
  /// In en, this message translates to:
  /// **'{count} images'**
  String wallpaper_count(Object count);

  /// No description provided for @wallpaper_not_uploaded.
  ///
  /// In en, this message translates to:
  /// **'No wallpaper uploaded'**
  String get wallpaper_not_uploaded;

  /// No description provided for @wallpaper_upload_from_gallery.
  ///
  /// In en, this message translates to:
  /// **'Upload from gallery'**
  String get wallpaper_upload_from_gallery;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @wallpaper_reupload.
  ///
  /// In en, this message translates to:
  /// **'Reupload'**
  String get wallpaper_reupload;

  /// No description provided for @missing_device_id_upload_wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Missing device ID. Unable to upload wallpaper.'**
  String get missing_device_id_upload_wallpaper;

  /// No description provided for @photo_permission_required_upload_wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Photo permission is required to upload wallpaper.'**
  String get photo_permission_required_upload_wallpaper;

  /// No description provided for @wallpaper_upload_limit.
  ///
  /// In en, this message translates to:
  /// **'You can select up to {count} images; trimmed to the first {count}.'**
  String wallpaper_upload_limit(Object count);

  /// No description provided for @wallpaper_upload_too_large.
  ///
  /// In en, this message translates to:
  /// **'Image exceeds {size}. Please choose a smaller one.'**
  String wallpaper_upload_too_large(Object size);

  /// No description provided for @wallpaper_image_size_unrecognized.
  ///
  /// In en, this message translates to:
  /// **'Unable to read image size. Please try another image or export and retry.'**
  String get wallpaper_image_size_unrecognized;

  /// No description provided for @wallpaper_dimension_too_large.
  ///
  /// In en, this message translates to:
  /// **'Image dimensions are too large: {width}×{height}. Max long side is {maxDim}px. Please crop or export and retry.'**
  String wallpaper_dimension_too_large(Object width, Object height, Object maxDim);

  /// No description provided for @wallpaper_pixels_too_large.
  ///
  /// In en, this message translates to:
  /// **'Image resolution is too large: {width}×{height}. Recommended not to exceed {maxWidth}×{maxHeight}.'**
  String wallpaper_pixels_too_large(Object width, Object height, Object mp, Object maxMp, Object maxWidth, Object maxHeight);

  /// No description provided for @image_processing_wait.
  ///
  /// In en, this message translates to:
  /// **'Processing images... This may take a few seconds.'**
  String get image_processing_wait;

  /// No description provided for @wallpaper_processing_timeout_index.
  ///
  /// In en, this message translates to:
  /// **'Image {count} processing timed out. Please remove it then retry.'**
  String wallpaper_processing_timeout_index(Object count);

  /// No description provided for @image_processing_timeout_hint.
  ///
  /// In en, this message translates to:
  /// **'Image processing timed out. Reduce the number of images or try again later.'**
  String get image_processing_timeout_hint;

  /// No description provided for @image_processing_failed.
  ///
  /// In en, this message translates to:
  /// **'Image processing failed. Please try another image.'**
  String get image_processing_failed;

  /// No description provided for @image_processing_failed_index.
  ///
  /// In en, this message translates to:
  /// **'Image {count} could not be processed.'**
  String image_processing_failed_index(Object count);

  /// No description provided for @image_processing_failed_index_retry.
  ///
  /// In en, this message translates to:
  /// **'Image {count} processing failed. Please try another image.'**
  String image_processing_failed_index_retry(Object count);

  /// No description provided for @missing_device_id_delete_wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Missing device ID. Unable to delete wallpaper.'**
  String get missing_device_id_delete_wallpaper;

  /// No description provided for @image_format_not_supported.
  ///
  /// In en, this message translates to:
  /// **'To ensure stable display on the device, only {formatStr} images are supported.'**
  String image_format_not_supported(Object formatStr);

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get viewDetails;

  /// No description provided for @new_wallpaper.
  ///
  /// In en, this message translates to:
  /// **'New wallpaper'**
  String get new_wallpaper;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @force_update_title.
  ///
  /// In en, this message translates to:
  /// **'Update Required'**
  String get force_update_title;

  /// No description provided for @force_update_message.
  ///
  /// In en, this message translates to:
  /// **'Please update to the latest version to continue.'**
  String get force_update_message;

  /// No description provided for @force_update_button.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get force_update_button;

  /// No description provided for @force_update_download_via_web.
  ///
  /// In en, this message translates to:
  /// **'Download via browser'**
  String get force_update_download_via_web;

  /// No description provided for @task_menu_item.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get task_menu_item;

  /// No description provided for @environment_switch_title.
  ///
  /// In en, this message translates to:
  /// **'Switch Environment'**
  String get environment_switch_title;

  /// No description provided for @environment_current.
  ///
  /// In en, this message translates to:
  /// **'Current: {environment}'**
  String environment_current(Object environment);

  /// No description provided for @environment_switched.
  ///
  /// In en, this message translates to:
  /// **'Switched to {environment}'**
  String environment_switched(Object environment);

  /// No description provided for @environment_pre_release.
  ///
  /// In en, this message translates to:
  /// **'Pre-release'**
  String get environment_pre_release;

  /// No description provided for @environment_production.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get environment_production;

  /// No description provided for @task_list_title.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get task_list_title;

  /// No description provided for @task_unnamed.
  ///
  /// In en, this message translates to:
  /// **'Untitled task'**
  String get task_unnamed;

  /// No description provided for @task_loading_data.
  ///
  /// In en, this message translates to:
  /// **'Loading data...'**
  String get task_loading_data;

  /// No description provided for @task_empty.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet'**
  String get task_empty;

  /// No description provided for @task_preview_only_success.
  ///
  /// In en, this message translates to:
  /// **'Only successful tasks can be previewed'**
  String get task_preview_only_success;

  /// No description provided for @task_status_pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get task_status_pending;

  /// No description provided for @task_status_running.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get task_status_running;

  /// No description provided for @task_status_success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get task_status_success;

  /// No description provided for @task_status_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get task_status_failed;

  /// No description provided for @task_status_cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get task_status_cancelled;

  /// No description provided for @task_created_time.
  ///
  /// In en, this message translates to:
  /// **'Created: {time}'**
  String task_created_time(Object time);

  /// No description provided for @task_view_result.
  ///
  /// In en, this message translates to:
  /// **'View result'**
  String get task_view_result;

  /// No description provided for @task_pdf_default_title.
  ///
  /// In en, this message translates to:
  /// **'PDF Preview'**
  String get task_pdf_default_title;

  /// No description provided for @task_pdf_missing_task_id.
  ///
  /// In en, this message translates to:
  /// **'Missing task ID'**
  String get task_pdf_missing_task_id;

  /// No description provided for @task_pdf_no_available_link.
  ///
  /// In en, this message translates to:
  /// **'No PDF link available'**
  String get task_pdf_no_available_link;

  /// No description provided for @task_pdf_no_preview_file.
  ///
  /// In en, this message translates to:
  /// **'No preview file available'**
  String get task_pdf_no_preview_file;

  /// No description provided for @task_pdf_link_expired_open_local_export.
  ///
  /// In en, this message translates to:
  /// **'Link expired, local export is opened'**
  String get task_pdf_link_expired_open_local_export;

  /// No description provided for @task_pdf_file_cached.
  ///
  /// In en, this message translates to:
  /// **'File cached: {path}'**
  String task_pdf_file_cached(Object path);

  /// No description provided for @task_pdf_share_failed.
  ///
  /// In en, this message translates to:
  /// **'Share failed. Please try again.'**
  String get task_pdf_share_failed;

  /// No description provided for @task_pdf_missing_storage_permission.
  ///
  /// In en, this message translates to:
  /// **'Missing storage permission, unable to download'**
  String get task_pdf_missing_storage_permission;

  /// No description provided for @task_pdf_download_started.
  ///
  /// In en, this message translates to:
  /// **'Download started, check Downloads later'**
  String get task_pdf_download_started;

  /// No description provided for @task_pdf_no_shareable_file.
  ///
  /// In en, this message translates to:
  /// **'No file available to share'**
  String get task_pdf_no_shareable_file;

  /// No description provided for @task_pdf_network_error.
  ///
  /// In en, this message translates to:
  /// **'Network error, please check connection'**
  String get task_pdf_network_error;

  /// No description provided for @task_pdf_invalid_link.
  ///
  /// In en, this message translates to:
  /// **'Invalid link format'**
  String get task_pdf_invalid_link;

  /// No description provided for @task_pdf_retry_later.
  ///
  /// In en, this message translates to:
  /// **'Please try again later'**
  String get task_pdf_retry_later;

  /// No description provided for @task_pdf_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get task_pdf_retry;

  /// No description provided for @task_pdf_download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get task_pdf_download;

  /// No description provided for @task_pdf_share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get task_pdf_share;

  /// No description provided for @task_pdf_loading.
  ///
  /// In en, this message translates to:
  /// **'Loading PDF...'**
  String get task_pdf_loading;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
