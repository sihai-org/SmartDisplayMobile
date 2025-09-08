# SmartDisplay Mobile App

🎯 **智能显示器配网手机应用** - 基于Flutter开发的跨平台配网应用，通过BLE和二维码技术为无输入智能显示器提供安全的Wi-Fi配置功能。

## 📋 项目概述

### 核心功能
- 📱 **二维码扫描** - 扫描显示器屏幕获取设备信息
- 🔗 **智能连接** - 自动连接对应的BLE设备  
- 🔐 **安全通信** - X25519 ECDH + AES-GCM端到端加密
- 📡 **网络配置** - 安全传输Wi-Fi凭据并实时监控配网状态
- 🛠️ **设备管理** - 设备绑定、命名和状态监控

### 技术架构
- **前端**: Flutter 3.16+ (iOS/Android)
- **通信**: BLE GATT服务
- **加密**: X25519 ECDH密钥交换 + AES-256-GCM
- **测试**: Mac BLE模拟器

## 🚀 快速开始

### 环境要求
- Flutter 3.16.7+
- Dart 3.2.4+
- iOS 13.0+ / Android 8.0+
- Xcode 15.0+ / Android Studio 2023.1+

### 安装依赖
```bash
flutter pub get
```

### 运行应用
```bash
# iOS
flutter run -d ios

# Android  
flutter run -d android
```

### 测试
```bash
# 单元测试
flutter test

# 集成测试
flutter test integration_test/
```

## 📚 项目文档

### 核心文档
- **[产品规格文档](docs/product-specification.md)** - 完整的产品功能规格、技术实现和开发计划
- **[技术方案概述](docs/tech-solution.md)** - BLE配网技术方案总体介绍  
- **[技术方案详细版](docs/tech-solution-details-1.0.md)** - 详细的技术实现方案和协议设计

### 文档导览

| 文档 | 描述 | 适用人群 |
|------|------|----------|
| [产品规格文档](docs/product-specification.md) | 🎯 **完整产品规格** - 功能定义、技术架构、开发计划、测试方案 | 项目经理、开发团队、测试团队 |
| [技术方案概述](docs/tech-solution.md) | 💡 **技术方案精要** - BLE配网核心技术和流程介绍 | 技术负责人、架构师 |
| [技术方案详细版](docs/tech-solution-details-1.0.md) | 🔧 **实现细节** - 协议设计、安全方案、生产部署 | 开发工程师、安全工程师 |

## 🏗️ 项目结构

```
SmartDisplayMobile/
├── lib/                    # Flutter应用源码
│   ├── main.dart          # 应用入口
│   ├── core/              # 核心工具和常量
│   ├── data/              # 数据层（API、本地存储）
│   ├── domain/            # 业务逻辑层
│   ├── presentation/      # UI展示层
│   └── services/          # 服务层（BLE、加密、二维码）
├── test/                  # 单元测试
├── integration_test/      # 集成测试
├── docs/                  # 项目文档
├── android/               # Android平台代码
├── ios/                   # iOS平台代码
└── README.md             # 项目说明
```

## 🔧 核心依赖

```yaml
dependencies:
  flutter_reactive_ble: ^5.3.1      # BLE通信
  mobile_scanner: ^3.5.6            # 二维码扫描
  cryptography: ^2.5.0              # 加密算法
  flutter_secure_storage: ^9.0.0    # 安全存储
  riverpod: ^2.4.9                  # 状态管理
  go_router: ^12.1.3                # 路由管理
```

## 📋 开发计划

| 阶段 | 时间 | 主要任务 | 状态 |
|------|------|----------|------|
| Phase 1 | Week 1-2 | 基础架构搭建 | 🟡 进行中 |
| Phase 2 | Week 3-4 | 核心功能开发 | ⏳ 待开始 |
| Phase 3 | Week 5-6 | 配网流程实现 | ⏳ 待开始 |
| Phase 4 | Week 7-8 | 测试和优化 | ⏳ 待开始 |
| Phase 5 | Week 9-10 | 发布准备 | ⏳ 待开始 |

## 🔄 用户流程

```mermaid
graph TD
    A[应用启动] --> B[权限申请]
    B --> C[扫描二维码]
    C --> D[解析设备信息]
    D --> E[自动连接BLE]
    E --> F[安全握手]
    F --> G[选择Wi-Fi网络]
    G --> H[输入密码]
    H --> I[配网过程]
    I --> J[完成绑定]
```

## 🛡️ 安全特性

- **🔐 端到端加密** - X25519 ECDH密钥交换 + AES-256-GCM加密
- **🔑 公钥验证** - 基于设备出厂公钥的身份验证
- **🚫 零明文存储** - Wi-Fi密码等敏感信息不落盘
- **⏰ 会话管理** - 密钥仅存储在内存中，及时清理

## 🧪 测试方案

### Mac BLE模拟器
为了独立测试手机端功能，项目包含一个Mac BLE模拟器：
- 模拟智能显示器的BLE GATT服务
- 在终端显示二维码供手机App扫描
- 完整的加密握手和配网状态模拟

### 测试覆盖
- ✅ 单元测试：加密、数据解析、状态管理
- ✅ 集成测试：BLE通信、配网流程
- ✅ 端到端测试：完整用户流程验证
- ✅ 兼容性测试：多设备多系统验证

## 📞 支持与反馈

- **🐛 问题反馈** - [GitHub Issues](https://github.com/sihai-org/SmartDisplayMobile/issues)
- **📖 技术文档** - 参见 [docs/](docs/) 目录
- **💡 功能建议** - 通过Issue提交功能请求

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

---

**开发团队**: Sihai Organization  
**最后更新**: 2025-01-08  
**版本**: 1.0.0
