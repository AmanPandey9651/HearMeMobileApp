import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FeelBackRingtone {
  static const MethodChannel _channel = MethodChannel('feelback_ringtone');

  static final Set<String> _acceptedCallIds = <String>{};
  static final Set<String> _terminalCallIds = <String>{};
  static final Map<String, String> _lastKnownCallStatus = <String, String>{};
  static String? _activeRingingCallId;

  /// Log structured timestamped event
  static void logEvent({
    required String event,
    required String source,
    String? callId,
    String? prevStatus,
    String? newStatus,
    String? details,
  }) {
    final now = DateTime.now().toIso8601String();
    final cId = callId ?? _activeRingingCallId ?? 'GLOBAL';
    final pStatus = prevStatus ?? _lastKnownCallStatus[cId] ?? 'UNKNOWN';
    final nStatus = newStatus ?? pStatus;
    if (newStatus != null && callId != null) {
      _lastKnownCallStatus[callId] = newStatus;
    }
    debugPrint(
      '[FeelBackRingtoneLog] timestamp=$now callId=$cId event=$event '
      'prevStatus=$pStatus newStatus=$nStatus source=$source ${details ?? ""}'.trim(),
    );
  }

  /// Mark call as permanently accepted — stops ringtone and permanently blocks any future restart for this callId.
  static void markAccepted(String callId, {String source = 'unspecified'}) {
    if (callId.isEmpty) return;
    final cId = callId.trim();
    _acceptedCallIds.add(cId);
    if (_activeRingingCallId == cId) {
      _activeRingingCallId = null;
    }
    logEvent(
      event: 'MARK_ACCEPTED_PERMANENT',
      source: source,
      callId: cId,
      newStatus: 'ACCEPTED',
      details: 'ringtone permanently blocked for this callId',
    );

    try {
      _channel.invokeMethod('markAccepted', {'callId': cId, 'source': source});
    } catch (_) {}
    stop(callId: cId, source: 'markAccepted:$source');
  }

  /// Mark call as permanently terminal (REJECTED, CANCELLED, ENDED, TIMEOUT)
  static void markTerminal(String callId, String status, {String source = 'unspecified'}) {
    if (callId.isEmpty) return;
    final cId = callId.trim();
    _terminalCallIds.add(cId);
    if (_activeRingingCallId == cId) {
      _activeRingingCallId = null;
    }
    logEvent(
      event: 'MARK_TERMINAL_PERMANENT',
      source: source,
      callId: cId,
      newStatus: status,
      details: 'terminal call-state guard active',
    );

    try {
      _channel.invokeMethod('markTerminal', {'callId': cId, 'status': status, 'source': source});
    } catch (_) {}
    stop(callId: cId, source: 'markTerminal:$source');
  }

  static bool isCallGuarded(String callId) {
    final cId = callId.trim();
    return _acceptedCallIds.contains(cId) || _terminalCallIds.contains(cId);
  }

  /// Starts the looping alarm-priority ringtone and vibration if not already accepted or terminal.
  static Future<void> start(String callId, {String source = 'unspecified'}) async {
    final cId = callId.trim();
    if (cId.isEmpty) return;

    if (_acceptedCallIds.contains(cId)) {
      logEvent(
        event: 'BLOCKED_START_IGNORED',
        source: source,
        callId: cId,
        details: 'reason=ALREADY_ACCEPTED',
      );
      return;
    }

    if (_terminalCallIds.contains(cId)) {
      logEvent(
        event: 'BLOCKED_START_IGNORED',
        source: source,
        callId: cId,
        details: 'reason=ALREADY_TERMINAL',
      );
      return;
    }

    if (_activeRingingCallId == cId) {
      logEvent(
        event: 'IDEMPOTENT_START_IGNORED',
        source: source,
        callId: cId,
        details: 'already ringing for this callId',
      );
      return;
    }

    _activeRingingCallId = cId;
    logEvent(
      event: 'START_RINGTONE',
      source: source,
      callId: cId,
      newStatus: 'RINGING',
    );

    try {
      await _channel.invokeMethod('start', {'callId': cId, 'source': source});
    } catch (e) {
      logEvent(
        event: 'START_RINGTONE_ERROR',
        source: source,
        callId: cId,
        details: 'error=$e',
      );
    }
  }

  /// Immediately stops any playing ringtone and vibration.
  static Future<void> stop({String? callId, String source = 'unspecified'}) async {
    final cId = callId?.trim() ?? _activeRingingCallId;
    _activeRingingCallId = null;

    logEvent(
      event: 'STOP_RINGTONE',
      source: source,
      callId: cId,
    );

    try {
      await _channel.invokeMethod('stop', {'callId': cId, 'source': source});
    } catch (_) {}
  }
}
