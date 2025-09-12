长期正确做法（建议尽快做）

- 在 TV 的 BLE 广播里加“唯一指纹”（比如 SHA256(publicKey) 的前 6–8 字节），放 Manufacturer Data 或 Service Data。
- 二维码里也包含同一指纹。
- App 扫描时解析广告数据，只认带该指纹的那个广播，从根上解决“同名多台/重复回调”的问题，并且跨 iOS/Android 都稳定。

⸻

另外两点排查

1. 你现在的 connectToDevice(...) 还是 stub（只是 Future.delayed 然后返回），即便命中了也只是“假连接”。要连真机，需要用 flutter_reactive_ble.connectToDevice(id: ...)，并在连接成功后做 MTU、discoverServices、subscribe 等逻辑。
2. 扫描到后记得停扫（你已做），并做去重：800ms 窗口里用 Map 按 deviceId 取 RSSI 最大值保留一条，UI 会清爽很多。

⸻

一句话结论

你“看到了对的设备”，但匹配规则过严（名字不完全一致、iOS 没 MAC/没业务 deviceId），导致从未调用连接。
先按上面 A/B 两个小改放宽匹配和带上 withServices，让流程走通；随后尽快把广播短指纹加上，才能在量产环境下做到“唯一正确匹配”。

# 完整连接

你现在“只能发现，但连不上”的最主要原因：你的 BleServiceSimple.connectToDevice() 还是个假实现（stub）——它只是 Future.delayed 然后返回“已连接”。所以 UI 再怎么点，底层都没真的去连。

把这个方法换成真实连接就能走起来。下面给你一段可直接替换的实现（基于 flutter_reactive_ble），包含：停止扫描 → 连接 → 设置 MTU→ 发现服务 → 订阅通知 → 返回已连接设备。

⸻

一步到位的 connectToDevice 实现（替换你现在的 stub）

// 在 BleServiceSimple 里加这些字段
static StreamSubscription<ConnectionStateUpdate>? \_connSub;
static QualifiedCharacteristic? \_statusCh; // 例如 A107 用于 notify
static const \_SERVICE = Uuid.parse('0000A100-0000-1000-8000-00805F9B34FB');
static const \_CH_STATUS = Uuid.parse('0000A107-0000-1000-8000-00805F9B34FB'); // 按你的规范改

static Future<BleDeviceData?> connectToDevice({
required BleDeviceData deviceData,
required Duration timeout,
}) async {
// iOS: 用 DiscoveredDevice.id（UUID）
// Android: 用 MAC（多数机型），你在扫描时已经把 address = id 传上来了
final deviceId = deviceData.bleAddress.isNotEmpty
? deviceData.bleAddress
: deviceData.deviceId; // 兜底

print('🔗 正在连接: $deviceId ...');
// 先停掉扫描，避免连接被扫描打断
await stopScan();

// 清理旧连接
await \_connSub?.cancel();
\_connSub = null;

final completer = Completer<BleDeviceData?>();
Timer? to;

// 发起连接（autoConnect 设为 false，连接更确定）
\_connSub = \_ble
.connectToDevice(id: deviceId, servicesWithCharacteristicsToDiscover: {
\_SERVICE: [], // 让库帮我们发现此服务；你也可以传空 map 然后手动 discover
}, connectionTimeout: timeout)
.listen((update) async {
print('🔗 状态: ${update.connectionState}');
switch (update.connectionState) {
case DeviceConnectionState.connected:
// 尝试申请更大的 MTU（iOS 会忽略但没关系）
try {
final mtu = await \_ble.requestMtu(deviceId: deviceId, mtu: 247);
print('📏 MTU = $mtu');
} catch (e) {
print('📏 MTU 请求失败: $e');
}

        // （可选）手动发现服务
        try {
          final services = await _ble.discoverServices(deviceId);
          print('🧭 已发现服务数: ${services.length}');
          // 找到状态通知特征，便于后续 subscribe
          for (final s in services) {
            if (s.serviceId == _SERVICE) {
              for (final c in s.characteristics) {
                if (c.characteristicId == _CH_STATUS) {
                  _statusCh = QualifiedCharacteristic(
                    deviceId: deviceId,
                    serviceId: s.serviceId,
                    characteristicId: c.characteristicId,
                  );
                  break;
                }
              }
            }
          }
        } catch (e) {
          print('🧭 发现服务失败: $e');
        }

        // 成功，组装返回数据
        final connected = deviceData.copyWith(
          status: BleDeviceStatus.connected,
          connectedAt: DateTime.now(),
          // 也可以把 deviceId/bleAddress 规范化成刚才用的 deviceId
          bleAddress: deviceId,
        );
        if (!completer.isCompleted) completer.complete(connected);
        break;

      case DeviceConnectionState.disconnected:
        // 如果还没完成，就当失败
        if (!completer.isCompleted) completer.complete(null);
        break;

      case DeviceConnectionState.connecting:
      case DeviceConnectionState.disconnecting:
        // 等状态变化
        break;
    }

}, onError: (e, st) {
print('❌ 连接错误: $e');
if (!completer.isCompleted) completer.complete(null);
});

// 保险超时（因为 connectToDevice 自带超时，但我们再包一层更稳）
to = Timer(timeout, () {
print('⏰ 连接超时');
if (!completer.isCompleted) completer.complete(null);
});

final result = await completer.future;
to?.cancel();
return result;
}

