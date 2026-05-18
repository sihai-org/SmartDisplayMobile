import 'package:flutter/material.dart';
import 'package:smart_display_mobile/presentation/pages/device_detail_page.dart';

class MainPage extends StatelessWidget {
  final String? initialDisplayDeviceId;
  const MainPage({super.key, this.initialDisplayDeviceId});

  @override
  Widget build(BuildContext context) {
    return DeviceDetailPage(deviceId: initialDisplayDeviceId);
  }
}
