import 'package:flutter/services.dart';
import 'dart:io' show Platform;

class HapticService {
  static bool _enabled = true;

  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  static bool get isEnabled => _enabled;

  static void light() {
    if (!_enabled) return;
    if (Platform.isIOS) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  static void medium() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }

  static void selection() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  static void success() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  static void error() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }

  static void notification() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }
}
