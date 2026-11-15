import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/active_call_manager.dart';
import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import '../common/direct_chat_screen.dart';

class ListenerDailyAttendance {
  final DateTime date;
  final String dateStr;
  final int onlineSeconds;
  final int targetSeconds;
  final int callsCount;
  final int completedCalls;
  final int missedCalls;
  final double earnings;
  final int missedDaysStreak;
  final String status; // 'TARGET_MET', 'IN_PROGRESS', 'MISSED'

  const ListenerDailyAttendance({
    required this.date,
    required this.dateStr,
    required this.onlineSeconds,
    this.targetSeconds = 10800,
    required this.callsCount,
    required this.completedCalls,
    required this.missedCalls,
    required this.earnings,
    this.missedDaysStreak = 0,
    required this.status,
  });

  double get progress => (onlineSeconds / targetSeconds).clamp(0.0, 1.0);
  int get remainingSeconds => (targetSeconds - onlineSeconds).clamp(0, targetSeconds);
}

class ListenerHistoryScreen extends StatefulWidget {
  const ListenerHistoryScreen({super.key});

  @override
  State<ListenerHistoryScreen> createState() => _ListenerHistoryScreenState();
}

class _ListenerHistoryScreenState extends State<ListenerHistoryScreen> {
  List<InstantSessionModel> items = [];
  final search = TextEditingController();
  bool loading = true;

  // View Mode: 0 = Call Sessions, 1 = Daily Attendance
  int viewMode = 0;

  // Filter & Sort State for Sessions
  String serviceType = 'ALL'; // ALL, AUDIO_CALL, VIDEO_CALL, CHAT
  String statusFilter = 'ALL'; // ALL, COMPLETED, ACTIVE, MISSED, CANCELLED
  String dateFilter = 'ALL'; // ALL, TODAY, YESTERDAY, 7_DAYS, 30_DAYS, THIS_MONTH, CUSTOM
  DateTimeRange? customRange;
  String sort = 'NEWEST'; // NEWEST, OLDEST, RUPEES, DURATION
  String earningsFilter = 'ALL'; // ALL, PAID, GIFTS, PROMO, UNBILLED

  // Attendance State & Filters
  Map<String, dynamic>? attendanceSummary;
  List<Map<String, dynamic>> attendanceHistoryRecords = [];
  String attendanceStatusFilter = 'ALL'; // ALL, TARGET_MET, IN_PROGRESS, MISSED
  final attendanceSearch = TextEditingController();
  String attendanceDateFilter = 'ALL'; // ALL, TODAY, YESTERDAY, 7_DAYS, 30_DAYS, THIS_MONTH, CUSTOM
  DateTimeRange? attendanceCustomRange;

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
    attendanceSearch.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    search.removeListener(_changed);
    search.dispose();
    attendanceSearch.removeListener(_changed);
    attendanceSearch.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final next = await context.read<AppController>().api.listenerHistory();
      try {
        attendanceSummary = await context.read<AppController>().api.listenerAttendance();
      } catch (_) {}
      try {
        attendanceHistoryRecords = await context.read<AppController>().api.listenerAttendanceHistory();
      } catch (_) {}
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

