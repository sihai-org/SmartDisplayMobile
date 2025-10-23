import 'package:flutter/material.dart';
import '../../core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/presentation/pages/device_detail_page.dart';
import 'package:smart_display_mobile/presentation/pages/profile_page.dart';

class MainPage extends StatefulWidget {
  final String? initialDeviceId;
  const MainPage({super.key, this.initialDeviceId});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  String? _detailDeviceId;

  @override
  void initState() {
    super.initState();
    // 若通过路由传入了 deviceId，则用于触发详情页的参数连接
    _detailDeviceId = widget.initialDeviceId;
  }

  @override
  void didUpdateWidget(covariant MainPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDeviceId != widget.initialDeviceId) {
      setState(() {
        _detailDeviceId = widget.initialDeviceId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = <Widget>[
      // Tab 0: 设备（始终显示详情；列表通过右上角按钮进入独立页面）
      DeviceDetailPage(
        deviceId: _detailDeviceId,
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
