import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../main.dart';
import '../../widgets/common_widgets.dart';

class ListenerReviewsScreen extends StatefulWidget {
  const ListenerReviewsScreen({super.key});

  @override
  State<ListenerReviewsScreen> createState() => _ListenerReviewsScreenState();
}

class _ListenerReviewsScreenState extends State<ListenerReviewsScreen> {
  List<dynamic> items = [];
  bool loading = true;
  String? expertId;
  String date = 'ALL';

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  final Map<String, String> dateOptions = {
    'ALL': 'All time',
    'TODAY': 'Today',
    '7_DAYS': 'Last 7 days',
    '30_DAYS': 'Last 30 days',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppController>().api;
      final p = await api.myExpertProfile();
      expertId = '${p['id']}';
      items = await api.expertReviews(expertId!, page: 0, size: 200);
      if (mounted) setState(() => loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  bool _dateOk(dynamic raw) {
    if (date == 'ALL') return true;
    final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (date == 'TODAY') return day == today;
    final count = date == '7_DAYS' ? 7 : 30;
    return !day.isBefore(today.subtract(Duration(days: count - 1))) && !day.isAfter(now);
  }

  List<dynamic> get filtered => items.where((x) {
        if (x is! Map) return false;
        return _dateOk(x['createdAt']);
      }).toList();

  Future<void> _respond(Map<String, dynamic> m) async {
    final c = TextEditingController(text: '${m['expertResponse'] ?? ''}');
    String? formError;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Respond to review', style: TextStyle(fontWeight: FontWeight.w800, color: textDark)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (formError != null)
                FormErrorBanner(
                  message: formError,
                  onDismiss: () => setLocal(() => formError = null),
                ),
              TextField(
                controller: c,
                minLines: 3,
                maxLines: 6,
                onChanged: (_) {
                  if (formError != null) setLocal(() => formError = null);
                },
                decoration: InputDecoration(
                  hintText: 'Write a thoughtful public response...',
                  filled: true,
                  fillColor: bgCream,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: borderWarm),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: borderWarm),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: primaryOrange, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: textMuted, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
              onPressed: () async {
                try {
                  if (c.text.trim().isEmpty) {
                    setLocal(() => formError = 'Enter a response first.');
                    return;
                  }
                  setLocal(() => formError = null);
                  await context.read<AppController>().api.respondToReview('${m['id']}', c.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  if (ctx.mounted) setLocal(() => formError = sanitizeErrorMessage(e));
                }
              },
              child: const Text('Post response', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    c.dispose();
  }

  void _showDateFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select review date',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textDark),
              ),
              const SizedBox(height: 12),
              ...dateOptions.entries.map((e) {
                final isSelected = date == e.key;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected ? primaryOrange : textDark,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded, color: primaryOrange)
                      : null,
                  onTap: () {
                    setState(() => date = e.key);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(dynamic raw) {
    final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    return d == null ? 'Recent' : DateFormat('dd MMM yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final rows = filtered;

    return Scaffold(
      backgroundColor: bgCream,
      body: Stack(
        children: [
          // Top-right peach ambient glow orb
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFD8C7).withValues(alpha: 0.7),
                    const Color(0xFFFFECE5).withValues(alpha: 0.35),
                    bgCream.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with back arrow, title, and speech bubbles illustration
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: textDark, size: 24),
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          } else {
                            TalkStrangersApp.navigatorKey.currentState?.maybePop();
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          'Caller reviews',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: textDark,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      // Top Right Speech Bubble Art
                      _SpeechBubbleArtwork(),
                    ],
                  ),
                ),

                Expanded(
                  child: loading
                      ? const LoadingBody()
                      : RefreshIndicator(
                          color: primaryOrange,
                          onRefresh: _load,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
                            children: [
                              // 1. Review Date Filter Card (Image 1)
                              InkWell(
                                onTap: _showDateFilterSheet,
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: borderWarm),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.03),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      // Left Calendar Outline Icon in soft peach rounded box
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: softPeach,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Center(
                                          child: Icon(Icons.calendar_today_outlined, color: primaryOrange, size: 20),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Review date',
                                              style: TextStyle(
                                                color: textMuted,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              dateOptions[date] ?? 'All time',
                                              style: const TextStyle(
                                                color: textDark,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.keyboard_arrow_down_rounded, color: textDark, size: 24),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),

                              // 2. Count text e.g. "3 of 3 reviews"
                              Text(
                                '${rows.length} of ${items.length} reviews',
                                style: const TextStyle(
                                  color: textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 3. Reviews list
                              if (rows.isEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 24),
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: borderWarm),
                                  ),
                                  child: const Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.star_outline_rounded, size: 48, color: Color(0xFFD1D5DB)),
                                        SizedBox(height: 12),
                                        Text(
                                          'No reviews yet for this filter',
                                          style: TextStyle(
                                            color: textDark,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Reviews left by callers will appear here.',
                                          style: TextStyle(color: textMuted, fontSize: 13),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              ...rows.map((x) {
                                final m = Map<String, dynamic>.from(x as Map);
                                final reply = '${m['expertResponse'] ?? ''}'.trim();
                                final rating = m['rating']?.toString() ?? '5';
                                final callerName = '${m['customerName'] ?? 'Anonymous caller'}';
                                final comment = '${m['comment'] ?? ''}'.trim();

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: borderWarm),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.03),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Top Row: Star, Rating, Dot, Caller Name
                                            Row(
                                              children: [
                                                const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 22),
                                                const SizedBox(width: 6),
                                                Text(
                                                  rating,
                                                  style: const TextStyle(
                                                    color: textDark,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                const Text(
                                                  '•',
                                                  style: TextStyle(
                                                    color: textDark,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    callerName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: textDark,
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),

                                            // Review Comment
                                            if (comment.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                comment,
                                                style: const TextStyle(
                                                  color: Color(0xFF374151),
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w500,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],

                                            // Listener Response if already provided
                                            if (reply.isNotEmpty) ...[
                                              const SizedBox(height: 10),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: softPeach.withValues(alpha: 0.6),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: primaryOrange.withValues(alpha: 0.2)),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'Your response:',
                                                      style: TextStyle(
                                                        color: primaryOrange,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      reply,
                                                      style: const TextStyle(
                                                        color: Color(0xFF4B5563),
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],

                                            // Date Row: Calendar icon + Date
                                            const SizedBox(height: 10),
                                            Row(
                                              children: [
                                                const Icon(Icons.calendar_today_outlined, size: 14, color: textMuted),
                                                const SizedBox(width: 6),
                                                Text(
                                                  _fmt(m['createdAt']),
                                                  style: const TextStyle(
                                                    color: textMuted,
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),

                                      // Reply curved action button matching Image 1
                                      Material(
                                        color: const Color(0xFFFFF1E8),
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () => _respond(m),
                                          child: const SizedBox(
                                            width: 42,
                                            height: 42,
                                            child: Center(
                                              child: Icon(
                                                Icons.reply_rounded,
                                                color: Color(0xFF4A3528),
                                                size: 22,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Artwork for the top right speech bubbles with star matching Image 1
class _SpeechBubbleArtwork extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Background soft bubble with dots
          Positioned(
            right: 0,
            top: 2,
            child: Container(
              width: 38,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFFFBF9B).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(radius: 2, backgroundColor: Colors.white),
                  SizedBox(width: 3),
                  CircleAvatar(radius: 2, backgroundColor: Colors.white),
                  SizedBox(width: 3),
                  CircleAvatar(radius: 2, backgroundColor: Colors.white),
                ],
              ),
            ),
          ),
          // Foreground bright orange bubble with yellow star
          Positioned(
            left: 2,
            bottom: 0,
            child: Container(
              width: 44,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF8543), Color(0xFFF95B3D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF95B3D).withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(Icons.star_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
          // Sparkle accent
          const Positioned(
            top: 0,
            right: 2,
            child: Icon(Icons.auto_awesome, color: Color(0xFFFFA05C), size: 14),
          ),
        ],
      ),
    );
  }
}
