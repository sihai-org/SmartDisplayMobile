# SmartDisplay Mobile App 产品规格文档

**版本**: 1.0  
**日期**: 2025-01-08  
**项目**: 智能显示器配网手机应用

---

## 1. 产品概述

### 1.1 项目背景

开发一款 Flutter 手机应用，用于为无输入设备的智能显示器（Android TV）提供 Wi-Fi 网络配置功能。通过蓝牙低功耗（BLE）技术实现安全的网络凭据传输。

### 1.2 核心功能

- **二维码扫描**: 扫描显示器屏幕二维码获取设备信息
- **智能连接**: 基于二维码信息自动连接对应 BLE 设备
- **安全通信**: 端到端加密的网络凭据传输
- **网络配置**: 安全传输 Wi-Fi 凭据并监控配网状态
- **设备管理**: 设备绑定、命名和状态监控

### 1.3 技术架构

- **手机端**: Flutter 跨平台应用（iOS/Android）
- **通信协议**: BLE GATT 服务
- **安全机制**: X25519 ECDH + AES-GCM 加密
- **身份验证**: 设备公钥二维码验证

---

## 2. 功能规格

### 2.1 用户流程

1. **应用启动** → 权限申请（相机、蓝牙、位置）
2. **扫描二维码** → 对准显示器屏幕上的二维码
3. **解析设备信息** → 获取设备公钥、序列号等信息
4. **自动连接 BLE** → 根据设备信息自动连接对应 BLE 设备
5. **安全握手** → 使用公钥建立加密会话
6. **选择网络** → 显示可用 Wi-Fi 列表
7. **输入凭据** → 用户输入 Wi-Fi 密码
8. **配网过程** → 实时显示连接状态
9. **完成绑定** → 设备命名并加入管理列表

### 2.2 核心模块

#### 2.2.1 二维码扫描模块

- **相机扫描**: 使用手机相机扫描屏幕二维码
- **数据解析**: 解析二维码中的设备信息（序列号、公钥等）
- **设备识别**: 根据序列号匹配对应的 BLE 设备
- **自动连接**: 扫码成功后自动发起 BLE 连接

#### 2.2.2 BLE 连接模块

- **设备搜索**: 根据序列号搜索匹配的 BLE 设备
- **连接建立**: 自动连接到目标 BLE 设备
- **身份验证**: 验证设备公钥指纹匹配二维码信息
- **密钥协商**: X25519 ECDH 生成会话密钥
- **数据加密**: AES-GCM 加密敏感数据

#### 2.2.3 网络配置模块

- **Wi-Fi 扫描**: 获取设备端扫描的网络列表
- **网络选择**: 显示 SSID、信号强度、加密类型
- **凭据输入**: 密码输入界面（支持显示/隐藏）
- **配置传输**: 加密发送网络凭据

#### 2.2.4 状态监控模块

- **实时状态**: 显示配网进度（applying→connecting→dhcp→online）
- **错误处理**: 友好的错误提示和重试机制
- **成功确认**: 显示设备 IP 地址和网络信息

#### 2.2.5 设备管理模块

- **设备列表**: 已配置设备的管理界面
- **设备信息**: 显示型号、序列号、IP 地址等
- **设备控制**: 重新配网、删除设备等操作

### 2.3 BLE GATT 服务设计

#### 服务 UUID

`0000A100-0000-1000-8000-00805F9B34FB`

#### 特征值列表

1. **Device_Info** (Read) - `0000A101-..`
   - 设备型号、固件版本、序列号、能力信息
2. **WiFi_Scan_Request** (Write) - `0000A102-..`
   - 触发设备 Wi-Fi 扫描
3. **WiFi_Scan_Result** (Notify/Read) - `0000A103-..`
   - 返回 Wi-Fi 扫描结果列表
4. **Session_Nonce** (Read/Notify) - `0000A104-..`
   - 握手随机数
5. **Secure_Handshake** (Write/Notify) - `0000A105-..`
   - 安全握手数据交换
6. **Provision_Request** (Write) - `0000A106-..`
   - 加密的配网请求
7. **Provision_Status** (Notify/Read) - `0000A107-..`
   - 配网状态通知
8. **OOB_QR_Info** (Read) - `0000A108-..`
   - 设备公钥等 OOB 信息

### 2.4 数据格式

#### 二维码格式

```
aidisplay:1|sn=AD12345678|pk=BASE64URL(X25519_public_key)|fp=BASE64URL(SHA256(pk))
```

