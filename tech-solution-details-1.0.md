# 概述

面向量产的手机端配网方案，目标是在 **无输入** 的 Android TV 设备上，通过 **手机 App + BLE** 安全下发 Wi‑Fi 凭据，实现设备自动入网；并提供 **SoftAP 回落** 与 **二维码/OOB** 安全增强。适配 iOS/Android 手机端；设备端为 Android TV，设备所有者（Device Owner，DO）/系统级 App。

---

## 术语与版本

- **设备/TV**：AI 显示器（Android TV）
- **App/手机端**：配套 iOS/Android/Flutter 应用
- **GATT**：BLE 通讯协议（Peripheral=设备，Central=手机）
- **OOB**：Out‑of‑Band（二维码、公钥指纹等）
- **本方案版本**：v1.0

---

# 架构与数据流

1. 设备开机 → 若未联网：广播 BLE（GATT 服务可发现）。
2. 手机 App 扫描到设备 → 建立 BLE 连接。
3. **安全握手**（X25519 ECDH + HKDF → AES‑GCM 会话密钥）。
4. 手机发起 Wi‑Fi 扫描请求 → 设备返回 SSID 列表。
5. 用户在 App 中选择 SSID、输入密码 → App 加密发送凭据。
6. 设备应用 Wi‑Fi 配置 → 回报状态（applying/connecting/dhcp/online/error）。
7. 若 BLE 失败/不可用 → 启用 **SoftAP 回落**（设备热点 + HTTP API）。

---

# BLE GATT 设计

**Service UUID**：`0000A100-0000-1000-8000-00805F9B34FB`

### Characteristics

1. **Device\_Info**（Read）UUID `0000A101-...`
   - JSON/CBOR：`{"model":"AIDisplay-1","fw":"1.0.3","sn":"AD12345678","cap":["2.4G","5G","WPA3"],"pk_fingerprint":"base64(sha256(pubkey))"}`
2. **WiFi\_Scan\_Request**（Write, no resp）UUID `0000A102-...`
   - 触发设备扫描；可附加参数：频段、时长。
3. **WiFi\_Scan\_Result**（Notify/Read）UUID `0000A103-...`
   - 分片推送；每项含：`ssid,rssi,bssid,security,band`。
4. **Session\_Nonce**（Read/Notify）UUID `0000A104-...`
   - 设备随机数（16 bytes+）。
5. **Secure\_Handshake**（Write/Notify）UUID `0000A105-...`
   - 写入握手帧；设备通知握手结果与会话 ID。
6. **Provision\_Request**（Write，E2E Encrypted）UUID `0000A106-...`
   - AES‑GCM 密文负载，见“消息与加密”。
7. **Provision\_Status**（Notify/Read）UUID `0000A107-...`
   - 进度与错误码：`phase,error_code,ip,gateway,dns`。
8. **OOB\_QR\_Info**（Read）UUID `0000A108-...`
   - 出厂写入的公钥/序列号/厂商 ID 等（供比对）。

### GATT 传输与分片

- 建议 **MTU ≥ 185/247**；仍需 **分片**：`seq(2) | total(2) | idx(2) | payload(n)`。
- 密文帧过大则拆分为多片；接收端按 `seq/idx` 重组。

---

# 安全与握手

> 目标：即使 BLE 链路被被动监听，也无法获取凭据；防中间人攻击。

## 模式 A（推荐）：设备出厂公钥

- 每台设备生成 **X25519 密钥对**；公钥写入设备与包装二维码。
- App 扫码获得设备公钥或指纹；连上设备后读取 `Session_Nonce`。
- App 生成临时密钥对，与设备做 **ECDH** → `shared_secret`。
- `K = HKDF-SHA256(shared_secret, info="aidisplay-provision", salt=nonce)`
- 随后所有敏感数据用 **AES‑GCM(K, 12B nonce)** 加密。

**二维码内容格式（例）**：

```
aidisplay:1|sn=AD12345678|pk=BASE64URL(X25519_public_key)|fp=BASE64URL(SHA256(pk))
```

## 模式 B：一次性 PIN（退一步）

- 出厂附 6–8 位 PIN；用 **PAKE（SPAKE2/SRP）** 派生 `K`。

## 设备与 App 身份校验

- App 校验设备公钥（与二维码一致/云侧登记一致）。
- 不强制 App 身份；如需“只允许官方 App”，可在握手中加入厂商签名校验。

---

# 消息与加密

## 未加密的控制帧（示例）

```json
{"op":"scan","seq":100,"band":"auto"}
```

## 加密负载格式（写入 `Provision_Request`）

```
frame := nonce(12) | ciphertext(N) | tag(16)

plaintext (JSON):
{
  "op":"provision",
  "seq":102,
  "ts":1736045132,
  "payload":{
    "ssid":"Home_5G",
    "password":"********",
    "bssid":"xx:xx:xx:xx:xx:xx",
    "band":"auto",
    "ip":{"mode":"dhcp"},
    "proxy":null,
    "meta":{"app":"1.5.0","os":"iOS 18.1"}
  }
}
```

## 状态通知（`Provision_Status`）

```json
{"op":"status","seq":102,"phase":"connecting","error_code":0}
{"op":"status","seq":102,"phase":"dhcp","error_code":0}
{"op":"status","seq":102,"phase":"online","error_code":0,"ip":"192.168.1.23","gw":"192.168.1.1","dns":["8.8.8.8"]}
```

## 错误码

- `0` 成功
- `1001` 握手失败/会话无效
- `2001` SSID 不存在/不可达
- `2002` 密码错误/认证失败
- `2003` 频段不匹配（仅 2.4G/仅 5G）
- `2004` DHCP 失败
- `2005` IP 冲突/无法到网关
- `9001` 权限不足/系统错误

