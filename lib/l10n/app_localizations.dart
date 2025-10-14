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
  /// **'SmartDisplay'**
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
  /// **'Follow System'**
  String get language_system;

  /// No description provided for @language_zh.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get language_zh;

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

  /// No description provided for @profile_title.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile_title;

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
  /// **'Datou SmartDisplay'**
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
  /// **'Sign in failed: {error}'**
  String login_failed(Object error);

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
  /// **'Device Management'**
  String get device_management;

  /// No description provided for @device_details.
  ///
  /// In en, this message translates to:
  /// **'Device Details'**
  String get device_details;

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

  /// No description provided for @sending_otp.
  ///
  /// In en, this message translates to:
  /// **'Sending verification code...'**
  String get sending_otp;

  /// No description provided for @otp_sent_to.
  ///
  /// In en, this message translates to:
  /// **'Verification code sent to {email}'**
  String otp_sent_to(Object email);

  /// No description provided for @send_failed.
  ///
  /// In en, this message translates to:
  /// **'Send failed: {error}'**
  String send_failed(Object error);

  /// No description provided for @signing_in.
  ///
  /// In en, this message translates to:
  /// **'Signing in, please wait...'**
  String get signing_in;

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

  /// No description provided for @email_signin.
  ///
  /// In en, this message translates to:
  /// **'Email Sign In'**
  String get email_signin;

  /// No description provided for @email_invalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get email_invalid;

  /// No description provided for @otp_code.
  ///
  /// In en, this message translates to:
  /// **'Verification Code'**
  String get otp_code;

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

  /// No description provided for @signin_with_google.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signin_with_google;

  /// No description provided for @signout_failed.
  ///
  /// In en, this message translates to:
  /// **'Sign out failed: {error}'**
  String signout_failed(Object error);

  /// No description provided for @google_signin_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get google_signin_placeholder;

  /// No description provided for @welcome_title.
  ///
  /// In en, this message translates to:
  /// **'Welcome to SmartDisplay'**
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

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

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
  /// **'Wi‑Fi credentials sent to TV: {ssid}'**
  String wifi_credentials_sent(Object ssid);

  /// No description provided for @wifi_credentials_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send Wi‑Fi credentials'**
  String get wifi_credentials_failed;

  /// No description provided for @connect_failed.
  ///
  /// In en, this message translates to:
  /// **'Connect failed: {error}'**
  String connect_failed(Object error);

  // New strings for device list and detail
  String get unknown_device;
  String get current_selected;
  String get set_current_device;
  String get check_update;
  String get delete_device;
  String get device_id_label;
  String get ble_label;
  String get last_connected_at;
  String get empty_saved_devices;
  String get empty_hint_add_by_scan;
  String get scan_qr_add_device;
  String get device_switched;
  String switch_device_failed(Object error);

  // QR scanner localized strings
  String get gallery_picker;
  String get torch;
  String get dark_env_hint;
  String get turn_on;
  String get scan_success;
  String get rescan;
  String get aim_qr;
  String get scan_success_will_show;
  String get status_ready;
  String get status_scanning;
  String get status_processing;
  String get status_failed;

  // Profile/My page additions
  String get user_fallback;
  String devices_count(Object count);
  String get logout_confirm_title;
  String get logout_confirm_ok;
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