#### 配网请求格式（加密前）

```json
{
  "op": "provision",
  "seq": 102,
  "ts": 1736045132,
  "payload": {
    "ssid": "Home_WiFi",
    "password": "********",
    "bssid": "aa:bb:cc:dd:ee:ff",
    "band": "auto"
  }
}
```

#### 状态响应格式

```json
{
  "op": "status",
  "seq": 102,
  "phase": "online",
  "error_code": 0,
  "ip": "192.168.1.100",
  "gateway": "192.168.1.1"
}
```

---

## 3. 技术实现

### 3.1 Flutter 架构设计

#### 3.1.1 项目结构

```
lib/
├── main.dart
├── core/
│   ├── constants/
│   ├── errors/
│   └── utils/
├── data/
│   ├── datasources/
│   ├── models/
│   └── repositories/
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── usecases/
├── presentation/
│   ├── pages/
│   ├── widgets/
│   └── providers/
└── services/
    ├── ble/
    ├── crypto/
    └── qr/
```

#### 3.1.2 核心依赖包

```yaml
dependencies:
  flutter: ^3.16.0
  flutter_reactive_ble: ^5.3.1 # BLE通信
  mobile_scanner: ^3.5.6 # 二维码扫描
  cryptography: ^2.5.0 # 加密算法
  flutter_secure_storage: ^9.0.0 # 安全存储
  riverpod: ^2.4.9 # 状态管理
  go_router: ^12.1.3 # 路由管理
  freezed: ^2.4.7 # 数据类生成
  json_annotation: ^4.8.1 # JSON序列化
```

#### 3.1.3 状态管理

使用 Riverpod 进行状态管理，主要 Provider 包括：

- `deviceDiscoveryProvider`: 设备发现状态
- `bleConnectionProvider`: BLE 连接状态
- `provisioningProvider`: 配网流程状态
- `deviceListProvider`: 已配置设备列表

### 3.2 BLE 通信实现

#### 3.2.1 二维码扫描后的 BLE 连接

```dart
class QrBasedBleConnector {
  Future<void> connectToDeviceByQr(QrData qrData) async {
    // 根据二维码信息搜索对应BLE设备
    final devices = await scanForDevicesWithSerial(qrData.serialNumber);
    final targetDevice = devices.firstWhere(
      (device) => device.name.contains(qrData.serialNumber)
    );

    // 自动连接
    await flutterReactiveBle.connectToDevice(id: targetDevice.id);
  }
}
```

#### 3.2.2 GATT 服务交互

```dart
class GattService {
  Future<void> writeCharacteristic(
    String deviceId,
    Uuid characteristicId,
    List<int> value
  ) async {
    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicId,
      deviceId: deviceId,
    );
    await flutterReactiveBle.writeCharacteristicWithResponse(
      characteristic,
      value: value
    );
  }
}
```

### 3.3 加密实现

#### 3.3.1 密钥交换

```dart
class CryptoService {
  Future<SessionKeys> performECDH(List<int> devicePublicKey) async {
    final keyPair = await X25519().newKeyPair();
    final sharedSecret = await x25519(keyPair.secretKey, devicePublicKey);
    final sessionKey = await hkdfSha256(sharedSecret, info: "aidisplay-provision");
    return SessionKeys(sessionKey: sessionKey, publicKey: keyPair.publicKey);
  }
}
```

#### 3.3.2 数据加密

```dart
Future<List<int>> encryptPayload(Map<String, dynamic> payload, List<int> key) async {
  final plaintext = utf8.encode(json.encode(payload));
  final nonce = SecureRandom().nextBytes(12);
  final cipher = await AesGcm.with256bits().encrypt(plaintext, secretKey: key, nonce: nonce);
  return [...nonce, ...cipher.cipherText, ...cipher.mac.bytes];
}
```

---

## 4. 测试方案

### 4.1 Mac BLE 模拟器

#### 4.1.1 模拟器功能

创建一个 macOS 命令行工具，模拟智能显示器的 BLE GATT 服务：

- **二维码显示**: 在终端显示二维码（包含设备公钥和序列号）
- **BLE 广播**: 使用序列号作为设备名称的一部分进行广播
- **GATT 服务**: 实现完整的 8 个特征值
- **Wi-Fi 模拟**: 返回预设的 Wi-Fi 网络列表
- **状态模拟**: 模拟配网过程的各个阶段
- **加密支持**: 完整的 ECDH 握手和 AES-GCM 加解密