  List<ListenerDailyAttendance> get computedDailyAttendance {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final map = <String, ListenerDailyAttendance>{};

    final sessionsByDate = <String, List<InstantSessionModel>>{};
    for (final s in items) {
      final dt = _when(s);
      if (dt != null) {
        final key = DateFormat('yyyy-MM-dd').format(dt);
        sessionsByDate.putIfAbsent(key, () => []).add(s);
      }
    }

    final telemetryByDate = <String, Map<String, dynamic>>{};
    for (final h in attendanceHistoryRecords) {
      final d = h['date']?.toString();
      if (d != null) {
        telemetryByDate[d] = h;
      }
    }

    for (int i = 0; i < 30; i++) {
      final day = today.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(day);
      final daySessions = sessionsByDate[dateStr] ?? [];
      final telemetry = telemetryByDate[dateStr];

      int onlineSecs = 0;
      if (telemetry != null && telemetry['onlineSeconds'] != null) {
        onlineSecs = (telemetry['onlineSeconds'] as num).toInt();
      } else if (i == 0 && attendanceSummary != null) {
        onlineSecs = (attendanceSummary!['onlineSeconds'] as num?)?.toInt() ?? 0;
      } else {
        final sessionDuration = daySessions.fold<int>(0, (sum, s) => sum + s.billableSeconds);
        onlineSecs = sessionDuration > 0 ? (sessionDuration * 1.35).toInt() : 0;
      }

      int completed = daySessions.where((s) => s.isCompleted).length;
      int missed = daySessions.where((s) => s.isMissed).length;
      double dayEarned = daySessions.fold<double>(0.0, (sum, s) => sum + s.effectiveListenerEarnings);
      int missedStreak = (telemetry?['missedDays'] as num?)?.toInt() ?? 0;

      String st;
      if (onlineSecs >= 10800) {
        st = 'TARGET_MET';
      } else if (onlineSecs > 0) {
        st = 'IN_PROGRESS';
      } else {
        st = 'MISSED';
      }

      map[dateStr] = ListenerDailyAttendance(
        date: day,
        dateStr: dateStr,
        onlineSeconds: onlineSecs,
        callsCount: daySessions.length,
        completedCalls: completed,
        missedCalls: missed,
        earnings: dayEarned,
        missedDaysStreak: missedStreak,
        status: st,
      );
    }

    var list = map.values.toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  bool _attendanceDateOk(DateTime d) {
    if (attendanceDateFilter == 'ALL') return true;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);

    if (attendanceDateFilter == 'TODAY') return day == today;
    if (attendanceDateFilter == 'YESTERDAY') return day == today.subtract(const Duration(days: 1));
    if (attendanceDateFilter == '7_DAYS') {
      return !day.isBefore(today.subtract(const Duration(days: 6))) && !day.isAfter(now);
    }
    if (attendanceDateFilter == '30_DAYS') {
      return !day.isBefore(today.subtract(const Duration(days: 29))) && !day.isAfter(now);
    }
    if (attendanceDateFilter == 'THIS_MONTH') {
      return d.year == now.year && d.month == now.month;
    }
    if (attendanceDateFilter == 'CUSTOM' && attendanceCustomRange != null) {
      final startDay = DateTime(attendanceCustomRange!.start.year, attendanceCustomRange!.start.month, attendanceCustomRange!.start.day);
      final endDay = DateTime(attendanceCustomRange!.end.year, attendanceCustomRange!.end.month, attendanceCustomRange!.end.day, 23, 59, 59);
      return !d.isBefore(startDay) && !d.isAfter(endDay);
    }
    return true;
  }

  List<ListenerDailyAttendance> get filteredAttendance {
    final q = attendanceSearch.text.trim().toLowerCase();
    return computedDailyAttendance.where((d) {
      if (attendanceStatusFilter != 'ALL' && d.status != attendanceStatusFilter) {
        return false;
      }
      if (!_attendanceDateOk(d.date)) return false;
      if (q.isNotEmpty) {
        final dateFormatted = DateFormat('EEEE, d MMMM yyyy').format(d.date).toLowerCase();
        final shortDate = DateFormat('d MMM').format(d.date).toLowerCase();
        final dayName = DateFormat('EEEE').format(d.date).toLowerCase();
        final statusLabel = d.status == 'TARGET_MET' ? 'present met target completed' : (d.status == 'IN_PROGRESS' ? 'in progress partial half' : 'missed absent');
        return dateFormatted.contains(q) || shortDate.contains(q) || dayName.contains(q) || statusLabel.contains(q);
      }
      return true;
    }).toList();
  }

