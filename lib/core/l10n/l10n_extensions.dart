import '../log/app_log.dart';
import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';

// Avoid log spamming: only log once when falling back.
bool _l10nFallbackLogged = false;

extension L10nX on BuildContext {
  AppLocalizations get l10n {
    final l10n = AppLocalizations.of(this);
    if (l10n != null) return l10n;
    if (!_l10nFallbackLogged) {
      _l10nFallbackLogged = true;
      AppLog.instance.warning('AppLocalizations not ready in this BuildContext; using English fallback.', tag: 'l10n');
    }
    return AppLocalizationsEn();
  }
}
