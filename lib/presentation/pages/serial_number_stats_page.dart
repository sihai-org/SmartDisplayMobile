import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/log/app_log.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/qr_data_parser.dart';
import '../../core/models/device_qr_data.dart';
import 'qr_scanner_page.dart';

class SerialNumberStatsPage extends ConsumerStatefulWidget {
  const SerialNumberStatsPage({super.key});

  @override
  ConsumerState<SerialNumberStatsPage> createState() =>
      _SerialNumberStatsPageState();
}

class _SerialNumberStatsPageState extends ConsumerState<SerialNumberStatsPage> {
  final _serialNumberController = TextEditingController();

  String? _scannedLink;
  DeviceQrData? _parsed;
  String? _parseError;
  bool _isReporting = false;

  @override
  void dispose() {
    _serialNumberController.dispose();
    super.dispose();
  }

  int? get _serialNumber {
    final raw = _serialNumberController.text.trim();
    if (raw.isEmpty) return null;
    final n = int.tryParse(raw);
    if (n == null || n <= 0) return null;
    return n;
  }

  Future<void> _scan() async {
    final result = await context.push<String>(
      AppRoutes.qrScanner,
      extra: QrScannerSuccessAction.popResult,
    );

    final text = result?.trim();
    if (text == null || text.isEmpty) return;

    DeviceQrData? parsed;
    String? parseError;
    try {
      parsed = QrDataParser.fromQrContent(text);
    } catch (e) {
      parseError = e.toString();
    }

    if (!mounted) return;
    setState(() {
      _serialNumberController.clear();
      _scannedLink = text;
      _parsed = parsed;
      _parseError = parseError;
    });
  }

  Future<void> _copyText(String? text) async {
    final value = text?.trim();
    if (value == null || value.isEmpty) return;
    final copiedMsg = context.l10n.copied;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    Fluttertoast.showToast(msg: copiedMsg);
  }

  String? _getUrlQueryParam(String key) {
    final link = _scannedLink?.trim();
    if (link == null || link.isEmpty) return null;
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    final value = uri.queryParameters[key]?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> _report() async {
    final n = _serialNumber;
    final link = _scannedLink;
    if (_isReporting) return;
    if (n == null || link == null || link.isEmpty) return;

    final accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      Fluttertoast.showToast(msg: context.l10n.login_expired);
      return;
    }

    setState(() => _isReporting = true);
    try {
      final response = await http.post(
        Uri.parse('https://api.smartdisplay.vzngpt.com/monitorapp/report'),
        headers: {
          'X-Device-Id': 'test',
          'X-Access-Token': accessToken,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'data': {
            'number': n,
            'link': link,
          },
        }),
      );

      if (response.statusCode != 200) {
        AppLog.instance.warning(
          '[SerialNumberStats] report non-200: ${response.statusCode} ${response.body}',
          tag: 'SerialStats',
        );
        Fluttertoast.showToast(msg: '上报失败：${response.statusCode}');
        return;
      }

      AppLog.instance.info(
        '[SerialNumberStats] reported: serial=$n, linkLen=${link.length}, id=${_parsed?.displayDeviceId}',
        tag: 'SerialStats',
      );
      Fluttertoast.showToast(msg: context.l10n.reported_success);

      if (!mounted) return;
      setState(() {
        _serialNumberController.clear();
        _scannedLink = null;
        _parsed = null;
        _parseError = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isReporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final canCopy = (_scannedLink?.isNotEmpty ?? false);
    final canReport = _serialNumber != null && canCopy;
    final urlN = _getUrlQueryParam('n');
    final urlId = _getUrlQueryParam('id');

    const labelStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: Colors.black87,
    );
    const textStyle = TextStyle(fontSize: 16, color: Colors.black54);
    Widget formItem({
      required int index,
      required Widget label,
      required Widget value,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTextStyle.merge(
            style: labelStyle,
            child: Row(
              children: [
                Text('$index. '),
                Expanded(child: label),
              ],
            ),
          ),
          const SizedBox(height: 8),
          value,
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.serial_number_stats)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle.merge(
                style: textStyle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    formItem(
                      index: 1,
                      label: Text(l10n.scan_qr),
                      value: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _scan,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(l10n.tap_to_scan),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    formItem(
                      index: 2,
                      label: Text(l10n.serial_number),
                      value: TextField(
                        controller: _serialNumberController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: textStyle,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: l10n.positive_integer_hint,
                          border: const UnderlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 12),
                    formItem(
                      index: 3,
                      label: Row(
                        children: [
                          Text(l10n.original_link),
                          if (canCopy) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _copyText(_scannedLink),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                l10n.copy_link,
                                style: TextStyle(
                                  fontSize:
                                      Theme.of(context).textTheme.labelLarge?.fontSize,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      value: SelectableText(
                        _scannedLink ?? '-',
                        style: textStyle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    formItem(
                      index: 4,
                      label: Text(l10n.device_name),
                      value: SelectableText(urlN ?? '-', style: textStyle),
                    ),
                    const SizedBox(height: 8),
                    formItem(
                      index: 5,
                      label: Text(l10n.device_id),
                      value: SelectableText(urlId ?? '-', style: textStyle),
                    ),
                    if (_parseError != null) ...[
                      const SizedBox(height: 8),
                      formItem(
                        index: 6,
                        label: Text(l10n.parse_failed),
                        value: Text(
                          '${l10n.parse_failed}: ${_parseError!}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 14,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canReport && !_isReporting ? _report : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                disabledBackgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.35),
                disabledForegroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimary.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isReporting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(l10n.report),
                      ],
                    )
                  : Text(l10n.report),
            ),
          ),
        ],
      ),
    );
  }
}
