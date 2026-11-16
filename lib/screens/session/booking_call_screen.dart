import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../services/android_voice_fx.dart';
import '../../services/api_service.dart';
import '../../services/call_recording_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/in_call_mini_games.dart';
import '../../widgets/video_privacy_filter.dart';
import '../../widgets/nudity_guard_overlay.dart';
import '../../services/in_call_voice_safety_service.dart';
import '../../services/pip_service.dart';
import '../../services/call_push_service.dart';

/// WebRTC room used by the legacy/scheduled booking flow that still exists in
/// CustomerBookingsPage on the web client. Billing and call state remain
/// server-authoritative through /calls/{bookingId}/... endpoints.
class BookingCallScreen extends StatefulWidget {
  final BookingModel booking;
  final bool callerSide;

  const BookingCallScreen({super.key, required this.booking, required this.callerSide});

  @override
  State<BookingCallScreen> createState() => _BookingCallScreenState();
}

class _BookingCallScreenState extends State<BookingCallScreen> with WidgetsBindingObserver {
  final localRenderer = RTCVideoRenderer();
final remoteRenderer = RTCVideoRenderer();

late final Future<void> _renderersReady;
  final voiceFx = AndroidVoiceFx();
  final _privacyAlerts = PrivacyAlertService();
  final gameSignal = ValueNotifier<Map<String, dynamic>?>(null);
  final chatController = TextEditingController();

  CallTokenModel? token;
  CallStatusModel? status;
  RTCPeerConnection? pc;
  RTCDataChannel? voiceChannel;
  MediaStream? localStream, remoteStream;
  Timer? signalPoll, statusPoll, reconnectTimer;
  int signalSince = 0;
  int reconnectSeconds = 30;
  bool loading = true, ending = false, mic = true, camera = true, speaker = true;
  bool reconnecting = false, gameSheetOpen = false, connectedRecorded = false, registeredActiveSession = false;
  bool peerVoiceFxCapable = false, nativeVoiceFxActive = false;
  final queuedCandidates = <Map<String, dynamic>>[];
  final inCallMessages = <Map<String, dynamic>>[];
  String? banner;
  String activeVoiceFilter = AndroidVoiceFx.normal;
  String peerVoiceFilter = AndroidVoiceFx.normal;
  String activeVideoFilter = VideoPrivacyFilter.none;
  String peerVideoFilter = VideoPrivacyFilter.none;
  bool isNudityBlurred = false;
  String? nuditySource;
  bool isNudityAllowed = false;
  bool _nudityCooldownActive = false;
  Timer? _nudityCooldownTimer;
  final String _clientId = '${DateTime.now().microsecondsSinceEpoch}_${(1000 + DateTime.now().millisecond * 7 % 9000)}';

  Future<void> _sendSignal(Map<String, dynamic> data) async {
    try {
      final payload = <String, dynamic>{
        ...data,
        'senderRole': widget.callerSide ? 'caller' : 'listener',
        'senderClientId': _clientId,
      };
      await _api.sendSignal(widget.booking.id, payload);
    } catch (_) {}
  }

  void _toggleNudityPermission({bool? forcedVal}) {
    if (!mounted) return;
    final nextVal = forcedVal ?? !isNudityAllowed;
    setState(() {
      isNudityAllowed = nextVal;
      if (nextVal) {
        isNudityBlurred = false;
        nuditySource = null;
        banner = '🔞 Nudity Mode ON — nudity allowed from both sides';
      } else {
        banner = '🛡️ Nudity protection re-enabled';
      }
    });
    _sendSignal({
      'type': 'NUDITY_PERMISSION_TOGGLED',
      'allowed': nextVal,
    });
  }

