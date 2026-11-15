import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/active_call_manager.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import '../auth/login_screen.dart';
import '../common/direct_chat_screen.dart';

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
  bool _initialSessionTriggered = false;

  String get expertUserId => '${expert['userId'] ?? widget.listener.userId ?? ''}';
  String get presence => '${expert['presence'] ?? widget.listener.presence}';
  String? get activeSessionType => (expert['activeSessionType'] ?? widget.listener.activeSessionType)?.toString();
  double _number(dynamic v, double fallback) => v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
  double get audioRate => _number(expert['ratePerMinute'], widget.listener.audioRate);
  double get videoRate => _number(expert['videoRatePerMinute'], widget.listener.videoRate);
  double get chatRate => _number(expert['chatRatePerMinute'], widget.listener.chatRate);
  String get country => (expert['country'] ?? widget.listener.country ?? 'India').toString().trim();
  bool get isInternational => country.isNotEmpty && country.toLowerCase() != 'india' && country.toLowerCase() != 'in';

  bool get isCallerIntl {
    final callerCountry = (context.read<AppController>().user?.country ?? '').trim().toLowerCase();
    return (callerCountry.isNotEmpty && callerCountry != 'india' && callerCountry != 'in') ||
        (DateTime.now().timeZoneOffset.inMinutes != 330);
  }

  bool get showDualRate => isInternational || isCallerIntl;

  double get effectiveAudioRate {
    final base = audioRate;
    if (!isCallerIntl) return base;
    if (!isInternational) {
      return (base * 2.0 < 25.0) ? 25.0 : base * 2.0;
    } else {
      return base < 60.0 ? 60.0 : base;
    }
  }

  double get effectiveVideoRate {
    final base = videoRate;
    if (!isCallerIntl) return base;
    if (!isInternational) {
      return (base * 2.0 < 40.0) ? 40.0 : base * 2.0;
    } else {
      return base < 90.0 ? 90.0 : base;
    }
  }

  double get effectiveChatRate {
    final base = chatRate;
    if (!isCallerIntl) return base;
    if (!isInternational) {
      return (base * 2.0 < 15.0) ? 15.0 : base * 2.0;
    } else {
      return base < 35.0 ? 35.0 : base;
    }
  }

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
    final app = context.read<AppController>();
    final api = app.api;
    final isLoggedIn = app.user != null;
    try {
      final results = await Future.wait<dynamic>([
        api.expertDetail(widget.listener.id),
        isLoggedIn ? api.followingStatus(widget.listener.id) : Future.value(<String, dynamic>{'following': false}),
        api.expertReviews(widget.listener.id),
        isLoggedIn ? api.nudgeStatus(widget.listener.id).catchError((_) => <String, dynamic>{}) : Future.value(<String, dynamic>{'notified': false}),
        isLoggedIn ? api.blockedByMeIds() : Future.value(<String>{}),
      ]);
      final detail = Map<String, dynamic>.from(results[0] as Map);
      final uid = '${detail['userId'] ?? widget.listener.userId ?? ''}';
      final blockedByThem = (isLoggedIn && uid.isNotEmpty) ? await api.amIBlockedBy(uid, force: true) : false;
      if (!mounted) return;
      setState(() {
        expert = detail;
        final f = Map<String, dynamic>.from(results[1] as Map);
        following = f['following'] == true;
        reviews = List<dynamic>.from(results[2] as List);
        final n = Map<String, dynamic>.from(results[3] as Map);
        nudgeNotified = n['notified'] == true;
        blockedByMe = (isLoggedIn && uid.isNotEmpty) && (results[4] as Set<String>).contains(uid);
        blockedByListener = blockedByThem;
        loading = false;
      });
      if (widget.initialSessionType != null && !_initialSessionTriggered) {
        _initialSessionTriggered = true;
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
      final callerCountry = (app.user?.country ?? '').trim().toLowerCase();
      final isCallerIntl = (callerCountry.isNotEmpty && callerCountry != 'india' && callerCountry != 'in') ||
          (DateTime.now().timeZoneOffset.inMinutes != 330);
      // Backend automatically checks 1-min balance and returns helpful message if insufficient
      final session = await app.api.requestSession(
        widget.listener.id,
        type,
        categorySlug: _categorySlug(),
        callerIsInternational: isCallerIntl,
        callerCountry: app.user?.country,
        callerTimezone: DateTime.now().timeZoneName,
      );
      if (!mounted) return;
      ActiveCallManager.instance.startCall(session, callerSide: true);
      _refreshPresence();
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
    final app = context.read<AppController>();
    if (app.user == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign in to notify'),
          content: Text('Please log in or create an account to notify ${widget.listener.displayName}.'),
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
    final isAdult = expert['adultTalkAllowed'] == true ||
        l.isAdult ||
        categories.any((c) {
          final s = c.toLowerCase().trim();
          return s == '18+ adult talk' || s == 'adult-talk' || s.contains('adult');
        });
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

    return Scaffold(
      backgroundColor: const Color(0xFFFAF5EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF5EE),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF1EAE0)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: Color(0xFF1E293B)),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
        title: Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF1E293B)),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFF1EAE0)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Direct Message',
              onPressed: () {
                final targetId = expertUserId.isNotEmpty ? expertUserId : (widget.listener.userId ?? widget.listener.id);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DirectChatScreen(
                      otherUserId: targetId,
                      otherUserName: displayName,
                      otherUserAvatar: avatar,
                      otherUserRole: 'EXPERT',
                      ratePerMinute: audioRate,
                    ),
                  ),
                );
              },
              icon: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFF64748B),
                size: 19,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFF1EAE0)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: following ? 'Remove favourite' : 'Add favourite',
              onPressed: blockedByListener ? null : _toggleFollow,
              icon: Icon(
                following ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: following ? const Color(0xFFE05D44) : const Color(0xFF64748B),
                size: 20,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 14),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFF1EAE0)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFF1E293B)),
              onSelected: _safety,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'report', child: Text('Report listener')),
                if (!blockedByMe) const PopupMenuItem(value: 'block', child: Text('Block listener')),
                if (blockedByMe) const PopupMenuItem(value: 'unblock', child: Text('Unblock listener')),
              ],
            ),
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
                        const Icon(Icons.person_off_outlined, size: 64, color: Color(0xFF94A3B8)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    if (blockedByMe)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.block_rounded, color: Color(0xFFDC2626)),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'You blocked this listener. Unblock anytime to interact.',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF991B1B)),
                              ),
                            ),
                            TextButton(
                              onPressed: _unblock,
                              child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFDC2626))),
                            ),
                          ],
                        ),
                      ),

                    // 1. Hero Listener Card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFF1EAE0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF78350F).withValues(alpha: 0.05),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Center(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(3.5),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: isOnline
                                          ? [const Color(0xFF10B981), const Color(0xFF34D399)]
                                          : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      if (isOnline)
                                        BoxShadow(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                          blurRadius: 14,
                                          spreadRadius: 2,
                                        ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(60),
                                    child: RemoteAvatar(url: avatar, radius: 48, fallback: displayName),
                                  ),
                                ),
                                if (isOnline)
                                  Positioned(
                                    bottom: 2,
                                    right: 4,
                                    child: Container(
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 3),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1E293B),
                                    letterSpacing: -0.3,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.verified_rounded, size: 20, color: Color(0xFFE05D44)),
                              if (isAdult) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1F2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFFDA4AF),
                                      width: 1.0,
                                    ),
                                  ),
                                  child: const Text(
                                    '🔞 18+ Adult Talk',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFE11D48),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            title.isNotEmpty ? title : 'Empathy & Wellness Listener',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: isInternational ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isInternational ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isInternational
                                      ? (country.toLowerCase().contains('united states') || country.toLowerCase().contains('usa') ? '🇺🇸' :
                                         country.toLowerCase().contains('united kingdom') || country.toLowerCase().contains('uk') ? '🇬🇧' :
                                         country.toLowerCase().contains('canada') ? '🇨🇦' :
                                         country.toLowerCase().contains('australia') ? '🇦🇺' :
                                         country.toLowerCase().contains('uae') ? '🇦🇪' : '🌐')
                                      : '🇮🇳',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isInternational ? '$country • International Listener' : 'India • Verified Domestic Listener',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: isInternational ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Live Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                    boxShadow: isOnline
                                        ? [BoxShadow(color: statusColor.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1)]
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  statusLabel.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.5,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          // 4 Modern Stat Badges
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF7F2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFF1EAE0)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _statBox('⭐ ${rating.toStringAsFixed(1)}', '$reviewCount reviews'),
                                _statDivider(),
                                _statBox('$sessions', 'Sessions'),
                                _statDivider(),
                                _statBox('${experience ?? 7}+ Yrs', 'Experience'),
                                if (response != null && response > 0) ...[
                                  _statDivider(),
                                  _statBox('~${response}m', 'Response'),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 2. Services & Live Rates Section
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Choose How to Connect',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B)),
                          ),
                          Text(
                            'Per-minute billing',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (consultationType != 'VIDEO')
                      _buildServiceConnectCard(
                        icon: Icons.phone_in_talk_rounded,
                        iconBg: const Color(0xFFFFF1EE),
                        iconColor: const Color(0xFFE05D44),
                        title: 'Voice Call',
                        subtitle: 'Instant private audio session',
                        rateText: showDualRate
                            ? '₹${effectiveAudioRate.toStringAsFixed(0)}/min (~\$${(effectiveAudioRate / 85.0).toStringAsFixed(2)})'
                            : '₹${effectiveAudioRate.toStringAsFixed(0)}/min',
                        isAvailable: audioAvailable,
                        isBusy: isBusy,
                        isOnline: isOnline,
                        onTap: () => _start('AUDIO_CALL'),
                        isPrimary: true,
                        primaryColor: const Color(0xFFE05D44),
                        actionLabel: 'Call Now',
                      ),

                    if (consultationType != 'AUDIO')
                      _buildServiceConnectCard(
                        icon: Icons.videocam_rounded,
                        iconBg: const Color(0xFFF5F3FF),
                        iconColor: const Color(0xFF7C3AED),
                        title: 'Video Call',
                        subtitle: 'Private 1-on-1 video session',
                        rateText: showDualRate
                            ? '₹${effectiveVideoRate.toStringAsFixed(0)}/min (~\$${(effectiveVideoRate / 85.0).toStringAsFixed(2)})'
                            : '₹${effectiveVideoRate.toStringAsFixed(0)}/min',
                        isAvailable: videoAvailable,
                        isBusy: isBusy,
                        isOnline: isOnline,
                        onTap: () => _start('VIDEO_CALL'),
                        isPrimary: false,
                        primaryColor: const Color(0xFF7C3AED),
                        actionLabel: 'Video Call',
                      ),

                    _buildServiceConnectCard(
                      icon: Icons.chat_bubble_rounded,
                      iconBg: const Color(0xFFEFF6FF),
                      iconColor: const Color(0xFF2563EB),
                      title: 'Private Chat',
                      subtitle: 'Real-time encrypted text chat',
                      rateText: showDualRate
                          ? '₹${effectiveChatRate.toStringAsFixed(0)}/min (~\$${(effectiveChatRate / 85.0).toStringAsFixed(2)})'
                          : '₹${effectiveChatRate.toStringAsFixed(0)}/min',
                      isAvailable: chatAvailable,
                      isBusy: isBusy,
                      isOnline: isOnline,
                      onTap: () => _start('CHAT'),
                      isPrimary: false,
                      primaryColor: const Color(0xFF2563EB),
                      actionLabel: 'Start Chat',
                    ),

                    if (presence == 'OFFLINE') ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
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
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
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
                                        'Send a quick push notification to request $displayName to come online.',
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
                                  nudgeNotified ? 'Notification Already Sent' : 'Message Listener to Come Online',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 3. About & Background Card
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF1EAE0)),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF78350F).withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
                        ],
                      ),
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person_pin_rounded, color: Color(0xFFE05D44), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'About $displayName',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                          if (bio.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF7F2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFF1EAE0)),
                              ),
                              child: Text(
                                '“$bio”',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontStyle: FontStyle.italic,
                                  color: Color(0xFF334155),
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                          if (categories.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text('Topics I Support', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B))),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: categories.map((cat) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3EC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFFFD8CC)),
                                ),
                                child: Text(
                                  cat,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFC2410C)),
                                ),
                              )).toList(),
                            ),
                          ],
                          if (skills.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text('Specialized Skills', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B))),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: skills.map((skill) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFBBF7D0)),
                                ),
                                child: Text(
                                  skill,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF15803D)),
                                ),
                              )).toList(),
                            ),
                          ],
                          if (languages.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text('Languages Spoken', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B))),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: languages.map((lang) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.language_rounded, size: 13, color: Color(0xFF475569)),
                                    const SizedBox(width: 5),
                                    Text(lang, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                                  ],
                                ),
                              )).toList(),
                            ),
                          ],
                          if ((gender?.isNotEmpty ?? false) || (hobbies?.isNotEmpty ?? false)) ...[
                            const SizedBox(height: 16),
                            const Text('Personal Interests & Profile', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF64748B))),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (gender?.isNotEmpty == true)
                                  _infoPill(Icons.person_outline_rounded, 'Gender: $gender'),
                                if (hobbies?.isNotEmpty == true)
                                  ...hobbies!.split(RegExp(r'[,•]')).map((h) => h.trim()).where((h) => h.isNotEmpty).map((h) => _infoPill(Icons.favorite_outline_rounded, h)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 4. Safety Assurance Card
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFF1EAE0)),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF78350F).withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFA7F3D0)),
                            ),
                            child: const Icon(Icons.shield_rounded, color: Color(0xFF059669), size: 24),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '100% Anonymous & Secure',
                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF1E293B)),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Your identity, phone number, and location stay private. All sessions are encrypted and protected by platform safeguards.',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 5. Caller Reviews Section
                    Container(
                      margin: const EdgeInsets.only(top: 14, bottom: 24),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFF1EAE0)),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF78350F).withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.rate_review_rounded, color: Color(0xFFE05D44), size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Caller Reviews',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1E293B)),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFD97706)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${rating.toStringAsFixed(1)} ($reviewCount)',
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF92400E)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (reviews.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: Text('No reviews yet. Be the first to leave a review!', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                              ),
                            )
                          else
                            ...reviews.take(10).map((r) {
                              final m = Map<String, dynamic>.from(r);
                              final reply = m['expertResponse'] ?? m['response'];
                              final rScore = (m['rating'] as num?)?.toDouble() ?? 5.0;
                              final rCustomer = '${m['customerName'] ?? 'Anonymous Caller'}';
                              final rComment = '${m['comment'] ?? ''}';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAF7F2),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFF1EAE0)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFFECE5),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              rCustomer.isNotEmpty ? rCustomer[0].toUpperCase() : 'A',
                                              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFE05D44), fontSize: 12),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            rCustomer,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1E293B)),
                                          ),
                                        ),
                                        Row(
                                          children: List.generate(
                                            5,
                                            (idx) => Icon(
                                              idx < rScore.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                                              size: 14,
                                              color: const Color(0xFFF59E0B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (rComment.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        rComment,
                                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.35),
                                      ),
                                    ],
                                    if (reply != null && '$reply'.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.reply_rounded, size: 14, color: Color(0xFF64748B)),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Listener response: $reply',
                                                style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Color(0xFF334155)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _statBox(String value, String sub) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 2),
        Text(
          sub,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _statDivider() {
    return Container(
      height: 26,
      width: 1,
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _infoPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF64748B)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceConnectCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String rateText,
    required bool isAvailable,
    required bool isBusy,
    required bool isOnline,
    required VoidCallback onTap,
    required bool isPrimary,
    required Color primaryColor,
    required String actionLabel,
  }) {
    final bool canConnect = isAvailable && isOnline && !isBusy && !busy;
    final bool canNudge = isAvailable && !isOnline && !isBusy && !nudgeNotified && !busy;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPrimary && canConnect ? primaryColor.withValues(alpha: 0.35) : const Color(0xFFF1EAE0),
          width: isPrimary && canConnect ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isPrimary && canConnect
                ? primaryColor.withValues(alpha: 0.08)
                : const Color(0xFF78350F).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isAvailable ? iconBg : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: isAvailable ? iconColor : const Color(0xFF94A3B8), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: !isAvailable
                            ? const Color(0xFFF1F5F9)
                            : isBusy
                                ? const Color(0xFFFEF3C7)
                                : isOnline
                                    ? const Color(0xFFECFDF5)
                                    : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        !isAvailable
                            ? 'Paused'
                            : isBusy
                                ? 'In Call'
                                : isOnline
                                    ? 'Online'
                                    : 'Offline',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: !isAvailable
                              ? const Color(0xFF94A3B8)
                              : isBusy
                                  ? const Color(0xFFD97706)
                                  : isOnline
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 5),
                Text(
                  rateText,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isAvailable ? primaryColor : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            height: 38,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: Size.zero,
                elevation: canConnect ? 2 : 0,
                backgroundColor: canConnect
                    ? primaryColor
                    : canNudge
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFF1F5F9),
                foregroundColor: canConnect || canNudge ? Colors.white : const Color(0xFF94A3B8),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: canConnect
                  ? onTap
                  : canNudge
                      ? _handleDirectNudge
                      : null,
              child: Text(
                !isAvailable
                    ? 'Off'
                    : isBusy
                        ? 'Busy'
                        : !isOnline
                            ? (nudgeNotified ? 'Notified' : 'Nudge')
                            : actionLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: canConnect || canNudge ? Colors.white : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _safety(String action) async {
    final app = context.read<AppController>();
    if (app.user == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign in required'),
          content: const Text('Please log in to report or block listeners.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen(initialTab: 0)));
              },
              icon: const Icon(Icons.login, size: 16),
              label: const Text('Log In'),
            ),
          ],
        ),
      );
      return;
    }
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
}
