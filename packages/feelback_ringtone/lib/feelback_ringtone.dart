import 'dart:async';
import 'package:flutter/services.dart';

class FeelBackRingtone {
  static const MethodChannel _channel = MethodChannel('feelback_ringtone');

  /// Starts the looping alarm-priority ringtone and vibration.
  static Future<void> start() async {
    try {
      await _channel.invokeMethod('start');
    } catch (_) {}
  }

  /// Immediately stops any playing ringtone and vibration.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
