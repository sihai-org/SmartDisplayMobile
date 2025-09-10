# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Essential Commands
```bash
# Install dependencies
flutter pub get

# Run code generation (for Freezed, JSON serialization, Riverpod)
flutter packages pub run build_runner build --delete-conflicting-outputs

# Development - iOS Simulator (specific device ID for testing)
flutter run -d "7B8C93DB-4AAE-4A95-8676-3C8B28D75BAF" --hot

# Development - Android
flutter run -d android

# Development - Web/Chrome  
flutter run -d chrome

# Production builds
flutter build apk --release                    # Android APK
flutter build ios --release                    # iOS (requires Xcode)

# Clean build
flutter clean && flutter pub get

# Code analysis and linting
flutter analyze

# Run tests
flutter test                                   # Unit tests
flutter test integration_test/                 # Integration tests
```


## Architecture Overview

### Clean Architecture Pattern
- **lib/core/**: Shared utilities, constants, themes, and base configurations
- **lib/features/**: Feature-specific modules with domain/presentation/data layers
- **lib/presentation/pages/**: UI screens and widgets

### Key Architectural Patterns

#### State Management - Riverpod
- Uses `StateNotifier` pattern for complex state
- Providers in `features/*/providers/` directories
- Auto-dispose with `ref.onDispose()` for resource cleanup

#### Navigation - Go Router
- Centralized routing in `lib/core/router/app_router.dart`
- Query parameters for passing data between screens
- Named routes with constants in `AppRoutes` class

#### Data Models - Freezed
- Immutable data classes with `.freezed.dart` and `.g.dart` generated files
- JSON serialization with `json_annotation`
- Run `build_runner` after modifying model classes

#### Feature Structure Example
```
features/qr_scanner/
├── models/          # Data models (Freezed classes)
├── providers/       # State management (StateNotifier)  
├── services/        # Business logic and external APIs
└── utils/          # Feature-specific utilities
```

### BLE Communication Architecture

#### Service UUIDs (from `lib/core/constants/ble_constants.dart`)
- Main Service: `0000A100-0000-1000-8000-00805F9B34FB`
- Device prefix: `AI-TV-`
- MTU: 247 preferred, 23-517 range

#### BLE Service Pattern
- `ble_service.dart`: Full implementation with all characteristics
- `ble_service_simple.dart`: Simplified version for basic connection testing
- Connection flow: Scan → Connect → Discover Services → Enable Notifications

### Permission Management
Smart permission handling to prevent repeated requests:
- Check existing permissions before requesting new ones
- Platform-specific permission handling (Android/iOS)
- Uses `permission_handler` package

## Key Dependencies & Their Usage

### Core State Management
- **flutter_riverpod** (^2.4.9): State management with auto-dispose
- **go_router** (^12.1.3): Declarative navigation

### BLE & Hardware
- **flutter_reactive_ble** (^5.3.1): BLE communication
- **mobile_scanner** (^3.5.6): QR code scanning
- **image_picker** (^1.0.4): Gallery access for QR scanning
- **permission_handler** (^11.0.1): Runtime permissions

### Code Generation
- **freezed** + **json_annotation**: Immutable data models
- **riverpod_generator**: Provider code generation
- **build_runner**: Code generation orchestration

### Security (for future phases)
- **cryptography** (^2.5.0): X25519 ECDH + AES-GCM encryption
- **flutter_secure_storage** (^8.1.0): Secure key storage

## Development Workflow

### Code Generation
After modifying any model classes or providers:
```bash
flutter packages pub run build_runner build --delete-conflicting-outputs
```

### Testing Workflow
1. Run Flutter app on iOS simulator or Android device
2. Use real BLE devices for testing
3. Test BLE connection flow end-to-end

### Platform-Specific Notes

#### iOS
- Requires specific simulator device ID: `7B8C93DB-4AAE-4A95-8676-3C8B28D75BAF`
- BLE testing works on both simulator and real devices
- Camera permissions required for QR scanning

#### Android
- Release APK builds tested and functional
- Smart permission management prevents repeated requests
- Gradle 8.7, AGP 8.6.0, Kotlin 1.8.10

#### Web
- Limited BLE support (Chrome only)
- UI and navigation fully functional
- QR scanning may have limitations

## Critical Implementation Details

### BLE Type Conflicts Resolution
- Uses `SimpleBLEScanResult` custom class to avoid conflicts
- Type conversion between reactive_ble service layers
- Proper stream handling with `BleStatus.ready` (not `poweredOn`)

### Resource Management
- All providers auto-dispose with `ref.onDispose()`
- Mobile scanner controllers properly disposed
- BLE connections cleaned up on navigation

### Error Handling
- Uses custom `Result` type in `lib/core/utils/result.dart`
- Comprehensive error states in all providers
- User-friendly error messages with recovery actions

## Current Implementation Status

### Completed Features ✅
- QR code scanning (camera + image picker)
- BLE device discovery and connection
- Clean architecture foundation
- Cross-platform builds (iOS, Android, Web)
- Smart permission management
- End-to-end testing with real BLE devices

### Next Development Phases
- **Phase 4**: X25519 ECDH key exchange + AES-GCM encryption
- **Phase 5**: Wi-Fi provisioning with secure credential transfer  
- **Phase 6**: Device management and pairing history

## Important Notes

- **Never commit sensitive data**: All encryption keys stored in memory only
- **Follow existing patterns**: Use established provider/service/model structure
- **Test with real devices**: Always verify changes with actual BLE devices
- **Run code generation**: After model changes, regenerate `.freezed.dart` and `.g.dart` files
- **Chinese UI text**: App supports both Chinese and English (Chinese primary)
- 每次任务结束, 如果有代码修改，确认提交代码