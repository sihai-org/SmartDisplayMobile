import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionManager {
  static Future<bool> ensureCamera() async {
    // iOS/Android: request camera at runtime
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;

    final result = await Permission.camera.request();
    return result.isGranted;
  }

  static Future<bool> ensureGalleryReadIfNeeded() async {
    // Only when using gallery-based scanning. Optional here.
    if (Platform.isIOS) {
      final s = await Permission.photos.status;
      if (s.isGranted) return true;
      if (s.isPermanentlyDenied) return false;
      final r = await Permission.photos.request();
      return r.isGranted;
    }

    // Android 13+: READ_MEDIA_IMAGES, older: READ_EXTERNAL_STORAGE
    final photos = Permission.photos; // permission_handler maps correctly per-API
    final s = await photos.status;
    if (s.isGranted) return true;
    if (s.isPermanentlyDenied) return false;
    final r = await photos.request();
    return r.isGranted;
  }

  static Future<bool> ensureBleScanAndConnect() async {
    // Handle platform and API differences
    final perms = <Permission>[];

    if (Platform.isAndroid) {
      // Android 12+ require bluetoothScan/connect; older need location
      if (!(await Permission.bluetoothScan.isGranted)) {
        perms.add(Permission.bluetoothScan);
      }
      if (!(await Permission.bluetoothConnect.isGranted)) {
        perms.add(Permission.bluetoothConnect);
      }

      // On Android <= 11, location is still required for BLE scans
      if (!(await Permission.locationWhenInUse.isGranted)) {
        perms.add(Permission.locationWhenInUse);
      }
    } else if (Platform.isIOS) {
      // iOS: permission is implicit via CoreBluetooth; app must include Info.plist keys.
      // permission_handler exposes bluetooth & location as no-ops/granted when not applicable.
      // We still request so settings sheet can appear if needed.
      if (!(await Permission.bluetooth.isGranted)) {
        perms.add(Permission.bluetooth);
      }
      if (!(await Permission.locationWhenInUse.isGranted)) {
        perms.add(Permission.locationWhenInUse);
      }
    }

    if (perms.isEmpty) return true;
    final results = await perms.request();
    return results.values.every((r) => r.isGranted);
  }

  static Future<bool> openSettings() => openAppSettings();
}

