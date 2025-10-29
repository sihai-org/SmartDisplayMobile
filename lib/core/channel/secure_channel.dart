abstract class SecureChannel {
  String get displayDeviceId;
  String get bleDeviceId;

  /// 确保底层已连接 + GATT 就绪 + 应用层握手完成
  Future<void> ensureAuthenticated();

  /// 发送一条“加密 JSON 指令”，返回设备应答（已解密解析）
  Future<Map<String, dynamic>> send(
      Map<String, dynamic> msg, {
        Duration? timeout,
        int retries = 0,
        bool Function(Map<String, dynamic>)? isFinal,
      });

  /// 设备侧推送事件（已解密）
  Stream<Map<String, dynamic>> get events;

  /// 主动销毁（断开、清理密钥/订阅/队列）
  Future<void> dispose();
}
