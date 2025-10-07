import 'dart:developer' as developer;
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
      developer.log(
        'AppLocalizations not ready in this BuildContext; using English fallback.',
        name: 'l10n',
        level: 1000, // SEVERE
      );
    }
    return AppLocalizationsEn();
  }
}
