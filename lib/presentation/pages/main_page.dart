import 'package:flutter/material.dart';
import '../../core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/presentation/pages/device_detail_page.dart';
import 'package:smart_display_mobile/presentation/pages/profile_page.dart';
import 'package:smart_display_mobile/presentation/pages/device_management_page.dart';
import '../../l10n/app_localizations.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  bool _showingDeviceDetail = false;

  void _openDeviceDetail([String? deviceId]) {
    setState(() {
      _showingDeviceDetail = true;
      _currentIndex = 0;
    });
  }

  void _openDeviceList() {
    setState(() {
      _showingDeviceDetail = false;
      _currentIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = <Widget>[
      // Tab 0: 设备（列表 或 详情）
      _showingDeviceDetail
          ? DeviceDetailPage(onBackToList: _openDeviceList)
          : DeviceManagementPage(
              onDeviceTapped: (_) => _openDeviceDetail(_),
            ),
      // Tab 1: 我的
      const ProfilePage(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            if (_currentIndex == 0 && _showingDeviceDetail == true) {
              // Stay as-is; user remains on detail inside 设备标签
            }
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.devices),
            label: l10n.devices_title,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: l10n.profile_title,
          ),
        ],
      ),
    );
  }
}