---

# 时序（文本示意）

```
App           TV
 |   Scan BLE  |
 |------------>|  Adv: AI-TV-XXXX
 | Connect     |
 |------------>|
 | Read Nonce  |
 |<------------|
 | ECDH+HKDF   |
 | Handshake   |
 |------------>|
 | <- Ack OK   |
 | Scan Req    |
 |------------>|
 | <- Scan Res |
 | 用户选SSID   |
 | Encrypted Provision
 |------------>|
 | <- Status: applying/connecting/dhcp/online
```

---

# 设备端（Android TV）实现要点

- **系统权限/DO**：
  - 通过 OEM 工厂配置，将你们 App 设为 **Device Owner**；或系统签名 App。
  - 需要可静默添加/切换 Wi‑Fi（普通应用在 Android 10+ 需要用户确认）。
- **GATT Server**：前台 Service 常驻；MTU 协商、分片重传、状态机（`IDLE→SCANNING→HS→PROVISIONING→ONLINE/ERROR`）。
- **Wi‑Fi 应用**：
  - 系统接口直接添加网络并连接；或使用 `WifiManager`/隐藏 API（OEM 侧开放）。
- **回退**：
  - N 分钟未配成功 → 自动启用 **SoftAP**（`AI-TV-XXXX`，密码随机）。
  - 运行最小 HTTP 服务：`/v1/scan`、`/v1/provision`、`/v1/status`；同样用会话密钥保护（或自签 TLS）。
- **幂等与断电恢复**：若设备已联网，BLE 仍可连接并上报 ONLINE；重新上电后根据存储状态自动恢复。

---

# 手机 App 设计（Flutter 优先）

- **框架**：Flutter（UI） + 平台通道封装 BLE；或使用 `flutter_reactive_ble`。
- **主要依赖**：
  - BLE：`flutter_reactive_ble`
  - Crypto：`cryptography`（X25519/AES‑GCM/HKDF）
  - QR：`mobile_scanner`
  - Secure Storage：`flutter_secure_storage`
- **层次**：Presentation（UI）/ Application（UseCase）/ Infrastructure（BLE, Crypto, QR）/ Domain（模型）。
- **关键页面**：发现设备 → 扫码/握手 → SSID 列表 → 凭据输入 → 配网进度 → 成功绑定与命名。

### Flutter 伪代码（英文注释）

```dart
Future<void> provisionFlow(Device dev) async {
  // 1) Connect & discover characteristics
  // 2) Read nonce, build ECDH shared secret, derive AES-GCM key
  // 3) Send handshake, await ack
  // 4) Request Wi-Fi scan, collect paged results
  // 5) Encrypt credentials and write Provision_Request
  // 6) Listen to Provision_Status until ONLINE or ERROR
}
```

---

# SoftAP 回落（HTTP API）

- **热点**：`AI-TV-XXXX`（WPA2，密码随机，贴在背标/屏提示）。
- **发现**：手机连上热点后，mDNS：`aidisplay.local` → `https://192.168.4.1`。
- **接口**：
  - `GET /v1/scan` → `[ {ssid,rssi,security,band} ]`
  - `POST /v1/provision` （Body=加密 JSON，同 BLE 负载）
  - `GET /v1/status` → `{phase,error_code,ip,...}`
- **安全**：与 BLE 相同的 ECDH→AES-GCM；或自签 TLS（在 App 内置根证书固定）。

---

# 生产与运维

- **出厂（FCT）**：注入公钥/指纹、SN；验证 GATT 服务、扫描/配网闭环。
- **日志与隐私**：仅记录匿名错误码/阶段；**不记录明文密码**；密钥只存于内存/安全存储，过期即销毁。
- **OTA**：联网后检查固件/应用版本，支持差分包；失败自动回滚。
- **批量配网**：App 支持附近设备多选、串行队列、SN 过滤；避免串扰。

---

# 测试用例（抽样）

- 路由器加密：WPA2/WPA3/混合；同名双频、Mesh。
- 频段：仅 2.4G/仅 5G/自动；密码错误；AP 关闭；RSSI<-75。
- DHCP 失败/静态 IP 冲突；企业网络（如有）。
- BLE 干扰/断连/MTU 小；分片丢失重传。
- 并发 20 台配网（串行队列）。

---

# 任务分解与里程碑（建议）

**T0‑T1（1 周）**

- 确认 DO/系统权限；冻结 GATT/协议与错误码表；生成出厂公钥流程与二维码模板。

**T1‑T3（2 周）**

- 设备端：GATT Server + Wi‑Fi 扫描/应用模块 + 状态机。
- 手机端：Flutter 工程 + BLE 封装 + ECDH/AES 封装 + 扫码 → 握手 → 扫描 → 配网 UI。

**T3‑T4（1 周）**

- SoftAP 回落链路；批量配网；埋点与 QA 覆盖；试产 FCT 工具。

---

# 附：Android TV 权限与 DO 提示

- 通过 OEM 预置或企业配备，将 App 设为 **Device Owner**（`dpm set-device-owner` 仅限出厂/测试）。
- 需要可调用系统 API 静默配置 Wi‑Fi；与 OEM 合作开放接口或以系统签名。

---

# 附：错误信息对用户的友好提示（示例）

- `2002 密码错误` → “密码不正确，请重新输入或靠近路由器后重试。”
- `2003 频段不匹配` → “当前网络仅支持 2.4G/5G，请选择兼容的网络。”
- `2004 DHCP 失败` → “无法获取 IP 地址，请重启路由器或改用静态 IP。”

---

> 本规范可直接作为对外发包与内部实现依据；如需，我可进一步提供 **握手帧二进制格式**、**分片协议细节** 与 **Flutter/Android TV 模板仓库结构**。

