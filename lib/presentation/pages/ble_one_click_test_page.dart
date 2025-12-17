import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ble/ble_one_click_test_runner.dart';
import '../../core/models/device_qr_data.dart';
import '../../core/providers/app_state_provider.dart';

class BleOneClickTestPage extends ConsumerStatefulWidget {
  const BleOneClickTestPage({super.key});

  @override
  ConsumerState<BleOneClickTestPage> createState() => _BleOneClickTestPageState();
}

class _BleOneClickTestPageState extends ConsumerState<BleOneClickTestPage> {
  BleOneClickTestRunner? _runner;
  bool _running = false;
  BleOneClickTestReport? _report;
  final List<String> _logs = [];

  void _appendLog(String line) {
    setState(() {
      _logs.add('${DateTime.now().toIso8601String()} $line');
      if (_logs.length > 400) _logs.removeRange(0, _logs.length - 400);
    });
  }

  DeviceQrData? _resolveTarget() {
    final qr = ref.read(appStateProvider).scannedQrData;
    if (qr == null) return null;
    if (qr.displayDeviceId.isEmpty || qr.publicKey.isEmpty) return null;
    if (qr.bleDeviceId.isEmpty || qr.deviceName.isEmpty) return null;
    return qr;
  }

  Future<void> _start() async {
    final target = _resolveTarget();
    if (target == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到目标设备：请先扫码进入绑定流程（拿到 DeviceQrData）')),
      );
      return;
    }

    setState(() {
      _running = true;
      _report = null;
      _logs.clear();
    });

    final runner = BleOneClickTestRunner(onLog: _appendLog);
    _runner = runner;

    try {
      final report = await runner.run(
        ref: ref,
        target: target,
        config: const BleOneClickTestConfig(
          stabilityCycles: 10,
          stressMessages: 50,
        ),
      );
      if (!mounted) return;
      setState(() {
        _report = report;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _running = false;
      });
    }
  }

  void _stop() {
    _runner?.cancel();
    _appendLog('Stop requested');
  }

  Future<void> _copyReport() async {
    final r = _report;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: r.toPrettyText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制测试结果到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = ref.watch(appStateProvider).scannedQrData;
    final targetText = target == null
        ? '目标设备：无（请先扫码）'
        : '目标设备：${target.deviceName} / ${target.displayDeviceId}';

    final reportText = _report?.toPrettyText() ?? '';
    final report = _report;
    final summaryText = report == null
        ? ''
        : '结果：${report.ok ? 'PASS' : 'FAIL'}  '
            '耗时：${report.finishedAt.difference(report.startedAt).inSeconds}s';

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE 一键测试'),
        actions: [
          IconButton(
            onPressed: _report == null ? null : _copyReport,
            icon: const Icon(Icons.copy),
            tooltip: '复制结果',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(targetText),
            if (summaryText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                summaryText,
                style: TextStyle(
                  color: report!.ok ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _running ? null : _start,
                    child: Text(_running ? '测试中…' : '开始一键测试'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _running ? _stop : null,
                  child: const Text('停止'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_running) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: '结果'),
                        Tab(text: '日志'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _ResultView(reportText: reportText),
                          _LogView(lines: _logs),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.reportText});

  final String reportText;

  @override
  Widget build(BuildContext context) {
    if (reportText.isEmpty) {
      return const Center(child: Text('尚未产生报告'));
    }
    return SingleChildScrollView(
      child: SelectableText(
        reportText,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const Center(child: Text('暂无日志'));
    }
    return ListView.builder(
      itemCount: lines.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          lines[index],
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
