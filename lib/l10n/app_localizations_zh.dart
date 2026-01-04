// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '心显智联';

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
  String get language_en => '英语';

  @override
  String get bluetooth_settings => '蓝牙设置';

  @override
  String get manage_bluetooth => '管理蓝牙连接和权限';

  @override
  String get camera_permission => '相机权限';

  @override
  String get camera_permission_denied => '相机权限被拒绝，请在系统设置中开启。';

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
  String get account_security => '账号与安全';

  @override
  String get delete_account => '注销账号';

  @override
  String get profile_title => '我的';

  @override
  String get meeting_minutes => '会议纪要';

  @override
  String get meeting_minutes_list => '会议纪要列表';

  @override
  String get meeting_minutes_empty => '暂无会议纪要';

  @override
  String get meeting_minutes_detail => '会议纪要详情';

  @override
  String get meeting_minutes_loading => '正在获取数据...';

  @override
  String get meeting_minutes_detail_empty => '暂无内容';

  @override
  String get meeting_minutes_generating => '会议纪要生成中...';

  @override
  String get meeting_minutes_failed => '生成失败';

  @override
  String get meeting_minutes_mock_title_1 => '项目周会纪要';

  @override
  String get meeting_minutes_mock_title_2 => '需求评审纪要';

  @override
  String get meeting_minutes_mock_title_3 => '客户反馈整理';

  @override
  String get meeting_minutes_mock_content_1 => '# 项目周会纪要\n\n## 参会人员\n- 产品\n- 设计\n- 开发\n\n## 关键结论\n1. 优先完成会议纪要列表页。\n2. 下周补齐详情页的数据接口。\n\n## 待办\n- [ ] 列表页样式评审\n- [ ] 接口联调';

  @override
  String get meeting_minutes_mock_content_2 => '# 需求评审纪要\n\n## 目标\n- 明确版本范围\n- 对齐交付节奏\n\n## 决策\n- 本期只做基础列表和详情。\n- 数据使用 mock。\n\n## 风险\n- 详情内容需支持 Markdown 渲染。';

  @override
  String get meeting_minutes_mock_content_3 => '# 客户反馈整理\n\n## 主要问题\n- 列表项信息层级不清晰\n- 详情内容可读性一般\n\n## 建议\n- 第二行左右对齐日期/时间\n- 标题加粗提升层级';

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
  String get splash_subtitle => '心显智联';

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
  String get device_management => '切换设备';

  @override
  String get device_details => '设备详情';

  @override
  String get current_device => '当前设备';

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
  String get qr_scanner_title => '扫描二维码';

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
  String get audit_mode_enabled => 'Audit/Review 模式已开启';

  @override
  String get login_expired => '登录已过期';

  @override
  String get welcome_title => '欢迎使用心显智联';

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

  @override
  String get unknown_device => '未知设备';

  @override
  String get current_selected => '当前选中';

  @override
  String get set_current_device => '设为当前设备';

  @override
  String get check_update => '检查更新';

  @override
  String get delete_device => '解绑设备';

  @override
  String get device_id_label => 'ID';

  @override
  String get ble_label => 'BLE';

  @override
  String get last_connected_at => '上次连接';

  @override
  String get empty_saved_devices => '暂无保存的设备';

  @override
  String get empty_hint_add_by_scan => '扫描设备上的二维码来添加新的智能显示器';

  @override
  String get scan_qr_add_device => '扫描二维码添加设备';

  @override
  String get device_switched => '已切换为当前设备';

  @override
  String switch_device_failed(Object error) {
    return '切换设备失败: $error';
  }

  @override
  String get missing_ble_params => '当前设备缺少蓝牙参数，请重新扫码或靠近设备后重试';

  @override
  String get no_device_title => '暂未添加设备';

  @override
  String get no_device_subtitle => '显示器开机后，扫描显示器屏幕上的二维码可添加设备';

  @override
  String get dark_env_hint => '请在光线更好的环境下扫码';

  @override
  String get turn_on => '打开手电筒';

  @override
  String get user_fallback => '匿名用户';

  @override
  String devices_count(Object count) {
    return '你有 $count 个设备';
  }

  @override
  String get logout_confirm_title => '确认退出登录';

  @override
  String get logout_confirm_ok => '退出';

  @override
  String get qr_content_title => '二维码内容';

  @override
  String get qr_unrecognized_hint => '未能识别为设备二维码，以下为原始内容：';

  @override
  String get copied_to_clipboard => '已复制到剪贴板';

  @override
  String get copy_text => '复制文本';

  @override
  String get qr_scan_success => '扫描成功，跳转中...';

  @override
  String get ble_disconnected_on_exit => '已断开绑定流程中的蓝牙连接';

  @override
  String get connect_success => '连接成功';

  @override
  String get connect_failed_retry => '连接失败，请重试';

  @override
  String get device_bound_elsewhere => '您与设备绑定用户不匹配';

  @override
  String get connect_failed_move_closer => '连接失败，请靠近重试';

  @override
  String get error_title => '错误';

  @override
  String get no_device_data_message => '未找到设备数据，请重新扫描二维码。';

  @override
  String get rescan => '重新扫描';

  @override
  String get connect_device_title => '连接设备';

  @override
  String get ble_connecting => '蓝牙连接中...';

  @override
  String get provision_success => '配网成功，设备已联网';

  @override
  String selected_network(Object ssid) {
    return '已选择网络: $ssid';
  }

  @override
  String get manual_wifi_entry_title => '或手动输入 Wi‑Fi 信息';

  @override
  String get wifi_name_label => 'Wi‑Fi 名称 (SSID)';

  @override
  String get wifi_password_label => 'Wi‑Fi 密码';

  @override
  String get please_enter_wifi_name => '请输入Wi‑Fi名称';

  @override
  String wifi_bssid_label(Object bssid) {
    return 'BSSID: $bssid';
  }

  @override
  String wifi_frequency_mhz_label(Object mhz) {
    return '频率: $mhz MHz';
  }

  @override
  String wifi_rssi_dbm_label(Object dbm) {
    return 'RSSI: $dbm dBm';
  }

  @override
  String get wifi_signal_strong => '信号强';

  @override
  String get wifi_signal_good => '信号良好';

  @override
  String get wifi_signal_weak => '信号弱';

  @override
  String get wifi_signal_unknown => '信号未知';

  @override
  String get provision_request_failed => '网络连接失败，请重试';

  @override
  String get send_provision_request => '开始连接';

  @override
  String get provisioning_please_wait => '网络连接中...';

  @override
  String get wifi_scanning => '正在扫描 Wi‑Fi…';

  @override
  String last_wifi_scan_time(Object time) {
    return '上次扫描：$time';
  }

  @override
  String get bind_device_title => '绑定设备';

  @override
  String get no_device_info_message => '未找到设备信息，请返回重新扫码';

  @override
  String get back_to_scan => '返回扫码';

  @override
  String get confirm_binding_title => '确认绑定';

  @override
  String get confirm_binding_question => '是否将该设备绑定到当前账号？';

  @override
  String get bind_button => '绑定';

  @override
  String fetch_otp_failed(Object error) {
    return '获取授权码失败: $error';
  }

  @override
  String get otp_empty => '授权码为空';

  @override
  String get bind_failed => '绑定失败';

  @override
  String get bind_success => '绑定成功';

  @override
  String bind_failed_error(Object error) {
    return '绑定失败: $error';
  }

  @override
  String get firmware_version_label => '固件版本';

  @override
  String get manage_network => '管理网络';

  @override
  String get refresh => '刷新';

  @override
  String get confirm_delete_device => '确定要解绑以下设备吗？';

  @override
  String get device_name_label => '设备名称';

  @override
  String get delete_consequence_hint => '解绑后将无法控制此设备，需要重新扫描二维码绑定';

  @override
  String get delete_success => '设备解绑成功';

  @override
  String get delete_failed => '设备解绑失败';

  @override
  String delete_failed_error(Object error) {
    return '设备解绑失败: $error';
  }

  @override
  String get ble_connected_text => '蓝牙已连接';

  @override
  String get ble_connecting_text => '蓝牙连接中';

  @override
  String get ble_disconnected_text => '蓝牙未连接';

  @override
  String get relative_just_now => '刚刚';

  @override
  String relative_minutes_ago(Object count) {
    return '$count分钟前';
  }

  @override
  String relative_hours_ago(Object count) {
    return '$count小时前';
  }

  @override
  String relative_days_ago(Object count) {
    return '$count天前';
  }

  @override
  String get sync_devices_in_progress => '正在同步设备…';

  @override
  String get sync_devices_success => '设备同步成功';

  @override
  String get sync_devices_failed => '设备同步失败';

  @override
  String get update_started => '设备开始更新，请保持电源与网络畅通';

  @override
  String get already_latest_version => '当前已是最新版本';

  @override
  String get check_update_failed_retry => '检查更新失败，请稍后重试';

  @override
  String check_update_failed_error(Object error) {
    return '检查更新失败：$error';
  }

  @override
  String nearby_networks_count(Object count) {
    return '附近网络（$count）';
  }

  @override
  String get no_scan_results_hint => '暂无扫描结果，请点击右上角刷新';

  @override
  String get last_updated => '上次更新';

  @override
  String get network_not_connected => '网络未连接';

  @override
  String get device_edit_title => '设备编辑';

  @override
  String get edit_device => '编辑设备';

  @override
  String get done => '完成';

  @override
  String get wallpaper_section_title => '设置壁纸';

  @override
  String get wallpaper_default => '默认壁纸';

  @override
  String get wallpaper_default_hint => '使用系统提供的默认壁纸';

  @override
  String get wallpaper_custom_upload => '自定义上传';

  @override
  String get wallpaper_custom_hint => '上传一张图片作为设备壁纸';

  @override
  String get layout_section_title => '选择布局';

  @override
  String get layout_default => '默认布局';

  @override
  String get layout_default_hint => '标准内容排版';

  @override
  String get layout_frame => '相框布局';

  @override
  String get layout_frame_hint => '突出展示照片的相框式排版';

  @override
  String get save_settings => '保存设置';

  @override
  String get reset_to_default => '恢复默认';

  @override
  String device_edit_load_failed(Object error) {
    return '加载失败：$error';
  }

  @override
  String get missing_device_id_save => '缺少设备 ID，无法保存';

  @override
  String get settings_saved => '保存成功';

  @override
  String get saving_ellipsis => '保存中...';

  @override
  String get processing_ellipsis => '处理中...';

  @override
  String get wallpaper_uploading_ellipsis => '上传中...';

  @override
  String wallpaper_processing_index_total(Object current, Object total) {
    return '正在处理第$current/$total张...';
  }

  @override
  String get current_label => '当前壁纸';

  @override
  String get set_as_current => '设为当前';

  @override
  String wallpaper_count(Object count) {
    return '$count 张';
  }

  @override
  String get wallpaper_not_uploaded => '未上传壁纸';

  @override
  String get wallpaper_upload_from_gallery => '从相册上传';

  @override
  String get delete => '删除';

  @override
  String get wallpaper_reupload => '重新上传';

  @override
  String get missing_device_id_upload_wallpaper => '缺少设备 ID，无法上传壁纸';

  @override
  String get photo_permission_required_upload_wallpaper => '需要相册权限才能上传壁纸';

  @override
  String wallpaper_upload_limit(Object count) {
    return '最多选择 $count 张，已自动截取前 $count 张';
  }

  @override
  String get image_processing_wait => '图片处理中...需要几秒，请耐心等待';

  @override
  String wallpaper_processing_timeout_index(Object count) {
    return '第$count张图片处理超时，请去掉后重试';
  }

  @override
  String get image_processing_timeout_hint => '图片处理超时，请减少图片数量或稍后重试';

  @override
  String image_processing_failed(Object error) {
    return '图片处理失败：$error';
  }

  @override
  String image_processing_failed_index(Object count, Object error) {
    return '第$count张图片处理失败：$error';
  }

  @override
  String image_processing_failed_index_retry(Object count) {
    return '第$count张图片处理失败，请更换图片后重试';
  }

  @override
  String get missing_device_id_delete_wallpaper => '缺少设备 ID，无法删除壁纸';

  @override
  String get image_format_not_supported => '仅支持 JPG / PNG 格式的图片';

  @override
  String get viewDetails => '查看详情';

  @override
  String get new_wallpaper => '新壁纸';

  @override
  String get loading => '加载中...';
}
