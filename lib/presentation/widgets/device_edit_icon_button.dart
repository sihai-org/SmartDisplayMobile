import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/router/app_router.dart';
import '../../core/constants/feature_gray.dart';

class DeviceEditIconButton extends StatelessWidget {
  final String displayDeviceId;
  final String? deviceName;
  final EdgeInsetsGeometry? padding;

  const DeviceEditIconButton({
    super.key,
    required this.displayDeviceId,
    this.deviceName,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    if (!FeatureGray.editDeviceGray) {
      return const SizedBox.shrink();
    }

    if (displayDeviceId.isEmpty) {
      return const SizedBox.shrink();
    }

    final resolvedName = (deviceName ?? '').isNotEmpty
        ? deviceName!
        : context.l10n.unknown_device;

    return IconButton(
      padding: padding ?? const EdgeInsets.all(8),
      icon: const Icon(Icons.edit_outlined),
      tooltip: context.l10n.edit_device,
      onPressed: () {
        final idParam = Uri.encodeComponent(displayDeviceId);
        final nameParam = Uri.encodeComponent(resolvedName);
        context.push(
          '${AppRoutes.deviceEdit}?displayDeviceId=$idParam&deviceName=$nameParam',
        );
      },
    );
  }
}