#### 4.1.2 实现技术栈

- **语言**: Swift
- **框架**: Core Bluetooth (CBPeripheralManager)
- **加密**: CryptoKit
- **运行环境**: macOS 命令行工具

#### 4.1.3 使用方式

```bash
# 启动模拟器，自动显示二维码
./ble_simulator --serial "AD20250108001"

# 指定模拟的Wi-Fi网络
./ble_simulator --serial "AD20250108001" --wifi-networks "Home_2.4G,Home_5G,Office_WiFi"

# 仅显示二维码（不启动BLE服务）
./ble_simulator --show-qr-only --serial "AD20250108001"
```

### 4.2 测试用例设计

#### 4.2.1 单元测试

- **加密模块测试**: ECDH 密钥交换、AES-GCM 加解密
- **数据解析测试**: 二维码解析、JSON 序列化
- **BLE 通信测试**: Mock BLE 服务的数据传输
- **状态管理测试**: Provider 状态变化验证

#### 4.2.2 集成测试

- **设备发现流程**: 扫描 → 发现 → 连接
- **安全握手流程**: 二维码扫描 → 密钥协商 → 会话建立
- **配网完整流程**: Wi-Fi 扫描 → 凭据输入 → 状态监控 → 完成确认
- **错误处理流程**: 各种异常情况的处理

#### 4.2.3 端到端测试

使用 Mac 模拟器进行完整的用户流程测试：

1. **正常配网流程**

   - 启动模拟器（自动显示二维码）
   - 手机 App 扫描屏幕二维码
   - App 自动识别并连接对应 BLE 设备
   - 建立安全会话并选择 Wi-Fi
   - 输入密码并验证配网状态

2. **异常场景测试**

   - BLE 连接中断重连
   - 密码错误处理
   - 超时重试机制
   - 多设备并发处理

3. **兼容性测试**
   - iOS 不同版本测试
   - Android 不同版本测试
   - 不同手机型号的 BLE 兼容性

### 4.3 测试环境配置

#### 4.3.1 开发环境

```yaml
# 开发工具版本
Flutter: 3.16.7+
Dart: 3.2.4+
Xcode: 15.0+
Android Studio: 2023.1+

# 测试设备
iOS: iPhone 12+ (iOS 15.0+)
Android: Pixel 6+ (Android 11+)
macOS: MacBook Pro (macOS 13.0+)
```

#### 4.3.2 自动化测试

```yaml
# GitHub Actions CI配置
name: Flutter Test
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter test
      - run: flutter test integration_test/
```

---

## 5. 开发计划

### 5.1 Phase 1: 基础架构 (Week 1-2)

- **项目初始化**: Flutter 项目创建和依赖配置
- **架构搭建**: 目录结构、状态管理、路由配置
- **UI 框架**: 基础页面和组件开发
- **BLE 封装**: BLE 通信基础服务实现

**验收标准**:

- ✅ 项目可正常编译和运行
- ✅ BLE 权限申请和基础扫描功能
- ✅ 基础 UI 导航流程完整

### 5.2 Phase 2: 核心功能 (Week 3-4)

- **设备发现**: BLE 设备扫描和列表显示
- **二维码扫描**: 集成扫码功能和数据解析
- **加密实现**: ECDH 密钥交换和 AES-GCM 加解密
- **GATT 通信**: 完整的特征值读写实现

**验收标准**:

- ✅ 可发现和连接 BLE 设备
- ✅ 二维码扫描解析正确
- ✅ 加密握手流程完整
- ✅ GATT 特征值操作正常

### 5.3 Phase 3: 配网流程 (Week 5-6)

- **Wi-Fi 管理**: Wi-Fi 列表显示和选择
- **凭据输入**: 密码输入界面和验证
- **状态监控**: 配网进度显示和错误处理
- **设备管理**: 设备绑定和信息存储

**验收标准**:

- ✅ 完整配网流程可执行
- ✅ 状态监控实时更新
- ✅ 错误处理友好提示
- ✅ 设备信息正确存储

### 5.4 Phase 4: 测试优化 (Week 7-8)

- **Mac 模拟器**: BLE 外设模拟器开发
- **测试覆盖**: 单元测试和集成测试
- **UI 优化**: 用户体验优化和动画效果
- **性能优化**: BLE 连接稳定性和响应速度

**验收标准**:

