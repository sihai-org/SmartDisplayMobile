import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/router/app_router.dart';
import '../../core/constants/feature_gray.dart';

class DeviceEditTrigger extends StatelessWidget {
  final String displayDeviceId;
  final String? deviceName;
  final EdgeInsetsGeometry? padding;

  const DeviceEditTrigger({
    super.key,
    required this.displayDeviceId,
    this.deviceName,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedName = (deviceName ?? '').isNotEmpty
        ? deviceName!
        : context.l10n.unknown_device;

    return TextButton(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: Theme.of(context).textTheme.bodyMedium,
        foregroundColor: Theme.of(context).textTheme.bodyMedium?.color,
        overlayColor: Colors.transparent,
      ),
      onPressed: () {
        final idParam = Uri.encodeComponent(displayDeviceId);
        final nameParam = Uri.encodeComponent(resolvedName);
        context.push(
          '${AppRoutes.deviceEdit}?displayDeviceId=$idParam&deviceName=$nameParam',
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.smallPadding),
        child: Text(
          context.l10n.edit_device,
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
