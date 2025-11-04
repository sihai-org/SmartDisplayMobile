import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../core/l10n/l10n_extensions.dart';

// TODO: 缺少返回按钮
// TODO: 这个解析很奇怪
/// 扫码无法解析时跳转使用（qr_scanner_page.dart）
/// 启动页兜底也会用到（splash_page.dart）
class QrCodeResultPage extends StatelessWidget {
  final String text;
  const QrCodeResultPage({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final decoded = Uri.decodeComponent(text);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.qr_content_title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.qr_unrecognized_hint,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  decoded,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: decoded));
                  if (context.mounted) {
                    Fluttertoast.showToast(msg: context.l10n.copied_to_clipboard);
                  }
                },
                icon: const Icon(Icons.copy),
                label: Text(context.l10n.copy_text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
