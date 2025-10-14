// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '大头智显';

  @override
  String get action_ok => '确定';

  @override
  String get action_cancel => '取消';

  @override
  String get nav_home => '首页';

  @override
  String get nav_settings => '设置';

  @override
  String get login_title => '登录';

  @override
  String get login_button => '登录';

  @override
  String get settings_title => '设置';

  @override
  String get app_info => '应用信息';

  @override
  String get app_name => '应用名称';

  @override
  String get version => '版本号';

  @override
  String get language => '语言';

  @override
  String get language_system => '跟随系统';

  @override
  String get language_zh => '中文';

  @override
  String get bluetooth_settings => '蓝牙设置';

  @override
  String get manage_bluetooth => '管理蓝牙连接和权限';

  @override
  String get camera_permission => '相机权限';

  @override
  String get manage_qr_permission => '管理二维码扫描权限';

  @override
  String get about => '关于';

  @override
  String get help => '使用帮助';

  @override
  String get help_desc => '查看使用说明和常见问题';

  @override
  String get feedback => '问题反馈';

  @override
  String get feedback_desc => '报告问题或提出建议';

  @override
  String get profile_title => '我的';

  @override
  String get logout => '退出登录';

  @override
  String get page_not_found => '页面未找到';

  @override
  String page_not_exist(Object path) {
    return '请求的页面不存在: $path';
  }

  @override
  String get back_to_home => '返回首页';

  @override
  String get splash_loading => '加载中...';

  @override
  String get splash_title => '你好';

  @override
  String get splash_subtitle => '大头智显';

  @override
  String get login_email => '邮箱';

  @override
  String get login_password => '密码';

  @override
  String login_failed(Object error) {
    return '登录失败：$error';
  }

  @override
  String get home_title => '首页';

  @override
  String get devices_title => '设备';

  @override
  String get device_management => '设备管理';

  @override
  String get device_details => '设备详情';

  @override
  String get connect => '连接';

  @override
  String get disconnect => '断开';

  @override
  String get scan_qr => '扫码';

  @override
  String get provision => '配网';

  @override
  String get wifi_selection => 'Wi‑Fi 选择';

  @override
  String get qr_scanner_title => '二维码扫描';

  @override
  String get no_data => '暂无数据';

  @override
  String get ok => '确定';

  @override
  String get cancel => '取消';

  @override
  String get sending_otp => '正在发送验证码...';

  @override
  String otp_sent_to(Object email) {
    return '验证码已发送到 $email';
  }

  @override
  String send_failed(Object error) {
    return '发送失败: $error';
  }

  @override
  String get signing_in => '正在登录，请稍候...';

  @override
  String get login_success => '登录成功';

  @override
  String get otp_invalid => '验证码无效，请重试';

  @override
  String get email_signin => '邮箱登录';

  @override
  String get email_invalid => '请输入正确的邮箱地址';

  @override
  String get otp_code => '验证码';

  @override
  String resend_in(Object seconds) {
    return '重新发送 (${seconds}s)';
  }

  @override
  String get send_otp => '发送验证码';

  @override
  String get signin_with_google => '使用 Google 登录';

  @override
  String signout_failed(Object error) {
    return '退出失败: $error';
  }

  @override
  String get google_signin_placeholder => '敬请期待';

  @override
  String get welcome_title => '欢迎使用大头智显';

  @override
  String get welcome_hint => '请扫描显示器上的二维码为显示器配置网络';

  @override
  String get reconnect => '重新连接';

  @override
  String get add_device => '添加设备';

  @override
  String get wifi_not_connected => '设备未连接网络，请选择Wi‑Fi网络进行配网：';

  @override
  String get wifi_status_unknown => '无法获取网络状态，显示可用Wi‑Fi网络：';

  @override
  String get connected => '已连接';

  @override
  String get unknown_network => '未知网络';

  @override
  String get band => '频段';

  @override
  String get no_wifi_found => '未找到Wi‑Fi网络';

  @override
  String get scan_networks => '扫描网络';

  @override
  String get refresh_networks => '刷新网络列表';

  @override
  String get enter_wifi_password => '请输入Wi‑Fi密码:';

  @override
  String get wifi_password_optional => 'Wi‑Fi密码（如果是开放网络请留空）:';

  @override
  String get enter_password => '请输入密码';

  @override
  String get leave_empty_if_open => '如果是开放网络请留空';

  @override
  String get secure_network_need_password => '检测到这是安全网络，需要密码';

  @override
  String get open_network_may_need_password => '检测到这是开放网络，但如果实际需要密码请输入';

  @override
  String get signal_strength => '信号强度';

  @override
  String connecting_to(Object ssid) {
    return '正在连接 $ssid...';
  }

  @override
  String wifi_credentials_sent(Object ssid) {
    return 'Wi‑Fi 凭证已发送到 TV：$ssid';
  }

  @override
  String get wifi_credentials_failed => '发送 Wi‑Fi 凭证失败';

  @override
  String connect_failed(Object error) {
    return '连接失败：$error';
  }
}
