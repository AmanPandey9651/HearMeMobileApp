import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';
import '../common/safety_support_screen.dart';
import '../session/booking_call_screen.dart';
import 'listener_detail_screen.dart';

class CallerHistoryScreen extends StatefulWidget {
  const CallerHistoryScreen({super.key});

  @override
  State<CallerHistoryScreen> createState() => _CallerHistoryScreenState();
}

class _CallerHistoryScreenState extends State<CallerHistoryScreen> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 2, vsync: this);
  final search = TextEditingController();

  List<InstantSessionModel> sessions = [];
  List<BookingModel> bookings = [];
  List<dynamic> disputes = [];
  bool loading = true;
  String modality = 'ALL';
  String status = 'ALL';
  String sortBy = 'NEWEST';
  String datePreset = 'ALL';

  static const Color bgCream = AppTheme.bgCream;
  static const Color borderWarm = AppTheme.borderWarm;
  static const Color primaryOrange = AppTheme.primaryOrange;
  // ignore: unused_field
  static const Color secondaryOrange = AppTheme.secondaryOrange;
  static const Color softPeach = AppTheme.softPeach;
  static const Color textDark = AppTheme.textDark;
  static const Color textMuted = AppTheme.textMuted;

  @override
  void initState() {
    super.initState();
    tabs.addListener(() {
      if (mounted) setState(() {});
    });
    search.addListener(_refreshFilters);
    _load();
  }

  @override
  void dispose() {
    search.removeListener(_refreshFilters);
    search.dispose();
    tabs.dispose();
    super.dispose();
  }

  void _refreshFilters() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppController>().api;
      final results = await Future.wait<dynamic>([
        api.callerHistory(),
        api.customerBookings().catchError((_) => <BookingModel>[]),
        api.myDisputes().catchError((_) => <dynamic>[]),
      ]);
      if (mounted) {
        setState(() {
          sessions = results[0] as List<InstantSessionModel>;
          bookings = results[1] as List<BookingModel>;
          disputes = results[2] as List<dynamic>;
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

  DateTime? _sessionDate(InstantSessionModel s) =>
      DateTime.tryParse(s.endedAt ?? s.startedAt ?? s.connectedAt ?? s.requestedAt ?? '')?.toLocal();

  bool _dateMatches(DateTime? value) {
    if (datePreset == 'ALL') return true;
    if (value == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    if (datePreset == 'TODAY') return date == today;
    final days = datePreset == '7_DAYS' ? 7 : 30;
    return !date.isBefore(today.subtract(Duration(days: days - 1))) && !date.isAfter(now);
  }

  bool _statusMatches(String raw) {
    if (status == 'ALL') return true;
    final value = raw.toUpperCase();
    if (status == 'COMPLETED') return value == 'COMPLETED';
    if (status == 'ACTIVE') {
      return const {'REQUESTED', 'ACCEPTED', 'CONNECTING', 'CONNECTED', 'ACTIVE', 'IN_PROGRESS'}.contains(value);
    }
    return const {'CANCELLED', 'CANCELLED_BY_USER', 'CANCELLED_BY_EXPERT', 'REJECTED', 'EXPIRED'}.contains(value);
  }

  List<InstantSessionModel> get filteredSessions {
    final q = search.text.trim().toLowerCase();
    final result = sessions.where((s) {
      final searchMatch = q.isEmpty ||
          s.listenerName.toLowerCase().contains(q) ||
          s.reference.toLowerCase().contains(q) ||
          (s.categorySlug ?? '').toLowerCase().contains(q);
      final modalityMatch = modality == 'ALL' || s.type == modality;
      return searchMatch && modalityMatch && _statusMatches(s.status) && _dateMatches(_sessionDate(s));
    }).toList();

    result.sort((a, b) {
      if (sortBy == 'DURATION') {
        final da = a.durationSeconds > 0 ? a.durationSeconds : a.billableSeconds;
        final db = b.durationSeconds > 0 ? b.durationSeconds : b.billableSeconds;
        return db.compareTo(da);
      }
      final ad = _sessionDate(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = _sessionDate(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return sortBy == 'OLDEST' ? ad.compareTo(bd) : bd.compareTo(ad);
    });
    return result;
  }

  List<BookingModel> get filteredBookings {
    final q = search.text.trim().toLowerCase();
    final result = bookings.where((b) {
      final mappedType = b.consultationType.toUpperCase().contains('VIDEO')
          ? 'VIDEO_CALL'
          : b.consultationType.toUpperCase().contains('CHAT')
              ? 'CHAT'
              : 'AUDIO_CALL';
      final searchMatch = q.isEmpty ||
          b.expertName.toLowerCase().contains(q) ||
          b.bookingReference.toLowerCase().contains(q) ||
          b.agenda.toLowerCase().contains(q);
      return searchMatch &&
          (modality == 'ALL' || modality == mappedType) &&
          _statusMatches(b.status) &&
          _dateMatches((b.endTime ?? b.startTime ?? b.createdAt)?.toLocal());
    }).toList();
    result.sort((a, b) {
      if (sortBy == 'DURATION') return b.durationMinutes.compareTo(a.durationMinutes);
      final ad = (a.endTime ?? a.startTime ?? a.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = (b.endTime ?? b.startTime ?? b.createdAt) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return sortBy == 'OLDEST' ? ad.compareTo(bd) : bd.compareTo(ad);
    });
    return result;
  }

  void _showFilterModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 28 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Filter Sessions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textDark)),
                  TextButton(
                    onPressed: () {
                      search.clear();
                      setState(() {
                        modality = 'ALL';
                        status = 'ALL';
                        sortBy = 'NEWEST';
                        datePreset = 'ALL';
                      });
                      Navigator.pop(ctx);
                    },
                    child: const Text('Reset', style: TextStyle(color: primaryOrange, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: modality,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const {
                        'ALL': 'All types',
                        'AUDIO_CALL': 'Audio call',
                        'VIDEO_CALL': 'Video call',
                        'CHAT': 'Chat',
                      }.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) {
                        setSheetState(() => modality = v ?? 'ALL');
                        setState(() => modality = v ?? 'ALL');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const {
                        'ALL': 'All status',
                        'COMPLETED': 'Completed',
                        'ACTIVE': 'Active',
                        'CANCELLED': 'Cancelled',
                      }.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) {
                        setSheetState(() => status = v ?? 'ALL');
                        setState(() => status = v ?? 'ALL');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: datePreset,
                      decoration: const InputDecoration(labelText: 'Date'),
                      items: const {
                        'ALL': 'All time',
                        'TODAY': 'Today',
                        '7_DAYS': 'Last 7 days',
                        '30_DAYS': 'Last 30 days',
                      }.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) {
                        setSheetState(() => datePreset = v ?? 'ALL');
                        setState(() => datePreset = v ?? 'ALL');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: sortBy,
                      decoration: const InputDecoration(labelText: 'Sort'),
                      items: const {
                        'NEWEST': 'Latest first',
                        'OLDEST': 'Oldest first',
                        'DURATION': 'Longest duration',
                      }.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) {
                        setSheetState(() => sortBy = v ?? 'NEWEST');
                        setState(() => sortBy = v ?? 'NEWEST');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetySupportScreen(initialTab: 2)));
                    },
                    icon: const Icon(Icons.support_agent_outlined, size: 16, color: primaryOrange),
                    label: const Text('Support inquiries', style: TextStyle(color: textDark, fontSize: 13)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetySupportScreen(initialTab: 0)));
                    },
                    icon: const Icon(Icons.block_outlined, size: 16, color: primaryOrange),
                    label: const Text('Blocked listeners', style: TextStyle(color: textDark, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryOrange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: bgCream,
        body: Center(child: CircularProgressIndicator(color: primaryOrange)),
      );
    }

    final activeCount = filteredSessions.length;

    return Scaffold(
      backgroundColor: bgCream,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subtitle under App Bar matching Screenshot 3
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Text(
                'Your calling history',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textMuted,
                ),
              ),
            ),

            // Search Bar with Filter Icon matching Screenshot 3
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: borderWarm),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 14, right: 8),
                      child: Icon(Icons.search_rounded, color: primaryOrange, size: 22),
                    ),
                    Expanded(
                      child: TextField(
                        controller: search,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 13.5),
                        decoration: const InputDecoration(
                          hintText: 'Search by listener name or session ID…',
                          hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.normal),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                          filled: false,
                        ),
                      ),
                    ),
                    if (search.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18, color: textMuted),
                        onPressed: () => search.clear(),
                      ),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, color: primaryOrange, size: 20),
                      tooltip: 'Filter',
                      onPressed: _showFilterModal,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),



            const SizedBox(height: 12),

            // Matching count & Sort dropdown matching Screenshot 3
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$activeCount matching sessions',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: textMuted,
                    ),
                  ),
                  PopupMenuButton<String>(
                    elevation: 3,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: borderWarm),
                    ),
                    onSelected: (v) => setState(() => sortBy = v),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          sortBy == 'DURATION'
                              ? 'Longest first'
                              : sortBy == 'OLDEST'
                                  ? 'Oldest first'
                                  : 'Latest first',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: primaryOrange,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: primaryOrange),
                      ],
                    ),
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'NEWEST', child: Text('Latest first')),
                      PopupMenuItem(value: 'OLDEST', child: Text('Oldest first')),
                      PopupMenuItem(value: 'DURATION', child: Text('Longest duration')),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Instant Sessions List
            Expanded(
              child: RefreshIndicator(
                color: primaryOrange,
                onRefresh: _load,
                child: _instantList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // INSTANT SESSIONS LIST (Screenshot 3)
  // ==========================================
  Widget _instantList() {
    final rows = filteredSessions;
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(
            child: Text(
              'No instant sessions match these filters.',
              style: TextStyle(color: textMuted, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 90),
      itemCount: rows.length,
      itemBuilder: (ctx, i) {
        final s = rows[i];
        final isCompleted = s.status.toUpperCase() == 'COMPLETED';
        final isAudio = s.type == 'AUDIO_CALL';
        final isVideo = s.type == 'VIDEO_CALL';
        final date = _sessionDate(s);
        final dateStr = date == null ? '' : DateFormat('dd MMM yyyy, h:mm a').format(date);
        final durationMin = s.durationSeconds > 0 ? (s.durationSeconds / 60).ceil() : s.billableMinutes;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderWarm),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _instantDetails(s),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Icon Circle matching Screenshot 3
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: softPeach,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isVideo
                            ? Icons.videocam_rounded
                            : isAudio
                                ? Icons.phone_rounded
                                : Icons.chat_bubble_rounded,
                        color: primaryOrange,
                        size: 20,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Middle details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.listenerName,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: textDark,
                            ),
                          ),
                          const SizedBox(height: 3),

                          // Sub-row: dot + TYPE + dot + STATUS
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: primaryOrange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                s.type.replaceAll('_', ' '),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: textMuted,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 3,
                                height: 3,
                                decoration: const BoxDecoration(
                                  color: textMuted,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                s.status.replaceAll('_', ' '),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isCompleted ? primaryOrange : textMuted,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 3),

                          // Session ID and date
                          Text(
                            '${s.reference}${dateStr.isEmpty ? '' : ' • $dateStr'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Right side: duration, price, chevron
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time_rounded, size: 12.5, color: textMuted),
                            const SizedBox(width: 3),
                            Text(
                              '$durationMin min',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${s.grossAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: primaryOrange,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(width: 8),

                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: softPeach,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.chevron_right_rounded, color: primaryOrange, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // SCHEDULED CONSULTATIONS LIST
  // ==========================================
  // ignore: unused_element
  Widget _bookingList() {
    final rows = filteredBookings;
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(
            child: Text(
              'No scheduled consultations match these filters.',
              style: TextStyle(color: textMuted, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 90),
      itemCount: rows.length,
      itemBuilder: (ctx, i) {
        final b = rows[i];
        final when = b.startTime == null ? '' : DateFormat('dd MMM yyyy, h:mm a').format(b.startTime!.toLocal());

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderWarm),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      b.expertName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: textDark),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: softPeach,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCDFD5)),
                    ),
                    child: Text(
                      b.status.replaceAll('_', ' '),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: primaryOrange),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${b.bookingReference}${when.isEmpty ? '' : ' • $when'}',
                style: const TextStyle(fontSize: 12, color: textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                '${b.consultationType} • ${b.durationMinutes} min${b.capturedAmount > 0 ? ' • Charged ₹${b.capturedAmount.toStringAsFixed(2)}' : ''}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: textDark),
              ),
              if (b.agenda.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Agenda: ${b.agenda}', style: const TextStyle(fontSize: 12, color: textMuted)),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (b.isJoinable)
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => BookingCallScreen(booking: b, callerSide: true)));
                        await _load();
                      },
                      icon: const Icon(Icons.video_call_rounded, size: 16),
                      label: const Text('Reconnect / Join', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      style: FilledButton.styleFrom(backgroundColor: primaryOrange),
                    ),
                  if (!const {'COMPLETED', 'IN_PROGRESS', 'CANCELLED_BY_USER', 'CANCELLED_BY_EXPERT', 'EXPIRED'}.contains(b.status))
                    OutlinedButton.icon(
                      onPressed: () => _cancelBooking(b),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel', style: TextStyle(fontSize: 12.5)),
                    ),
                  if (b.isCompleted) ...[
                    OutlinedButton.icon(
                      onPressed: () => _bookingReceipt(b),
                      icon: const Icon(Icons.receipt_long_rounded, size: 16),
                      label: const Text('Receipt', style: TextStyle(fontSize: 12.5)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _dispute(b),
                      icon: const Icon(Icons.report_problem_outlined, size: 16),
                      label: const Text('Report', style: TextStyle(fontSize: 12.5)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _blockBookingListener(b),
                      icon: const Icon(Icons.block_rounded, size: 16),
                      label: const Text('Block', style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // BOOKING DIALOGS & ACTIONS
  // ==========================================
  Future<void> _cancelBooking(BookingModel b) async {
    final reason = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Cancel Consultation', style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
        content: TextField(controller: reason, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Cancellation reason')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep Booking', style: TextStyle(color: textMuted))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, reason.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: primaryOrange),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    reason.dispose();
    if (value == null || value.isEmpty) return;
    try {
      await context.read<AppController>().api.cancelBooking(b.id, value);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _bookingReceipt(BookingModel b) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Consultation Receipt', style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _receiptLine('Reference', b.bookingReference),
            _receiptLine('Listener', b.expertName),
            _receiptLine('Type', b.consultationType),
            _receiptLine('Duration', '${b.durationMinutes} min'),
            _receiptLine('Status', b.status),
            _receiptLine('Charged', '₹${b.capturedAmount.toStringAsFixed(2)}'),
            if (b.startTime != null) _receiptLine('Started', DateFormat('dd MMM yyyy, h:mm a').format(b.startTime!.toLocal())),
            if (b.endTime != null) _receiptLine('Ended', DateFormat('dd MMM yyyy, h:mm a').format(b.endTime!.toLocal())),
          ]),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(backgroundColor: primaryOrange),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _receiptLine(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: textMuted, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 13.5))),
        ]),
      );

  Future<void> _dispute(BookingModel b) async {
    String reason = 'TECHNICAL_FAILURE';
    final details = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Report Consultation Issue', style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: reason,
                decoration: const InputDecoration(labelText: 'Reason'),
                items: const [
                  DropdownMenuItem(value: 'POOR_AUDIO_VIDEO_QUALITY', child: Text('Poor Audio / Video Quality')),
                  DropdownMenuItem(value: 'EXPERT_NO_SHOW', child: Text('Listener Did Not Show Up')),
                  DropdownMenuItem(value: 'TECHNICAL_FAILURE', child: Text('Technical Failure / Disconnection')),
                  DropdownMenuItem(value: 'INCORRECT_BILLING', child: Text('Incorrect Billing / Overcharge')),
                  DropdownMenuItem(value: 'POOR_SERVICE', child: Text('Unprofessional Conduct / Poor Service')),
                ],
                onChanged: (v) => setLocal(() => reason = v ?? reason),
              ),
              const SizedBox(height: 10),
              TextField(controller: details, minLines: 4, maxLines: 7, decoration: const InputDecoration(labelText: 'Detailed explanation')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: textMuted))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: primaryOrange),
              child: const Text('Submit Dispute'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        if (details.text.trim().isEmpty) throw Exception('Please describe what happened.');
        await context.read<AppController>().api.createDispute(bookingId: b.id, reason: reason, description: details.text.trim());
        await _load();
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
    details.dispose();
  }

  Future<void> _blockBookingListener(BookingModel b) async {
    if (!await confirm(context, 'Block ${b.expertName}?', 'This listener will be hidden from discovery and future interactions.')) return;
    try {
      await context.read<AppController>().api.blockUser(b.expertId, targetName: b.expertName, targetRole: 'EXPERT');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listener blocked.')));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // ==========================================
  // INSTANT DETAILS DIALOG
  // ==========================================
  Future<void> _instantDetails(InstantSessionModel s) async {
    final api = context.read<AppController>().api;
    List<dynamic> messages = [];
    List<dynamic> gifts = [];
    try {
      final data = await Future.wait<dynamic>([
        api.messages(s.id).catchError((_) => <dynamic>[]),
        api.sessionGifts(s.id).catchError((_) => <dynamic>[]),
      ]);
      messages = List<dynamic>.from(data[0] as List);
      gifts = List<dynamic>.from(data[1] as List);
    } catch (_) {}
    if (!mounted) return;

    final rating = ValueNotifier<int>(5);
    final comment = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      s.listenerName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: textDark),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, color: textMuted)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Session Receipt', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textDark)),
                    const SizedBox(height: 10),
                    _receiptLine('Reference', s.reference),
                    _receiptLine('Type', s.type.replaceAll('_', ' ')),
                    _receiptLine('Status', s.status),
                    _receiptLine('Rate', '₹${s.ratePerMinute.toStringAsFixed(2)}/min'),
                    _receiptLine('Billable', '${s.billableSeconds}s (${s.billableMinutes} min)'),
                    _receiptLine('Charged', '₹${s.grossAmount.toStringAsFixed(2)}'),
                    if (s.requestedAt != null) _receiptLine('Requested', _formatTimestamp(s.requestedAt)),
                    if (s.connectedAt != null) _receiptLine('Connected', _formatTimestamp(s.connectedAt)),
                    if (s.startedAt != null && s.startedAt != s.connectedAt) _receiptLine('Started', _formatTimestamp(s.startedAt)),
                    if (s.endedAt != null) _receiptLine('Ended', _formatTimestamp(s.endedAt)),
                    if ((s.notes ?? '').trim().isNotEmpty) _receiptLine('Notes', s.notes!.trim()),
                    const Divider(height: 26, color: borderWarm),
                    if (messages.isNotEmpty) ...[
                      Row(children: [
                        const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: primaryOrange),
                        const SizedBox(width: 8),
                        Text('Chat Transcript (${messages.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
                      ]),
                      const SizedBox(height: 10),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(border: Border.all(color: borderWarm), borderRadius: BorderRadius.circular(12), color: const Color(0xFFFFFBF7)),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(10),
                          itemCount: messages.length,
                          separatorBuilder: (_, __) => const Divider(height: 14, color: borderWarm),
                          itemBuilder: (_, i) {
                            final m = Map<String, dynamic>.from(messages[i] as Map);
                            final sender = '${m['senderName'] ?? m['senderRole'] ?? 'User'}';
                            final when = _formatTimestamp(m['timestamp']?.toString());
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('$sender${when.isEmpty ? '' : ' • $when'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: textMuted)),
                              const SizedBox(height: 2),
                              SelectableText('${m['text'] ?? ''}', style: const TextStyle(fontSize: 13, color: textDark)),
                            ]);
                          },
                        ),
                      ),
                      const Divider(height: 26, color: borderWarm),
                    ],
                    if (gifts.isNotEmpty) ...[
                      Row(children: [
                        const Icon(Icons.card_giftcard_rounded, size: 18, color: primaryOrange),
                        const SizedBox(width: 8),
                        Text('Gifts (${gifts.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
                      ]),
                      ...gifts.map((raw) {
                        final g = Map<String, dynamic>.from(raw as Map);
                        final amount = g['grossAmount'] is num ? (g['grossAmount'] as num).toDouble() : double.tryParse('${g['grossAmount'] ?? 0}') ?? 0;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Text('${g['giftEmoji'] ?? '🎁'}', style: const TextStyle(fontSize: 22)),
                          title: Text('${g['giftName'] ?? g['giftType'] ?? 'Gift'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: ('${g['note'] ?? ''}').trim().isEmpty ? null : Text('${g['note']}'),
                          trailing: Text('₹${amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: primaryOrange)),
                        );
                      }),
                      const Divider(height: 26, color: borderWarm),
                    ],
                    if (s.ended) ...[
                      const Text('Rate This Session', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textDark)),
                      const SizedBox(height: 4),
                      ValueListenableBuilder<int>(
                        valueListenable: rating,
                        builder: (_, v, __) => Wrap(
                          children: List.generate(
                            5,
                            (i) => IconButton(
                              onPressed: () => rating.value = i + 1,
                              icon: Icon(i < v ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFF59E0B)),
                            ),
                          ),
                        ),
                      ),
                      TextField(
                        controller: comment,
                        decoration: const InputDecoration(labelText: 'Optional review comment', hintText: 'How was your conversation?'),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () async {
                          try {
                            await context.read<AppController>().api.createReview(sessionId: s.id, rating: rating.value, comment: comment.text.trim());
                            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Review submitted.')));
                          } catch (e) {
                            if (ctx.mounted) showError(ctx, e);
                          }
                        },
                        icon: const Icon(Icons.star_rounded, size: 16),
                        label: const Text('Submit Review'),
                        style: FilledButton.styleFrom(backgroundColor: primaryOrange),
                      ),
                    ],
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _reportInstantIssue(ctx, s),
                      icon: const Icon(Icons.report_problem_outlined, size: 16),
                      label: const Text('Report issue'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _blockInstantListener(ctx, s),
                      icon: const Icon(Icons.block_rounded, size: 16),
                      label: const Text('Block'),
                    ),
                    FilledButton.icon(
                      onPressed: () => _connectAgain(ctx, s),
                      icon: const Icon(Icons.forum_outlined, size: 16),
                      label: const Text('Connect again'),
                      style: FilledButton.styleFrom(backgroundColor: primaryOrange),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    rating.dispose();
    comment.dispose();
  }

  String _formatTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    return dt == null ? raw : DateFormat('dd MMM yyyy, h:mm a').format(dt);
  }

  Future<void> _connectAgain(BuildContext dialogContext, InstantSessionModel s) async {
    try {
      final api = context.read<AppController>().api;
      ListenerCardModel? listener;
      final all = await api.allListeners();
      for (final candidate in all) {
        if (candidate.id == s.listenerId || candidate.userId == s.listenerUserId) {
          listener = candidate;
          break;
        }
      }
      if (listener == null) {
        final detail = await api.expertDetail(s.listenerId);
        listener = ListenerCardModel.fromJson({
          ...detail,
          'id': detail['id'] ?? s.listenerId,
          'userId': detail['userId'] ?? s.listenerUserId,
          'displayName': detail['displayName'] ?? s.listenerName,
          'avatarUrl': detail['avatarUrl'] ?? s.listenerAvatarUrl,
        });
      }
      if (!mounted) return;
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ListenerDetailScreen(listener: listener!)));
    } catch (e) {
      if (dialogContext.mounted) showError(dialogContext, e);
    }
  }

  Future<void> _blockInstantListener(BuildContext dialogContext, InstantSessionModel s) async {
    final id = (s.listenerUserId?.isNotEmpty == true ? s.listenerUserId : s.listenerId) ?? s.listenerId;
    if (!await confirm(dialogContext, 'Block ${s.listenerName}?', 'They will be hidden from listener discovery and future interactions.')) return;
    try {
      await context.read<AppController>().api.blockUser(id, targetName: s.listenerName, targetRole: 'EXPERT', reason: 'Blocked from session history');
      if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Listener blocked.')));
    } catch (e) {
      if (dialogContext.mounted) showError(dialogContext, e);
    }
  }

  Future<void> _reportInstantIssue(BuildContext dialogContext, InstantSessionModel s) async {
    String category = 'CALL_QUALITY';
    final subject = TextEditingController(text: 'Issue with session ${s.reference}');
    final message = TextEditingController();
    final email = TextEditingController(text: context.read<AppController>().user?.email ?? '');
    final submit = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Report Session Issue', style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const ['CALL_QUALITY', 'BILLING', 'LISTENER_BEHAVIOR', 'TECHNICAL', 'FEEDBACK', 'OTHER']
                    .map((x) => DropdownMenuItem(value: x, child: Text(x.replaceAll('_', ' '))))
                    .toList(),
                onChanged: (v) => setLocal(() => category = v ?? category),
              ),
              const SizedBox(height: 8),
              TextField(controller: subject, decoration: const InputDecoration(labelText: 'Subject')),
              const SizedBox(height: 8),
              TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Contact email')),
              const SizedBox(height: 8),
              TextField(controller: message, minLines: 4, maxLines: 7, decoration: const InputDecoration(labelText: 'What happened?')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: textMuted))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: primaryOrange),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (submit == true) {
      try {
        final mail = email.text.trim();
        if (subject.text.trim().isEmpty || message.text.trim().isEmpty) throw Exception('Please add a subject and describe the issue.');
        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(mail)) throw Exception('Enter a valid contact email.');
        await context.read<AppController>().api.submitInquiry({
          'subject': subject.text.trim(),
          'category': category,
          'message': 'Session ${s.reference} (${s.type}): ${message.text.trim()}',
          'contactEmail': mail,
        });
        if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Support inquiry submitted.')));
      } catch (e) {
        if (dialogContext.mounted) showError(dialogContext, e);
      }
    }
    subject.dispose();
    message.dispose();
    email.dispose();
  }
}

// ignore: unused_element
class _HistoryTabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HistoryTabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  colors: [AppTheme.primaryOrange, AppTheme.secondaryOrange],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryOrange.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
              color: selected ? Colors.white : AppTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
