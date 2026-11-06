import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/api_client.dart';

/// InCallVoiceSafetyService
/// Listens on-device for off-platform contact sharing and bank/UPI solicitation triggers
/// during audio and video calls.
class InCallVoiceSafetyService {
  static final InCallVoiceSafetyService instance = InCallVoiceSafetyService._internal();
  InCallVoiceSafetyService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;
  String? _currentSessionId;
  ApiClient? _apiClient;
  void Function(String warningMessage)? _onLeakageDetected;

  DateTime? _lastAlertTime;

  // Number words mapping (English & Hinglish)
  static final RegExp _digitSequencePattern = RegExp(r'\b(?:\d[ -]?){8,12}\d\b');

  static final List<String> _bankKeywords = [
    'account number',
    'khata number',
    'bank account',
    'ifsc',
    'ifsc code',
    'branch code',
    'saving account',
    'current account',
  ];

  static final List<String> _paymentKeywords = [
    'gpay',
    'google pay',
    'phonepe',
    'phone pe',
    'paytm',
    'bhim upi',
    'upi id',
    'send money',
    'paisa bhejo',
    'paise bhejo',
    'paise dal do',
    'qr code',
  ];

  static final List<String> _socialContactKeywords = [
    'whatsapp',
    'whats app',
    'telegram',
    'instagram',
    'insta id',
    'snapchat',
    'snap id',
    'phone number',
    'mobile number',
    'contact number',
    'mera number',
    'apna number',
  ];

  /// Initialize and start background listening for an active session
  Future<void> startMonitoring({
    required String sessionId,
    required ApiClient apiClient,
    void Function(String warningMessage)? onLeakageDetected,
  }) async {
    _currentSessionId = sessionId;
    _apiClient = apiClient;
    _onLeakageDetected = onLeakageDetected;

    // Critical guard for mobile: Concurrent on-device speech recognition (SpeechRecognizer on
    // Android / AVAudioEngine on iOS) while WebRTC is capturing microphone audio triggers an
    // exclusive hardware lock collision on the microphone HAL. On Android, this silences WebRTC's
    // WebRtcAudioRecord (transmitting zero/silent audio). On iOS, it crashes the app.
    // In-call voice safety monitoring is handled by the dedicated backend Whisper service.
    debugPrint('[InCallVoiceSafety] On-device speech recognition bypassed during active call to preserve WebRTC audio capture.');
    return;

    try {
      if (!_isInitialized) {
        _isInitialized = await _speech.initialize(
          onError: (val) {
            debugPrint('[InCallVoiceSafety] Speech error: ${val.errorMsg}');
            _isListening = false;
          },
          onStatus: (status) {
            debugPrint('[InCallVoiceSafety] Status: $status');
            if (status == 'notListening' && _currentSessionId != null) {
              // Automatically restart listening while in active call
              _restartListening();
            }
          },
        );
      }

      if (_isInitialized) {
        _startListeningLoop();
      }
    } catch (e) {
      debugPrint('[InCallVoiceSafety] Initialization skipped or unsupported: $e');
    }
  }

  void _startListeningLoop() {
    if (_isListening || _currentSessionId == null) return;
    try {
      _speech.listen(
        onResult: (result) {
          final words = result.recognizedWords;
          if (words.isNotEmpty) {
            _analyzeTranscript(words);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
      );
      _isListening = true;
    } catch (e) {
      debugPrint('[InCallVoiceSafety] Listen error: $e');
      _isListening = false;
    }
  }

  void _restartListening() {
    if (_currentSessionId == null) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (_currentSessionId != null && !_isListening) {
        _startListeningLoop();
      }
    });
  }

  /// Analyzes the recognized speech for off-platform leakage triggers
  void _analyzeTranscript(String transcript) {
    final lower = transcript.toLowerCase().trim();
    if (lower.isEmpty) return;

    // Check debounce (avoid spamming within 25 seconds)
    if (_lastAlertTime != null && DateTime.now().difference(_lastAlertTime!).inSeconds < 25) {
      return;
    }

    String? detectedReason;

    // 1. Spoken digit sequence (e.g. 8-12 digits)
    if (_digitSequencePattern.hasMatch(lower)) {
      detectedReason = 'Spoken phone or account number sequence detected';
    }

    // 2. Bank triggers
    if (detectedReason == null) {
      for (final kw in _bankKeywords) {
        if (lower.contains(kw)) {
          detectedReason = 'Bank account / IFSC reference spoken: "$kw"';
          break;
        }
      }
    }

    // 3. Payment / UPI triggers
    if (detectedReason == null) {
      for (final kw in _paymentKeywords) {
        if (lower.contains(kw)) {
          detectedReason = 'Direct UPI / external payment keyword spoken: "$kw"';
          break;
        }
      }
    }

    // 4. Social / direct contact triggers
    if (detectedReason == null) {
      for (final kw in _socialContactKeywords) {
        if (lower.contains(kw)) {
          detectedReason = 'Direct off-platform contact keyword spoken: "$kw"';
          break;
        }
      }
    }

    if (detectedReason != null) {
      _lastAlertTime = DateTime.now();
      _triggerSafetyViolation(detectedReason, transcript);
    }
  }

  void _triggerSafetyViolation(String reason, String snippet) {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    final userNotice = '⚠️ Safety Notice: Sharing phone numbers, bank accounts, or external payment handles is strictly prohibited and monitored.';

    // Notify UI to render prominent in-call HUD alert
    _onLeakageDetected?.call(userNotice);

    // Report silently to backend audit-transcript & security-alert
    final sessId = _currentSessionId;
    final client = _apiClient;
    if (sessId != null && client != null) {
      // 1. Audit transcript
      client.post('/safety/audit-transcript', body: {
        'sessionId': sessId,
        'transcript': snippet,
      }).catchError((_) => null);

      // 2. Record security alert
      client.post('/safety/security-alert', body: {
        'sessionId': sessId,
        'alertType': 'OFF_PLATFORM_LEAKAGE_ATTEMPT',
        'details': '$reason. Recognized phrase: "$snippet"',
      }).catchError((_) => null);
    }
  }

  /// Stop monitoring when call ends
  void stopMonitoring() {
    _currentSessionId = null;
    _apiClient = null;
    _onLeakageDetected = null;
    if (_isListening) {
      try {
        _speech.stop();
      } catch (_) {}
      _isListening = false;
    }
  }
}
