import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import '../session/session_screen.dart';

class ListenerHistoryScreen extends StatefulWidget {
  const ListenerHistoryScreen({super.key});

  @override
  State<ListenerHistoryScreen> createState() => _ListenerHistoryScreenState();
}

class _ListenerHistoryScreenState extends State<ListenerHistoryScreen> {
  List<InstantSessionModel> items = [];
  final search = TextEditingController();
  bool loading = true;

  // Filter & Sort State
  String serviceType = 'ALL'; // ALL, AUDIO_CALL, VIDEO_CALL, CHAT
  String statusFilter = 'ALL'; // ALL, COMPLETED, ACTIVE, MISSED, CANCELLED
  String dateFilter = 'ALL'; // ALL, TODAY, YESTERDAY, 7_DAYS, 30_DAYS, THIS_MONTH, CUSTOM
  DateTimeRange? customRange;
  String sort = 'NEWEST'; // NEWEST, OLDEST, RUPEES, DURATION
  String earningsFilter = 'ALL'; // ALL, PAID, GIFTS, PROMO, UNBILLED

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    search.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    search.removeListener(_changed);
    search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final next = await context.read<AppController>().api.listenerHistory();
      if (mounted) {
        setState(() {
          items = next;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  DateTime? _when(InstantSessionModel s) =>
      DateTime.tryParse(s.connectedAt ?? s.startedAt ?? s.requestedAt ?? '')?.toLocal();

  bool _dateOk(DateTime? d) {
    if (dateFilter == 'ALL') return true;
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);

    if (dateFilter == 'TODAY') return day == today;
    if (dateFilter == 'YESTERDAY') return day == today.subtract(const Duration(days: 1));
    if (dateFilter == '7_DAYS') {
      return !day.isBefore(today.subtract(const Duration(days: 6))) && !day.isAfter(now);
    }
    if (dateFilter == '30_DAYS') {
      return !day.isBefore(today.subtract(const Duration(days: 29))) && !day.isAfter(now);
    }
    if (dateFilter == 'THIS_MONTH') {
      return d.year == now.year && d.month == now.month;
    }
    if (dateFilter == 'CUSTOM' && customRange != null) {
      final startDay = DateTime(customRange!.start.year, customRange!.start.month, customRange!.start.day);
      final endDay = DateTime(customRange!.end.year, customRange!.end.month, customRange!.end.day, 23, 59, 59);
      return !d.isBefore(startDay) && !d.isAfter(endDay);
    }
    return true;
  }

  bool _statusOk(InstantSessionModel s) {
    if (statusFilter == 'ALL') return true;
    if (statusFilter == 'COMPLETED') return s.status == 'COMPLETED';
    if (statusFilter == 'ACTIVE') return s.isLive;
    if (statusFilter == 'MISSED') return s.isMissed;
    if (statusFilter == 'CANCELLED') return s.status == 'CANCELLED';
    return true;
  }

  bool _serviceOk(InstantSessionModel s) {
    if (serviceType == 'ALL') return true;
    return s.type.toUpperCase() == serviceType.toUpperCase();
  }

  bool _earningsOk(InstantSessionModel s) {
    final earned = s.effectiveListenerEarnings;
    if (earningsFilter == 'ALL') return true;
    if (earningsFilter == 'PAID') return earned > 0;
    if (earningsFilter == 'GIFTS') return s.giftEarnings > 0;
    if (earningsFilter == 'PROMO') {
      return s.promotionalBonusUsed || (s.isCompleted && s.grossAmount > 0 && earned == 0);
    }
    if (earningsFilter == 'UNBILLED') return earned == 0 && !s.isMissed;
    return true;
  }

  List<InstantSessionModel> get filteredItems {
    final q = search.text.trim().toLowerCase();
    var list = items.where((s) {
      if (!_dateOk(_when(s))) return false;
      if (!_statusOk(s)) return false;
      if (!_serviceOk(s)) return false;
      if (!_earningsOk(s)) return false;

      if (q.isEmpty) return true;
      final ref = s.reference.toLowerCase();
      final nick = s.callerNickname.toLowerCase();
      final type = s.type.toLowerCase();
      return ref.contains(q) || nick.contains(q) || type.contains(q);
    }).toList();

    list.sort((a, b) {
      if (sort == 'OLDEST') {
        final ad = _when(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = _when(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      }
      if (sort == 'RUPEES') {
        return b.effectiveListenerEarnings.compareTo(a.effectiveListenerEarnings);
      }
      if (sort == 'DURATION') {
        return b.billableSeconds.compareTo(a.billableSeconds);
      }
      final ad = _when(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = _when(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return list;
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (picked != null) {
      setState(() {
        customRange = picked;
        dateFilter = 'CUSTOM';
      });
    }
  }

  Future<void> _callback(InstantSessionModel s) async {
    try {
      var callback = await context.read<AppController>().api.callbackSession(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ringing ${s.callerNickname}…'),
        backgroundColor: const Color(0xFF10B981),
      ));
      for (var i = 0; i < 40 && mounted; i++) {
        if (const {'ACCEPTED', 'CONNECTED', 'ACTIVE'}.contains(callback.status)) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SessionScreen(initialSession: callback, callerSide: false)),
          );
          await _load();
          return;
        }
        if (const {'EXPIRED', 'REJECTED', 'CANCELLED'}.contains(callback.status)) {
          throw Exception('Callback was not picked up. Try again later.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        callback = await context.read<AppController>().api.session(callback.id);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _details(InstantSessionModel s) async {
    List<dynamic> gifts = [];
    try {
      final r = await context.read<AppController>().api.sessionGifts(s.id).catchError((_) => <dynamic>[]);
      gifts = List<dynamic>.from(r);
    } catch (_) {}
    if (!mounted) return;

    final earnedRupees = s.effectiveListenerEarnings;
    final callRupees = (earnedRupees - s.giftEarnings).clamp(0.0, 999999.0);
    final isPromo = s.promotionalBonusUsed || (s.isCompleted && s.grossAmount > 0 && earnedRupees == 0);

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: borderWarm)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: softPeach,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_serviceIcon(s.type), color: primaryOrange, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.callerNickname,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800, color: textDark)),
                          Row(
                            children: [
                              Text(s.reference,
                                  style: const TextStyle(
                                      fontSize: 12, color: textMuted, fontFamily: 'monospace')),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: s.reference));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Session reference copied!'),
                                        duration: Duration(seconds: 1)),
                                  );
                                },
                                child: const Icon(Icons.copy_rounded, size: 14, color: textMuted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: textMuted),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Total Payout Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBF7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderWarm),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Take-Home', style: TextStyle(color: textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _statusBgColor(s),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(_statusLabel(s),
                                      style: TextStyle(color: _statusTextColor(s), fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '₹${earnedRupees.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                    color: earnedRupees > 0 ? const Color(0xFF10B981) : textDark,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isPromo)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('PROMO / SEED',
                                        style: TextStyle(
                                            color: Color(0xFFB45309), fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Breakdown
                      _receiptRow('Duration billed', '${(s.billableSeconds / 60).toStringAsFixed(1)} mins (${s.billableSeconds}s)'),
                      _receiptRow('Per-minute rate', '₹${s.ratePerMinute.toStringAsFixed(2)} / min'),
                      _receiptRow('Session earnings', '₹${callRupees.toStringAsFixed(2)}'),
                      _receiptRow('Gift bonus credits', '₹${s.giftEarnings.toStringAsFixed(2)}'),
                      const Divider(height: 20, color: borderWarm),
                      _receiptRow('Total Net Payout', '₹${earnedRupees.toStringAsFixed(2)}', isBold: true),

                      if (gifts.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        const Text('Gifts Received', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
                        const SizedBox(height: 6),
                        ...gifts.map((g) {
                          final gm = Map<String, dynamic>.from(g as Map);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Text('🎁', style: TextStyle(fontSize: 20)),
                            title: Text('${gm['giftName'] ?? 'Gift'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: Text('+₹${(gm['coins'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'}',
                                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                          );
                        }),
                      ],
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

  Widget _receiptRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isBold ? textDark : textMuted, fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(color: textDark, fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }

  IconData _serviceIcon(String type) {
    final t = type.toUpperCase();
    if (t.contains('VIDEO')) return Icons.videocam_rounded;
    if (t.contains('AUDIO') || t.contains('VOICE')) return Icons.call_rounded;
    return Icons.chat_bubble_rounded;
  }

  String _statusLabel(InstantSessionModel s) {
    if (s.isLive) return 'Active';
    if (s.isMissed) return 'Missed';
    if (s.status == 'CANCELLED') return 'Cancelled';
    if (s.isCompleted) return 'Completed';
    return s.status;
  }

  Color _statusTextColor(InstantSessionModel s) {
    if (s.isLive) return const Color(0xFFEA580C);
    if (s.isMissed || s.status == 'CANCELLED') return const Color(0xFFDC2626);
    if (s.isCompleted) return const Color(0xFF059669);
    return const Color(0xFF4B5563);
  }

  Color _statusBgColor(InstantSessionModel s) {
    if (s.isLive) return const Color(0xFFFFEDD5);
    if (s.isMissed || s.status == 'CANCELLED') return const Color(0xFFFEE2E2);
    if (s.isCompleted) return const Color(0xFFD1FAE5);
    return const Color(0xFFF3F4F6);
  }

  String _fmtRange(InstantSessionModel s) {
    final start = DateTime.tryParse(s.startedAt ?? s.requestedAt ?? '')?.toLocal();
    final end = DateTime.tryParse(s.endedAt ?? '')?.toLocal();
    if (start == null) return 'Recent';
    final fmt = DateFormat('h:mm a');
    if (end != null) {
      return '${fmt.format(start)} – ${fmt.format(end)}';
    }
    return fmt.format(start);
  }

  String _fmtDate(InstantSessionModel s) {
    final start = DateTime.tryParse(s.startedAt ?? s.requestedAt ?? '')?.toLocal();
    if (start == null) return 'Today';
    final now = DateTime.now();
    if (start.year == now.year && start.month == now.month && start.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (start.year == yesterday.year && start.month == yesterday.month && start.day == yesterday.day) {
      return 'Yesterday';
    }
    return DateFormat('dd MMM').format(start);
  }

  String _fmtDuration(int seconds) {
    if (seconds <= 0) return '0s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }

  Color _avatarColor(String nickname) {
    const colors = [
      Color(0xFF8B5CF6),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFF3B82F6),
      Color(0xFFEC4899),
      Color(0xFF06B6D4),
    ];
    final hash = nickname.hashCode.abs();
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(backgroundColor: bgCream, body: LoadingBody());

    final totalEarnings = items.fold<double>(0, (sum, s) => sum + s.effectiveListenerEarnings);
    final totalGifts = items.fold<double>(0, (sum, s) => sum + s.giftEarnings);
    final completedCount = items.where((s) => s.isCompleted).length;
    final missedCount = items.where((s) => s.isMissed || s.status == 'CANCELLED').length;
    final totalSeconds = items.fold<int>(0, (sum, s) => sum + s.billableSeconds);
    final totalHours = totalSeconds / 3600;

    final channelAll = items.length;
    final channelAudio = items.where((s) => s.type.toUpperCase().contains('AUDIO') || s.type.toUpperCase().contains('VOICE')).length;
    final channelVideo = items.where((s) => s.type.toUpperCase().contains('VIDEO')).length;
    final channelChat = items.where((s) => s.type.toUpperCase().contains('CHAT')).length;

    final list = filteredItems;

    return Scaffold(
      backgroundColor: bgCream,
      body: Stack(
        children: [
          // Top-right warm peach ambient glow orb
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFD8C7).withValues(alpha: 0.7),
                    const Color(0xFFFFECE5).withValues(alpha: 0.35),
                    const Color(0xFFFAF5EE).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: RefreshIndicator(
              color: primaryOrange,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
                children: [
                  // Title Header
                  const Text(
                    'Sessions & Attendance',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 1. Top 3 Stat Cards Row matching Screenshot 4
                  Row(
                    children: [
                      // Card 1: Total Earnings (Coral/Orange Gradient)
                      Expanded(
                        flex: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [primaryOrange, secondaryOrange],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primaryOrange.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Total Earnings',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.25),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.monetization_on_rounded, color: Colors.white, size: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '₹${totalEarnings.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Incl. ₹${totalGifts.toStringAsFixed(0)} gifts 🎁',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Card 2: Sessions Taken (White Card)
                      Expanded(
                        flex: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderWarm),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Sessions Taken',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: textMuted, fontSize: 10.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                      color: softPeach,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.headphones_rounded, color: primaryOrange, size: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${items.length}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$completedCount done • $missedCount missed',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: textMuted, fontSize: 9, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Card 3: Total (White Card)
                      Expanded(
                        flex: 9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderWarm),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Total',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: textMuted, fontSize: 10.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                      color: softPeach,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.bar_chart_rounded, color: primaryOrange, size: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${items.length}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${totalHours.toStringAsFixed(1)} hours',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: textMuted, fontSize: 9, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 2. Channel Filter Pills (Horizontal Scrolling Row matching Screenshot 4)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildChannelPill(
                          label: 'All Channels',
                          count: channelAll,
                          icon: Icons.grid_view_rounded,
                          isSelected: serviceType == 'ALL',
                          onTap: () => setState(() => serviceType = 'ALL'),
                        ),
                        const SizedBox(width: 8),
                        _buildChannelPill(
                          label: 'Audio Calls',
                          count: channelAudio,
                          icon: Icons.call_rounded,
                          isSelected: serviceType == 'AUDIO_CALL',
                          onTap: () => setState(() => serviceType = 'AUDIO_CALL'),
                        ),
                        const SizedBox(width: 8),
                        _buildChannelPill(
                          label: 'Video Calls',
                          count: channelVideo,
                          icon: Icons.videocam_rounded,
                          isSelected: serviceType == 'VIDEO_CALL',
                          onTap: () => setState(() => serviceType = 'VIDEO_CALL'),
                        ),
                        const SizedBox(width: 8),
                        _buildChannelPill(
                          label: 'Chat Sessions',
                          count: channelChat,
                          icon: Icons.chat_bubble_rounded,
                          isSelected: serviceType == 'CHAT',
                          onTap: () => setState(() => serviceType = 'CHAT'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3. Search and Date/Filter Bar matching Screenshot 4
                  Row(
                    children: [
                      // Search Input (Expanded)
                      Expanded(
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderWarm),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: search,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'Search caller, ID, ref...',
                              hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12.5),
                              prefixIcon: Icon(Icons.search_rounded, color: primaryOrange, size: 20),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Date Dropdown
                      Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderWarm),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: dateFilter == 'CUSTOM' ? 'CUSTOM' : dateFilter,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 18),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: textDark),
                            items: [
                              DropdownMenuItem(
                                value: 'ALL',
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today_rounded, color: primaryOrange, size: 15),
                                    const SizedBox(width: 6),
                                    const Text('All time'),
                                  ],
                                ),
                              ),
                              const DropdownMenuItem(value: 'TODAY', child: Text('Today')),
                              const DropdownMenuItem(value: 'YESTERDAY', child: Text('Yesterday')),
                              const DropdownMenuItem(value: '7_DAYS', child: Text('7 days')),
                              const DropdownMenuItem(value: '30_DAYS', child: Text('30 days')),
                              const DropdownMenuItem(value: 'THIS_MONTH', child: Text('This month')),
                              DropdownMenuItem(
                                value: 'CUSTOM',
                                child: Text(customRange != null
                                    ? '${DateFormat('d/M').format(customRange!.start)}–${DateFormat('d/M').format(customRange!.end)}'
                                    : 'Custom…'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v == 'CUSTOM') {
                                _pickCustomRange();
                              } else {
                                setState(() {
                                  dateFilter = v ?? 'ALL';
                                  customRange = null;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Filter Sliders Icon Button
                      InkWell(
                        onTap: () => _showFilterSheet(),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderWarm),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.tune_rounded, color: primaryOrange, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 4. Session Cards List matching Screenshot 4
                  if (list.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderWarm),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off_rounded, size: 48, color: Color(0xFFD1D5DB)),
                          SizedBox(height: 12),
                          Text(
                            'No sessions found',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textDark),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Try changing filters or search terms.',
                            style: TextStyle(fontSize: 12.5, color: textMuted),
                          ),
                        ],
                      ),
                    )
                  else
                    ...list.map((s) => _buildSessionCard(s)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelPill({
    required String label,
    required int count,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? primaryOrange : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? primaryOrange : borderWarm),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: primaryOrange.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : primaryOrange,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : textDark,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionCard(InstantSessionModel s) {
    final callerNick = s.callerNickname.isNotEmpty ? s.callerNickname : 'Anonymous Caller';
    final ref = s.reference;
    final earned = s.effectiveListenerEarnings;
    final isVideo = s.type.toUpperCase().contains('VIDEO');
    final isChat = s.type.toUpperCase().contains('CHAT');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderWarm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Avatar + Caller Nickname & Ref + Right Badges
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Circle Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _avatarColor(callerNick),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    callerNick.isNotEmpty ? callerNick.substring(0, 1).toUpperCase() : 'S',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Nickname & SES ID
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      callerNick,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: textDark,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          ref,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: textMuted,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: ref));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied reference!'), duration: Duration(seconds: 1)),
                            );
                          },
                          child: const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF9CA3AF)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Right: Modality badge + Status badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Modality Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isVideo
                          ? const Color(0xFFF3E8FF)
                          : (isChat ? const Color(0xFFFEF3C7) : const Color(0xFFECFDF5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isVideo ? Icons.videocam_rounded : (isChat ? Icons.chat_bubble_rounded : Icons.call_rounded),
                          size: 12,
                          color: isVideo ? const Color(0xFF7C3AED) : (isChat ? const Color(0xFFD97706) : const Color(0xFF059669)),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isVideo ? 'Video' : (isChat ? 'Chat' : 'Audio'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isVideo ? const Color(0xFF7C3AED) : (isChat ? const Color(0xFFD97706) : const Color(0xFF059669)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: _statusBgColor(s),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusLabel(s),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: _statusTextColor(s),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Middle Box: Time Range & Duration Box matching Screenshot 4
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderWarm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left half: Time & Day
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.access_time_filled_rounded, size: 14, color: primaryOrange),
                        const SizedBox(width: 6),
                        Text(
                          _fmtRange(s),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: textDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 12, color: textMuted),
                        const SizedBox(width: 6),
                        Text(
                          _fmtDate(s),
                          style: const TextStyle(fontSize: 11, color: textMuted),
                        ),
                      ],
                    ),
                  ],
                ),

                // Right half: Duration & Rate
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer_rounded, size: 14, color: Color(0xFF6366F1)),
                        const SizedBox(width: 4),
                        Text(
                          _fmtDuration(s.billableSeconds),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: textDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '₹${s.ratePerMinute.toStringAsFixed(0)}/min',
                      style: const TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Row: Price / Earnings + Action Buttons (Receipt & Call Back)
          Row(
            children: [
              // Price text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '₹${earned.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: earned > 0 ? const Color(0xFF10B981) : textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      earned == 0 ? 'Unbilled (for seed call)' : 'Net Listener Payout',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: earned == 0 ? const Color(0xFFEF4444) : textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Action Buttons: Receipt & Call Back
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Receipt Button
                  InkWell(
                    onTap: () => _details(s),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderWarm),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.description_outlined, size: 14, color: textDark),
                          SizedBox(width: 4),
                          Text(
                            'Receipt',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textDark),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Call Back Button
                  InkWell(
                    onTap: () => _callback(s),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: primaryOrange,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: primaryOrange.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isChat ? Icons.chat_bubble_rounded : (isVideo ? Icons.videocam_rounded : Icons.call_rounded),
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isChat ? 'Chat Back' : 'Call Back',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Filter Sessions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const Divider(color: borderWarm),
            const SizedBox(height: 8),
            const Text('Status Filter', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textDark)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: ['ALL', 'COMPLETED', 'ACTIVE', 'MISSED', 'CANCELLED'].map((st) {
                final sel = statusFilter == st;
                return ChoiceChip(
                  label: Text(st == 'ALL' ? 'All Status' : st),
                  selected: sel,
                  selectedColor: softPeach,
                  labelStyle: TextStyle(color: sel ? primaryOrange : textDark, fontWeight: FontWeight.bold, fontSize: 12),
                  side: BorderSide(color: sel ? primaryOrange : borderWarm),
                  backgroundColor: Colors.white,
                  onSelected: (_) {
                    setState(() => statusFilter = st);
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textDark)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                {'id': 'NEWEST', 'label': 'Newest First'},
                {'id': 'OLDEST', 'label': 'Oldest First'},
                {'id': 'RUPEES', 'label': 'Highest Earnings'},
                {'id': 'DURATION', 'label': 'Longest Duration'},
              ].map((s) {
                final sel = sort == s['id'];
                return ChoiceChip(
                  label: Text('${s['label']}'),
                  selected: sel,
                  selectedColor: softPeach,
                  labelStyle: TextStyle(color: sel ? primaryOrange : textDark, fontWeight: FontWeight.bold, fontSize: 12),
                  side: BorderSide(color: sel ? primaryOrange : borderWarm),
                  backgroundColor: Colors.white,
                  onSelected: (_) {
                    setState(() => sort = '${s['id']}');
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
