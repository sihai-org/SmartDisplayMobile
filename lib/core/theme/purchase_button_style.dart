import 'package:flutter/material.dart';

class PurchaseButtonStyle {
  const PurchaseButtonStyle._();

  static const Color darkColor = Color(0xFF161616);
  static const Color lightColor = Color(0xFFFFE7A8);
  static const Color heavyLightColor = Color(0xFFFFC400);
  static const Color disabledBackgroundColor = Color(0xFF2A2A2A);
  static const Color invertedDisabledBackgroundColor = Color(0xFFF2E0A9);
  static const Color invertedDisabledForegroundColor = Color(0xFF5A5547);

  static ButtonStyle filledButtonStyle({
    EdgeInsetsGeometry? padding,
    OutlinedBorder? shape,
    TextStyle? textStyle,
    Size? minimumSize,
  }) {
    return FilledButton.styleFrom(
      elevation: 0,
      backgroundColor: darkColor,
      foregroundColor: lightColor,
      disabledBackgroundColor: disabledBackgroundColor,
      disabledForegroundColor: lightColor.withValues(alpha: 0.55),
      padding: padding,
      shape: shape,
      textStyle: textStyle,
      minimumSize: minimumSize,
    );
  }

  static ButtonStyle invertedFilledButtonStyle({
    EdgeInsetsGeometry? padding,
    OutlinedBorder? shape,
    TextStyle? textStyle,
    Size? minimumSize,
  }) {
    return FilledButton.styleFrom(
      elevation: 0,
      backgroundColor: lightColor,
      foregroundColor: darkColor,
      disabledBackgroundColor: invertedDisabledBackgroundColor,
      disabledForegroundColor: invertedDisabledForegroundColor,
      padding: padding,
      shape: shape,
      textStyle: textStyle,
      minimumSize: minimumSize,
    );
  }
}
