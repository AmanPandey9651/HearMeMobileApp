import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../core/active_call_manager.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../services/android_voice_fx.dart';
import '../../services/api_service.dart';
import '../../services/call_recording_service.dart';
import '../../widgets/call_pulse_avatar.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/in_call_mini_games.dart';
import '../../widgets/video_privacy_filter.dart';

class SessionScreen extends StatefulWidget {
  final InstantSessionModel initialSession;
  final bool callerSide;
  final bool isHostedInGlobalManager;

  const SessionScreen({
    super.key,
    required this.initialSession,
    required this.callerSide,
    this.isHostedInGlobalManager = false,
  });

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late InstantSessionModel session = widget.initialSession;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  final voiceFx = AndroidVoiceFx();
  final _privacyAlerts = PrivacyAlertService();
  final gameSignal = ValueNotifier<Map<String, dynamic>?>(null);
  final messageController = TextEditingController();
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  RTCPeerConnection? pc;
  RTCDataChannel? voiceChannel;
  MediaStream? localStream, remoteStream;
  Timer? sessionPoll, signalPoll, heartbeat, clock, messagePoll, reconnectTimer, _offerWatchdogTimer;
  int seconds = 0, signalSince = 0, reconnectSeconds = 30, ringRemaining = 45, elapsedRinging = 1;
  bool joining = false, mic = true, camera = true, speaker = true, ending = false;
  bool reconnecting = false, gameSheetOpen = false, registeredActiveSession = false, everLive = false;
  bool peerVoiceFxCapable = false, nativeVoiceFxActive = false;
  final queuedCandidates = <Map<String, dynamic>>[];
  List<dynamic> messages = [];
  String? banner;
  String activeVoiceFilter = AndroidVoiceFx.normal;
  String peerVoiceFilter = AndroidVoiceFx.normal;
  String activeVideoFilter = VideoPrivacyFilter.none;
  String peerVideoFilter = VideoPrivacyFilter.none;
  bool _recordingStarted = false;
  late final ApiService _api;
  bool _isDisposed = false;

  @override
  void setState(VoidCallback fn) {
    if (!mounted || _isDisposed) return;
    super.setState(fn);
  }

  bool get isChat => session.type == 'CHAT';
  bool get isVideo => session.type == 'VIDEO_CALL';
  bool get isLive => const {'ACCEPTED', 'CONNECTING', 'CONNECTED', 'ACTIVE'}.contains(session.status);

  Future<void> _startRecordingIfEligible() async {
    if (_recordingStarted || ending || session.ended || isChat) return;

    try {
      final app = mounted ? context.read<AppController>() : null;
      if (app != null) {
        await app.refreshGovernance();
      }
      final gov = app?.recordingGovernance;

      final audioAllowed = gov?.audioRecordingEnabled ?? true;
      final videoAllowed = gov?.videoRecordingEnabled ?? true;

      if (isVideo && !videoAllowed) {
        debugPrint('[RecordingGovernance] Mobile: Video recording disabled by admin policy.');
        return;
      }
      if (!isVideo && !audioAllowed) {
        debugPrint('[RecordingGovernance] Mobile: Audio recording disabled by admin policy.');
        return;
      }

      _recordingStarted = true;

      if (isVideo) {
        final remoteVid = remoteStream?.getVideoTracks().firstOrNull;
        final localVid = localStream?.getVideoTracks().firstOrNull;
        final targetTrack = remoteVid ?? localVid;
        if (targetTrack != null) {
          await CallRecordingService.startVideoRecording(session.id, targetTrack);
        }
        await CallRecordingService.startAudioRecording(session.id);
        debugPrint('[RecordingGovernance] Mobile: Started video call recording for session ${session.id}');
      } else {
        await CallRecordingService.startAudioRecording(session.id);
        debugPrint('[RecordingGovernance] Mobile: Started audio call recording for session ${session.id}');
      }
    } catch (e) {
      debugPrint('[RecordingGovernance] Mobile: Error starting call recording: $e');
    }
  }

