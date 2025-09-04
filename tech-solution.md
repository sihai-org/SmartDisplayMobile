#

下面给你一份**手机端配网技术方案（蓝牙 BLE + 备选 SoftAP/二维码）**。整体按“可落地、可扩展、可量产”的标准来写，默认你的电视端是 Android TV（你们的全屏 App 为系统级/设备所有者，具备改 Wi-Fi 的权限）。

BLE 是 Bluetooth Low Energy 的缩写，也叫 低功耗蓝牙。

它和我们常见的蓝牙（Bluetooth Classic）有几点区别：

- 功耗更低：设计目标是让设备长时间待机或使用电池供电时更省电。
- 传输数据量小：适合传感器、智能家居、可穿戴设备、智能硬件做数据交换，而不是传大文件或高质量音频。
- 通信模式不同：通常通过 GATT（Generic Attribute Profile） 定义服务和特征（Characteristics），手机可以作为 Central（中心），硬件作为 Peripheral（外设），手机可以读写数据。
- 适用场景：智能手环、蓝牙秤、电子锁、智能显示器配网等，尤其适合“短距离、低功耗、安全通信”的场景。

在你的方案里，BLE 的作用就是：
让手机 App 和显示器硬件在没有键盘输入的情况下，能够通过蓝牙交换 Wi-Fi 配置信息（SSID 和密码），并通过安全握手保证密码不会被窃取。

---

# **目标与约束**

- **目标**：手机 App 通过蓝牙安全地把 Wi-Fi SSID/密码下发到电视端，让其自动入网；无需遥控器或键盘。
- **约束**：
  - 电视端**无输入**与**无可视键盘**（开机直接进你们的全屏 App）。
  - 需要在**iOS 与 Android**手机都可用。
  - 密码传输必须**端到端加密**，**不可明文**。
  - 工程化：靠**稳定的蓝牙连接**与**可回退的配网策略**（SoftAP/二维码）。

---

# **架构总览**

## **组件**

1. **电视端（Android TV）服务**
   - 常驻进程（你们的全屏 App 或其前台 Service）
   - 暴露一个 **BLE GATT 服务**（Peripheral）
   - 扫描周边 Wi-Fi、接收凭据、写入系统 Wi-Fi 配置、上报状态
   - 需要系统权限（NETWORK_SETTINGS/设备所有者 DO 权限）来静默加入网络
2. **手机 App（iOS/Android/Flutter）**
   - 作为 **BLE Central**，发现并连接设备
   - 拉取设备端的**Wi-Fi 扫描列表**给用户选择
   - 本地对 Wi-Fi 凭据加密 → 通过 BLE 写入
   - 监听状态回执，提示用户成功/失败与重试
   - 可选：**同一代码基线用 Flutter**（推荐），BLE 用平台通道封装
3. **备选链路**
   - **SoftAP 回落**：设备开机若 N 分钟未配网，自动开启热点（如 AI-TV-XXXX），手机连上后走 HTTP 局域网配网。
   - **二维码快速配网**：包装/铭牌印制设备公钥与序列号，手机 App 扫码后与设备建立“可信会话”（见安全方案）。

---

# **BLE GATT 设计（核心）**

> 建议自定义 128-bit UUID，下面给出示例。你可以按模块化一个服务多个特征。

**Service（设备配网服务）**

- UUID：0000A100-0000-1000-8000-00805F9B34FB

**Characteristics**

1. Device_Info（读）
   - UUID：0000A101-...
   - 内容：JSON/CBOR

```
{
  "model": "AIDisplay-1",
  "fw": "1.0.3",
  "sn": "AD12345678",
  "cap": ["2.4G","5G","WPA3"],
  "pk_fingerprint": "base64(sha256(pubkey))"
}
```

2. WiFi_Scan_Request（写，无响应）
   - UUID：0000A102-...
   - 作用：触发设备端扫描 Wi-Fi（指定频段/时长可选）
3. WiFi_Scan_Result（通知/读）
   - UUID：0000A103-...
   - 内容：分片推送列表（避免 MTU 限制），每条含 ssid, rssi, bssid, security（WPA2/WPA3/OWE…），band（2.4/5G）
4. Session_Nonce（读/通知）
   - UUID：0000A104-...
   - 内容：设备生成的随机数（用于握手）
