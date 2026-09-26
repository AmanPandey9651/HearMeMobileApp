import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import '../auth/login_screen.dart';
import '../session/session_screen.dart';
import 'schedule_consultation_screen.dart';

class ListenerDetailScreen extends StatefulWidget {
  final ListenerCardModel listener;
  final String? initialSessionType;
  const ListenerDetailScreen({super.key, required this.listener, this.initialSessionType});

  @override
  State<ListenerDetailScreen> createState() => _ListenerDetailScreenState();
}

class _ListenerDetailScreenState extends State<ListenerDetailScreen> {
  bool following = false;
  bool busy = false;
  bool loading = true;
  bool nudgeNotified = false;
  bool blockedByMe = false;
  bool blockedByListener = false;
  List<dynamic> reviews = [];
  Map<String, dynamic> expert = <String, dynamic>{};
  Timer? refreshTimer;

  String get expertUserId => '${expert['userId'] ?? widget.listener.userId ?? ''}';
  String get presence => '${expert['presence'] ?? widget.listener.presence}';
  String? get activeSessionType => (expert['activeSessionType'] ?? widget.listener.activeSessionType)?.toString();
  double _number(dynamic v, double fallback) => v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
  double get audioRate => _number(expert['ratePerMinute'], widget.listener.audioRate);
  double get videoRate => _number(expert['videoRatePerMinute'], widget.listener.videoRate);
  double get chatRate => _number(expert['chatRatePerMinute'], widget.listener.chatRate);

