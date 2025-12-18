import '../../l10n/app_localizations.dart';

import 'package:flutter/material.dart';

enum WifiSignalStrength {
  strong,
  good,
  weak,
  unknown,
}

WifiSignalStrength wifiSignalStrengthFromRssiDbm(int? rssiDbm) {
  if (rssiDbm == null || rssiDbm == 0) return WifiSignalStrength.unknown;
  if (rssiDbm >= -50) return WifiSignalStrength.strong;
  if (rssiDbm >= -70) return WifiSignalStrength.good;
  return WifiSignalStrength.weak;
}

String wifiSignalStrengthLabel(AppLocalizations l10n, int? rssiDbm) {
  return switch (wifiSignalStrengthFromRssiDbm(rssiDbm)) {
    WifiSignalStrength.strong => l10n.wifi_signal_strong,
    WifiSignalStrength.good => l10n.wifi_signal_good,
    WifiSignalStrength.weak => l10n.wifi_signal_weak,
    WifiSignalStrength.unknown => l10n.wifi_signal_unknown,
  };
}

IconData wifiSignalIconFromRssiDbm(int? rssiDbm) {
  return switch (wifiSignalStrengthFromRssiDbm(rssiDbm)) {
    WifiSignalStrength.strong => Icons.signal_wifi_4_bar,
    WifiSignalStrength.good => Icons.network_wifi_2_bar,
    WifiSignalStrength.weak => Icons.network_wifi_1_bar,
    WifiSignalStrength.unknown => Icons.wifi,
  };
}
