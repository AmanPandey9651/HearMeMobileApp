import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../services/android_voice_fx.dart';
import '../../services/call_recording_service.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/in_call_mini_games.dart';
import '../../widgets/video_privacy_filter.dart';

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
  bool _recordingStarted = false;

  bool get isVideo => widget.booking.consultationType == 'VIDEO';
  String get peerName => widget.callerSide ? widget.booking.expertName : (widget.booking.customerName.isEmpty ? 'Caller' : widget.booking.customerName);

  Future<void> _startRecordingIfEligible() async {
    if (_recordingStarted || ending) return;

    try {
      final app = context.read<AppController>();
      await app.refreshGovernance();
      final gov = app.recordingGovernance;

      final audioAllowed = gov?.audioRecordingEnabled ?? true;
      final videoAllowed = gov?.videoRecordingEnabled ?? true;

      if (isVideo && !videoAllowed) {
        debugPrint('[RecordingGovernance] Mobile Booking: Video recording disabled by admin policy.');
        return;
      }
      if (!isVideo && !audioAllowed) {
        debugPrint('[RecordingGovernance] Mobile Booking: Audio recording disabled by admin policy.');
        return;
      }

      _recordingStarted = true;

      if (isVideo) {
        final remoteVid = remoteStream?.getVideoTracks().firstOrNull;
        final localVid = localStream?.getVideoTracks().firstOrNull;
        final targetTrack = remoteVid ?? localVid;
        if (targetTrack != null) {
          await CallRecordingService.startVideoRecording(widget.booking.id, targetTrack);
        }
        await CallRecordingService.startAudioRecording(widget.booking.id);
        debugPrint('[RecordingGovernance] Mobile Booking: Started video call recording for ${widget.booking.id}');
      } else {
        await CallRecordingService.startAudioRecording(widget.booking.id);
        debugPrint('[RecordingGovernance] Mobile Booking: Started audio call recording for ${widget.booking.id}');
      }
    } catch (e) {
      debugPrint('[RecordingGovernance] Mobile Booking: Error starting call recording: $e');
    }
  }

  Future<void> _stopAndUploadRecording() async {
    if (!_recordingStarted) return;
    _recordingStarted = false;

    try {
      final recordedFile = await CallRecordingService.stopAndCollectRecording();
      if (recordedFile != null && await recordedFile.exists() && await recordedFile.length() > 1000) {
        debugPrint('[Recording] Uploading booking call recording (${await recordedFile.length()} bytes) for ${widget.booking.id}...');
        await context.read<AppController>().api.uploadRecording(widget.booking.id, recordedFile);
        debugPrint('[Recording] Booking call recording successfully uploaded to backend!');
      }
    } catch (e) {
      debugPrint('[Recording] Failed to upload booking recording: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    localRenderer.initialize();
    remoteRenderer.initialize();
    voiceFx.onFrame = (frame) {
      final dc = voiceChannel;
      if (dc != null && mic) dc.send(RTCDataChannelMessage.fromBinary(frame)).catchError((_) {});
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppController>().enterActiveSession();
      registeredActiveSession = true;
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    try {
      final api = context.read<AppController>().api;
      token = await api.callToken(widget.booking.id);
      status = await api.callStatus(widget.booking.id);
      await _joinMedia();
      signalPoll = Timer.periodic(const Duration(milliseconds: 650), (_) => _pollSignals());
      statusPoll = Timer.periodic(const Duration(seconds: 1), (_) => _pollStatus());
      if (mounted) setState(() => loading = false);
      _privacyAlerts.start(_onPrivacyAlert);
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  void _onPrivacyAlert(String type) {
    context.read<AppController>().api
        .securityAlert(widget.booking.id, type, 'Mobile screenshot/screen-recording attempt detected')
        .catchError((_) {});
    if (mounted) {
      setState(() => banner = '🚫 Screenshot / recording is prohibited and has been reported.');
    }
  }

  Future<void> _joinMedia() async {
    final perms = <Permission>[Permission.microphone, if (isVideo) Permission.camera];
    final result = await perms.request();
    if (result.values.any((v) => !v.isGranted)) {
      throw Exception('Microphone${isVideo ? ' and camera' : ''} permission is required.');
    }

    final api = context.read<AppController>().api;
    final ice = await api.iceServers();
    pc = await createPeerConnection({'iceServers': ice});

    pc!.onTrack = (event) async {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams.first;
      } else {
        remoteStream ??= await createLocalMediaStream('booking_remote_stream');
        if (!remoteStream!.getTracks().any((t) => t.id == event.track.id)) {
          remoteStream!.addTrack(event.track);
        }
      }
      if (remoteRenderer.srcObject != remoteStream) {
        remoteRenderer.srcObject = remoteStream;
      }
      _startRecordingIfEligible();
      if (mounted) setState(() {});
    };
    pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      api.sendSignal(widget.booking.id, {
        'type': 'candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }
      }).catchError((_) {});
    };
    pc!.onDataChannel = _attachVoiceChannel;
    pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _finishReconnect();
        _startRecordingIfEligible();
        if (!connectedRecorded) {
          connectedRecorded = true;
          api.recordCallConnected(widget.booking.id).catchError((_) {});
        }
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected || state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _beginReconnect();
      }
    };

    // Keep a normal WebRTC audio track for Android <-> web/iOS compatibility.
    // The custom native PCM path is enabled only for a non-natural effect after
    // both mobile peers advertise support.
    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': isVideo ? {'facingMode': 'user'} : false});

    if (localStream != null) {
      localRenderer.srcObject = localStream;
      for (final track in localStream!.getTracks()) {
        await pc!.addTrack(track, localStream!);
      }
    }

    if (widget.callerSide) {
      final init = RTCDataChannelInit()
        ..ordered = false
        ..maxRetransmits = 0;
      _attachVoiceChannel(await pc!.createDataChannel('voice_fx', init));
    }
    await api.sendSignal(widget.booking.id, {
      'type': 'VOICE_FX_CAPABILITY',
      'supported': voiceFx.supported,
    }).catchError((_) {});
    if (widget.callerSide) await _sendOffer();
  }

  void _attachVoiceChannel(RTCDataChannel channel) {
    voiceChannel = channel;
    channel.onMessage = (data) {
      if (data.isBinary && voiceFx.supported) voiceFx.play(data.binary).catchError((_) {});
    };
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
    await peer.setLocalDescription(offer);
    await context.read<AppController>().api.sendSignal(widget.booking.id, {
      'type': 'offer',
      'restart': restart,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  Future<void> _pollSignals() async {
    if (ending) return;
    try {
      final signals = await context.read<AppController>().api.signals(widget.booking.id, signalSince);
      for (final raw in signals) {
        final s = Map<String, dynamic>.from(raw as Map);
        final ts = (s['timestamp'] as num?)?.toInt() ?? signalSince;
        if (ts > signalSince) signalSince = ts;
        await _processSignal(s);
      }
    } catch (_) {}
  }

  Future<void> _processSignal(Map<String, dynamic> s) async {
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
    if (type == 'VOICE_FX_CAPABILITY') {
      if (mounted) setState(() => peerVoiceFxCapable = s['supported'] == true);
      return;
    }
    if (type == 'VOICE_FILTER_CHANGED') {
      final filter = '${s['filter'] ?? AndroidVoiceFx.normal}';
      if (mounted) setState(() {
        peerVoiceFilter = filter;
        banner = filter == AndroidVoiceFx.normal ? 'Peer returned to natural voice.' : 'Peer enabled a voice privacy effect.';
      });
      return;
    }

    final peer = pc;
    if (peer == null) return;
    if (type == 'offer' && !widget.callerSide) {
      final d = Map<String, dynamic>.from(s['sdp'] as Map);
      await peer.setRemoteDescription(RTCSessionDescription(d['sdp']?.toString(), d['type']?.toString()));
      await _flushCandidates();
      final answer = await peer.createAnswer();
      await peer.setLocalDescription(answer);
      await context.read<AppController>().api.sendSignal(widget.booking.id, {
        'type': 'answer',
        'restart': s['restart'] == true,
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
    } else if (type == 'answer' && widget.callerSide) {
      final d = Map<String, dynamic>.from(s['sdp'] as Map);
      await peer.setRemoteDescription(RTCSessionDescription(d['sdp']?.toString(), d['type']?.toString()));
      await _flushCandidates();
    } else if (type == 'candidate' && s['candidate'] is Map) {
      final c = Map<String, dynamic>.from(s['candidate'] as Map);
      final desc = await peer.getRemoteDescription();
      if (desc == null) {
        queuedCandidates.add(c);
      } else {
        await peer.addCandidate(RTCIceCandidate(c['candidate']?.toString(), c['sdpMid']?.toString(), (c['sdpMLineIndex'] as num?)?.toInt()));
      }
    }
  }

  Future<void> _flushCandidates() async {
    final peer = pc;
    if (peer == null) return;
    for (final c in List<Map<String, dynamic>>.from(queuedCandidates)) {
      await peer.addCandidate(RTCIceCandidate(c['candidate']?.toString(), c['sdpMid']?.toString(), (c['sdpMLineIndex'] as num?)?.toInt()));
    }
    queuedCandidates.clear();
  }

  Future<void> _pollStatus() async {
    if (ending) return;
    try {
      final next = await context.read<AppController>().api.callStatus(widget.booking.id);
      if (!mounted) return;
      setState(() => status = next);
      if (const {'COMPLETED', 'CANCELLED', 'TERMINATED'}.contains(next.status) || next.endedAt != null) {
        await _peerEnded();
      }
    } catch (_) {}
  }

  void _beginReconnect() {
    if (reconnecting || ending) return;
    reconnecting = true;
    reconnectSeconds = 30;
    if (mounted) setState(() => banner = 'Connection interrupted. Reconnecting… 30s');
    if (widget.callerSide) _sendOffer(restart: true).catchError((_) {});
    reconnectTimer?.cancel();
    reconnectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !reconnecting) {
        timer.cancel();
        return;
      }
      reconnectSeconds--;
      if (reconnectSeconds <= 0) {
        timer.cancel();
        reconnecting = false;
        setState(() => banner = 'Could not restore the call. You can end it safely.');
        return;
      }
      if (widget.callerSide && reconnectSeconds % 5 == 0) _sendOffer(restart: true).catchError((_) {});
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

  Future<void> _peerEnded() async {
    if (ending) return;
    ending = true;
    await _cleanup();
    if (!mounted) return;
    await _summary(peerEnded: true);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _end() async {
    if (ending) return;
    ending = true;
    try {
      await context.read<AppController>().api.sendSignal(widget.booking.id, {'type': 'call_ended', 'reason': 'USER_ENDED'});
    } catch (_) {}
    try {
      await context.read<AppController>().api.endBookingCall(widget.booking.id);
    } catch (_) {}
    try {
      status = await context.read<AppController>().api.callStatus(widget.booking.id);
    } catch (_) {}
    await _cleanup();
    if (!mounted) return;
    await _summary();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _cleanup() async {
    await _stopAndUploadRecording();
    signalPoll?.cancel();
    statusPoll?.cancel();
    reconnectTimer?.cancel();
    _privacyAlerts.stop();
    await voiceFx.stop();
    try {
      await voiceChannel?.close();
    } catch (_) {}
    voiceChannel = null;
    for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    await localStream?.dispose();
    localStream = null;
    for (final track in remoteStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    await remoteStream?.dispose();
    remoteStream = null;
    await pc?.close();
    pc = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && !ending) {
      context.read<AppController>().api.endBookingCall(widget.booking.id).catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanup();
    if (registeredActiveSession) {
      try {
        context.read<AppController>().exitActiveSession();
      } catch (_) {}
    }
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
            Text(_time(elapsed), style: Theme.of(context).textTheme.labelSmall),
          ]),
          actions: [IconButton(onPressed: loading ? null : _showTools, icon: const Icon(Icons.auto_awesome))],
        ),
        body: loading
            ? const LoadingBody()
            : Column(children: [
                if (banner != null)
                  MaterialBanner(content: Text(banner!), actions: [TextButton(onPressed: () => setState(() => banner = null), child: const Text('Dismiss'))]),
                Expanded(child: _callBody(elapsed)),
              ]),
      ),
    );
  }

  Widget _callBody(int elapsed) => Stack(children: [
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
            _round(Icons.volume_up, speaker, _toggleSpeaker),
            FloatingActionButton(backgroundColor: Colors.red, onPressed: _end, child: const Icon(Icons.call_end)),
          ]),
        ),
      ]);

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
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.chat_bubble_outline), title: const Text('In-call chat'), onTap: () { Navigator.pop(ctx); _chat(); }),
          ListTile(leading: const Icon(Icons.graphic_eq), title: const Text('Voice privacy effects'), subtitle: Text(_voiceLabel(activeVoiceFilter)), onTap: () { Navigator.pop(ctx); _voiceFilters(); }),
          if (isVideo)
            ListTile(leading: const Icon(Icons.masks), title: const Text('Video masks & privacy filters'), subtitle: Text(_videoLabel(activeVideoFilter)), onTap: () { Navigator.pop(ctx); _videoFilters(); }),
          ListTile(leading: const Icon(Icons.lightbulb_outline), title: const Text('Send an icebreaker topic'), onTap: () { Navigator.pop(ctx); _topic(); }),
          ListTile(leading: const Icon(Icons.sports_esports), title: const Text('Open mini games'), subtitle: const Text('Tic-Tac-Toe • Would You Rather • 20 Questions'), onTap: () { Navigator.pop(ctx); _openGames(); }),
          ListTile(leading: const Icon(Icons.report_outlined), title: const Text('Report the other person'), onTap: () { Navigator.pop(ctx); _report(); }),
          ListTile(leading: const Icon(Icons.block), title: const Text('Block the other person'), onTap: () { Navigator.pop(ctx); _block(); }),
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
    await context.read<AppController>().api.sendSignal(widget.booking.id, {'type': 'VOICE_FILTER_CHANGED', 'filter': selected});
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
    await context.read<AppController>().api.sendSignal(widget.booking.id, {'type': 'VIDEO_FILTER_CHANGED', 'filter': selected});
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
          await context.read<AppController>().api.sendSignal(widget.booking.id, {'type': 'IN_CALL_CHAT', 'message': message});
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
      await context.read<AppController>().api.sendSignal(widget.booking.id, {'type': 'TOPIC_BROADCAST', 'topic': topic});
      if (mounted) setState(() => banner = '💡 Topic: $topic');
    }
  }

  Future<void> _openGames({bool fromPeer = false}) async {
    if (!mounted || gameSheetOpen) return;
    gameSheetOpen = true;
    if (!fromPeer) {
      await context.read<AppController>().api.sendSignal(widget.booking.id, {
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
        send: (payload) => context.read<AppController>().api.sendSignal(widget.booking.id, {'type': 'GAME_ACTION', 'payload': payload}),
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

  Future<void> _summary({bool peerEnded = false}) async {
    if (!mounted) return;
    final rating = ValueNotifier<int>(5);
    final comment = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(peerEnded ? 'Call ended' : 'Consultation complete'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Duration: ${status?.billableMinutes ?? 0} billable min'),
          if (widget.callerSide) Text('Charged: ₹${(status?.currentCost ?? widget.booking.capturedAmount).toStringAsFixed(2)}'),
          if (widget.callerSide) ...[
            const SizedBox(height: 14),
            const Text('Rate this consultation', style: TextStyle(fontWeight: FontWeight.bold)),
            ValueListenableBuilder<int>(
              valueListenable: rating,
              builder: (_, v, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) => IconButton(onPressed: () => rating.value = i + 1, icon: Icon(i < v ? Icons.star : Icons.star_border)))),
            ),
            TextField(controller: comment, decoration: const InputDecoration(labelText: 'Optional comment')),
          ],
        ]),
        actions: [
          if (widget.callerSide) TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Skip')),
          FilledButton(
            onPressed: () async {
              if (widget.callerSide) {
                try {
                  await context.read<AppController>().api.createReview(bookingId: widget.booking.id, rating: rating.value, comment: comment.text.trim());
                } catch (_) {}
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(widget.callerSide ? 'Submit' : 'Done'),
          ),
        ],
      ),
    );
    rating.dispose();
    comment.dispose();
  }
}