- ✅ Mac 模拟器功能完整
- ✅ 测试覆盖率>80%
- ✅ 用户体验流畅
- ✅ 性能指标达标

### 5.5 Phase 5: 发布准备 (Week 9-10)

- **兼容性测试**: 多设备多系统测试
- **安全审计**: 加密实现和数据安全检查
- **文档完善**: 用户手册和开发文档
- **应用商店准备**: 应用描述、截图、隐私政策

**验收标准**:

- ✅ 所有目标设备测试通过
- ✅ 安全审计无重大问题
- ✅ 文档完整准确
- ✅ 应用商店提交就绪

---

## 6. 质量保证

### 6.1 代码质量

- **代码规范**: 使用 Dart/Flutter 官方代码规范
- **静态分析**: 集成 dart analyzer 和 flutter_lints
- **代码审查**: 所有代码变更必须通过审查
- **测试覆盖**: 单元测试覆盖率要求 80%+

### 6.2 安全要求

- **加密强度**: 使用业界标准的 X25519 和 AES-256-GCM
- **密钥管理**: 会话密钥仅存储在内存中，及时清理
- **数据保护**: Wi-Fi 密码等敏感信息不落盘记录
- **通信安全**: 所有敏感数据端到端加密传输

### 6.3 性能指标

- **启动时间**: 应用冷启动时间<3 秒
- **连接时间**: BLE 设备连接建立时间<5 秒
- **配网时间**: 完整配网流程时间<30 秒
- **电池消耗**: BLE 扫描时电池消耗<5%/小时

### 6.4 兼容性要求

- **iOS 版本**: iOS 13.0+
- **Android 版本**: Android 8.0+ (API Level 26+)
- **BLE 版本**: Bluetooth 5.0+
- **屏幕适配**: 支持 4.7"-6.7"屏幕尺寸

---

## 7. 风险评估

### 7.1 技术风险

- **BLE 兼容性**: 不同手机厂商的 BLE 实现差异
  - **缓解措施**: 广泛的设备测试和兼容性处理
- **加密性能**: 移动设备上的加密计算性能
  - **缓解措施**: 异步处理和性能优化
- **Flutter 生态**: 第三方包的稳定性和维护
  - **缓解措施**: 选择成熟稳定的包，准备备选方案

### 7.2 业务风险

- **用户体验**: 配网流程复杂度对用户的影响
  - **缓解措施**: 简化流程，提供详细指导
- **支持成本**: 不同设备兼容性带来的支持成本
  - **缓解措施**: 完善的错误诊断和自助解决方案

### 7.3 项目风险

- **开发进度**: 技术难点可能影响开发进度
  - **缓解措施**: 预留缓冲时间，分阶段交付
- **资源依赖**: 依赖显示器端配合调试
  - **缓解措施**: Mac 模拟器独立开发和测试

---

## 8. 交付物清单

### 8.1 代码交付

- ✅ Flutter 应用源代码（iOS/Android）
- ✅ Mac BLE 模拟器源代码
- ✅ 单元测试和集成测试代码
- ✅ CI/CD 配置文件

### 8.2 文档交付

- ✅ 技术架构文档
- ✅ API 接口文档
- ✅ 用户操作手册
- ✅ 开发部署指南

### 8.3 测试交付

- ✅ 测试用例和测试报告
- ✅ 性能测试报告
- ✅ 兼容性测试报告
- ✅ 安全审计报告

### 8.4 发布交付

- ✅ 应用商店可发布的安装包
- ✅ 应用商店提交材料
- ✅ 隐私政策和用户协议
- ✅ 用户手册和 FAQ

---

## 9. 成功标准

### 9.1 功能标准

- [x] 可成功发现和连接智能显示器设备
- [x] 二维码扫描和安全握手 100%成功率
- [x] Wi-Fi 配网成功率>95%（正确密码情况下）
- [x] 支持 iOS 和 Android 双平台

### 9.2 性能标准

- [x] 设备发现时间<10 秒
- [x] 配网完整流程时间<60 秒
- [x] 应用响应时间<1 秒
- [x] 崩溃率<0.1%

### 9.3 用户体验标准

- [x] 操作流程直观易懂
- [x] 错误提示清晰有用
- [x] 界面美观符合设计规范
- [x] 用户满意度>4.0/5.0

---

**文档维护**: 本文档随开发进展持续更新  
**负责人**: 开发团队  
**审批人**: 产品经理、技术负责人