5. Secure_Handshake（写/通知）
   - UUID：0000A105-...
   - 手机写入：握手报文（见安全方案）
   - 设备通知：握手结果（含会话密钥协商是否成功）
6. Provision_Request（写，**加密**）
   - UUID：0000A106-...
   - 内容（密文，AES-GCM）：

```
{
  "ssid": "Home_5G",
  "password": "********",
  "bssid": "xx:xx:xx:xx:xx:xx",   // 可选，锁定AP
  "band": "5G",                   // 可选
  "static_ip": { ... },           // 可选：静态IP配置
  "proxy": { ... }                // 可选
}
```

7. Provision_Status（通知/读）
   - UUID：0000A107-...
   - 内容：

```
{
  "phase": "applying|connecting|dhcp|online|error",
  "error_code": 0,
  "ip": "192.168.1.23",
  "gw": "192.168.1.1",
  "dns": ["8.8.8.8","1.1.1.1"]
}
```

8. OOB_QR_Info（读）
   - UUID：0000A108-...
   - 内容：设备出厂写入的**公钥/序列号/厂商 ID**等 OOB 信息（用于扫码绑定/鉴权）

> 说明：传输内容建议用 CBOR（二进制紧凑）或 JSON（调试友好）。BLE 包大小受 MTU 限制，需要分片与序号。

---

# **安全方案（强烈建议）**

BLE 的 “Just Works” 安全不足，**必须做应用层端到端加密**。推荐两种可量产策略：

## **A. 设备出厂公钥（推荐）**

1. **出厂为每台设备生成 ECDSA/ECDH 密钥对**，公钥烧录在设备并印在包装贴纸的 **二维码** 中（或公钥指纹 + 云侧校验）。
2. 手机 App 开始配网时，**扫码二维码**获得设备公钥（或指纹 + 从设备 OOB 读取核验），随后：
   - 双方做 **ECDH（X25519）** 协商出会话密钥 K
   - 所有敏感数据（Wi-Fi 密码）用 **AES-GCM(K, nonce)** 加密
3. App 验证设备公钥（与二维码/OOB/云登记一致）后才继续；防**中间人攻击**。

## **B. 一次性 PIN 纸卡（退而求其次）**

- 出厂随盒子附带 6~8 位 PIN。
- 握手时 App 与设备用 PIN 做 **PAKE（如 SRP/SPAKE2）** → 派生会话密钥。
- 用户体验略差，但仍比明文好。

> 两端都要零日志地处理密码；手机端用 Keychain/Keystore 短暂缓存会话密钥；过期即销毁。设备端只持久化 Wi-Fi 配置，不落盘明文密码（系统 API 会安全保存）。

---

# **电视端实现要点（Android TV）**

- 形态：你们的 App 作为 **Device Owner（DO）/系统 App**，持有以下能力：
  - 使用 WifiManager/系统 API **静默添加/连接**网络（Android 10+ 普通 App 需用户确认，系统/DO 可绕过）。
  - 后台扫描 Wi-Fi 并返回结果（WifiScanner 或系统接口）。
- BLE 外设实现：
  - 长驻 Service 开启 GATT Server，维护**会话状态机**（IDLE → SCANNING → HANDSHAKE → PROVISIONING → ONLINE/ERROR）
  - **MTU 协商**（请求 247 或更大），**分片组包**与**重传**
  - 断电/重启后的**幂等**：若已联网，GATT 仍可工作并上报 ONLINE；若未联网，维持可发现广播。
- 失败回退：
  - N 分钟未配成功 → 自动启用 **SoftAP**（Android TV 上可经系统接口/扩展支持）
  - SoftAP 模式下，跑一个仅内网可访问的 HTTP Server（/scan、/provision、/status），同样使用**TLS（自签证书）**或会话级对称加密

---

# **手机 App 交互流程（UX & 时序）**

1. **发现设备**
   - 打开 App → 请求蓝牙/定位权限（Android 必要）→ 扫描广告名形如 AI-TV-xxxx
   - 可支持**批量发现**与**就近强信号排序**