  void _dismissNudityBlur() {
    if (!mounted) return;
    setState(() {
      isNudityBlurred = false;
      nuditySource = null;
      _nudityCooldownActive = true;
    });
    _nudityCooldownTimer?.cancel();
    _nudityCooldownTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() => _nudityCooldownActive = false);
      }
    });
    _sendSignal({
      'type': 'NUDITY_ACKNOWLEDGED',
    });
  }

  DateTime? _lastNudityReportTime;

  Future<String?> _captureUnblurredSnapshot({String? source}) async {
    try {
      final isLocal = (source == 'local' || (source == 'user' && widget.callerSide) || (source == 'listener' && !widget.callerSide));
      final stream = isLocal ? localStream : (remoteStream ?? localStream);
      final videoTracks = stream?.getVideoTracks() ?? <MediaStreamTrack>[];
      if (videoTracks.isEmpty) return null;
      final track = videoTracks.first;
      final byteBuffer = await track.captureFrame();
      final bytes = byteBuffer.asUint8List();
      if (bytes.isEmpty) return null;
      final base64Str = base64Encode(bytes);
      return 'data:image/jpeg;base64,$base64Str';
    } catch (e) {
      debugPrint('[NudityModeration] Silent snapshot capture skipped or failed: $e');
      return null;
    }
  }

  void _reportNudityIncidentSilently({String? source}) {
    final now = DateTime.now();
    if (_lastNudityReportTime != null &&
        now.difference(_lastNudityReportTime!).inSeconds < 15) {
      return;
    }
    _lastNudityReportTime = now;

    // Capture unblurred frame thumbnail silently and send to backend for admin inspection
    _captureUnblurredSnapshot(source: source).then((snapshot) {
      final myRole = widget.callerSide ? 'CALLER' : 'EXPERT';
      final myName = widget.callerSide ? widget.booking.customerName : widget.booking.expertName;
      final peerNameStr = widget.callerSide ? widget.booking.expertName : widget.booking.customerName;

      _api.reportNudityIncident(
        sessionId: widget.booking.id,
        userId: widget.callerSide ? widget.booking.customerId : widget.booking.expertId,
        userName: myName,
        userRole: myRole,
        peerId: widget.callerSide ? widget.booking.expertId : widget.booking.customerId,
        peerName: peerNameStr,
        detectedSource: source ?? 'remote_peer',
        classificationLabel: 'PORN',
        confidenceScore: 0.92,
        actionTaken: 'SCREEN_BLURRED',
        isNudityAllowed: isNudityAllowed,
        snapshotData: snapshot,
      ).catchError((e) {
        debugPrint('[NudityModeration] Background report failed silently: $e');
      });
    }).catchError((_) {});
  }

  void _triggerNudityBlur({String? source}) {
    if (isNudityAllowed) return;
    if (_nudityCooldownActive) return;
    setState(() {
      isNudityBlurred = true;
      nuditySource = source ?? 'peer';
    });
    _sendSignal({
      'type': 'NUDITY_DETECTED',
      'source': source ?? (widget.callerSide ? 'user' : 'listener'),
      'reason': 'Nudity is strictly prohibited',
    });

    // Silently capture unblurred snapshot & report to admin without notifying users
    _reportNudityIncidentSilently(source: source);
  }
  bool _recordingStarted = false;
  late final ApiService _api;
  bool _isDisposed = false;

  @override
  void setState(VoidCallback fn) {
    if (!mounted || _isDisposed) return;
    super.setState(fn);
  }

  bool get isVideo => widget.booking.consultationType == 'VIDEO';
  String get peerName => widget.callerSide ? widget.booking.expertName : (widget.booking.customerName.isEmpty ? 'Caller' : widget.booking.customerName);

  Future<void> _startRecordingIfEligible() async {
    if (_recordingStarted || ending) return;

    try {
      final app = mounted ? context.read<AppController>() : null;
      if (app != null) {
        await app.refreshGovernance();
      }

      /*
       * IMPORTANT:
       * On Android, starting native Android MediaRecorder(AudioSource.MIC) or
       * flutter_webrtc MediaRecorder during an active call takes an exclusive
       * hardware lock on the microphone HAL, silencing WebRTC's WebRtcAudioRecord
       * and breaking bi-directional voice transmission.
       * Live WebRTC stream media is safely preserved without hardware HAL collision.
       */
      _recordingStarted = true;
      debugPrint(
        '[RecordingGovernance] Dedicated WebRTC audio/video transmission active for booking session ${widget.booking.id}',
      );
    } catch (e) {
      debugPrint(
        '[RecordingGovernance] Mobile Booking: Error checking recording eligibility: $e',
      );
      _recordingStarted = false;
    }
  }

  Future<void> _stopAndUploadRecording() async {
    if (!_recordingStarted) return;
    _recordingStarted = false;

    try {
      final recordedFile = await CallRecordingService.stopAndCollectRecording();
      if (recordedFile != null && await recordedFile.exists() && await recordedFile.length() > 1000) {
        debugPrint('[Recording] Uploading booking call recording (${await recordedFile.length()} bytes) for ${widget.booking.id}...');
        await _api.uploadRecording(widget.booking.id, recordedFile);
        debugPrint('[Recording] Booking call recording successfully uploaded to backend!');
      }
    } catch (e) {
      debugPrint('[Recording] Failed to upload booking recording: $e');
    }
  }

  @override
