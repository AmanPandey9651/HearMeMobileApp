import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../services/android_voice_fx.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/in_call_mini_games.dart';
import '../../widgets/video_privacy_filter.dart';

class SessionScreen extends StatefulWidget {
  final InstantSessionModel initialSession;
  final bool callerSide;
  const SessionScreen({super.key, required this.initialSession, required this.callerSide});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> with WidgetsBindingObserver {
  late InstantSessionModel session = widget.initialSession;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  final voiceFx = AndroidVoiceFx();
  final gameSignal = ValueNotifier<Map<String, dynamic>?>(null);
  final messageController = TextEditingController();

  RTCPeerConnection? pc;
  RTCDataChannel? voiceChannel;
  MediaStream? localStream;
  Timer? sessionPoll, signalPoll, heartbeat, clock, messagePoll, reconnectTimer;
  int seconds = 0, signalSince = 0, reconnectSeconds = 30, ringRemaining = 45;
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

  bool get isChat => session.type == 'CHAT';
  bool get isVideo => session.type == 'VIDEO_CALL';
  bool get isLive => const {'ACCEPTED', 'CONNECTING', 'CONNECTED', 'ACTIVE'}.contains(session.status);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    everLive = isLive;
    ringRemaining = _remainingRingSeconds();
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
    });
    _startPolling();
  }

  void _startPolling() {
    sessionPoll = Timer.periodic(const Duration(milliseconds: 800), (_) => _refreshSession());
    heartbeat = Timer.periodic(const Duration(seconds: 12), (_) {
      if (isLive) context.read<AppController>().api.sessionHeartbeat(session.id).catchError((_) {});
    });
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (isLive) {
        setState(() {
          everLive = true;
          seconds++;
        });
      } else if (!session.ended) {
        setState(() => ringRemaining = _remainingRingSeconds());
      }
    });
    messagePoll = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (isLive) _refreshMessages();
    });
    if (isChat) {
      signalPoll = Timer.periodic(const Duration(milliseconds: 650), (_) => _pollSignals());
    }
  }

  Future<void> _refreshSession() async {
    if (session.ended || ending) return;
    try {
      final next = await context.read<AppController>().api.session(session.id);
      if (!mounted) return;
      setState(() {
        session = next;
        if (isLive) everLive = true;
        if (!isLive && !next.ended) ringRemaining = _remainingRingSeconds();
      });
      if (next.ended) {
        await _cleanupMedia();
        if (!mounted) return;
        if (everLive || next.status == 'COMPLETED') {
          await _showEndSummary(next, peerEnded: true);
        } else {
          await _showRequestEnded(next);
        }
        if (mounted) Navigator.pop(context);
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
      pc = await createPeerConnection({'iceServers': ice});
      pc!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
          if (mounted) setState(() {});
        }
      };
      pc!.onIceCandidate = (candidate) {
        if (candidate.candidate != null) {
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
        'video': isVideo ? {'facingMode': 'user'} : false,
      });

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

      signalPoll ??= Timer.periodic(const Duration(milliseconds: 650), (_) => _pollSignals());
      await api.sendSignal(session.id, {
        'type': 'VOICE_FX_CAPABILITY',
        'supported': voiceFx.supported,
      }).catchError((_) {});
      if (widget.callerSide) await _sendOffer();
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
    await peer.setLocalDescription(offer);
    await context.read<AppController>().api.sendSignal(session.id, {
      'type': 'offer',
      'restart': restart,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  void _beginReconnect() {
    if (reconnecting || ending || session.ended) return;
    reconnecting = true;
    reconnectSeconds = 30;
    if (mounted) setState(() => banner = 'Connection interrupted. Reconnecting… 30s');
    if (widget.callerSide) _sendOffer(restart: true).catchError((_) {});
    reconnectTimer?.cancel();
    reconnectTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || !reconnecting) {
        t.cancel();
        return;
      }
      reconnectSeconds--;
      if (reconnectSeconds <= 0) {
        t.cancel();
        reconnecting = false;
        setState(() => banner = 'Could not restore the connection. You can end the session safely.');
        return;
      }
      if (widget.callerSide && reconnectSeconds % 5 == 0) {
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
    try {
      final list = await context.read<AppController>().api.signals(session.id, signalSince);
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
      if (mounted) setState(() => peerVideoFilter = filter);
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
    if (type == 'SAFETY_ALERT') {
      if (mounted) setState(() => banner = '⚠️ ${s['reason'] ?? 'Safety alert'}');
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
      await context.read<AppController>().api.sendSignal(session.id, {
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

  Future<void> _refreshMessages() async {
    try {
      final v = await context.read<AppController>().api.messages(session.id);
      if (mounted) setState(() => messages = v);
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;
    messageController.clear();
    try {
      final app = context.read<AppController>();
      final name = widget.callerSide ? 'Anonymous' : (app.user?.fullName ?? 'Listener');
      await app.api.sendMessage(session.id, text, senderName: name, senderRole: widget.callerSide ? 'USER' : 'LISTENER');
      await _refreshMessages();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  int _remainingRingSeconds() {
    final expires = DateTime.tryParse(session.expiresAt ?? '')?.toLocal();
    if (expires == null) return ringRemaining.clamp(0, 45).toInt();
    final left = expires.difference(DateTime.now()).inSeconds;
    return left.clamp(0, 45).toInt();
  }

  Future<void> _showRequestEnded(InstantSessionModel ended) async {
    if (!mounted) return;
    final message = switch (ended.status) {
      'REJECTED' => 'Listener is currently unavailable. No money was deducted.',
      'EXPIRED' => 'Listener did not answer within the ringing window. No money was deducted.',
      'CANCELLED' => 'Connection request was cancelled. No money was deducted.',
      _ => 'The connection request ended before the session started.',
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Session not connected'),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _finishFromPeer() async {
    ending = true;
    await _cleanupMedia();
    InstantSessionModel ended = session;
    try { ended = await context.read<AppController>().api.session(session.id); } catch (_) {}
    if (!mounted) return;
    setState(() => session = ended);
    if (everLive || ended.status == 'COMPLETED') {
      await _showEndSummary(ended, peerEnded: true);
    } else {
      await _showRequestEnded(ended);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _end() async {
    if (ending) return;
    ending = true;
    InstantSessionModel ended = session;
    try {
      await context.read<AppController>().api.sendSignal(session.id, {'type': 'call_ended', 'reason': 'USER_ENDED'});
      ended = await context.read<AppController>().api.endSession(session.id);
    } catch (_) {}
    await _cleanupMedia();
    if (!mounted) return;
    setState(() => session = ended);
    await _showEndSummary(ended);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _cancel() async {
    ending = true;
    try { await context.read<AppController>().api.cancelSession(session.id); } catch (_) {}
    await _cleanupMedia();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _cleanupMedia() async {
    sessionPoll?.cancel();
    signalPoll?.cancel();
    heartbeat?.cancel();
    messagePoll?.cancel();
    clock?.cancel();
    reconnectTimer?.cancel();
    await voiceFx.stop();
    try { await voiceChannel?.close(); } catch (_) {}
    voiceChannel = null;
    for (final t in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      t.stop();
    }
    await localStream?.dispose();
    localStream = null;
    await pc?.close();
    pc = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && !session.ended && !ending) {
      context.read<AppController>().api.endSession(session.id).catchError((_) => session);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupMedia();
    if (registeredActiveSession) {
      try { context.read<AppController>().exitActiveSession(); } catch (_) {}
    }
    localRenderer.dispose();
    remoteRenderer.dispose();
    messageController.dispose();
    gameSignal.dispose();
    super.dispose();
  }

  String _time(int value) => '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final peerName = widget.callerSide ? session.listenerName : session.callerNickname;
    return PopScope(
      canPop: session.ended,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await confirm(context, 'End session?', 'Leaving will end the active session.')) await _end();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(peerName),
            if (!isChat && isLive) Text(_time(seconds), style: Theme.of(context).textTheme.labelSmall),
          ]),
          actions: [IconButton(onPressed: _showTools, icon: const Icon(Icons.auto_awesome))],
        ),
        body: Column(
          children: [
            if (banner != null)
              MaterialBanner(
                content: Text(banner!),
                actions: [TextButton(onPressed: () => setState(() => banner = null), child: const Text('Dismiss'))],
              ),
            Expanded(
              child: !isLive && !session.ended
                  ? _ringingBody(peerName)
                  : isChat
                      ? _chatBody()
                      : _callBody(peerName),
            ),
            if (isChat && isLive && !session.ended) _chatInput(),
          ],
        ),
      ),
    );
  }

  Widget _ringingBody(String peerName) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text('Ringing $peerName…', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${ringRemaining}s remaining • Status: ${session.status}'),
            const SizedBox(height: 6),
            const Text('You are charged only after the listener accepts and the session starts.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: _cancel, child: const Text('Cancel request')),
          ]),
        ),
      );

  Widget _callBody(String peerName) {
    return Stack(
      children: [
        Positioned.fill(
          child: isVideo
              ? FilteredVideoView(
                  filter: peerVideoFilter,
                  child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                )
              : Container(
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    RemoteAvatar(url: widget.callerSide ? session.listenerAvatarUrl : session.callerAvatarUrl, radius: 70, fallback: peerName),
                    const SizedBox(height: 16),
                    Text(peerName, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    Text(_time(seconds), style: Theme.of(context).textTheme.titleLarge),
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
      ],
    );
  }

  Widget _round(IconData icon, bool active, VoidCallback tap) => FloatingActionButton.small(
        heroTag: null,
        onPressed: tap,
        backgroundColor: active ? Colors.white24 : Colors.redAccent,
        child: Icon(icon),
      );

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

  Widget _chatBody() => ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: messages.length,
        itemBuilder: (context, i) {
          final m = Map<String, dynamic>.from(messages[i]);
          final mine = (m['senderRole'] == 'USER') == widget.callerSide;
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: mine ? Theme.of(context).colorScheme.primaryContainer : Colors.white10, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m['senderName'] ?? ''}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                Text('${m['text'] ?? ''}'),
              ]),
            ),
          );
        },
      );

  Widget _chatInput() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Expanded(child: TextField(controller: messageController, onSubmitted: (_) => _sendMessage(), decoration: const InputDecoration(hintText: 'Type a message…'))),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _sendMessage, icon: const Icon(Icons.send)),
            IconButton(onPressed: _end, icon: const Icon(Icons.close, color: Colors.redAccent)),
          ]),
        ),
      );

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
          await app.api.sendMessage(session.id, text, senderName: widget.callerSide ? 'Anonymous' : (app.user?.fullName ?? 'Listener'), senderRole: widget.callerSide ? 'USER' : 'LISTENER');
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

  Future<void> _showEndSummary(InstantSessionModel ended, {bool peerEnded = false}) async {
    if (!mounted) return;
    final rating = ValueNotifier<int>(5);
    final comment = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(peerEnded ? 'Session ended' : 'Session complete'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Duration: ${ended.billableMinutes} billable min'),
            Text(widget.callerSide ? 'Charged: ₹${ended.grossAmount.toStringAsFixed(2)}' : 'Earned: ₹${ended.netListenerEarnings.toStringAsFixed(2)}'),
            if (widget.callerSide) ...[
              const SizedBox(height: 16),
              const Text('How was the conversation?', style: TextStyle(fontWeight: FontWeight.bold)),
              ValueListenableBuilder<int>(
                valueListenable: rating,
                builder: (_, v, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (i) => IconButton(onPressed: () => rating.value = i + 1, icon: Icon(i < v ? Icons.star : Icons.star_border)))),
              ),
              TextField(controller: comment, decoration: const InputDecoration(labelText: 'Optional comment')),
            ],
          ]),
        ),
        actions: [
          if (widget.callerSide)
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Skip')),
          FilledButton(
            onPressed: () async {
              if (widget.callerSide) {
                try {
                  await context.read<AppController>().api.createReview(sessionId: ended.id, rating: rating.value, comment: comment.text.trim());
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
