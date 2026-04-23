import 'dart:math' as math;

import 'package:intl/intl.dart';

double floorToDecimalPlaces(double value, int fractionDigits) {
  final factor = math.pow(10, fractionDigits).toDouble();
  // Offset by a tiny epsilon so values like 1.23 don't become 1.22 after
  // floating-point multiplication.
  return ((value * factor) + 1e-9).floorToDouble() / factor;
}

String formatBillingAmount({
  required String locale,
  required double amount,
  int fractionDigits = 2,
}) {
  final truncated = floorToDecimalPlaces(amount, fractionDigits);
  return NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: fractionDigits,
  ).format(truncated);
}

String formatBillingCreditAmount({
  required String locale,
  required double amount,
}) {
  final truncated = floorToDecimalPlaces(amount, 2);
  final fractionDigits = truncated == truncated.truncateToDouble() ? 0 : 2;
  return NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: fractionDigits,
  ).format(truncated);
}

String formatBillingDeltaAmount({
  required String locale,
  required double amount,
  int fractionDigits = 2,
}) {
  final truncated = floorToDecimalPlaces(amount, fractionDigits);
  final prefix = truncated >= 0 ? '+' : '-';
  return '$prefix${formatBillingAmount(locale: locale, amount: truncated.abs(), fractionDigits: fractionDigits)}';
}