2. **建立安全会话**
   - 若采用二维码方案：先**扫码**（公钥/指纹/序列号）→ 连接 BLE → 读取 Session_Nonce → **ECDH 握手**写入 Secure_Handshake → 等待 Provision_Status: session_ready
   - 若无二维码：读取 OOB_QR_Info 进行云校验或提示用户输入 PIN 再做 PAKE
3. **拉取 Wi-Fi 列表**
   - 写 WiFi_Scan_Request → 连续从 WiFi_Scan_Result 收到分片 → 展示 SSID 列表（标注 2.4G/5G、安全类型、信号强度）
4. **下发凭据**
   - 用户选择 SSID → 输入密码（显示“可见/隐藏”切换、密码强度校验、WPA/WPA3 兼容提示）
   - App 用会话密钥 AES-GCM 加密 payload → 写 Provision_Request
5. **状态反馈**
   - 监听 Provision_Status：applying → connecting → dhcp → online
   - 成功后可提示：“已联网：192.168.1.23”。失败给出明确原因（密码错误、AP 不可达、信号弱、IP 冲突、认证失败、仅 5G/仅 2.4G 不匹配等）并给一键重试
6. **设备命名与绑定（可选）**
   - 让用户给设备命名并绑定账号（后续远程管理、OTA、日志上报）

---

# **数据与协议细节**

## **加密载荷（建议）**

- **算法**：X25519 ECDH → HKDF-SHA256 导出 256-bit K；每次写操作用随机 nonce 做 **AES-GCM** 加密
- **消息结构**（未加密前）：

```
{
  "op": "provision",
  "seq": 102,                // sequence for idempotency
  "ts": 1736045132,
  "payload": {
    "ssid": "...",
    "password": "...",
    "bssid": "...",
    "band": "2.4G|5G|auto",
    "ip": { "mode":"dhcp" },
    "meta": { "app":"1.5.0","os":"iOS 18.1" }
  }
}
```

- **响应**：

```
{
  "op":"status",
  "seq":102,
  "phase":"online|error|...",
  "error_code":0,
  "reason":""
}
```

## **错误码（示例）**

- 0 成功
- 1001 握手失败/密钥非法
- 2001 SSID 不存在/不可达
- 2002 密码错误/认证失败
- 2003 频段不匹配（仅 2.4G/仅 5G）
- 2004 DHCP 失败
- 9001 内部错误/权限不足

---

# **跨平台实现建议（Flutter 优先）**

你之前有 Flutter 经验，推荐**Flutter + 原生插件**方式，一套 UI，分别调用平台 BLE 能力。

## **Flutter 侧**

- 状态管理：Riverpod/Bloc 任选
- BLE：flutter_reactive_ble 或 flutter_blue_plus
- 加密：cryptography（支持 X25519、AES-GCM、HKDF）
- 二维码：mobile_scanner（扫码设备公钥/指纹）
- 存储：flutter_secure_storage（会话密钥/绑定 token）
- 架构：Repository + UseCase + ViewModel，UI 与业务分离

## **Android 原生要点**

- 权限：BLUETOOTH_SCAN/CONNECT, ACCESS_FINE_LOCATION（扫描必要），后台扫描需额外声明
- 若做 SoftAP 回落：需系统接口或预装权限
- Keystore：存储本地长/短期密钥材料
- 机型兼容：MTU 变化、某些机型通知包大小限制

## **iOS 原生要点**

- CoreBluetooth：前台扫描与连接
- iOS 不允许 App 主动获取手机附近网络列表（没关系，**由电视端扫描**并回传）
- Keychain：会话密钥存储
- 后台模式（可选）：BLE 连接保活（谨慎使用）

---

# **量产与运维**

- **出厂测试（FCT）**：写入设备公钥/指纹，校验 GATT 服务与基本配网闭环
- **日志与埋点**：手机端仅记录匿名错误码与阶段；**不采集明文密码**；设备端可将错误码与 RSSI 上报到云端用于质量分析
- **OTA 升级**：联网后立即检查固件/应用版本并支持差分更新
- **批量配网**：支持“附近设备”多选与串行配网；增加序列号过滤，避免串扰
- **隐私合规**：密码只在端侧加密后传输，不写日志。出厂公钥与序列号不属于个人敏感信息，但要告知用途

---

# 关键路径伪代码（仅示例，注释英文）

### **Flutter：握手与下发**