  Future<void> _stopAndUploadRecording() async {
    if (!_recordingStarted) return;
    _recordingStarted = false;

    try {
      final recordedFile = await CallRecordingService.stopAndCollectRecording();
      if (recordedFile != null && await recordedFile.exists() && await recordedFile.length() > 1000) {
        debugPrint('[Recording] Uploading call recording (${await recordedFile.length()} bytes) for session ${session.id} in background...');
        _api.uploadRecording(session.id, recordedFile).catchError((e) {
          debugPrint('[Recording] Background recording upload error: $e');
          return <String, dynamic>{};
        });
      }
    } catch (e) {
      debugPrint('[Recording] Failed to stop recording: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _api = context.read<AppController>().api;
    WidgetsBinding.instance.addObserver(this);
    everLive = isLive;
    ringRemaining = _initRingRemaining();
    localRenderer.initialize();
    remoteRenderer.initialize();
    voiceFx.onFrame = (frame) {
      final dc = voiceChannel;
      if (dc == null || !mic) return;
      dc.send(RTCDataChannelMessage.fromBinary(frame)).catchError((_) {});
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppController>().enterActiveSession();
      registeredActiveSession = true;
      if (widget.isHostedInGlobalManager) {
        ActiveCallManager.instance.bindCallControls(
          toggleMute: _toggleMic,
          endCall: () {
            if (!ending && !session.ended) _end();
          },
          maximizeCall: () {
            if (mounted) setState(() {});
          },
        );
      }
    });
    _startPolling();
    _privacyAlerts.start(_onPrivacyAlert);
  }

  /// Called by PrivacyAlertService whenever native Android detects a
  /// screenshot or screen-recording attempt during an active session.
  void _onPrivacyAlert(String type) {
    // Report silently to backend for admin audit log
    context.read<AppController>().api
        .securityAlert(session.id, type, 'Mobile screenshot/screen-recording attempt detected')
        .catchError((_) {});
    // Show an in-session warning banner to the user
    if (mounted) {
      setState(() => banner = '🚫 Screenshot / recording is prohibited and has been reported.');
    }
  }

  void _startPolling() {
    sessionPoll = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      _refreshSession();
    });
    heartbeat = Timer.periodic(const Duration(seconds: 12), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      if (isLive) _api.sessionHeartbeat(session.id).catchError((_) {});
    });
    clock = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      if (isLive) {
        everLive = true;
        final startStr = session.connectedAt ?? session.startedAt;
        if (startStr != null && startStr.isNotEmpty) {
          final startTime = DateTime.tryParse(startStr)?.toUtc();
          if (startTime != null) {
            final elapsed = DateTime.now().toUtc().difference(startTime).inSeconds;
            if (elapsed >= 0) {
              seconds = elapsed;
            } else {
              seconds++;
            }
          } else {
            seconds++;
          }
        } else {
          seconds++;
        }
        if (!mounted || _isDisposed) return;
        setState(() {});
        if (widget.isHostedInGlobalManager) {
          ActiveCallManager.instance.updateState(
            seconds: seconds,
            muted: !mic,
            live: true,
            updatedSession: session,
          );
        }
      } else if (!session.ended) {
        if (!mounted || _isDisposed) return;
        setState(() {
          elapsedRinging++;
          if (ringRemaining > 0) {
            ringRemaining--;
          }
        });
        if (ringRemaining <= 0 && !ending) {
          _handleRingTimeout();
        }
      }
    });
    messagePoll = Timer.periodic(const Duration(milliseconds: 1100), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      if (isLive) _refreshMessages();
    });
    signalPoll = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted || _isDisposed) {
        timer.cancel();
        return;
      }
      _pollSignals();
    });
  }

  Future<void> _refreshSession() async {
    if (session.ended || ending || _isDisposed) return;
    try {
      final next = await _api.session(session.id);
      if (!mounted || _isDisposed) return;
      setState(() {
        session = next;
        if (isLive) {
          everLive = true;
          final startStr = next.connectedAt ?? next.startedAt;
          if (startStr != null && startStr.isNotEmpty) {
            final startTime = DateTime.tryParse(startStr)?.toUtc();
            if (startTime != null) {
              final elapsed = DateTime.now().toUtc().difference(startTime).inSeconds;
              if (elapsed >= 0) {
                seconds = elapsed;
              }
            }
          } else if (next.durationSeconds > 0 && next.durationSeconds > seconds) {
            seconds = next.durationSeconds;
          }
        }
      });
      if (next.ended) {
        if (!ending) {
          ending = true;
          clock?.cancel();
          sessionPoll?.cancel();
          signalPoll?.cancel();
          heartbeat?.cancel();
          try { localRenderer.srcObject = null; } catch (_) {}
          try { remoteRenderer.srcObject = null; } catch (_) {}
          unawaited(_cleanupMedia());
          if (widget.isHostedInGlobalManager) {
            ActiveCallManager.instance.clearCall();
          } else if (mounted) {
            Navigator.pop(context);
          }
        }
        return;
      } else if (isLive && !isChat && pc == null && !joining) {
        await _joinMedia();
      }
    } catch (_) {}
  }

  Future<void> _joinMedia() async {
    joining = true;
    try {
      final api = context.read<AppController>().api;
      try { session = await api.startSession(session.id); } catch (_) {}

      final perms = <Permission>[Permission.microphone, if (isVideo) Permission.camera];
      final statuses = await perms.request();
      if (statuses.values.any((v) => !v.isGranted)) {
        throw Exception('Microphone${isVideo ? ' and camera' : ''} permission is required.');
      }

      final ice = await api.iceServers();
      pc = await createPeerConnection({
        'iceServers': ice,
        'sdpSemantics': 'unified-plan',
      });
      pc!.onTrack = (event) async {
        debugPrint('[WebRTC] Mobile onTrack: kind=${event.track.kind}, id=${event.track.id}, streams=${event.streams.length}');
        if (event.streams.isNotEmpty) {
          remoteStream = event.streams.first;
        } else {
          remoteStream ??= await createLocalMediaStream('remote_stream');
          if (!remoteStream!.getTracks().any((t) => t.id == event.track.id)) {
            remoteStream!.addTrack(event.track);
          }
        }
        // Force rebind to remoteRenderer by clearing first so Flutter WebRTC's setter doesn't skip
        if (event.track.kind == 'video' || remoteStream!.getVideoTracks().isNotEmpty) {
          remoteRenderer.srcObject = null;
        }
        remoteRenderer.srcObject = remoteStream;
        _startRecordingIfEligible();
        if (mounted) setState(() {});
      };
      pc!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && candidate.candidate!.trim().isNotEmpty) {
          api.sendSignal(session.id, {
            'type': 'candidate',
            'candidate': {
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            }
          }).catchError((_) {});
        }
      };
      pc!.onDataChannel = _attachVoiceChannel;
      pc!.onConnectionState = (state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _finishReconnect();
          _startRecordingIfEligible();
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed || state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _beginReconnect();
        }
      };

      // Always establish a standards-based WebRTC audio track first. This keeps
      // Android <-> web/iOS calls interoperable. The native PCM bridge is only
      // activated when BOTH peers advertise mobile voice-FX capability and the
      // local user selects a non-natural effect.
      localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
                'frameRate': {'ideal': 30},
              }
            : false,
      });


      if (localStream != null) {
        // Clear renderer first to force Flutter WebRTC texture refresh (fixes local video not showing)
        localRenderer.srcObject = null;
        await Future.delayed(const Duration(milliseconds: 80));
        localRenderer.srcObject = localStream;
        // Strictly add audio first, then video so m-line order is: mid 0 = audio, mid 1 = video
        for (final track in localStream!.getAudioTracks()) {
          await pc!.addTrack(track, localStream!);
        }
        for (final track in localStream!.getVideoTracks()) {
          await pc!.addTrack(track, localStream!);
        }
        if (mounted) setState(() {});
        // Secondary setState to ensure platform video texture is fully mounted and rendered
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && !_isDisposed) setState(() {});
        });
      }

      if (widget.callerSide) {
        final init = RTCDataChannelInit()
          ..ordered = false
          ..maxRetransmits = 0;
        _attachVoiceChannel(await pc!.createDataChannel('voice_fx', init));
      }

      signalPoll ??= Timer.periodic(const Duration(milliseconds: 650), (_) => _pollSignals());
      await api.sendSignal(session.id, {
        'type': 'VOICE_FX_CAPABILITY',
        'supported': voiceFx.supported,
      }).catchError((_) {});
      if (widget.callerSide) {
        await _sendOffer();
      } else {
        await api.sendSignal(session.id, {'type': 'peer_ready'}).catchError((_) {});
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      joining = false;
    }
  }

  void _attachVoiceChannel(RTCDataChannel channel) {
    voiceChannel = channel;
    channel.onMessage = (RTCDataChannelMessage data) {
      if (data.isBinary && voiceFx.supported) {
        voiceFx.play(data.binary).catchError((_) {});
      }
    };
    channel.onDataChannelState = (_) {
      if (mounted) setState(() {});
    };
  }

  static String _preferVP8(String sdp) {
    if (!sdp.contains('m=video')) return sdp;
    final lines = sdp.split('\r\n');
    int? mVideoIndex;
    String? vp8Payload;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('m=video ')) {
        mVideoIndex = i;
      } else if (line.startsWith('a=rtpmap:') && line.contains('VP8/90000')) {
        final match = RegExp(r'a=rtpmap:(\d+)\s+VP8/90000').firstMatch(line);
        if (match != null) {
          vp8Payload = match.group(1);
        }
      }
    }

    if (mVideoIndex != null && vp8Payload != null) {
      final parts = lines[mVideoIndex].split(' ');
      if (parts.length > 3) {
        final header = parts.sublist(0, 3);
        final payloads = parts.sublist(3);
        payloads.remove(vp8Payload);
        payloads.insert(0, vp8Payload);
        lines[mVideoIndex] = (header + payloads).join(' ');
      }
    }

    return lines.join('\r\n');
  }

  Future<void> _sendOffer({bool restart = false}) async {
    final peer = pc;
    if (peer == null) return;
    if (restart) {
      try { await (peer as dynamic).restartIce(); } catch (_) {}
    }
    final offer = await peer.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': isVideo,
      if (restart) 'iceRestart': true,
    });
    final sdp = _preferVP8(offer.sdp ?? '');
    final finalOffer = RTCSessionDescription(sdp, offer.type);
    await peer.setLocalDescription(finalOffer);
    await context.read<AppController>().api.sendSignal(session.id, {
      'type': 'offer',
      'restart': restart,
      'sdp': {'type': finalOffer.type, 'sdp': finalOffer.sdp},
    });

    if (widget.callerSide && !isChat) {
      _offerWatchdogTimer?.cancel();
      _offerWatchdogTimer = Timer.periodic(const Duration(milliseconds: 2000), (timer) async {
        if (!mounted || _isDisposed || ending || session.ended) {
          timer.cancel();
          return;
        }
        final currentPc = pc;
        if (currentPc == null) {
          timer.cancel();
          return;
        }
        final state = await currentPc.getSignalingState();
        final connState = await currentPc.getConnectionState();
        if (connState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
            state == RTCSignalingState.RTCSignalingStateStable) {
          timer.cancel();
          return;
        }
        if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          final localDesc = await currentPc.getLocalDescription();
          if (localDesc != null) {
            await context.read<AppController>().api.sendSignal(session.id, {
              'type': 'offer',
              'sdp': {'type': localDesc.type, 'sdp': localDesc.sdp},
            }).catchError((_) {});
          }
        }
      });
    }
  }

  void _beginReconnect() async {
    if (reconnecting || ending || session.ended) return;
    try {
      final s = await _api.session(session.id);
      if (s.ended) {
        _finishFromPeer();
        return;
      }
    } catch (_) {}

    reconnecting = true;
    reconnectSeconds = 10;
    if (mounted) setState(() => banner = 'Connection interrupted. Reconnecting… 10s');
    if (widget.callerSide) _sendOffer(restart: true).catchError((_) {});
    reconnectTimer?.cancel();
    reconnectTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted || _isDisposed || !reconnecting) {
        t.cancel();
        return;
      }
      reconnectSeconds--;
      if (reconnectSeconds % 2 == 0) {
        try {
          final s = await _api.session(session.id);
          if (s.ended) {
            t.cancel();
            _finishFromPeer();
            return;
          }
        } catch (_) {}
      }
      if (reconnectSeconds <= 0) {
        t.cancel();
        reconnecting = false;
        if (!ending && !session.ended) {
          _end();
        }
        return;
      }
      if (widget.callerSide && reconnectSeconds % 3 == 0) {
        _sendOffer(restart: true).catchError((_) {});
      }
      setState(() => banner = 'Connection interrupted. Reconnecting… ${reconnectSeconds}s');
    });
  }

  void _finishReconnect() {
    reconnectTimer?.cancel();
    if (!reconnecting) return;
    reconnecting = false;
    reconnectSeconds = 30;
    if (mounted) setState(() => banner = 'Connection restored.');
  }

  Future<void> _pollSignals() async {
    if (_isDisposed) return;
    try {
      final list = await _api.signals(session.id, signalSince);
      for (final raw in list) {
        final s = Map<String, dynamic>.from(raw);
        final ts = (s['timestamp'] as num?)?.toInt() ?? signalSince;
        if (ts > signalSince) signalSince = ts;
        await _processSignal(s);
      }
    } catch (_) {}
  }

  Future<void> _processSignal(Map<String, dynamic> s) async {
    final type = '${s['type'] ?? ''}';
    if (const {'call_ended', 'hangup', 'peer_left'}.contains(type)) {
      if (!ending) await _finishFromPeer();
      return;
    }
    if (type == 'gift_sent') {
      if (mounted) setState(() => banner = '🎁 Gift received: ${s['gift']?['giftEmoji'] ?? '🎁'} ${s['gift']?['giftName'] ?? 'Gift'}');
      return;
    }
    if (type == 'TOPIC_BROADCAST') {
      if (mounted) setState(() => banner = '💡 Topic: ${s['topic'] ?? ''}');
      return;
    }
    if (type == 'GAME_ACTION') {
      final payload = s['payload'] is Map ? Map<String, dynamic>.from(s['payload'] as Map) : <String, dynamic>{};
      gameSignal.value = payload;
      if (!gameSheetOpen && mounted) {
        Future.microtask(() => _openGames(fromPeer: true));
      }
      return;
    }
    if (type == 'VIDEO_FILTER_CHANGED') {
      final filter = '${s['filter'] ?? VideoPrivacyFilter.none}';
      if (mounted) {
        setState(() => peerVideoFilter = filter);
      }
      return;
    }
    if (type == 'VOICE_FX_CAPABILITY') {
      if (mounted) {
        setState(() => peerVoiceFxCapable = s['supported'] == true);
      }
      return;
    }
    if (type == 'VOICE_FILTER_CHANGED') {
      final filter = '${s['filter'] ?? AndroidVoiceFx.normal}';
      if (mounted) {
        setState(() {
          peerVoiceFilter = filter;
          banner = filter == AndroidVoiceFx.normal ? 'Peer returned to natural voice.' : 'Peer enabled a voice privacy effect.';
        });
      }
      return;
    }
    if (type == 'SAFETY_ALERT') {
      if (mounted) {
        setState(() => banner = '⚠️ ${s['reason'] ?? 'Safety alert'}');
      }
      return;
    }
    if (type == 'peer_ready' && widget.callerSide && !isChat) {
      final peer = pc;
      if (peer != null) {
        final connState = await peer.getConnectionState();
        if (connState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          return;
        }
        final state = await peer.getSignalingState();
        if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          final offer = await peer.getLocalDescription();
          if (offer != null) {
            await context.read<AppController>().api.sendSignal(session.id, {
              'type': 'offer',
              'sdp': {'type': offer.type, 'sdp': offer.sdp},
            });
          }
        } else if (state == RTCSignalingState.RTCSignalingStateStable) {
          final localDesc = await peer.getLocalDescription();
          if (localDesc != null) {
            await context.read<AppController>().api.sendSignal(session.id, {
              'type': 'offer',
              'sdp': {'type': localDesc.type, 'sdp': localDesc.sdp},
            });
          } else {
            await _sendOffer();
          }
        }
      }
      return;
    }
    if (type == 'IN_CALL_CHAT' && s['message'] is Map) {
      final msg = Map<String, dynamic>.from(s['message'] as Map);
      if (mounted) {
        setState(() {
          final isDup = messages.any((m) =>
            (msg['id'] != null && m['id'] == msg['id']) ||
            (m['text'] == msg['text'] && m['senderRole'] == msg['senderRole'])
          );
          if (!isDup) {
            messages.add(msg);
          }
        });
      }
      return;
    }

    final peer = pc;
    if (peer == null) return;
    if (type == 'offer' && !widget.callerSide) {
      final d = Map<String, dynamic>.from(s['sdp'] as Map);
      final rawSdp = d['sdp']?.toString() ?? '';
      await peer.setRemoteDescription(RTCSessionDescription(_preferVP8(rawSdp), d['type']?.toString()));
      await _flushCandidates();
      final answer = await peer.createAnswer();
      final finalAnswer = RTCSessionDescription(_preferVP8(answer.sdp ?? ''), answer.type);
      await peer.setLocalDescription(finalAnswer);
      await context.read<AppController>().api.sendSignal(session.id, {
        'type': 'answer',
        'restart': s['restart'] == true,
        'sdp': {'type': finalAnswer.type, 'sdp': finalAnswer.sdp},
      });
    } else if (type == 'answer' && widget.callerSide) {
      final d = Map<String, dynamic>.from(s['sdp'] as Map);
      final rawSdp = d['sdp']?.toString() ?? '';
      await peer.setRemoteDescription(RTCSessionDescription(_preferVP8(rawSdp), d['type']?.toString()));
      await _flushCandidates();
    } else if (type == 'candidate' && s['candidate'] is Map) {
      final c = Map<String, dynamic>.from(s['candidate'] as Map);
      final rawCand = c['candidate']?.toString() ?? '';
      if (rawCand.trim().isEmpty) return;
      final desc = await peer.getRemoteDescription();
      final lineIdx = c['sdpMLineIndex'] is num
          ? (c['sdpMLineIndex'] as num).toInt()
          : int.tryParse('${c['sdpMLineIndex'] ?? ''}');
      final cand = RTCIceCandidate(
        rawCand,
        c['sdpMid']?.toString(),
        lineIdx,
      );
      if (desc == null) {
        queuedCandidates.add(c);
      } else {
        await peer.addCandidate(cand);
      }
    }
  }

  Future<void> _flushCandidates() async {
    final peer = pc;
    if (peer == null) return;
    for (final c in List<Map<String, dynamic>>.from(queuedCandidates)) {
      final rawCand = c['candidate']?.toString() ?? '';
      if (rawCand.trim().isEmpty) continue;
      final lineIdx = c['sdpMLineIndex'] is num
          ? (c['sdpMLineIndex'] as num).toInt()
          : int.tryParse('${c['sdpMLineIndex'] ?? ''}');
      await peer.addCandidate(RTCIceCandidate(
        rawCand,
        c['sdpMid']?.toString(),
        lineIdx,
      ));
    }
    queuedCandidates.clear();
  }

  Future<void> _refreshMessages() async {
    if (_isDisposed) return;
    try {
      final v = await _api.messages(session.id);
      if (mounted && !_isDisposed) setState(() => messages = v);
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;
    messageController.clear();
    try {
      final app = context.read<AppController>();
      final name = widget.callerSide ? 'Anonymous' : (app.user?.fullName ?? 'Listener');
      final role = widget.callerSide ? 'USER' : 'LISTENER';
      final newMsg = {
        'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
        'senderId': app.user?.id,
        'senderRole': role,
        'senderName': name,
        'text': text,
        'time': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        'timestamp': DateTime.now().toIso8601String(),
      };
      if (mounted) setState(() => messages.add(newMsg));
      app.api.sendSignal(session.id, {
        'type': 'IN_CALL_CHAT',
        'message': newMsg,
      }).catchError((_) {});
      await app.api.sendMessage(session.id, text, senderName: name, senderRole: role);
      await _refreshMessages();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  int _initRingRemaining() {
    final expires = DateTime.tryParse(session.expiresAt ?? '')?.toLocal();
    if (expires == null) return 45;
    final left = expires.difference(DateTime.now()).inSeconds;
    if (left <= 0 || left > 45) return 45;
    return left.toInt();
  }

  Future<void> _handleRingTimeout() async {
    if (ending || session.ended) return;
    ending = true;
    try {
      await context.read<AppController>().api.sendSignal(session.id, {
        'type': 'call_ended',
        'reason': 'RING_TIMEOUT',
      });
      await context.read<AppController>().api.cancelSession(session.id);
    } catch (_) {}
    await _cleanupMedia();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No Answer'),
        content: Text(
          widget.callerSide
              ? 'Listener did not answer within 45 seconds. No money was deducted.'
              : 'Caller did not answer your callback.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.clearCall();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }


  Future<void> _finishFromPeer() async {
    if (ending) return;
    ending = true;

    // Immediately stop timer and pollers
    clock?.cancel();
    clock = null;
    sessionPoll?.cancel();
    sessionPoll = null;
    signalPoll?.cancel();
    signalPoll = null;
    heartbeat?.cancel();
    heartbeat = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _offerWatchdogTimer?.cancel();
    _offerWatchdogTimer = null;
    _privacyAlerts.stop();

    // Immediately detach renderers and stop local hardware tracks
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try { t.stop(); } catch (_) {}
    }

    unawaited(_cleanupMedia());

    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.clearCall();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _end() async {
    if (ending) return;
    ending = true;

    // 1. Immediately freeze duration timer and cancel all polling
    clock?.cancel();
    clock = null;
    sessionPoll?.cancel();
    sessionPoll = null;
    signalPoll?.cancel();
    signalPoll = null;
    heartbeat?.cancel();
    heartbeat = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _offerWatchdogTimer?.cancel();
    _offerWatchdogTimer = null;
    _privacyAlerts.stop();

    // 2. Immediately detach renderers and stop microphone & camera hardware tracks
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try { t.stop(); } catch (_) {}
    }

    // 3. Dispatch end signals to backend in background
    try {
      final api = context.read<AppController>().api;
      api.sendSignal(session.id, {'type': 'call_ended', 'reason': 'USER_ENDED'}).catchError((_) {});
      api.endSession(session.id).catchError((_) => session);
    } catch (_) {}

    // 4. Cleanup native media in background without blocking UI
    unawaited(_cleanupMedia());

    // 5. Instantly dismiss call UI
    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.clearCall();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _cancel() async {
    ending = true;
    clock?.cancel();
    clock = null;
    sessionPoll?.cancel();
    sessionPoll = null;
    heartbeat?.cancel();
    heartbeat = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _offerWatchdogTimer?.cancel();
    _offerWatchdogTimer = null;

    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try { t.stop(); } catch (_) {}
    }

    try {
      final api = context.read<AppController>().api;
      api.sendSignal(session.id, {
        'type': 'call_ended',
        'reason': 'CALL_CANCELLED',
      }).catchError((_) {});
      api.cancelSession(session.id).catchError((_) => session);
    } catch (_) {}

    unawaited(_cleanupMedia());

    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.clearCall();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _cleanupMedia() async {
    sessionPoll?.cancel();
    sessionPoll = null;
    signalPoll?.cancel();
    signalPoll = null;
    heartbeat?.cancel();
    heartbeat = null;
    messagePoll?.cancel();
    messagePoll = null;
    clock?.cancel();
    clock = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _offerWatchdogTimer?.cancel();
    _offerWatchdogTimer = null;
    _privacyAlerts.stop();

    // 1. Detach renderers FIRST before destroying native media objects
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}

    _stopAndUploadRecording();
    try { await voiceFx.stop().timeout(const Duration(milliseconds: 250), onTimeout: () {}); } catch (_) {}
    try { await voiceChannel?.close(); } catch (_) {}
    voiceChannel = null;

    final oldLocal = localStream;
    final oldRemote = remoteStream;
    final oldPc = pc;
    localStream = null;
    remoteStream = null;
    pc = null;

    try {
      for (final t in oldLocal?.getTracks() ?? <MediaStreamTrack>[]) {
        try { t.stop(); } catch (_) {}
      }
      for (final t in oldRemote?.getTracks() ?? <MediaStreamTrack>[]) {
        try { t.stop(); } catch (_) {}
      }
      await Future.wait([
        if (oldLocal != null) oldLocal.dispose().timeout(const Duration(milliseconds: 300), onTimeout: () {}),
        if (oldRemote != null) oldRemote.dispose().timeout(const Duration(milliseconds: 300), onTimeout: () {}),
        if (oldPc != null) oldPc.close().timeout(const Duration(milliseconds: 300), onTimeout: () {}),
      ]).timeout(const Duration(milliseconds: 500), onTimeout: () => []);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && !session.ended && !ending) {
      _api.endSession(session.id).catchError((_) => session);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    sessionPoll?.cancel();
    sessionPoll = null;
    signalPoll?.cancel();
    signalPoll = null;
    heartbeat?.cancel();
    heartbeat = null;
    messagePoll?.cancel();
    messagePoll = null;
    clock?.cancel();
    clock = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _privacyAlerts.stop();
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _cleanupMedia();
    if (registeredActiveSession) {
      try { context.read<AppController>().exitActiveSession(); } catch (_) {}
    }
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}
    localRenderer.dispose();
    remoteRenderer.dispose();
    messageController.dispose();
    gameSignal.dispose();
    super.dispose();
  }

  String _time(int value) => '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

  void _minimizeCall() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.minimize();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final peerName = widget.callerSide ? session.listenerName : session.callerNickname;
    final isRinging = !isLive && !session.ended;
    final isCallback = session.reference.startsWith('CB-') || (!widget.callerSide && session.status == 'REQUESTED');
    final peerAvatar = widget.callerSide ? session.listenerAvatarUrl : session.callerAvatarUrl;

    final isChat = session.type == 'CHAT';
    final isVideo = session.type == 'VIDEO_CALL';

    final Color serviceAccent;
    final Color serviceBg;
    final IconData serviceIcon;
    final String serviceShortTag;
    final String servicePillText;
    final String serviceSubtitle;
    final String serviceNoticeText;
    final String serviceCancelText;
    final IconData serviceCancelIcon;
    final String servicePrivacyText;

    if (isVideo) {
      serviceAccent = const Color(0xFF7C3AED); // Royal Violet
      serviceBg = const Color(0xFFF3E8FF);     // Soft Lavender
      serviceIcon = Icons.videocam_rounded;
      serviceShortTag = 'VIDEO CALL';
      servicePillText = isCallback ? 'REQUESTED VIDEO' : 'OUTGOING VIDEO CALL';
      serviceSubtitle = isCallback ? 'Ringing for video callback…' : 'Starting video call…';
      serviceNoticeText = isCallback
          ? 'Waiting for caller to accept your video callback.'
          : 'Connecting video call to the listener.';
      serviceCancelText = isCallback ? 'Cancel callback' : 'Cancel video call';
      serviceCancelIcon = Icons.videocam_off_outlined;
      servicePrivacyText = isCallback
          ? "Camera connects when they accept."
          : "Your video call stays private and encrypted.";
    } else if (isChat) {
      serviceAccent = const Color(0xFF059669); // Emerald Teal
      serviceBg = const Color(0xFFECFDF5);     // Soft Mint
      serviceIcon = Icons.chat_bubble_rounded;
      serviceShortTag = 'CHAT';
      servicePillText = isCallback ? 'REQUESTED CHAT' : 'OUTGOING CHAT REQUEST';
      serviceSubtitle = isCallback ? 'Waiting for chat callback…' : 'Connecting to chat…';
      serviceNoticeText = isCallback
          ? 'Waiting for caller to accept your chat callback.'
          : 'Connecting private chat with the listener.';
      serviceCancelText = isCallback ? 'Cancel callback' : 'Cancel chat';
      serviceCancelIcon = Icons.chat_bubble_outline_rounded;
      servicePrivacyText = isCallback
          ? "Chat opens when they accept."
          : "Your chat messages stay private and encrypted.";
    } else {
      serviceAccent = const Color(0xFFF95B3D); // Coral Orange
      serviceBg = const Color(0xFFFFECE5);     // Soft Peach
      serviceIcon = Icons.phone_rounded;
      serviceShortTag = 'VOICE CALL';
      servicePillText = isCallback ? 'REQUESTED AUDIO' : 'OUTGOING';
      serviceSubtitle = isCallback ? 'Ringing for callback…' : 'Calling…';
      serviceNoticeText = isCallback
          ? 'Waiting for caller to accept your callback.'
          : 'Connecting you to the listener.';
      serviceCancelText = isCallback ? 'Cancel callback' : 'Cancel call';
      serviceCancelIcon = Icons.cancel_outlined;
      servicePrivacyText = isCallback
          ? "You'll be connected when they accept."
          : "Your call stays private and secure.";
    }

    final isMinimized = widget.isHostedInGlobalManager && ActiveCallManager.instance.isMinimized;
    return PopScope(
      canPop: isMinimized || session.ended,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || isMinimized) return;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          if (isLive && !session.ended) {
            _minimizeCall();
          } else if (!isLive && !session.ended) {
            final serviceName = isVideo ? 'video call' : (isChat ? 'chat' : 'call');
            final shouldCancel = await confirm(
              context,
              widget.callerSide ? 'Cancel $serviceName request?' : 'Cancel callback?',
              'Do you want to cancel and go back?',
            );
            if (shouldCancel && mounted) {
              await _cancel();
            }
          } else {
            final shouldEnd = await confirm(
              context,
              'End session?',
              'Leaving will end the active session.',
            );
            if (shouldEnd && mounted) {
              await _end();
            }
          }
        });
      },
      child: isRinging
          ? Scaffold(
              backgroundColor: const Color(0xFFFAF5EE),
              appBar: AppBar(
                backgroundColor: const Color(0xFFFAF5EE),
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 22),
                  onPressed: () async {
                    final serviceName = isVideo ? 'video call' : (isChat ? 'chat' : 'call');
                    if (await confirm(context, widget.callerSide ? 'Cancel $serviceName request?' : 'Cancel callback?', 'Do you want to cancel and go back?')) {
                      await _cancel();
                    }
                  },
                ),
                titleSpacing: 0,
                title: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: serviceBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: serviceAccent.withValues(alpha: 0.3), width: 1),
                      ),
                      child: ClipOval(
                        child: peerAvatar != null && peerAvatar.isNotEmpty
                            ? RemoteAvatar(
                                url: peerAvatar,
                                radius: 17,
                                fallback: peerName,
                              )
                            : Center(
                                child: Icon(
                                  Icons.person_rounded,
                                  size: 20,
                                  color: serviceAccent,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            peerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Row(
                            children: [
                              Icon(serviceIcon, size: 10, color: serviceAccent),
                              const SizedBox(width: 3),
                              Text(
                                serviceShortTag,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: serviceAccent,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF0F172A), size: 22),
                    onPressed: _showTools,
                  ),
                ],
              ),
              body: SafeArea(
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // Animated Centerpiece with Service-Themed Waves & Badge
                    Center(
                      child: CallPulseAvatar(
                        name: peerName,
                        avatarUrl: peerAvatar,
                        size: 200,
                        serviceType: session.type,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Status Pill: Service-specific (● OUTGOING VIDEO CALL / ● OUTGOING CHAT / ● OUTGOING)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: serviceBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: serviceAccent.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(serviceIcon, size: 12, color: serviceAccent),
                            const SizedBox(width: 6),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: serviceAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              servicePillText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: serviceAccent,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Peer Name Heading
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        peerName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Subtitle (Service-specific)
                    Text(
                      serviceSubtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Big Timer: 45s remaining countdown
                    Text(
                      '${ringRemaining}s',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: serviceAccent,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'remaining',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Info Notice Row (Service-specific)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          serviceIcon,
                          size: 15,
                          color: serviceAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          serviceNoticeText,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Outlined Pill Action Button: Cancel callback or Cancel service
                    InkWell(
                      onTap: _cancel,
                      borderRadius: BorderRadius.circular(26),
                      child: Container(
                        width: 220,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: serviceAccent,
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: serviceAccent.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              serviceCancelIcon,
                              size: 18,
                              color: serviceAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              serviceCancelText,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: serviceAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(flex: 3),

                    // Bottom Privacy Card (Service-specific)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: serviceBg.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: serviceAccent.withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: serviceBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                isVideo
                                    ? Icons.videocam_rounded
                                    : (isChat ? Icons.lock_rounded : Icons.verified_user_rounded),
                                size: 16,
                                color: serviceAccent,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 18,
                              color: serviceAccent.withValues(alpha: 0.3),
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            Expanded(
                              child: Text(
                                servicePrivacyText,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : (isChat
              ? _buildLiveChatScreen(peerName, peerAvatar)
              : isVideo
                  ? _buildLiveVideoScreen(peerName, peerAvatar)
                  : _buildLiveAudioScreen(peerName, peerAvatar)),
    );
  }

  /// Floating notification banner for reconnection/security alerts
  Widget _buildTopBanner() {
    if (banner == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFCA5A5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                banner!,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF991B1B),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => banner = null),
              child: const Icon(Icons.close_rounded, color: Color(0xFF991B1B), size: 18),
            ),
          ],
        ),
      ),
    );
  }

  /// -------------------------------------------------------------
  /// LIVE AUDIO CALL SCREEN (Matches media_1790781859761.png)
  /// -------------------------------------------------------------
  Widget _buildLiveAudioScreen(String peerName, String? peerAvatar) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF5EE),
      body: Stack(
        children: [
          // Background Painter with fluid silk curves and subtle ambient sparkle dots
          Positioned.fill(
            child: CustomPaint(
              painter: SilkWavesPainter(),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Bar: Minimize button, Center Peer Name, Sparkles/Tools button
                _buildLiveAudioTopBar(peerName),

                // Floating Banner if any
                if (banner != null) _buildTopBanner(),

                const Spacer(flex: 2),

                // Center Visualizer: Equalizer Waves + Glowing Avatar + Equalizer Waves
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      EqualizerBars(animation: _pulseController, isLeft: true),
                      const SizedBox(width: 8),
                      _buildPickedUpAvatarOrb(peerName, peerAvatar),
                      const SizedBox(width: 8),
                      EqualizerBars(animation: _pulseController, isLeft: false),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Peer Name Heading
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    peerName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Call Duration Timer
                Text(
                  _time(seconds),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),

                if (peerVoiceFilter != AndroidVoiceFx.normal) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFECE5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      '🎭 Peer voice privacy effect active',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF95B3D),
                      ),
                    ),
                  ),
                ],

                const Spacer(flex: 3),

                // Bottom Floating Controls: 3 circular buttons (Mic, Speaker, End Call)
                _buildLiveAudioControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Top Bar for Picked-Up Audio Call
  Widget _buildLiveAudioTopBar(String peerName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Minimize Button (Frosted circular button with downward chevron)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.lightImpact();
              _minimizeCall();
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF4E4D9).withValues(alpha: 0.7),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF1E293B),
                size: 28,
              ),
            ),
          ),

          // Center Peer Name
          Expanded(
            child: Text(
              peerName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
                letterSpacing: -0.2,
              ),
            ),
          ),

          // Tools / Sparkle Button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _showTools();
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF4E4D9).withValues(alpha: 0.7),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Color(0xFF1E293B),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Center glowing avatar orb with concentric aura and silhouette
  Widget _buildPickedUpAvatarOrb(String peerName, String? peerAvatar) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = _pulseController.value;
        final scale = 1.0 + 0.02 * pulse;

        return SizedBox(
          width: 250,
          height: 250,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outermost soft glowing halo
              Container(
                width: 235 * scale,
                height: 235 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFF2EB).withValues(alpha: 0.65),
                ),
              ),

              // Middle thin luminous cream ring
              Container(
                width: 195,
                height: 195,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 1.5,
                  ),
                ),
              ),

              // Inner peach-rose glowing orb
              Container(
                width: 156,
                height: 156,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.15, -0.25),
                    radius: 0.85,
                    colors: [
                      Color(0xFFFFBBA8),
                      Color(0xFFF99D85),
                      Color(0xFFFED8C5),
                    ],
                    stops: [0.0, 0.65, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF97316).withValues(alpha: 0.28),
                      blurRadius: 34,
                      spreadRadius: 4,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: peerAvatar != null && peerAvatar.isNotEmpty
                      ? RemoteAvatar(
                          url: peerAvatar,
                          radius: 78,
                          fallback: peerName,
                        )
                      : _buildDefaultSilhouette(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Translucent white avatar silhouette matching screenshot
  Widget _buildDefaultSilhouette() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 7),
          Container(
            width: 82,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(41)),
            ),
          ),
        ],
      ),
    );
  }

  /// Bottom Controls Dock (3 circular buttons: Mic, Speaker, End Call)
  Widget _buildLiveAudioControls() {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Microphone Toggle
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _toggleMic();
            },
            child: Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: mic ? const Color(0xFFF7ECE4) : const Color(0xFFFFE4E1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                mic ? Icons.mic_rounded : Icons.mic_off_rounded,
                color: mic ? const Color(0xFF475569) : const Color(0xFFE11D48),
                size: 28,
              ),
            ),
          ),

          // 2. Speaker Toggle
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _toggleSpeaker();
            },
            child: Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF7ECE4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                color: const Color(0xFF475569),
                size: 28,
              ),
            ),
          ),

          // 3. End Call Button
          GestureDetector(
            onTap: () {
              HapticFeedback.heavyImpact();
              _end();
            },
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5E5E), Color(0xFFE53935)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF4B4B).withValues(alpha: 0.38),
                    blurRadius: 22,
                    spreadRadius: 3,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.call_end_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// -------------------------------------------------------------
  /// LIVE VIDEO CALL SCREEN (Modern State-of-the-Art Luxury)
  /// -------------------------------------------------------------
  Widget _buildLiveVideoScreen(String peerName, String? peerAvatar) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final bottomPadding = mediaQuery.padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      resizeToAvoidBottomInset: false,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Fullscreen Remote Video or Connecting Fallback
            Positioned.fill(
              child: (remoteRenderer.srcObject != null &&
                      remoteStream != null &&
                      remoteStream!.getVideoTracks().isNotEmpty)
                  ? FilteredVideoView(
                      filter: peerVideoFilter,
                      child: RTCVideoView(
                        remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    )
                  : _buildVideoConnectingFallback(peerName, peerAvatar),
            ),

            // 2. Subtle Cinematic Vignette Overlays
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 160,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.75),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 200,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),

            // 3. Floating PiP Local Video (top right)
            Positioned(
              right: 16,
              top: topPadding + 62,
              width: 108,
              height: 154,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.lightImpact();
                  _switchCamera();
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.45),
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        camera
                            ? FilteredVideoView(
                                filter: activeVideoFilter,
                                showBadge: false,
                                child: RTCVideoView(
                                  localRenderer,
                                  mirror: true,
                                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                                ),
                              )
                            : Container(
                                color: const Color(0xFF1E2433),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.08),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.videocam_off_rounded,
                                          size: 22,
                                          color: Color(0xFFEF4444),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Camera Off',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                        // Tap-to-flip camera icon badge at bottom-right corner of PiP
                        if (camera)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.55),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: const Icon(
                                Icons.flip_camera_ios_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 4. Floating Top Bar (Strictly positioned at the top)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // Minimize Call Button
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _minimizeCall();
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.45),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Peer Name & Live Duration Timer Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 130),
                              child: Text(
                                peerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _time(seconds),
                              style: const TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      // Tools / Sparkle Button
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _showTools();
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.45),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Top Banner if active
            if (banner != null)
              Positioned(
                top: topPadding + 62,
                left: 16,
                right: 136,
                child: _buildTopBanner(),
              ),

            // 5. Floating Bottom Controls Dock (Firmly positioned at the bottom)
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomPadding + 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111520).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(38),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mic
                    _buildVideoGlassButton(
                      icon: mic ? Icons.mic_rounded : Icons.mic_off_rounded,
                      isActive: mic,
                      tooltip: mic ? 'Mute' : 'Unmute',
                      onTap: _toggleMic,
                    ),
                    // Video Camera
                    _buildVideoGlassButton(
                      icon: camera ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                      isActive: camera,
                      tooltip: camera ? 'Turn off camera' : 'Turn on camera',
                      onTap: _toggleCamera,
                    ),
                    // Camera Switch
                    _buildVideoGlassButton(
                      icon: Icons.flip_camera_ios_rounded,
                      isActive: true,
                      tooltip: 'Switch camera',
                      onTap: _switchCamera,
                    ),
                    // Video Privacy Filter
                    _buildVideoGlassButton(
                      icon: Icons.face_retouching_natural_rounded,
                      isActive: activeVideoFilter != VideoPrivacyFilter.none,
                      isFilter: true,
                      tooltip: 'Video filters',
                      onTap: _videoFilters,
                    ),
                    // Speaker
                    _buildVideoGlassButton(
                      icon: speaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                      isActive: speaker,
                      tooltip: speaker ? 'Speaker' : 'Earpiece',
                      onTap: _toggleSpeaker,
                    ),
                    // End Call Button
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        _end();
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF5252), Color(0xFFDC2626)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFDC2626).withValues(alpha: 0.5),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Modern full-screen connecting fallback for video call
  Widget _buildVideoConnectingFallback(String peerName, String? peerAvatar) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.2,
          colors: [
            Color(0xFF1E1B4B), // Deep indigo
            Color(0xFF0F172A), // Slate navy
            Color(0xFF060913), // Deep obsidian
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildVideoConnectingAvatarOrb(peerName, peerAvatar),
                const SizedBox(height: 22),
                Text(
                  peerName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFA78BFA).withValues(alpha: 0.45),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Connecting video feed…',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE2E8F0),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'End-to-end encrypted private video',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Glowing neon-accented avatar orb for video screen connecting state
  Widget _buildVideoConnectingAvatarOrb(String peerName, String? peerAvatar) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final pulse = _pulseController.value;
        final scale = 1.0 + 0.05 * pulse;

        return SizedBox(
          width: 170,
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outermost soft glowing violet halo
              Container(
                width: 165 * scale,
                height: 165 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.22 * (1.0 - pulse * 0.3)),
                ),
              ),

              // Middle neon accent ring
              Container(
                width: 142,
                height: 142,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFA78BFA).withValues(alpha: 0.45 + 0.35 * pulse),
                    width: 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

              // Inner avatar circle
              Container(
                width: 124,
                height: 124,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.9),
                    width: 2.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: peerAvatar != null && peerAvatar.isNotEmpty
                      ? RemoteAvatar(
                          url: peerAvatar,
                          radius: 62,
                          fallback: peerName,
                        )
                      : Container(
                          color: const Color(0xFF1E293B),
                          child: const Icon(
                            Icons.person_rounded,
                            size: 58,
                            color: Color(0xFFA78BFA),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoGlassButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    bool isFilter = false,
    String? tooltip,
  }) {
    final Color bgColor;
    final Color iconColor;
    if (isFilter) {
      bgColor = isActive
          ? const Color(0xFF7C3AED).withValues(alpha: 0.85)
          : Colors.white.withValues(alpha: 0.12);
      iconColor = isActive ? Colors.white : Colors.white.withValues(alpha: 0.9);
    } else {
      bgColor = isActive
          ? Colors.white.withValues(alpha: 0.14)
          : const Color(0xFFEF4444).withValues(alpha: 0.88);
      iconColor = Colors.white;
    }

    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bgColor,
            border: Border.all(
              color: Colors.white.withValues(alpha: isActive ? 0.2 : 0.4),
              width: 0.8,
            ),
            boxShadow: isActive
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 21,
          ),
        ),
      ),
    );
  }

  /// -------------------------------------------------------------
  /// LIVE CHAT SCREEN (Silk Cream Luxury HearMe Theme)
  /// -------------------------------------------------------------
  Widget _buildLiveChatScreen(String peerName, String? peerAvatar) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF5EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF5EE),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28, color: Color(0xFF0F172A)),
          tooltip: 'Minimize chat',
          onPressed: _minimizeCall,
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFFFFECE5),
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: peerAvatar != null && peerAvatar.isNotEmpty
                    ? RemoteAvatar(
                        url: peerAvatar,
                        radius: 18,
                        fallback: peerName,
                      )
                    : const Center(
                        child: Icon(Icons.person_rounded, size: 22, color: Color(0xFFF95B3D)),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Chatting • ${_time(seconds)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF95B3D),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _showTools,
            icon: const Icon(Icons.auto_awesome, color: Color(0xFF0F172A)),
          ),
          IconButton(
            onPressed: _end,
            icon: const Icon(Icons.close_rounded, color: Color(0xFFE11D48)),
          ),
        ],
      ),
      body: Column(
        children: [
          if (banner != null) _buildTopBanner(),

          // Security & anonymity reassurance pill
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFECE5).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 12, color: Color(0xFFF95B3D)),
                SizedBox(width: 6),
                Text(
                  'End-to-end encrypted • Anonymous Chat',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF95B3D),
                  ),
                ),
              ],
            ),
          ),

          // Messages list
          Expanded(child: _chatBody()),

          // Quick Action Pills Row (Icebreakers, Gifts, Games)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _buildQuickActionChip(
                  icon: Icons.lightbulb_outline_rounded,
                  label: 'Topic',
                  onTap: _topic,
                ),
                if (widget.callerSide)
                  _buildQuickActionChip(
                    icon: Icons.card_giftcard_rounded,
                    label: 'Send Gift',
                    onTap: _gift,
                  ),
                _buildQuickActionChip(
                  icon: Icons.sports_esports_rounded,
                  label: 'Play Game',
                  onTap: () => _openGames(),
                ),
                _buildQuickActionChip(
                  icon: Icons.report_outlined,
                  label: 'Report',
                  onTap: _report,
                ),
              ],
            ),
          ),

          // Chat Input Bar
          _chatInput(),
        ],
      ),
    );
  }

  Widget _buildQuickActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFECE5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: const Color(0xFFF95B3D)),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatBody() => ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        itemCount: messages.length,
        itemBuilder: (context, i) {
          final m = Map<String, dynamic>.from(messages[i]);
          final mine = (m['senderRole'] == 'USER') == widget.callerSide;
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 290),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: mine
                    ? const LinearGradient(
                        colors: [Color(0xFFF95B3D), Color(0xFFFF7A59)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: mine ? null : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(mine ? 18 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 18),
                ),
                border: mine
                    ? null
                    : Border.all(
                        color: const Color(0xFFFFECE5),
                        width: 1,
                      ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '${m['senderName'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF95B3D),
                        ),
                      ),
                    ),
                  Text(
                    '${m['text'] ?? ''}',
                    style: TextStyle(
                      fontSize: 14.5,
                      color: mine ? Colors.white : const Color(0xFF0F172A),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _chatInput() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFFFECE5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: messageController,
                    onSubmitted: (_) => _sendMessage(),
                    style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
                    decoration: const InputDecoration(
                      hintText: 'Type a message…',
                      hintStyle: TextStyle(fontSize: 14.5, color: Color(0xFF94A3B8)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFF95B3D), Color(0xFFFF7A59)],
                      ),
                    ),
                    child: const Icon(
                      Icons.arrow_upward_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );


  Future<void> _switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
      if (mounted) setState(() {});
    }
  }

  void _toggleMic() {
    final next = !mic;
    mic = next;
    if (nativeVoiceFxActive) {
      for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = false;
      }
      if (next) {
        voiceFx.start(activeVoiceFilter).catchError((_) {});
      } else {
        voiceFx.stopCapture().catchError((_) {});
      }
    } else {
      for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = next;
      }
    }
    if (widget.isHostedInGlobalManager) {
      ActiveCallManager.instance.updateState(
        seconds: seconds,
        muted: !next,
        live: isLive,
        updatedSession: session,
      );
    }
    setState(() {});
  }

  void _toggleCamera() {
    camera = !camera;
    for (final t in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = camera;
    }
    setState(() {});
  }

  void _toggleSpeaker() {
    speaker = !speaker;
    Helper.setSpeakerphoneOn(speaker).catchError((_) {});
    setState(() {});
  }

  Future<void> _showTools() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          if (widget.callerSide)
            ListTile(leading: const Icon(Icons.card_giftcard), title: const Text('Send a virtual gift'), onTap: () { Navigator.pop(ctx); _gift(); }),
          if (!isChat)
            ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('In-call chat'), onTap: () { Navigator.pop(ctx); _inCallChat(); }),
          if (!isChat)
            ListTile(leading: const Icon(Icons.graphic_eq), title: const Text('Voice privacy effects'), subtitle: Text(_voiceLabel(activeVoiceFilter)), onTap: () { Navigator.pop(ctx); _voiceFilters(); }),
          if (isVideo)
            ListTile(leading: const Icon(Icons.masks), title: const Text('Video masks & privacy filters'), subtitle: Text(_videoLabel(activeVideoFilter)), onTap: () { Navigator.pop(ctx); _videoFilters(); }),
          ListTile(leading: const Icon(Icons.lightbulb_outline), title: const Text('Send an icebreaker topic'), onTap: () { Navigator.pop(ctx); _topic(); }),
          ListTile(leading: const Icon(Icons.sports_esports), title: const Text('Open mini games'), subtitle: const Text('Tic-Tac-Toe • Would You Rather • 20 Questions'), onTap: () { Navigator.pop(ctx); _openGames(); }),
          ListTile(leading: const Icon(Icons.report_outlined), title: const Text('Report the other person'), onTap: () { Navigator.pop(ctx); _report(); }),
        ]),
      ),
    );
  }

  String _voiceLabel(String id) => AndroidVoiceFx.options.firstWhere((x) => x.id == id, orElse: () => AndroidVoiceFx.options.first).label;
  String _videoLabel(String id) => VideoPrivacyFilter.options.firstWhere((x) => x['id'] == id, orElse: () => VideoPrivacyFilter.options.first)['label']!;

  Future<void> _voiceFilters() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Voice privacy effects'),
        children: AndroidVoiceFx.options.map((o) => RadioListTile<String>(
          value: o.id,
          groupValue: activeVoiceFilter,
          title: Text('${o.emoji} ${o.label}'),
          subtitle: Text(o.description),
          onChanged: (v) => Navigator.pop(ctx, v),
        )).toList(),
      ),
    );
    if (selected == null || selected == activeVoiceFilter) return;
    if (selected != AndroidVoiceFx.normal && !voiceFx.supported) {
      if (mounted) showError(context, Exception('Voice effects are currently available on Android.'));
      return;
    }
    if (selected != AndroidVoiceFx.normal && !peerVoiceFxCapable) {
      if (mounted) {
        showError(context, Exception('This voice effect requires the other participant to use the TalkStrangers Android app. Natural WebRTC audio will continue normally.'));
      }
      return;
    }

    activeVoiceFilter = selected;
    nativeVoiceFxActive = selected != AndroidVoiceFx.normal;
    for (final t in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = mic && !nativeVoiceFxActive;
    }
    if (nativeVoiceFxActive && mic) {
      await voiceFx.start(selected);
    } else {
      await voiceFx.stopCapture();
    }
    await context.read<AppController>().api.sendSignal(session.id, {'type': 'VOICE_FILTER_CHANGED', 'filter': selected});
    if (mounted) setState(() {});
  }

  Future<void> _videoFilters() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Video privacy filters'),
        children: VideoPrivacyFilter.options.map((o) => RadioListTile<String>(
          value: o['id']!,
          groupValue: activeVideoFilter,
          title: Text('${o['emoji']} ${o['label']}'),
          subtitle: Text(o['description']!),
          onChanged: (v) => Navigator.pop(ctx, v),
        )).toList(),
      ),
    );
    if (selected == null || selected == activeVideoFilter) return;
    activeVideoFilter = selected;
    await context.read<AppController>().api.sendSignal(session.id, {'type': 'VIDEO_FILTER_CHANGED', 'filter': selected});
    if (mounted) setState(() {});
  }

  Future<void> _inCallChat() async {
    await _refreshMessages();
    if (!mounted) return;
    final controller = TextEditingController();
    Timer? localPoll;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        localPoll ??= Timer.periodic(const Duration(milliseconds: 900), (_) async {
          try {
            messages = await context.read<AppController>().api.messages(session.id);
            if (ctx.mounted) setLocal(() {});
          } catch (_) {}
        });
        Future<void> send() async {
          final text = controller.text.trim();
          if (text.isEmpty) return;
          controller.clear();
          final app = context.read<AppController>();
          final name = widget.callerSide ? 'Anonymous' : (app.user?.fullName ?? 'Listener');
          final role = widget.callerSide ? 'USER' : 'LISTENER';
          final newMsg = {
            'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
            'senderId': app.user?.id,
            'senderRole': role,
            'senderName': name,
            'text': text,
            'time': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
            'timestamp': DateTime.now().toIso8601String(),
          };
          messages.add(newMsg);
          if (ctx.mounted) setLocal(() {});
          app.api.sendSignal(session.id, {
            'type': 'IN_CALL_CHAT',
            'message': newMsg,
          }).catchError((_) {});
          await app.api.sendMessage(session.id, text, senderName: name, senderRole: role);
          messages = await app.api.messages(session.id);
          if (ctx.mounted) setLocal(() {});
        }
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .68,
            child: Column(children: [
              const Padding(padding: EdgeInsets.all(14), child: Text('In-call chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
              Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: messages.length, itemBuilder: (_, i) {
                final m = Map<String, dynamic>.from(messages[i]);
                return ListTile(dense: true, title: Text('${m['senderName'] ?? ''}'), subtitle: Text('${m['text'] ?? ''}'));
              })),
              SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [Expanded(child: TextField(controller: controller, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'Message…'))), IconButton.filled(onPressed: send, icon: const Icon(Icons.send))]))),
            ]),
          ),
        );
      }),
    );
    localPoll?.cancel();
    controller.dispose();
  }

  Future<void> _gift() async {
    try {
      final gifts = await context.read<AppController>().api.gifts();
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        builder: (ctx) => ListView(
          shrinkWrap: true,
          children: gifts.map((g) {
            final m = Map<String, dynamic>.from(g);
            return ListTile(
              leading: Text('${m['emoji'] ?? '🎁'}', style: const TextStyle(fontSize: 30)),
              title: Text('${m['name'] ?? 'Gift'}'),
              subtitle: Text('₹${m['price'] ?? ''} • ${m['description'] ?? ''}'),
              onTap: () async {
                try {
                  final sent = await context.read<AppController>().api.sendGift(session.id, '${m['id'] ?? m['giftType'] ?? m['name']}');
                  await context.read<AppController>().api.sendSignal(session.id, {'type': 'gift_sent', 'gift': sent});
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) showError(ctx, e);
                }
              },
            );
          }).toList(),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _topic() async {
    const topics = [
      'What made you smile recently?',
      'What is something you wish people understood about you?',
      'If you could travel anywhere tomorrow, where would you go?',
      'What song matches your mood today?',
      'What is one small thing you are grateful for?',
    ];
    final topic = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose a topic'),
        children: topics.map((t) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, t), child: Padding(padding: const EdgeInsets.all(8), child: Text(t)))).toList(),
      ),
    );
    if (topic != null) {
      await context.read<AppController>().api.sendSignal(session.id, {'type': 'TOPIC_BROADCAST', 'topic': topic});
      if (mounted) setState(() => banner = '💡 Topic: $topic');
    }
  }

  Future<void> _openGames({bool fromPeer = false}) async {
    if (!mounted || gameSheetOpen) return;
    gameSheetOpen = true;
    if (!fromPeer) {
      await context.read<AppController>().api.sendSignal(session.id, {
        'type': 'GAME_ACTION',
        'payload': {'game': 'TTT', 'action': 'OPEN', 'data': <String, dynamic>{}}
      });
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => InCallMiniGames(
        isCaller: widget.callerSide,
        incomingSignal: gameSignal,
        send: (payload) => context.read<AppController>().api.sendSignal(session.id, {'type': 'GAME_ACTION', 'payload': payload}),
      ),
    );
    gameSheetOpen = false;
  }

  Future<void> _report() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report'),
        content: TextField(controller: c, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'What happened?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Submit')),
        ],
      ),
    );
    c.dispose();
    if (text != null && text.trim().isNotEmpty) {
      final target = widget.callerSide ? (session.listenerUserId ?? session.listenerId) : (session.callerId ?? '');
      try {
        await context.read<AppController>().api.reportUser(target, sessionId: session.id, reason: 'SESSION_REPORT', description: text.trim());
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted.')));
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

}

/// Animated multi-bar soundwave equalizer for live call
class EqualizerBars extends StatelessWidget {
  final Animation<double> animation;
  final bool isLeft;

  const EqualizerBars({
    super.key,
    required this.animation,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    // 6 bars with harmonious resting and active heights
    final baseHeights = isLeft
        ? const [14.0, 22.0, 38.0, 48.0, 30.0, 16.0]
        : const [16.0, 30.0, 48.0, 38.0, 22.0, 14.0];

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(baseHeights.length, (i) {
            final phase = (i * 0.22);
            final wave = 0.5 + 0.5 * ((t + phase) % 1.0);
            final dynamicHeight = (baseHeights[i] * (0.65 + 0.45 * wave)).clamp(8.0, 50.0);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.2),
              width: 3.5,
              height: dynamicHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3.5),
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFDBA74).withValues(alpha: 0.85),
                    const Color(0xFFF97316).withValues(alpha: 0.65),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Custom painter for soft peach silk waves and subtle ambient sparkle dots
class SilkWavesPainter extends CustomPainter {
  SilkWavesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Base background gradient
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFFF9F5), Color(0xFFFDECE2), Color(0xFFFAF0E6)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // Wave 1: Flowing from top left across to right
    final wave1Paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFFCEADE).withValues(alpha: 0.65),
          const Color(0xFFFADCCB).withValues(alpha: 0.35),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final path1 = Path();
    path1.moveTo(0, h * 0.14);
    path1.cubicTo(w * 0.3, h * 0.22, w * 0.7, h * 0.08, w, h * 0.26);
    path1.lineTo(w, h * 0.40);
    path1.cubicTo(w * 0.6, h * 0.24, w * 0.25, h * 0.36, 0, h * 0.24);
    path1.close();
    canvas.drawPath(path1, wave1Paint);

    // Wave 2: Sweeping across lower-middle
    final wave2Paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFFDE8DC).withValues(alpha: 0.55),
          const Color(0xFFF9D6C4).withValues(alpha: 0.30),
        ],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(0, h * 0.54);
    path2.cubicTo(w * 0.35, h * 0.66, w * 0.65, h * 0.50, w, h * 0.70);
    path2.lineTo(w, h * 0.84);
    path2.cubicTo(w * 0.6, h * 0.68, w * 0.3, h * 0.80, 0, h * 0.68);
    path2.close();
    canvas.drawPath(path2, wave2Paint);

    // Wave 3: Bottom subtle wave
    final wave3Paint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFFCE6D6).withValues(alpha: 0.50),
          const Color(0xFFFBD7C4).withValues(alpha: 0.20),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final path3 = Path();
    path3.moveTo(0, h * 0.80);
    path3.cubicTo(w * 0.4, h * 0.73, w * 0.7, h * 0.90, w, h * 0.86);
    path3.lineTo(w, h);
    path3.lineTo(0, h);
    path3.close();
    canvas.drawPath(path3, wave3Paint);

    // Subtle ambient sparkle dots matching screenshot
    final dotPaint = Paint()..color = const Color(0xFFF6C8B2).withValues(alpha: 0.55);
    canvas.drawCircle(Offset(w * 0.25, h * 0.26), 2.0, dotPaint);
    canvas.drawCircle(Offset(w * 0.63, h * 0.25), 2.2, dotPaint);
    canvas.drawCircle(Offset(w * 0.32, h * 0.49), 2.0, dotPaint);
    canvas.drawCircle(Offset(w * 0.55, h * 0.52), 1.8, dotPaint);
    canvas.drawCircle(Offset(w * 0.81, h * 0.30), 2.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
