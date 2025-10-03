# BLE 重连后写入失败分析

1. 复现现象
   - 第二次启动 App 时手机系统会自动恢复与电视的 BLE 连接（电视端作为 GATT server 一直在线），两端状态栏都显示“已连接”。
   - 进入设备管理页直接点击“退出登录”等命令，Flutter 端经常抛出 `writeCharacteristic` 失败；偶尔写入成功但电视无响应。

2. 检查命令发送入口 (`lib/presentation/pages/device_management_page.dart:311`)
   - `SavedDeviceRecord` 仅保存上次连接时的 `lastBleAddress`，按钮点击后直接调用 `BleServiceSimple.writeCharacteristic(...)` 写入 JSON 命令，没有任何重新连接或握手流程。
   - 这意味着页面假设“系统状态显示已连接” ⇔ “FlutterReactiveBle 也处于连接态”，这一点需要验证。

3. 追踪底层写特征实现 (`lib/features/device_connection/services/ble_service_simple.dart:246`)
   - `writeCharacteristic` 直接调用 `_ble.writeCharacteristicWithResponse(...)`，若 `FlutterReactiveBle` 当前没有处于 `connected` 状态，插件会抛出 `BleDisconnectedException`，函数捕获后返回 `false`，从而触发调用处的“写入失败”。
   - 代码中没有任何“自动重连”或“查询当前连接状态”的逻辑。

4. 对比首次连接流程 (`lib/features/device_connection/providers/device_connection_provider.dart:152-235`)
   - 首次扫码时会：申请权限 → 扫描目标设备 → `BleServiceSimple.connectToDevice(...)` 建立连接 → 订阅通知 → `_startAuthentication` 完成密钥交换。
   - 这套流程不仅让 `FlutterReactiveBle` 拿到有效的连接句柄，也在电视端完成认证初始化。

5. 重新进入 App 时的现有流程
   - App 直接从本地存储恢复 `SavedDeviceRecord`，但没有任何地方重新触发第 4 步的连接/认证流程；`DeviceManagementPage` 只做“立即写指令”。
   - 虽然系统层面已经和电视建立了链路，但 `FlutterReactiveBle` 并不知道，需要重新调用 `connectToDevice` 订阅其 `ConnectionStateUpdate` 才能写入。

6. 定位失败原因
   - **主要原因**：重新进入 App 没有通过 `FlutterReactiveBle` 建立新的 GATT 会话，导致插件认为“不在连接态”，所以写特征直接失败。
   - **次要风险**：即使偶尔操作系统帮助恢复了 GATT 会话，也跳过了 `_startAuthentication` 的安全握手，电视端可能因为没有会话密钥而忽略命令，从而表现为“写成功但无响应”。

7. 影响范围
   - 所有依赖 `BleServiceSimple.writeCharacteristic` 的操作（退出登录、检查更新、登录授权码、配网等）在非首连场景都会不稳定。
   - 用户只要换一个页面或杀进程重开 App，就必须再次手动扫码才能稳定控制电视。

8. 建议验证与修复方向
   - 在设备管理页面执行任何命令前，先调用一段“确保连接”逻辑：使用缓存的设备信息重新走 `connectToDevice + _initGattSession + _startAuthentication`，或抽出一个公共的“确保会话可用”方法。
   - 如果设备需要每次重新握手，建议把握手流程封装成可复用服务，在 App 启动或切回前台时主动触发，并在成功后再允许写特征。
   - 补充日志：打印 `_ble` 的 `connectionStateUpdate`，确认写失败时真正的插件状态；也可以在电视端记录是否收到了写入请求，以验证第二个风险点。