```
// Pseudocode: E2E BLE provisioning

Future<void> provision(String deviceId) async {
  // 1) Connect & discover
  final dev = await ble.connect(deviceId);
  final service = await dev.discoverService('0000A100-...');
  final chNonce = service.char('0000A104-...');
  final chHs    = service.char('0000A105-...');
  final chReq   = service.char('0000A106-...');
  final chStat  = service.char('0000A107-...');

  // 2) Handshake: X25519 ECDH
  final appKeyPair = await X25519().newKeyPair();
  final deviceNonce = await chNonce.read();
  final devicePubKey = await obtainDevicePubKeyByQR(); // from QR or OOB
  final shared = await x25519(appKeyPair.secretKey, devicePubKey);
  final sessionKey = hkdfSha256(shared, deviceNonce); // derive AES key

  // 3) Send handshake frame (app public key + signature)
  final hsFrame = buildHandshake(appKeyPair.publicKey, deviceNonce);
  await chHs.write(hsFrame, withResponse: true);
  await expectHandshakeAck(chHs); // throws on failure

  // 4) Encrypt Wi-Fi credentials
  final payload = {
    'ssid': selectedSsid,
    'password': inputPassword,
    'bssid': selectedBssid,
    'band': 'auto',
    'ip': {'mode':'dhcp'}
  };
  final cipher = aesGcmEncrypt(jsonEncode(payload), sessionKey);
  await chReq.write(cipher, withResponse: true);

  // 5) Wait status
  await for (final s in chStat.notifications()) {
    final st = parseStatus(s);
    if (st.phase == 'online') break;
    if (st.phase == 'error') throw ProvisionError(st);
  }
}
```

### **Android TV：应用 Wi-Fi（Kotlin 伪码）**

```
// Pseudocode: apply Wi-Fi on Android TV with system privileges

fun applyWifi(cfg: WifiConfig) {
    // Require DO/system app privileges
    val wifiManager = context.getSystemService(WifiManager::class.java)

    // Remove old network if conflicts, then add new
    val spec = when (cfg.security) {
        WPA3 -> WifiNetworkSuggestion.Builder()
                  .setSsid(cfg.ssid)
                  .setWpa3Passphrase(cfg.password).build()
        else -> WifiNetworkSuggestion.Builder()
                  .setSsid(cfg.ssid)
                  .setWpa2Passphrase(cfg.password).build()
    }

    // For system app, you may directly add and connect:
    val netId = wifiManager.addNetwork(buildWifiConfiguration(cfg))
    wifiManager.enableNetwork(netId, true)
    wifiManager.reconnect()

    // Emit Provision_Status via GATT as phases progress
}
```

> 备注：实际 Android 10+ 上普通应用需用户确认；你们是系统/DO 时可静默连接。与 OEM 同步好签名与权限。

---

# **回退方案：SoftAP（简述）**

- 设备端创建热点 AI-TV-XXXX（密码随机），打印在包装/屏幕提示（若能简短显示）。
- 手机连上该热点 → 打开 App → 自动发现 http://192.168.4.1（或 mDNS）
- 走 **HTTPS（自签）** 或握手后对称加密，接口同 BLE：/scan、/provision、/status
- 成功入网后自动关闭 SoftAP

---

# **测试用例（抽样）**

- 不同路由器加密：WPA2/WPA3/混合模式
- 仅 2.4G / 仅 5G / Mesh / 同名双频
- 密码错误、AP 关机、信号弱（RSSI<-75）
- DHCP 失败 / 静态 IP 冲突
- 大量干扰 & BLE 断连（自动重连与断点续传）
- 批量 20 台并行配网（串行队列 + 去重）

---

# **项目落地清单**

- 与 OEM 确认 **系统权限**与签名；你们 App 设为 **Device Owner**
- 设备出厂 **公钥生成与注入**流程（含二维码打印）
- 定义并固化 **GATT UUID/协议** 与错误码表
- Flutter 基线工程 + BLE/加密封装（SDK 模块化）
- 电视端 GATT Server + Wi-Fi 控制模块 + 状态机
- SoftAP 回落路径（固件侧 & App 侧）
- 安全审计（渗透测试、明文检查、日志脱敏）
- 产测工具（扫描、握手、自测配网一条龙）
- OTA/日志上报与质控面板

---
