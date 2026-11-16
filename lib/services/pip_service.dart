import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PipService {
  PipService._();
  static final PipService instance = PipService._();

  static const MethodChannel _channel = MethodChannel('talkstrangers/pip');

  final ValueNotifier<bool> isPipMode = ValueNotifier<bool>(false);

  bool _initialized = false;

  void initialize() {
    if (_initialized || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPictureInPictureChanged') {
        final args = call.arguments as Map?;
        final isPip = args?['isPip'] == true;
        isPipMode.value = isPip;
        debugPrint('[PipService] onPictureInPictureChanged: isPip=$isPip');
      }
    });
  }

  Future<bool> isSupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isSupported');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> enableAutoPiP(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      initialize();
      await _channel.invokeMethod('enableAutoPiP', {'enabled': enabled});
      debugPrint('[PipService] enableAutoPiP: $enabled');
    } catch (e) {
      debugPrint('[PipService] enableAutoPiP error: $e');
    }
  }

  Future<bool> enterPiP() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      initialize();
      final res = await _channel.invokeMethod<bool>('enterPiP');
      return res == true;
    } catch (e) {
      debugPrint('[PipService] enterPiP error: $e');
      return false;
    }
  }
}