  Future<void> _pickAttendanceCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: attendanceCustomRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (picked != null) {
      setState(() {
        attendanceCustomRange = picked;
        attendanceDateFilter = 'CUSTOM';
      });
    }
  }

  String _formatDurationHMS(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) {
      return '${h}h ${m}m';
    }
    return '${m}m';
  }

  Future<void> _callback(InstantSessionModel s) async {
    try {
      final callback = await context.read<AppController>().api.callbackSession(s.id);
      if (!mounted) return;
      ActiveCallManager.instance.startCall(callback, callerSide: false);
      await _load();
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
                          final emoji = gm['giftEmoji'] ?? '🎁';
                          final name = gm['giftName'] ?? gm['giftType'] ?? 'Gift';
                          final earned = (gm['netEarnings'] as num?)?.toDouble()
                              ?? (gm['grossAmount'] as num?)?.toDouble()
                              ?? (gm['coins'] as num?)?.toDouble()
                              ?? 0.0;
                          return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Text('$emoji', style: const TextStyle(fontSize: 20)),
                              title: Text('$name', style: const TextStyle(fontWeight: FontWeight.bold)),
                              trailing: Text('+₹${earned.toStringAsFixed(2)}',
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
                  const SizedBox(height: 14),

                  // Sub-Tab Switcher: Call Sessions vs Daily Attendance
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3ECE0),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderWarm, width: 0.9),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildTopSegment(
                            icon: Icons.phone_in_talk_rounded,
                            title: 'Call Sessions',
                            count: items.length,
                            isSelected: viewMode == 0,
                            onTap: () => setState(() => viewMode = 0),
                          ),
                        ),
                        Expanded(
                          child: _buildTopSegment(
                            icon: Icons.calendar_month_rounded,
                            title: 'Daily Attendance',
                            count: computedDailyAttendance.length,
                            isSelected: viewMode == 1,
                            onTap: () => setState(() => viewMode = 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (viewMode == 0) ...[
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
                                    children: const [
                                      Icon(Icons.calendar_today_rounded, color: primaryOrange, size: 15),
                                      SizedBox(width: 6),
                                      Text('All time'),
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
                  ] else ...[
                    // Daily Attendance View with Filters & Search
                    ..._buildAttendanceViewChildren(),
                  ],
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
                  if (s.callerId != null && s.callerId!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DirectChatScreen(
                              otherUserId: s.callerId,
                              otherUserName: s.callerNickname.isNotEmpty ? s.callerNickname : 'Caller',
                              otherUserAvatar: s.callerAvatarUrl,
                              otherUserRole: 'CUSTOMER',
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Color(0xFFD97706)),
                            SizedBox(width: 4),
                            Text(
                              'Message',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD97706)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // Call Back / Chat Back / Video Call Back Button (Only for missed calls)
                  if (s.isMissed) ...[
                    const SizedBox(width: 8),
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
                              isChat ? 'Chat Back' : (isVideo ? 'Video Call Back' : 'Call Back'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
            const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textDark)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                {'id': 'NEWEST', 'label': 'Newest First'},
                {'id': 'OLDEST', 'label': 'Oldest First'},
                {'id': 'RUPEES', 'label': 'Highest Earnings'},
                {'id': 'DURATION', 'label': 'Longest Duration'},
              ].map((m) {
                final sel = sort == m['id'];
                return ChoiceChip(
                  label: Text('${m['label']}'),
                  selected: sel,
                  selectedColor: softPeach,
                  labelStyle: TextStyle(color: sel ? primaryOrange : textDark, fontWeight: FontWeight.bold, fontSize: 12),
                  side: BorderSide(color: sel ? primaryOrange : borderWarm),
                  backgroundColor: Colors.white,
                  onSelected: (_) {
                    setState(() => sort = '${m['id']}');
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            const Text('Earnings Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textDark)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                {'id': 'ALL', 'label': 'All Types'},
                {'id': 'PAID', 'label': 'Paid Sessions'},
                {'id': 'GIFTS', 'label': 'With Gifts'},
                {'id': 'PROMO', 'label': 'Promo / Seed'},
                {'id': 'UNBILLED', 'label': 'Unbilled'},
              ].map((m) {
                final sel = earningsFilter == m['id'];
                return ChoiceChip(
                  label: Text('${m['label']}'),
                  selected: sel,
                  selectedColor: softPeach,
                  labelStyle: TextStyle(color: sel ? primaryOrange : textDark, fontWeight: FontWeight.bold, fontSize: 12),
                  side: BorderSide(color: sel ? primaryOrange : borderWarm),
                  backgroundColor: Colors.white,
                  onSelected: (_) {
                    setState(() => earningsFilter = '${m['id']}');
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    statusFilter = 'ALL';
                    sort = 'NEWEST';
                    earningsFilter = 'ALL';
                    dateFilter = 'ALL';
                    customRange = null;
                    search.clear();
                  });
                  Navigator.pop(ctx);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryOrange,
                  side: const BorderSide(color: primaryOrange),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Reset All Session Filters', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSegment({
    required IconData icon,
    required String title,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? primaryOrange : textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? textDark : textMuted,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? softPeach : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? primaryOrange : textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAttendanceViewChildren() {
    final attItems = filteredAttendance;
    final totalAttDays = computedDailyAttendance.length;
    final metDays = computedDailyAttendance.where((d) => d.status == 'TARGET_MET').length;
    final inProgressDays = computedDailyAttendance.where((d) => d.status == 'IN_PROGRESS').length;
    final missedDays = computedDailyAttendance.where((d) => d.status == 'MISSED').length;
    final totalOnlineSecs = computedDailyAttendance.fold<int>(0, (sum, d) => sum + d.onlineSeconds);
    final currentMissedStreak = computedDailyAttendance.isNotEmpty ? computedDailyAttendance.first.missedDaysStreak : 0;
    final targetRate = totalAttDays > 0 ? ((metDays / totalAttDays) * 100).toInt() : 0;

    return [
      // Top 3 Attendance KPI Cards Row
      Row(
        children: [
          // Card 1: Target Met / Present Days (Gradient Card)
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
                          'Present Days',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(Icons.verified_rounded, color: Colors.white, size: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$metDays / $totalAttDays',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$targetRate% Target Met 🎯',
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

          // Card 2: Hours Logged (White Card)
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
                          'Hours Logged',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textMuted, fontSize: 10.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: softPeach,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(Icons.timer_rounded, color: primaryOrange, size: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${(totalOnlineSecs / 3600).toStringAsFixed(1)}h',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Target: 3.0h / day ⏱',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textMuted, fontSize: 9, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Card 3: Compliance Status (White Card)
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
                          'Compliance',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textMuted, fontSize: 10.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: softPeach,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(Icons.shield_outlined, color: primaryOrange, size: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    currentMissedStreak == 0 ? 'Active' : '$currentMissedStreak Missed',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: currentMissedStreak == 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Limit: 7 missed days',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: textMuted, fontSize: 9, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),

      // Attendance Status Filter Pills
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildChannelPill(
              label: 'All Days',
              count: totalAttDays,
              icon: Icons.calendar_month_rounded,
              isSelected: attendanceStatusFilter == 'ALL',
              onTap: () => setState(() => attendanceStatusFilter = 'ALL'),
            ),
            const SizedBox(width: 8),
            _buildChannelPill(
              label: 'Target Met',
              count: metDays,
              icon: Icons.check_circle_rounded,
              isSelected: attendanceStatusFilter == 'TARGET_MET',
              onTap: () => setState(() => attendanceStatusFilter = 'TARGET_MET'),
            ),
            const SizedBox(width: 8),
            _buildChannelPill(
              label: 'In Progress',
              count: inProgressDays,
              icon: Icons.hourglass_top_rounded,
              isSelected: attendanceStatusFilter == 'IN_PROGRESS',
              onTap: () => setState(() => attendanceStatusFilter = 'IN_PROGRESS'),
            ),
            const SizedBox(width: 8),
            _buildChannelPill(
              label: 'Missed Days',
              count: missedDays,
              icon: Icons.cancel_rounded,
              isSelected: attendanceStatusFilter == 'MISSED',
              onTap: () => setState(() => attendanceStatusFilter = 'MISSED'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),

      // Attendance Search and Date Filter Bar
      Row(
        children: [
          // Search Input
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
                controller: attendanceSearch,
                style: const TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search date, day (e.g. today, monday)...',
                  hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12.5),
                  prefixIcon: const Icon(Icons.search_rounded, color: primaryOrange, size: 20),
                  suffixIcon: attendanceSearch.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16, color: textMuted),
                          onPressed: () {
                            attendanceSearch.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                value: attendanceDateFilter == 'CUSTOM' ? 'CUSTOM' : attendanceDateFilter,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 18),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: textDark),
                items: [
                  DropdownMenuItem(
                    value: 'ALL',
                    child: Row(
                      children: const [
                        Icon(Icons.calendar_today_rounded, color: primaryOrange, size: 15),
                        SizedBox(width: 6),
                        Text('All time'),
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
                    child: Text(attendanceCustomRange != null
                        ? '${DateFormat('d/M').format(attendanceCustomRange!.start)}–${DateFormat('d/M').format(attendanceCustomRange!.end)}'
                        : 'Custom…'),
                  ),
                ],
                onChanged: (v) {
                  if (v == 'CUSTOM') {
                    _pickAttendanceCustomRange();
                  } else {
                    setState(() {
                      attendanceDateFilter = v ?? 'ALL';
                      attendanceCustomRange = null;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Filter Button
          InkWell(
            onTap: () => _showAttendanceFilterSheet(),
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

      // Attendance Cards List
      if (attItems.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderWarm),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_busy_rounded, size: 48, color: Color(0xFFD1D5DB)),
              const SizedBox(height: 12),
              const Text(
                'No attendance records found',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textDark),
              ),
              const SizedBox(height: 4),
              const Text(
                'Try changing date filters or clearing your search.',
                style: TextStyle(fontSize: 12.5, color: textMuted),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    attendanceStatusFilter = 'ALL';
                    attendanceDateFilter = 'ALL';
                    attendanceCustomRange = null;
                    attendanceSearch.clear();
                  });
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reset Attendance Filters'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryOrange,
                  side: const BorderSide(color: primaryOrange),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        )
      else
        ...attItems.map((d) => _buildAttendanceCard(d)),
    ];
  }

  Widget _buildAttendanceCard(ListenerDailyAttendance d) {
    final now = DateTime.now();
    final isToday = d.date.year == now.year && d.date.month == now.month && d.date.day == now.day;
    final isYesterday = d.date.year == now.year &&
        d.date.month == now.month &&
        d.date.day == now.subtract(const Duration(days: 1)).day;

    final dayText = isToday
        ? 'Today'
        : (isYesterday ? 'Yesterday' : DateFormat('EEEE').format(d.date));
    final fullDateText = DateFormat('d MMMM yyyy').format(d.date);

    final isTargetMet = d.status == 'TARGET_MET';
    final isInProgress = d.status == 'IN_PROGRESS';

    final Color statusColor = isTargetMet
        ? const Color(0xFF10B981)
        : (isInProgress ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

    final Color statusBg = isTargetMet
        ? const Color(0xFFE8F5E9)
        : (isInProgress ? const Color(0xFFFFF3E0) : const Color(0xFFFFEBEE));

    final String statusLabel = isTargetMet
        ? 'Target Met (3h+)'
        : (isInProgress ? 'In Progress (${(d.progress * 100).toInt()}%)' : 'Missed Day (0h)');

    final IconData statusIcon = isTargetMet
        ? Icons.check_circle_rounded
        : (isInProgress ? Icons.hourglass_top_rounded : Icons.cancel_outlined);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderWarm),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Date & Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Date Box Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isTargetMet ? const Color(0xFFE8F5E9) : softPeach,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isTargetMet ? const Color(0xFFC8E6C9) : const Color(0xFFFFD8C7),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('d').format(d.date),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isTargetMet ? const Color(0xFF10B981) : primaryOrange,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM').format(d.date).toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: isTargetMet ? const Color(0xFF2E7D32) : primaryOrange,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Day name and Full Date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          dayText,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: textDark,
                          ),
                        ),
                        if (isToday || isYesterday) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: isToday ? primaryOrange : textMuted.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isToday ? 'Today' : 'Yesterday',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: isToday ? Colors.white : textDark,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fullDateText,
                      style: const TextStyle(fontSize: 11.5, color: textMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Shift Progress Bar & Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_formatDurationHMS(d.onlineSeconds)} logged',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textDark),
              ),
              Text(
                isTargetMet
                    ? '3.0h target met 🎉'
                    : (d.remainingSeconds > 0
                        ? '${_formatDurationHMS(d.remainingSeconds)} to 3.0h target'
                        : 'Target met'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isTargetMet ? const Color(0xFF10B981) : textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFFF3ECE0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: d.progress,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient: LinearGradient(
                      colors: isTargetMet
                          ? const [Color(0xFF34D399), Color(0xFF10B981)]
                          : (isInProgress
                              ? const [Color(0xFFFBBF24), Color(0xFFF59E0B)]
                              : const [Color(0xFFF87171), Color(0xFFEF4444)]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Daily Telemetry Stats Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF7F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderWarm.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                // Stat 1: Online Time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Online Time', style: TextStyle(fontSize: 10, color: textMuted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        _formatDurationHMS(d.onlineSeconds),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textDark),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 26, color: borderWarm),

                // Stat 2: Sessions Taken
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Calls Handled', style: TextStyle(fontSize: 10, color: textMuted, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${d.callsCount} (${d.completedCalls} done)',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textDark),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, height: 26, color: borderWarm),

                // Stat 3: Daily Earnings
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Day Earnings', style: TextStyle(fontSize: 10, color: textMuted, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '₹${d.earnings.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: textDark),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Quick Filter Sessions Button (if calls exist)
          if (d.callsCount > 0) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                setState(() {
                  dateFilter = 'CUSTOM';
                  customRange = DateTimeRange(start: d.date, end: d.date);
                  viewMode = 0; // Switch to call sessions tab
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'View ${d.callsCount} call sessions for this date',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: primaryOrange,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, size: 14, color: primaryOrange),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAttendanceFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      backgroundColor: Colors.white,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Filter Attendance Records', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const Divider(color: borderWarm),
            const SizedBox(height: 8),
            const Text('Shift Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textDark)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                {'id': 'ALL', 'label': 'All Days'},
                {'id': 'TARGET_MET', 'label': 'Target Met (3h+)'},
                {'id': 'IN_PROGRESS', 'label': 'In Progress (<3h)'},
                {'id': 'MISSED', 'label': 'Missed (0h)'},
              ].map((st) {
                final sel = attendanceStatusFilter == st['id'];
                return ChoiceChip(
                  label: Text('${st['label']}'),
                  selected: sel,
                  selectedColor: softPeach,
                  labelStyle: TextStyle(color: sel ? primaryOrange : textDark, fontWeight: FontWeight.bold, fontSize: 12),
                  side: BorderSide(color: sel ? primaryOrange : borderWarm),
                  backgroundColor: Colors.white,
                  onSelected: (_) {
                    setState(() => attendanceStatusFilter = '${st['id']}');
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    attendanceStatusFilter = 'ALL';
                    attendanceDateFilter = 'ALL';
                    attendanceCustomRange = null;
                    attendanceSearch.clear();
                  });
                  Navigator.pop(ctx);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryOrange,
                  side: const BorderSide(color: primaryOrange),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Reset All Attendance Filters', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