void initState() {
  super.initState();

  _api = context.read<AppController>().api;

  WidgetsBinding.instance.addObserver(this);

  /*
   * Initialize renderers once.
   */
  _renderersReady = Future.wait([
    localRenderer.initialize(),
    remoteRenderer.initialize(),
  ]).then((_) {});

  voiceFx.onFrame = (frame) {
    final dc = voiceChannel;

    if (dc != null && mic) {
      dc.send(
        RTCDataChannelMessage.fromBinary(frame),
      ).catchError((_) {});
    }
  };

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;

    context.read<AppController>().enterActiveSession();

    registeredActiveSession = true;

    if (!isVideo && defaultTargetPlatform != TargetPlatform.iOS) {
      try {
        InCallVoiceSafetyService.instance.startMonitoring(
          sessionId: widget.booking.id,
          apiClient: context.read<AppController>().client,
          onLeakageDetected: (warning) {
            if (mounted) {
              setState(() => banner = warning);
            }
          },
        );
      } catch (e) {
        debugPrint('[InCallVoiceSafety] Safe start error: $e');
      }
    }

    _bootstrap();
  });
}

  Future<void> _bootstrap() async {
    try {
      final api = context.read<AppController>().api;
      token = await api.callToken(widget.booking.id);
      status = await api.callStatus(widget.booking.id);
      await _joinMedia();
      signalPoll = Timer.periodic(const Duration(milliseconds: 650), (timer) {
        if (!mounted || _isDisposed) {
          timer.cancel();
          return;
        }
        _pollSignals();
      });
      statusPoll = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _isDisposed) {
          timer.cancel();
          return;
        }
        _pollStatus();
      });
      if (mounted && !_isDisposed) setState(() => loading = false);
      _privacyAlerts.start(_onPrivacyAlert);
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  void _onPrivacyAlert(String type) {
    final sId = widget.booking.id;
    final apiService = context.read<AppController>().api;
    apiService.securityAlert(sId, type, 'Mobile screenshot/screen-recording attempt detected').catchError((_) {});
    apiService.logInterceptionAudit({
      'sessionId': sId,
      'captureType': type.contains('RECORD') ? 'SCREEN_RECORDING' : 'SCREENSHOT',
      'commandPressed': type,
      'platform': 'MOBILE',
      'actionTaken': 'FLAG_SECURE_BLOCKED',
      'pageUrl': 'mobile/booking/' + sId,
    }).catchError((_) {});
    if (mounted) {
      setState(() => banner = '🚫 Screenshot / recording is prohibited and has been reported.');
    }
  }

  Future<MediaStream> _createBookingLocalStream() async {
    final constraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': isVideo
          ? <String, dynamic>{
              'facingMode': 'user',
              'mandatory': <String, dynamic>{
                'minWidth': 640,
                'minHeight': 480,
                'minFrameRate': 15,
              },
              'optional': <dynamic>[],
            }
          : false,
    };

    try {
      debugPrint('[WebRTC Booking] Requesting camera/mic stream.');
      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      for (final track in stream.getTracks()) {
        track.enabled = true;
      }
      debugPrint(
        '[WebRTC Booking] Capture success. '
        'stream=${stream.id}, '
        'videoTracks=${stream.getVideoTracks().length}',
      );
      return stream;
    } catch (e) {
      debugPrint('[WebRTC Booking] Standard camera failed: $e, using front camera fallback');
      final fallbackConstraints = <String, dynamic>{
        'audio': true,
        'video': isVideo ? {'facingMode': 'user'} : false,
      };
      final stream = await navigator.mediaDevices.getUserMedia(fallbackConstraints);
      for (final track in stream.getTracks()) {
        track.enabled = true;
      }
      return stream;
    }
  }

    Future<void> _checkAndPromptPermissions(bool isVideo) async {
    final permissions = <Permission>[
      Permission.microphone,
      if (isVideo) Permission.camera,
    ];

    Map<Permission, PermissionStatus> statuses = {};
    try {
      statuses = await permissions.request();
    } catch (e) {
      debugPrint('[Permissions] request error: $e');
    }

    final hasDenied = statuses.values.any((s) => !s.isGranted);
    if (hasDenied) {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.perm_device_information_rounded, color: Color(0xFFF97316), size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Permission Required', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            content: Text(
              isVideo
                  ? 'Microphone and camera permissions are required to start the video call.\n\nPlease grant permission in Settings to continue.'
                  : 'Microphone permission is required to start the audio call.\n\nPlease grant permission in Settings to continue.',
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  openAppSettings();
                },
                child: const Text('Open Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      }
      throw Exception(
        'Microphone${isVideo ? ' and camera' : ''} permission is required.',
      );
    }
  }

  Future<void> _joinMedia() async {
  /*
   * Permissions
   */
  await _checkAndPromptPermissions(isVideo);

  /*
   * Wait for renderer surfaces.
   */
  await _renderersReady;

  if (!mounted || _isDisposed || ending) {
    return;
  }

  final api = context.read<AppController>().api;

  /*
   * ============================================================
   * CREATE CAMERA STREAM FIRST
   * ============================================================
   */
  final capturedStream =
      await _createBookingLocalStream();

  if (!mounted || _isDisposed || ending) {
    for (final track in capturedStream.getTracks()) {
      try {
        track.stop();
      } catch (_) {}
    }

    try {
      await capturedStream.dispose();
    } catch (_) {}

    return;
  }

  localStream = capturedStream;

  localRenderer.srcObject = capturedStream;

  if (mounted) {
    setState(() {});
  }

  /*
   * ============================================================
   * CREATE WEBRTC CONNECTION
   * ============================================================
   */
  final ice = await api.iceServers();

  final peer = await createPeerConnection({
    'iceServers': ice,
    'sdpSemantics': 'unified-plan',
    'bundlePolicy': 'balanced',
    'rtcpMuxPolicy': 'require',
  });

  peer.onIceConnectionState = (state) {
    debugPrint('[WebRTC] Booking call ICE connection state = $state');
  };

  pc = peer;

  /*
   * Remote media
   */
  peer.onTrack = (event) async {
    if (_isDisposed || ending) return;

    debugPrint(
      '[WebRTC Booking] onTrack '
      'kind=${event.track.kind}, '
      'id=${event.track.id}, '
      'streams=${event.streams.length}',
    );

    event.track.enabled = true;

    if (event.streams.isNotEmpty) {
      remoteStream = event.streams[0];
    } else {
      remoteStream ??= await createLocalMediaStream('remote_${widget.booking.id}');
      await remoteStream!.addTrack(event.track);
    }

    if (remoteStream != null) {
      for (final track in remoteStream!.getTracks()) {
        track.enabled = true;
      }
      if (remoteRenderer.srcObject != remoteStream) {
        remoteRenderer.srcObject = remoteStream;
      }
    }

    Helper.setSpeakerphoneOn(speaker).catchError((_) {});

    if (mounted) {
      setState(() {});
    }
  };

  peer.onAddStream = (stream) {
    if (_isDisposed || ending) return;
    debugPrint('[WebRTC Booking] onAddStream id=${stream.id}');
    remoteStream = stream;
    for (final track in stream.getTracks()) {
      track.enabled = true;
    }
    if (remoteRenderer.srcObject != stream) {
      remoteRenderer.srcObject = stream;
    }
    Helper.setSpeakerphoneOn(speaker).catchError((_) {});
    if (mounted) setState(() {});
  };

  /*
   * ICE
   */
  peer.onIceCandidate = (candidate) {
    final value = candidate.candidate;

    if (value == null || value.trim().isEmpty) {
      return;
    }

    _sendSignal({
      'type': 'candidate',
      'candidate': {
        'candidate': value,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  };

  peer.onDataChannel = _attachVoiceChannel;

  peer.onConnectionState = (state) {
    if (_isDisposed || ending) {
      return;
    }

    debugPrint(
      '[WebRTC Booking] connectionState=$state',
    );

    if (state ==
        RTCPeerConnectionState
            .RTCPeerConnectionStateConnected) {
      _finishReconnect();
      Helper.setSpeakerphoneOn(true).catchError((_) {});
      _startRecordingIfEligible();
      CallPushService.instance.showOngoingCallNotification(
        peerName: peerName,
        isVideo: isVideo,
      );
      if (isVideo) {
        PipService.instance.enableAutoPiP(true);
      }
      if (mounted) setState(() {});

      if (!connectedRecorded) {
        connectedRecorded = true;

        api.recordCallConnected(
          widget.booking.id,
        ).catchError((_) {});
      }
    } else if (state ==
            RTCPeerConnectionState
                .RTCPeerConnectionStateDisconnected ||
        state ==
            RTCPeerConnectionState
                .RTCPeerConnectionStateFailed) {
      _beginReconnect();
    }
  };

  /*
   * Add local audio first.
   */
  for (final track
      in capturedStream.getAudioTracks()) {
    await peer.addTrack(
      track,
      capturedStream,
    );

    debugPrint(
      '[WebRTC Booking] Added audio track ${track.id}',
    );
  }

  /*
   * Add local camera second.
   */
  for (final track
      in capturedStream.getVideoTracks()) {
    await peer.addTrack(
      track,
      capturedStream,
    );

    debugPrint(
      '[WebRTC Booking] Added video track ${track.id}',
    );
  }

  /*
   * Caller data channel
   */
  if (widget.callerSide) {
    final init = RTCDataChannelInit()
      ..ordered = false
      ..maxRetransmits = 0;

    final channel =
        await peer.createDataChannel(
      'voice_fx',
      init,
    );

    _attachVoiceChannel(channel);
  }

  /*
   * Voice capability
   */
  await _sendSignal({
    'type': 'VOICE_FX_CAPABILITY',
    'supported': voiceFx.supported,
  });

  /*
   * Caller creates offer; Listener announces peer_ready
   */
  if (widget.callerSide) {
    await _sendOffer();
  } else {
    await _sendSignal({
      'type': 'peer_ready',
    });
  }

  if (mounted) {
    setState(() {});
  }
}

  void _attachVoiceChannel(RTCDataChannel channel) {
    voiceChannel = channel;
    channel.onMessage = (data) {
      if (data.isBinary && voiceFx.supported) voiceFx.play(data.binary).catchError((_) {});
    };
  }

  static String _preferVP8(String sdp) {
    if (!sdp.contains('m=video')) return sdp;
    final lines = sdp.split(RegExp(r'\r\n|\r|\n'));
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
      try {
        await (peer as dynamic).restartIce();
      } catch (_) {}
    }
    final offer = await peer.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': isVideo,
      if (restart) 'iceRestart': true,
    });
    final sdp = _preferVP8(offer.sdp ?? '');
    final finalOffer = RTCSessionDescription(sdp, offer.type);
    await peer.setLocalDescription(finalOffer);
    await _sendSignal({
      'type': 'offer',
      'restart': restart,
      'sdp': {'type': finalOffer.type, 'sdp': finalOffer.sdp},
    });
  }

  Future<void> _pollSignals() async {
    if (ending || _isDisposed) return;
    try {
      final signals = await _api.signals(
        widget.booking.id,
        signalSince,
        _clientId,
        widget.callerSide ? 'caller' : 'listener',
      );
      for (final raw in signals) {
        final s = Map<String, dynamic>.from(raw as Map);
        final ts = (s['timestamp'] as num?)?.toInt() ?? signalSince;
        if (ts > signalSince) signalSince = ts;
        await _processSignal(s);
      }
    } catch (_) {}
  }

  Future<void> _processSignal(Map<String, dynamic> s) async {
    final senderClientId = s['senderClientId']?.toString();
    if (senderClientId != null && senderClientId == _clientId) {
      return;
    }
    final senderRole = s['senderRole']?.toString();
    if (senderRole != null && senderRole.toLowerCase() == (widget.callerSide ? 'caller' : 'listener')) {
      return;
    }
    final type = '${s['type'] ?? ''}';
    if (const {'call_ended', 'hangup', 'peer_left'}.contains(type)) {
      await _peerEnded();
      return;
    }
    if (type == 'IN_CALL_CHAT') {
      final raw = s['message'];
      if (raw is Map) {
        inCallMessages.add(Map<String, dynamic>.from(raw));
        if (mounted) setState(() => banner = 'New in-call message');
      }
      return;
    }
    if (type == 'TOPIC_BROADCAST') {
      if (mounted) setState(() => banner = '💡 Topic: ${s['topic'] ?? ''}');
      return;
    }
    if (type == 'GAME_ACTION') {
      final payload = s['payload'] is Map ? Map<String, dynamic>.from(s['payload'] as Map) : <String, dynamic>{};
      gameSignal.value = payload;
      if (!gameSheetOpen && mounted) Future.microtask(() => _openGames(fromPeer: true));
      return;
    }
    if (type == 'VIDEO_FILTER_CHANGED') {
      if (mounted) setState(() => peerVideoFilter = '${s['filter'] ?? VideoPrivacyFilter.none}');
      return;
    }
    if (type == 'NUDITY_PERMISSION_TOGGLED') {
      final allowed = s['allowed'] == true;
      if (mounted) {
        setState(() {
          isNudityAllowed = allowed;
          if (allowed) {
            isNudityBlurred = false;
            nuditySource = null;
            banner = '🔞 $peerName enabled Nudity Mode (allowed from both sides)';
          } else {
            banner = '🛡️ $peerName turned off Nudity Mode — protection re-enabled';
          }
        });
      }
      return;
    }
    if (type == 'NUDITY_DETECTED') {
      if (isNudityAllowed) return;
      if (mounted && !_nudityCooldownActive) {
        setState(() {
          isNudityBlurred = true;
          nuditySource = s['source']?.toString() ?? 'peer';
        });
      }
      return;
    }
    if (type == 'NUDITY_ACKNOWLEDGED') {
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

    final peer = pc;
    if (peer == null) return;
    if (type == 'peer_ready' && widget.callerSide) {
      final connState = await peer.getConnectionState();
      if (connState != RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        await _sendOffer();
      }
      return;
    }
    if (type == 'offer' && !widget.callerSide) {
      final d = Map<String, dynamic>.from(s['sdp'] as Map);
      final rawSdp = d['sdp']?.toString() ?? '';
      await peer.setRemoteDescription(RTCSessionDescription(_preferVP8(rawSdp), d['type']?.toString()));
      final answer = await peer.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': isVideo,
      });
      final finalAnswer = RTCSessionDescription(_preferVP8(answer.sdp ?? ''), answer.type);
      await peer.setLocalDescription(finalAnswer);
      await _sendSignal({
        'type': 'answer',
        'restart': s['restart'] == true,
        'sdp': {'type': finalAnswer.type, 'sdp': finalAnswer.sdp},
      });
      await _flushCandidates();
    } else if (type == 'answer' && widget.callerSide) {
      final d = Map<String, dynamic>.from(s['sdp'] as Map);
      final rawSdp = d['sdp']?.toString() ?? '';
      await peer.setRemoteDescription(RTCSessionDescription(_preferVP8(rawSdp), d['type']?.toString()));
      await _flushCandidates();
    } else if (type == 'candidate' && s['candidate'] is Map) {
      final c = Map<String, dynamic>.from(s['candidate'] as Map);
      final desc = await peer.getRemoteDescription();
      if (desc == null) {
        queuedCandidates.add(c);
      } else {
        try {
          await peer.addCandidate(RTCIceCandidate(c['candidate']?.toString(), c['sdpMid']?.toString(), (c['sdpMLineIndex'] as num?)?.toInt()));
        } catch (_) {}
      }
    }
  }

  Future<void> _flushCandidates() async {
    final peer = pc;
    if (peer == null || queuedCandidates.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(queuedCandidates);
    queuedCandidates.clear();
    for (final c in batch) {
      try {
        await peer.addCandidate(RTCIceCandidate(c['candidate']?.toString(), c['sdpMid']?.toString(), (c['sdpMLineIndex'] as num?)?.toInt()));
      } catch (_) {}
    }
  }

  Future<void> _pollStatus() async {
    if (ending || _isDisposed) return;
    try {
      final next = await _api.callStatus(widget.booking.id);
      if (!mounted || _isDisposed) return;
      setState(() => status = next);
      if (const {'COMPLETED', 'CANCELLED', 'TERMINATED'}.contains(next.status) || next.endedAt != null) {
        await _peerEnded();
      }
    } catch (_) {}
  }

  void _beginReconnect() {
    if (reconnecting || ending || _isDisposed) return;
    reconnecting = true;
    reconnectSeconds = 30;
    if (mounted && !_isDisposed) setState(() => banner = 'Connection interrupted. Reconnecting… 30s');
    if (widget.callerSide) _sendOffer(restart: true).catchError((_) {});
    reconnectTimer?.cancel();
    reconnectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isDisposed || !reconnecting) {
        timer.cancel();
        return;
      }
      reconnectSeconds--;
      if (reconnectSeconds <= 0) {
        timer.cancel();
        reconnecting = false;
        if (mounted && !_isDisposed) setState(() => banner = 'Could not restore the call. You can end it safely.');
        return;
      }
      if (widget.callerSide && reconnectSeconds % 5 == 0) _sendOffer(restart: true).catchError((_) {});
      if (mounted && !_isDisposed) setState(() => banner = 'Connection interrupted. Reconnecting… ${reconnectSeconds}s');
    });
  }

  void _finishReconnect() {
    reconnectTimer?.cancel();
    if (!reconnecting) return;
    reconnecting = false;
    reconnectSeconds = 30;
    if (mounted) setState(() => banner = 'Connection restored.');
  }

  Future<void> _showCallSummaryDialog({
    required int finalSeconds,
    required double cost,
    required double remainingHold,
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
            SizedBox(width: 8),
            Text('Booking Call Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session with $peerName has concluded.', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Call Duration:', style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(_time(finalSeconds), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                  const Divider(height: 16),
                  if (widget.callerSide) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Amount Deducted:', style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(
                          cost > 0 ? '-₹${cost.toStringAsFixed(2)}' : '₹0.00',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            color: cost > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Remaining Hold Balance:', style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(
                          '₹${remainingHold.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Earned:', style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(
                          '₹${(cost * 0.8).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF059669)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _peerEnded() async {
    if (ending) return;
    ending = true;

    final elapsed = status?.elapsedSeconds ?? 0;
    final dur = widget.booking.durationMinutes > 0 ? widget.booking.durationMinutes : 15;
    final rate = widget.booking.holdAmount > 0 ? (widget.booking.holdAmount / dur) : 20.0;
    final cost = (elapsed / 60.0) * rate;
    final rem = (widget.booking.holdAmount - cost).clamp(0.0, double.infinity);

    signalPoll?.cancel();
    statusPoll?.cancel();
    reconnectTimer?.cancel();
    InCallVoiceSafetyService.instance.stopMonitoring();
    _privacyAlerts.stop();
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}
    unawaited(_cleanup());

    if (elapsed > 0 && mounted) {
      await _showCallSummaryDialog(
        finalSeconds: elapsed,
        cost: cost,
        remainingHold: rem,
      );
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _end() async {
    if (ending) return;
    ending = true;

    final elapsed = status?.elapsedSeconds ?? 0;
    final dur = widget.booking.durationMinutes > 0 ? widget.booking.durationMinutes : 15;
    final rate = widget.booking.holdAmount > 0 ? (widget.booking.holdAmount / dur) : 20.0;
    final cost = (elapsed / 60.0) * rate;
    final rem = (widget.booking.holdAmount - cost).clamp(0.0, double.infinity);

    signalPoll?.cancel();
    statusPoll?.cancel();
    reconnectTimer?.cancel();
    _privacyAlerts.stop();
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}

    try {
      _sendSignal({'type': 'call_ended', 'reason': 'USER_ENDED'});
      final api = context.read<AppController>().api;
      api.endBookingCall(widget.booking.id).catchError((_) {});
    } catch (_) {}

    unawaited(_cleanup());

    if (elapsed > 0 && mounted) {
      await _showCallSummaryDialog(
        finalSeconds: elapsed,
        cost: cost,
        remainingHold: rem,
      );
    }

    if (mounted) Navigator.pop(context);
  }

  Future<void> _cleanup() async {
    signalPoll?.cancel();
    signalPoll = null;
    statusPoll?.cancel();
    statusPoll = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _privacyAlerts.stop();

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
      for (final track in oldLocal?.getTracks() ?? <MediaStreamTrack>[]) {
        try { track.stop(); } catch (_) {}
      }
      for (final track in oldRemote?.getTracks() ?? <MediaStreamTrack>[]) {
        try { track.stop(); } catch (_) {}
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
    if (state == AppLifecycleState.detached && !ending) {
      CallPushService.instance.dismissOngoingCallNotification();
      _api.endBookingCall(widget.booking.id).catchError((_) {});
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (PipService.instance.isPipMode.value) {
        return;
      }
      if (isVideo && localStream != null) {
        for (final t in localStream!.getVideoTracks()) {
          try { t.enabled = false; } catch (_) {}
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (isVideo && localStream != null && camera) {
        for (final t in localStream!.getVideoTracks()) {
          try { t.enabled = true; } catch (_) {}
        }
      }
    }
  }

  @override
  void dispose() {
    CallPushService.instance.dismissOngoingCallNotification();
    PipService.instance.enableAutoPiP(false);
    _isDisposed = true;
    signalPoll?.cancel();
    signalPoll = null;
    statusPoll?.cancel();
    statusPoll = null;
    reconnectTimer?.cancel();
    reconnectTimer = null;
    _privacyAlerts.stop();
    WidgetsBinding.instance.removeObserver(this);
    _cleanup();
    if (registeredActiveSession) {
      try {
        context.read<AppController>().exitActiveSession();
      } catch (_) {}
    }
    try { localRenderer.srcObject = null; } catch (_) {}
    try { remoteRenderer.srcObject = null; } catch (_) {}
    localRenderer.dispose();
    remoteRenderer.dispose();
    gameSignal.dispose();
    chatController.dispose();
    super.dispose();
  }

  String _time(int seconds) => '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final elapsed = status?.elapsedSeconds ?? 0;
    return ValueListenableBuilder<bool>(
      valueListenable: PipService.instance.isPipMode,
      builder: (context, inPip, _) {
        if (inPip && isVideo) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: remoteRenderer.srcObject != null
                  ? FilteredVideoView(
                      filter: peerVideoFilter,
                      child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                    )
                  : const CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        return PopScope(
      canPop: ending,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          if (await confirm(context, 'End call?', 'Leaving will end this scheduled consultation.')) {
            if (mounted) await _end();
          }
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(peerName),
            Row(
              children: [
                Text(_time(elapsed), style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 6),
                Builder(builder: (_) {
                  final dur = widget.booking.durationMinutes > 0 ? widget.booking.durationMinutes : 15;
                  final rate = widget.booking.holdAmount > 0 ? (widget.booking.holdAmount / dur) : 20.0;
                  final cost = (elapsed / 60.0) * rate;
                  if (widget.callerSide) {
                    final rem = (widget.booking.holdAmount - cost).clamp(0.0, double.infinity);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECDD3), width: 0.8),
                      ),
                      child: Text(
                        '▼ ₹${rem.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE11D48),
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  } else {
                    final earn = cost * 0.8;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0), width: 0.8),
                      ),
                      child: Text(
                        '▲ +₹${earn.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF059669),
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  }
                }),
              ],
            ),
          ]),
          actions: [IconButton(onPressed: loading ? null : _showTools, icon: const Icon(Icons.auto_awesome))],
        ),
        body: loading
            ? const LoadingBody()
            : Column(children: [
                if (banner != null)
                  MaterialBanner(content: Text(banner!), actions: [TextButton(onPressed: () => setState(() => banner = null), child: const Text('Dismiss'))]),
                _buildSafetyDeterrenceStrip(),
                Expanded(child: _callBody(elapsed)),
              ]),
      ),
    );
      },
    );
  }

  Widget _buildSafetyDeterrenceStrip() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDBA74), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.shield_outlined, color: Color(0xFFEA580C), size: 13),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Calls monitored • Off-platform contact or bank/UPI sharing strictly prohibited',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9A3412),
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _callBody(int elapsed) => NudityGuardOverlay(
        isBlurred: isNudityBlurred,
        source: nuditySource == 'local' ? 'Your camera' : (nuditySource != null ? "$nuditySource's camera" : "$peerName's camera"),
        onDismiss: _dismissNudityBlur,
        onAllowNudity: () => _toggleNudityPermission(forcedVal: true),
        child: Stack(children: [
        Positioned.fill(
          child: isVideo
              ? FilteredVideoView(filter: peerVideoFilter, child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
              : Container(
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircleAvatar(radius: 70, child: Icon(Icons.person, size: 64)),
                    const SizedBox(height: 16),
                    Text(peerName, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    Text(_time(elapsed), style: Theme.of(context).textTheme.titleLarge),
                    Text('${status?.billableMinutes ?? 0} billable min • ₹${(status?.currentCost ?? 0).toStringAsFixed(2)}'),
                    if (peerVoiceFilter != AndroidVoiceFx.normal)
                      const Padding(padding: EdgeInsets.only(top: 8), child: Chip(label: Text('🎭 Peer voice privacy effect active'))),
                  ]),
                ),
        ),
        if (isVideo)
          Positioned(
            right: 16,
            top: 16,
            width: 110,
            height: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: FilteredVideoView(
                filter: activeVideoFilter,
                showBadge: false,
                child: RTCVideoView(localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 22,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _round(Icons.mic, mic, _toggleMic),
            if (isVideo) _round(Icons.videocam, camera, _toggleCamera),
            if (isVideo) _round(isNudityAllowed ? Icons.shield_rounded : Icons.shield_outlined, isNudityAllowed, _toggleNudityPermission),
            _round(Icons.volume_up, speaker, _toggleSpeaker),
            FloatingActionButton(backgroundColor: Colors.red, onPressed: _end, child: const Icon(Icons.call_end)),
          ]),
        ),
      ]),
    );

  Widget _round(IconData icon, bool active, VoidCallback onTap) => FloatingActionButton.small(
        heroTag: null,
        onPressed: onTap,
        backgroundColor: active ? Colors.white24 : Colors.redAccent,
        child: Icon(icon),
      );

  void _toggleMic() {
    mic = !mic;
    if (nativeVoiceFxActive) {
      for (final track in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        track.enabled = false;
      }
      if (mic) {
        voiceFx.start(activeVoiceFilter).catchError((_) {});
      } else {
        voiceFx.stopCapture().catchError((_) {});
      }
    } else {
      for (final track in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        track.enabled = mic;
      }
    }
    setState(() {});
  }

  void _toggleCamera() {
    camera = !camera;
    for (final track in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = camera;
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
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'In-Call Tools & Features',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Text(
                            'Enhance conversation, privacy & engagement',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 16),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      _buildLuxuryToolTile(
                        icon: Icons.chat_bubble_outline_rounded,
                        gradientColors: const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                        title: 'In-Call Chat',
                        subtitle: 'Exchange text messages quietly while talking',
                        onTap: () {
                          Navigator.pop(ctx);
                          _chat();
                        },
                      ),
                      _buildLuxuryToolTile(
                        icon: Icons.graphic_eq_rounded,
                        gradientColors: const [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                        title: 'Voice Privacy Effects',
                        subtitle: _voiceLabel(activeVoiceFilter),
                        onTap: () {
                          Navigator.pop(ctx);
                          _voiceFilters();
                        },
                      ),
                      if (isVideo)
                        _buildLuxuryToolTile(
                          icon: Icons.face_retouching_natural_rounded,
                          gradientColors: const [Color(0xFFEC4899), Color(0xFFA855F7)],
                          title: 'Video Masks & Privacy Filters',
                          subtitle: _videoLabel(activeVideoFilter),
                          onTap: () {
                            Navigator.pop(ctx);
                            _videoFilters();
                          },
                        ),
                      if (isVideo)
                        _buildLuxuryToolTile(
                          icon: isNudityAllowed ? Icons.shield_rounded : Icons.shield_outlined,
                          gradientColors: isNudityAllowed
                              ? const [Color(0xFFEC4899), Color(0xFFF43F5E)]
                              : const [Color(0xFF10B981), Color(0xFF059669)],
                          title: isNudityAllowed ? 'Nudity Mode is ON (Allowed)' : 'Mutual Nudity Consent',
                          subtitle: isNudityAllowed
                              ? 'Nudity allowed from both sides. Tap to disable.'
                              : 'Permit adult/nudity on both sides without blur',
                          onTap: () {
                            Navigator.pop(ctx);
                            _toggleNudityPermission();
                          },
                        ),
                      if (isVideo && !isNudityAllowed)
                        _buildLuxuryToolTile(
                          icon: Icons.shield_outlined,
                          gradientColors: const [Color(0xFFEF4444), Color(0xFFDC2626)],
                          title: 'Trigger Safety Blur',
                          subtitle: 'Instantly blur the video feed for privacy',
                          onTap: () {
                            Navigator.pop(ctx);
                            _triggerNudityBlur(source: 'peer');
                          },
                        ),
                      _buildLuxuryToolTile(
                        icon: Icons.lightbulb_outline_rounded,
                        gradientColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
                        title: 'Send an Icebreaker Topic',
                        subtitle: 'Spark fresh topics when conversation pauses',
                        onTap: () {
                          Navigator.pop(ctx);
                          _topic();
                        },
                      ),
                      _buildLuxuryToolTile(
                        icon: Icons.sports_esports_rounded,
                        gradientColors: const [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                        title: 'Open Mini Games',
                        subtitle: 'Tic-Tac-Toe • Would You Rather • 20 Questions',
                        onTap: () {
                          Navigator.pop(ctx);
                          _openGames();
                        },
                      ),
                      _buildLuxuryToolTile(
                        icon: Icons.report_problem_outlined,
                        gradientColors: const [Color(0xFF64748B), Color(0xFF475569)],
                        title: 'Report User',
                        subtitle: 'Flag harassment, abuse, or policy violations',
                        onTap: () {
                          Navigator.pop(ctx);
                          _report();
                        },
                      ),
                      _buildLuxuryToolTile(
                        icon: Icons.block_rounded,
                        gradientColors: const [Color(0xFFDC2626), Color(0xFF991B1B)],
                        title: 'Block User',
                        subtitle: 'Permanently block and prevent future calls',
                        onTap: () {
                          Navigator.pop(ctx);
                          _block();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLuxuryToolTile({
    required IconData icon,
    required List<Color> gradientColors,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradientColors),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
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
      if (mounted) showError(context, 'Voice effects are currently available on Android.');
      return;
    }
    if (selected != AndroidVoiceFx.normal && !peerVoiceFxCapable) {
      if (mounted) {
        showError(context, 'This voice effect requires the other participant to use the TalkStrangers Android app. Natural WebRTC audio will continue normally.');
      }
      return;
    }
    activeVoiceFilter = selected;
    nativeVoiceFxActive = selected != AndroidVoiceFx.normal;
    for (final track in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = mic && !nativeVoiceFxActive;
    }
    if (nativeVoiceFxActive && mic) {
      await voiceFx.start(selected);
    } else {
      await voiceFx.stopCapture();
    }
    await _sendSignal({'type': 'VOICE_FILTER_CHANGED', 'filter': selected});
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
    await _sendSignal({'type': 'VIDEO_FILTER_CHANGED', 'filter': selected});
    if (mounted) setState(() {});
  }

  Future<void> _chat() async {
    final controller = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> send() async {
          final text = controller.text.trim();
          if (text.isEmpty) return;
          controller.clear();
          final message = <String, dynamic>{
            'sender': widget.callerSide ? 'Anonymous User' : 'Listener',
            'text': text,
            'isMe': true,
            'timestamp': DateTime.now().toIso8601String(),
          };
          inCallMessages.add(message);
          await _sendSignal({'type': 'IN_CALL_CHAT', 'message': message});
          if (ctx.mounted) setLocal(() {});
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * .65,
            child: Column(children: [
              const Padding(padding: EdgeInsets.all(14), child: Text('In-call chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
              Expanded(child: ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: inCallMessages.length,
                itemBuilder: (_, i) {
                  final m = inCallMessages[i];
                  return ListTile(dense: true, title: Text('${m['sender'] ?? ''}'), subtitle: Text('${m['text'] ?? ''}'));
                },
              )),
              SafeArea(child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Expanded(child: TextField(controller: controller, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'Message…'))),
                  IconButton.filled(onPressed: send, icon: const Icon(Icons.send)),
                ]),
              )),
            ]),
          ),
        );
      }),
    );
    controller.dispose();
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
      await _sendSignal({'type': 'TOPIC_BROADCAST', 'topic': topic});
      if (mounted) setState(() => banner = '💡 Topic: $topic');
    }
  }

  Future<void> _openGames({bool fromPeer = false}) async {
    if (!mounted || gameSheetOpen) return;
    gameSheetOpen = true;
    if (!fromPeer) {
      await _sendSignal({
        'type': 'GAME_ACTION',
        'payload': {'game': 'TTT', 'action': 'OPEN', 'data': <String, dynamic>{}},
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
        send: (payload) => _sendSignal({'type': 'GAME_ACTION', 'payload': payload}),
      ),
    );
    gameSheetOpen = false;
  }

  Future<void> _report() async {
    final details = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report'),
        content: TextField(controller: details, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'What happened?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, details.text), child: const Text('Submit')),
        ],
      ),
    );
    details.dispose();
    if (text == null || text.trim().isEmpty) return;
    final target = widget.callerSide ? widget.booking.expertId : widget.booking.customerId;
    try {
      await context.read<AppController>().api.reportUser(target, sessionId: widget.booking.id, reason: 'BOOKING_CALL_REPORT', description: text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted.')));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _block() async {
    if (!await confirm(context, 'Block this person?', 'They will be hidden from future interactions where applicable.')) return;
    final target = widget.callerSide ? widget.booking.expertId : widget.booking.customerId;
    try {
      await context.read<AppController>().api.blockUser(target, targetName: peerName, targetRole: widget.callerSide ? 'EXPERT' : 'CUSTOMER');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User blocked.')));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

}
