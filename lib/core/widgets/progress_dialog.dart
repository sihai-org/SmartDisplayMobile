import 'package:flutter/material.dart';

import '../log/app_log.dart';

enum ProgressDialogStatus { loading, success, error }

/// 公共进度模态框控制器：支持动态更新文案 / 关闭弹窗
class ProgressDialogController {
  final ValueNotifier<String> message;
  final ValueNotifier<ProgressDialogStatus> status;

  /// 用于定位“弹窗所在的 Navigator”的宿主 context（外层 context 即可）
  /// 注意：我们强制用 rootNavigator 弹出/关闭，保证不会 pop 到页面。
  final BuildContext _hostContext;

  bool _closed = false;

  ProgressDialogController._(
    this._hostContext, {
    required String initialMessage,
  })  : message = ValueNotifier(initialMessage),
        status = ValueNotifier(ProgressDialogStatus.loading);

  void update(String text) {
    if (_closed) return;
    status.value = ProgressDialogStatus.loading;
    message.value = text;
  }

  void success([String? text]) {
    if (_closed) return;
    status.value = ProgressDialogStatus.success;
    if (text != null) message.value = text;
  }

  void error([String? text]) {
    if (_closed) return;
    status.value = ProgressDialogStatus.error;
    if (text != null) message.value = text;
  }

  void close() {
    if (_closed) return;
    _closed = true;

    // ✅ 只 pop rootNavigator 的栈顶（也就是这个 dialog），不会影响页面
    try {
      final nav = Navigator.of(_hostContext, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    } catch (e, st) {
      AppLog.instance.warning(
        '[ProgressDialogController.close] failed to pop dialog',
        error: e,
        stackTrace: st,
      );
    } finally {
      message.dispose();
      status.dispose();
    }
  }
}

/// 显示一个不可取消的进度弹窗，返回 controller 用于更新文案/切换状态/关闭。
Future<ProgressDialogController> showProgressDialog(
  BuildContext context, {
  required String initialMessage,
  bool barrierDismissible = false,
  double width = 160,
  EdgeInsets contentPadding = const EdgeInsets.all(20),
  double radius = 12,
}) async {
  final controller = ProgressDialogController._(
    context,
    initialMessage: initialMessage,
  );

  showDialog(
    context: context,
    useRootNavigator: true, // ✅ 强制挂到 rootNavigator，避免嵌套 Navigator 错层
    barrierDismissible: barrierDismissible,
    builder: (_) {
      return PopScope(
        canPop: false, // ✅ 禁止返回键/手势 pop（需要 Flutter 3.11+）
        child: Center(
          child: SizedBox(
            width: width,
            child: Material(
              borderRadius: BorderRadius.all(Radius.circular(radius)),
              child: Padding(
                padding: contentPadding,
                child: ValueListenableBuilder<String>(
                  valueListenable: controller.message,
                  builder: (_, msg, __) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder<ProgressDialogStatus>(
                          valueListenable: controller.status,
                          builder: (_, st, __) {
                            switch (st) {
                              case ProgressDialogStatus.loading:
                                return const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                );
                              case ProgressDialogStatus.success:
                                return const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 28,
                                );
                              case ProgressDialogStatus.error:
                                return const Icon(
                                  Icons.error,
                                  color: Colors.red,
                                  size: 28,
                                );
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(msg, textAlign: TextAlign.center),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  // 这里其实不强依赖，但保留无害
  await Future<void>.delayed(Duration.zero);
  return controller;
}
