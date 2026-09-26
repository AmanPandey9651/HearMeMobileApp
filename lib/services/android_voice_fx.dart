import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VoiceFxOption {
  final String id;
  final String label;
  final String emoji;
  final String description;
  const VoiceFxOption(this.id, this.label, this.emoji, this.description);
}

class AndroidVoiceFx {
  static const normal = 'NORMAL';
  static const deep = 'DEEP_BARITONE';
  static const helium = 'HELIUM';
  static const robot = 'ROBOT';
  static const radio = 'RADIO';

  static const options = <VoiceFxOption>[
    VoiceFxOption(normal, 'Natural Voice', '🎙️', 'Original microphone audio'),
    VoiceFxOption(deep, 'Deep Baritone', '🗿', 'Warm low-frequency anonymizer'),
    VoiceFxOption(helium, 'Bright / High Pitch', '🎈', 'Bright presence anonymizer'),
    VoiceFxOption(robot, 'Cyber Robot', '🤖', 'Ring-modulated synthetic voice'),
    VoiceFxOption(radio, 'Vintage Radio', '📻', 'Walkie-talkie band-pass effect'),
  ];

  static const _methods = MethodChannel('talkstrangers/voice_fx');
  static const _frames = EventChannel('talkstrangers/voice_fx_frames');

  StreamSubscription<dynamic>? _subscription;
  void Function(Uint8List frame)? onFrame;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> start(String filter) async {
    if (!supported) return;
    await stopCapture();
    _subscription = _frames.receiveBroadcastStream().listen((event) {
      if (event is Uint8List) onFrame?.call(event);
      if (event is ByteData) onFrame?.call(event.buffer.asUint8List());
      if (event is List<int>) onFrame?.call(Uint8List.fromList(event));
    });
    await _methods.invokeMethod<void>('startCapture', {'filter': filter});
  }

  Future<void> setFilter(String filter) async {
    if (!supported) return;
    await _methods.invokeMethod<void>('setFilter', {'filter': filter});
  }

  Future<void> play(Uint8List frame) async {
    if (!supported || frame.isEmpty) return;
    await _methods.invokeMethod<void>('playPcm', frame);
  }

  Future<void> stopCapture() async {
    await _subscription?.cancel();
    _subscription = null;
    if (supported) {
      try { await _methods.invokeMethod<void>('stopCapture'); } catch (_) {}
    }
  }

  Future<void> stopPlayback() async {
    if (supported) {
      try { await _methods.invokeMethod<void>('stopPlayback'); } catch (_) {}
    }
  }

  Future<void> stop() async {
    await stopCapture();
    await stopPlayback();
  }

  Future<void> dispose() => stop();
}

class PrivacyPlatform {
  static const _methods = MethodChannel('talkstrangers/privacy');

  static Future<void> setSecure(bool secure) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try { await _methods.invokeMethod<void>('setSecure', {'secure': secure}); } catch (_) {}
  }
}
