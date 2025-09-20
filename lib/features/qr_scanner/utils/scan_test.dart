import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Scaffold(body: BleScanner()));
  }
}

class BleScanner extends StatefulWidget {
  @override
  State<BleScanner> createState() => _BleScannerState();
}

class _BleScannerState extends State<BleScanner> {
  final _ble = FlutterReactiveBle();
  late Stream<DiscoveredDevice> _scanStream;
  final List<DiscoveredDevice> _devices = [];

  @override
  void initState() {
    super.initState();
    _scanStream = _ble.scanForDevices(
      withServices: [], // 不过滤
      scanMode: ScanMode.balanced,
      requireLocationServicesEnabled: false,
    );

    _scanStream.listen((device) {
      if (!_devices.any((d) => d.id == device.id)) {
        setState(() {
          _devices.add(device);
        });
      }
      print("发现设备: ${device.name} / id=${device.id} / uuids=${device.serviceUuids}");
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: _devices
          .map((d) => ListTile(
        title: Text(d.name.isNotEmpty ? d.name : "Unknown"),
        subtitle: Text("id=${d.id}\nUUIDs=${d.serviceUuids}"),
      ))
          .toList(),
    );
  }
}
