import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QrCodeResultPage extends StatelessWidget {
  final String text;
  const QrCodeResultPage({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final decoded = Uri.decodeComponent(text);
    return Scaffold(
      appBar: AppBar(
        title: const Text('二维码内容'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '未能识别为设备二维码，以下为原始内容：',
              style: TextStyle(fontSize: 14, color: Colors.grey),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('复制文本'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