  @override
  void initState() {
    super.initState();
    _load();
    refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshPresence());
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<AppController>().api;
    try {
      final results = await Future.wait<dynamic>([
        api.expertDetail(widget.listener.id),
        api.followingStatus(widget.listener.id),
        api.expertReviews(widget.listener.id),
        api.nudgeStatus(widget.listener.id).catchError((_) => <String, dynamic>{}),
        api.blockedByMeIds(),
      ]);
      final detail = Map<String, dynamic>.from(results[0] as Map);
      final uid = '${detail['userId'] ?? widget.listener.userId ?? ''}';
      final blockedByThem = uid.isNotEmpty ? await api.amIBlockedBy(uid, force: true) : false;
      if (!mounted) return;
      setState(() {
        expert = detail;
        final f = Map<String, dynamic>.from(results[1] as Map);
        following = f['following'] == true;
        reviews = List<dynamic>.from(results[2] as List);
        final n = Map<String, dynamic>.from(results[3] as Map);
        nudgeNotified = n['notified'] == true;
        blockedByMe = uid.isNotEmpty && (results[4] as Set<String>).contains(uid);
        blockedByListener = blockedByThem;
        loading = false;
      });
      if (widget.initialSessionType != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _start(widget.initialSessionType!);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _refreshPresence() async {
    if (!mounted || busy) return;
    try {
      final detail = await context.read<AppController>().api.expertDetail(widget.listener.id);
      if (!mounted) return;
      setState(() => expert = detail);
    } catch (_) {}
  }

  String? _categorySlug() {
    final cats = expert['categories'];
    if (cats is List && cats.isNotEmpty && cats.first is Map) {
      final slug = (cats.first as Map)['slug']?.toString();
      if (slug?.isNotEmpty == true) return slug;
    }
    return null;
  }

  Future<void> _start(String type) async {
    if (context.read<AppController>().user == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign in to connect'),
          content: Text('Please log in or create an anonymous account to connect with ${widget.listener.displayName}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(initialTab: 0)));
              },
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Log In / Sign Up'),
            ),
          ],
        ),
      );
      return;
    }

    if (blockedByListener) {
      showError(context, 'This listener is currently unavailable for your account.');
      return;
    }
    final chatAvailable = expert['chatAvailable'] != false && widget.listener.chatAvailable;
    final audioAvailable = expert['audioAvailable'] != false && widget.listener.audioAvailable;
    final videoAvailable = expert['videoAvailable'] != false && widget.listener.videoAvailable;
    if (type == 'AUDIO_CALL' && !audioAvailable) {
      showError(context, '${widget.listener.displayName} is currently not accepting audio calls.');
      return;
    }
    if (type == 'VIDEO_CALL' && !videoAvailable) {
      showError(context, '${widget.listener.displayName} is currently not accepting video calls.');
      return;
    }
    if (type == 'CHAT' && !chatAvailable) {
      showError(context, '${widget.listener.displayName} is currently not accepting chat sessions.');
      return;
    }
    if (presence != 'ONLINE') {
      if (presence == 'OFFLINE') {
        if (nudgeNotified) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This listener has already been notified that you want to talk.')));
          return;
        }
        await _handleDirectNudge();
      } else {
        final busyType = (activeSessionType ?? '').toUpperCase();
        final detailMsg = busyType.contains('CHAT')
            ? 'Listener is currently busy in a chat session.'
            : busyType.contains('VIDEO')
                ? 'Listener is currently busy in a video call.'
                : 'Listener is currently busy in a voice call.';
        showError(context, detailMsg);
      }
      return;
    }

    setState(() => busy = true);
    try {
      final app = context.read<AppController>();
      final wallet = await app.api.wallet();
      final rate = type == 'VIDEO_CALL' ? videoRate : type == 'CHAT' ? chatRate : audioRate;
      if (wallet.totalBalance < rate) {
        throw Exception('Minimum ₹${rate.toStringAsFixed(0)} (1 minute) is required. Recharge your wallet before starting.');
      }
      final session = await app.api.requestSession(widget.listener.id, type, categorySlug: _categorySlug());
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SessionScreen(initialSession: session, callerSide: true)));
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _toggleFollow() async {
    if (context.read<AppController>().user == null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(initialTab: 0)));
      return;
    }
    try {
      if (following) {
        await context.read<AppController>().api.unfollow(widget.listener.id);
      } else {
        await context.read<AppController>().api.follow(widget.listener.id);
      }
      if (mounted) setState(() => following = !following);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _handleDirectNudge() async {
    if (nudgeNotified) return;
    setState(() => busy = true);
    try {
      final result = await context.read<AppController>().api.nudge(widget.listener.id);
      if (mounted) {
        final success = result['success'] != false;
        if (success) {
          setState(() => nudgeNotified = true);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  success ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result['message']?.toString() ??
                        (success
                            ? 'Notification sent! ${widget.listener.displayName} has been alerted.'
                            : 'Could not notify listener.'),
                  ),
                ),
              ],
            ),
            backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _unblock() async {
    try {
      await context.read<AppController>().api.unblockUser(widget.listener.id);
      if (mounted) {
        setState(() => blockedByMe = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listener unblocked.')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  List<String> _names(dynamic list) {
    if (list is! List) return const [];
    return list.map((e) {
      if (e is Map) return '${e['name'] ?? e['slug'] ?? e['code'] ?? ''}';
      return '$e';
    }).where((e) => e.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.listener;
    final displayName = '${expert['name'] ?? l.displayName}';
    final title = '${expert['professionalTitle'] ?? l.professionalTitle}';
    final bio = '${expert['bio'] ?? l.bio}';
    final avatar = expert['avatarUrl']?.toString() ?? l.avatarUrl;
    final rating = _number(expert['ratingAvg'], l.rating);
    final reviewCount = (expert['reviewCount'] as num?)?.toInt() ?? l.reviewCount;
    final sessions = (expert['totalConsultations'] as num?)?.toInt() ?? l.totalConsultations;
    final categories = _names(expert['categories']);
    final languages = _names(expert['languages']);
    final skills = _names(expert['skills']);
    final experience = (expert['experienceYears'] as num?)?.toInt();
    final response = (expert['responseTimeMinutes'] as num?)?.toInt();
    final gender = expert['gender']?.toString() ?? l.gender;
    final hobbies = expert['hobbies']?.toString() ?? l.hobbies;
    final consultationType = '${expert['consultationType'] ?? 'BOTH'}';
    final chatAvailable = expert['chatAvailable'] != false && widget.listener.chatAvailable;
    final audioAvailable = expert['audioAvailable'] != false && widget.listener.audioAvailable;
    final videoAvailable = expert['videoAvailable'] != false && widget.listener.videoAvailable;

    final isOnline = presence == 'ONLINE';
    final isBusy = presence == 'BUSY_IN_CALL' || presence == 'BUSY';
    final busyType = (activeSessionType ?? '').toUpperCase();
    final Color statusColor = isOnline
        ? const Color(0xFF10B981)
        : isBusy
            ? (busyType.contains('CHAT')
                ? const Color(0xFF3B82F6)
                : busyType.contains('VIDEO')
                    ? const Color(0xFF8B5CF6)
                    : const Color(0xFFF59E0B))
            : const Color(0xFF94A3B8);
    final String statusLabel = isOnline
        ? 'Live Online'
        : isBusy
            ? (busyType.contains('CHAT')
                ? 'Busy in Chat'
                : busyType.contains('VIDEO')
                    ? 'Busy in Video Call'
                    : 'Busy in Audio Call')
            : 'Offline';
    final IconData statusIcon = isOnline
        ? Icons.circle
        : isBusy
            ? (busyType.contains('CHAT')
                ? Icons.chat
                : busyType.contains('VIDEO')
                    ? Icons.videocam
                    : Icons.phone_in_talk)
            : Icons.schedule;

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
        actions: [
          IconButton(
            tooltip: following ? 'Remove favourite' : 'Add favourite',
            onPressed: blockedByListener ? null : _toggleFollow,
            icon: Icon(following ? Icons.favorite : Icons.favorite_border, color: following ? Colors.redAccent : null),
          ),
          PopupMenuButton<String>(
            onSelected: _safety,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'report', child: Text('Report listener')),
              if (!blockedByMe) const PopupMenuItem(value: 'block', child: Text('Block listener')),
              if (blockedByMe) const PopupMenuItem(value: 'unblock', child: Text('Unblock listener')),
            ],
          ),
        ],
      ),
      body: loading
          ? const LoadingBody()
          : blockedByListener
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_off_outlined, size: 64),
                        const SizedBox(height: 16),
                        Text('Listener unavailable', style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 10),
                        const Text('This listener profile is currently unavailable for instant sessions or consultations.', textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Browse other listeners')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    if (blockedByMe)
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: ListTile(
                          leading: const Icon(Icons.block),
                          title: const Text('You blocked this listener'),
                          subtitle: const Text('Unblock them anytime to restore normal interactions.'),
                          trailing: TextButton(onPressed: _unblock, child: const Text('Unblock')),
                        ),
                      ),
                    Center(child: RemoteAvatar(url: avatar, radius: 52, fallback: displayName)),
                    const SizedBox(height: 12),
                    Text(displayName, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                    Text(title, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Center(child: Text('✓ Verified listener  •  ⭐ ${rating.toStringAsFixed(1)} ($reviewCount reviews)')),
                    Center(child: Text('$sessions conversations${experience != null ? ' • $experience yrs experience' : ''}')),
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 15, color: statusColor),
                            const SizedBox(width: 6),
                            Text(
                              statusLabel.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (presence == 'OFFLINE' && nudgeNotified) ...[
                      const SizedBox(height: 6),
                      const Center(child: Chip(avatar: Icon(Icons.notifications_active, size: 18), label: Text('Listener notified'))),
                    ],
                    const SizedBox(height: 16),
                    if (bio.isNotEmpty) ...[
                      Text('About me', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(bio),
                    ],
                    if (categories.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Text('Topics I support: ${categories.join(', ')}')),
                    if (skills.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Skills: ${skills.join(', ')}')),
                    if (languages.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Languages: ${languages.join(', ')}')),
                    if ((gender?.isNotEmpty ?? false) || (hobbies?.isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text([
                          if (gender?.isNotEmpty == true) 'Gender: $gender',
                          if (hobbies?.isNotEmpty == true) 'Interests: $hobbies',
                        ].join(' • ')),
                      ),
                    if (response != null && response > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Typical response time: about $response minutes')),
                    const SizedBox(height: 18),

                    // Modality Availability Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _detailModalityChip('Voice Call', audioAvailable, Icons.call, const Color(0xFF34D399)),
                        _detailModalityChip('Video Call', videoAvailable, Icons.videocam, const Color(0xFFC084FC)),
                        _detailModalityChip('Private Chat', chatAvailable, Icons.chat_bubble_outline, const Color(0xFF60A5FA)),
                      ],
                    ),
                    const SizedBox(height: 14),

                    if (consultationType != 'VIDEO')
                      FilledButton.icon(
                        onPressed: (busy || !audioAvailable || isBusy) ? null : () => _start('AUDIO_CALL'),
                        icon: const Icon(Icons.call),
                        label: Text(!audioAvailable
                            ? 'Audio call (Not accepting calls)'
                            : isBusy
                                ? 'Audio call (Currently busy)'
                                : 'Audio call • ₹${audioRate.toStringAsFixed(0)}/min'),
                      ),
                    if (consultationType != 'VIDEO') const SizedBox(height: 9),
                    if (consultationType != 'AUDIO')
                      FilledButton.tonalIcon(
                        onPressed: (busy || !videoAvailable || isBusy) ? null : () => _start('VIDEO_CALL'),
                        icon: const Icon(Icons.videocam),
                        label: Text(!videoAvailable
                            ? 'Video call (Not accepting calls)'
                            : isBusy
                                ? 'Video call (Currently busy)'
                                : 'Video call • ₹${videoRate.toStringAsFixed(0)}/min'),
                      ),
                    if (consultationType != 'AUDIO') const SizedBox(height: 9),
                    OutlinedButton.icon(
                      onPressed: (busy || !chatAvailable || isBusy) ? null : () => _start('CHAT'),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(!chatAvailable
                          ? 'Private chat (Not accepting chats)'
                          : isBusy
                              ? 'Private chat (Currently busy)'
                              : 'Private chat • ₹${chatRate.toStringAsFixed(0)}/min'),
                    ),
                    const SizedBox(height: 9),
                    OutlinedButton.icon(
                      onPressed: busy || blockedByMe
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ScheduleConsultationScreen(
                                    listener: widget.listener.copyWith(userId: expertUserId.isEmpty ? widget.listener.userId : expertUserId, presence: presence),
                                    audioRate: audioRate,
                                    videoRate: videoRate,
                                  ),
                                ),
                              ),
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Schedule a consultation'),
                    ),
                    if (presence == 'OFFLINE') ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.notifications_active_rounded, color: Color(0xFFD97706), size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Listener is currently away',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: Color(0xFF78350F),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Want to connect? Send a quick alert to request $displayName to come online.',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF92400E),
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: nudgeNotified ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: nudgeNotified || busy ? null : _handleDirectNudge,
                                icon: Icon(
                                  nudgeNotified ? Icons.check_circle_rounded : Icons.notifications_active_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  nudgeNotified ? 'Request Already Sent' : 'Message Listener to Come Online',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(13),
                        child: Row(
                          children: [
                            Icon(Icons.shield_outlined),
                            SizedBox(width: 10),
                            Expanded(child: Text('Your caller identity stays anonymous. Calls, chat and video are protected by the platform safety controls.')),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('Caller reviews', style: Theme.of(context).textTheme.titleLarge),
                    if (reviews.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No reviews yet.'))
                    else
                      ...reviews.take(20).map((r) {
                        final m = Map<String, dynamic>.from(r);
                        final reply = m['expertResponse'] ?? m['response'];
                        return Card(
                          child: ListTile(
                            title: Text('⭐ ${m['rating'] ?? ''} • ${m['customerName'] ?? 'Anonymous'}'),
                            subtitle: Text('${m['comment'] ?? ''}${reply != null && '$reply'.isNotEmpty ? '\nListener response: $reply' : ''}'),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }

  Future<void> _safety(String action) async {
    final name = '${expert['name'] ?? widget.listener.displayName}';
    final targetUserId = expertUserId;
    if (action == 'unblock') {
      await _unblock();
      return;
    }
    if (action == 'block') {
      if (await confirm(context, 'Block $name?', 'They will be hidden from your discovery and interactions.')) {
        try {
          await context.read<AppController>().api.blockUser(widget.listener.id, targetName: name, targetRole: 'EXPERT');
          if (mounted) setState(() => blockedByMe = true);
        } catch (e) {
          if (mounted) showError(context, e);
        }
      }
      return;
    }

    if (targetUserId.isEmpty) {
      showError(context, 'Could not resolve this listener account for reporting.');
      return;
    }
    final c = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report listener'),
        content: TextField(controller: c, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'What happened?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Submit')),
        ],
      ),
    );
    c.dispose();
    if (submitted?.isNotEmpty != true) return;
    try {
      await context.read<AppController>().api.reportUser(targetUserId, reason: 'USER_REPORT', description: submitted);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted.')));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _detailModalityChip(String label, bool isAvailable, IconData icon, Color activeColor) {
    final color = isAvailable ? activeColor : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
      decoration: BoxDecoration(
        color: isAvailable ? activeColor.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAvailable ? activeColor.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            '$label ${isAvailable ? '✓' : '✕'}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