备注
• 连接时一定要用扫描回调里的 id（iOS 是 UUID），不要用二维码的 deviceId 或 MAC（iOS 拿不到 MAC）。你在页面里已把 scanResult.address 传入了，记得那个在 iOS 上就是 id。
• servicesWithCharacteristicsToDiscover 传服务可以提升发现速度。也可留空后 discoverServices()。
• 连接成功后再进行 握手/写入/订阅 notify。

⸻

订阅 Notify / 读写示例（后续握手要用）

// 订阅状态通知（A107）
static Stream<List<int>>? subscribeStatus() {
final ch = \_statusCh;
if (ch == null) return null;
return \_ble.subscribeToCharacteristic(ch);
}

// 写入（比如 A106 Provision_Request）
static Future<void> writeEncrypted(Uuid chUuid, List<int> data) async {
final ch = QualifiedCharacteristic(
deviceId: \_statusCh!.deviceId, // 已连接的 deviceId
serviceId: \_SERVICE,
characteristicId: chUuid,
);
await \_ble.writeCharacteristicWithResponse(ch, value: data);
}

⸻

你页面层的小修正
• 传入用于连接的 ID：确保 \_connectToDevice 使用的是扫描到的 scanResult.deviceId（或你传给 bleAddress 的那个），而不是二维码里的业务 deviceId。你现在这行是对的：

\_connectToDevice(deviceData.copyWith(
bleAddress: scanResult.address, // iOS: 就是 UUID
rssi: scanResult.rssi,
));

    •	停止扫描再连：上面的 connectToDevice 里已 await stopScan()，避免“扫描-连接冲突”。

⸻

若仍连不上，按这个排查 1. 用通用 App（如 LightBlue / nRF Connect）能否连接？
• 不能：TV 端没打开 GATT Server/广播、或硬件不支持 Peripheral。
• 能：那就是你 App 侧参数问题。 2. TV 端是否只允许一个 Central？
• 已被别的手机连着时，你会“可发现但连不上”。先断开其他手机/工具。 3. Service UUID 是否广播出来？
• App 扫描时最好指定 withServices: [A100]，降噪并验证 TV 广播配置。 4. 权限
• iOS：只要蓝牙权限即可；
• Android 12+：BLUETOOTH_CONNECT 必须授予；Android 11- 还要定位权限+开启定位服务。 5. 距离/电源
• RSSI -57 已不错；电源省电策略（电视待机）可能把 BLE 挂起，注意保持活跃。

⸻

一句话总结
• 你现在“发现能看到，连接一直不动”，是因为底层没真的去连。
• 换成上面的 connectToDevice 实现，连接就会开始；连上后记得做 discover/MTU/subscribe，再进入你的 握手 流程。
• 若仍失败，用 LightBlue 验证 TV 侧；基本能快速定位是哪一侧的问题。
