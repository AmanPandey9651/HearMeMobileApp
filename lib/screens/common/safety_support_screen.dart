import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../main.dart';
import '../../widgets/common_widgets.dart';

class SafetySupportScreen extends StatefulWidget {
  final int initialTab;
  const SafetySupportScreen({super.key, this.initialTab = 0});

  @override
  State<SafetySupportScreen> createState() => _SafetySupportScreenState();
}

class _SafetySupportScreenState extends State<SafetySupportScreen> {
  int currentTab = 0; // 0: Support & Help, 1: Safety & Blocked, 2: Crisis Helplines
  int safetySubTab = 0; // 0: Blocked Users, 1: Audit History
  final searchController = TextEditingController();
  String inquiryStatus = 'ALL';

  List<dynamic> blocks = [];
  List<dynamic> history = [];
  List<dynamic> inquiries = [];
  bool loading = true;

  static const Color bgCream = AppTheme.bgCream;
  static const Color borderWarm = AppTheme.borderWarm;
  static const Color primaryOrange = AppTheme.primaryOrange;
  static const Color softPeach = AppTheme.softPeach;
  static const Color textDark = AppTheme.textDark;
  static const Color textMuted = AppTheme.textMuted;

  @override
  void initState() {
    super.initState();
    currentTab = widget.initialTab.clamp(0, 2);
    searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    searchController.removeListener(_onSearchChanged);
    searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppController>().api;
      final result = await Future.wait<dynamic>([
        api.blockedUsers(),
        api.blockHistory(),
        api.inquiries(),
      ]);
      if (!mounted) return;
      setState(() {
        blocks = List<dynamic>.from(result[0] as List);
        history = List<dynamic>.from(result[1] as List);
        inquiries = List<dynamic>.from(result[2] as List);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _callNumber(String number) async {
    final uri = Uri.parse('tel:$number');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) showError(context, 'Unable to dial $number directly.');
      }
    } catch (e) {
      if (mounted) showError(context, 'Could not initiate call: $e');
    }
  }

  Future<void> _sendEmail(String email) async {
    final uri = Uri.parse('mailto:$email?subject=FeelBack%20Support%20Request');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) showError(context, 'Please email us at $email');
      }
    } catch (e) {
      if (mounted) showError(context, 'Could not open email app: $e');
    }
  }

  Future<void> _unblock(String targetUserId, String name) async {
    final confirmed = await confirm(
      context,
      'Unblock $name?',
      'You will be able to receive and start sessions with this user again.',
    );
    if (!confirmed) return;
    try {
      await context.read<AppController>().api.unblockUser(targetUserId);
      await _load();
      if (mounted) showSuccess(context, 'Unblocked $name successfully.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _newInquiry() async {
    final subject = TextEditingController();
    final message = TextEditingController();
    final email = TextEditingController(text: context.read<AppController>().user?.email ?? '');
    String category = 'CALL_QUALITY';
    String? formError;
    bool isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primaryOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.help_outline_rounded, color: primaryOrange, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Raise Support Ticket',
                style: TextStyle(fontWeight: FontWeight.w800, color: textDark, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (formError != null)
                  FormErrorBanner(
                    message: formError,
                    onDismiss: () => setLocal(() => formError = null),
                  ),
                const Text(
                  'Submit your query regarding billing, calls, or listener safety. Our team reviews tickets rapidly.',
                  style: TextStyle(fontSize: 12, color: textMuted),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  items: const [
                    'CALL_QUALITY',
                    'BILLING',
                    'LISTENER_BEHAVIOR',
                    'TECHNICAL',
                    'FEEDBACK',
                    'OTHER'
                  ]
                      .map((x) => DropdownMenuItem(
                            value: x,
                            child: Text(
                              x.replaceAll('_', ' '),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textDark),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setLocal(() => category = v ?? 'OTHER'),
                  decoration: InputDecoration(
                    labelText: 'Category',
                    labelStyle: const TextStyle(color: textMuted, fontSize: 12.5),
                    filled: true,
                    fillColor: bgCream,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: subject,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: textDark),
                  decoration: InputDecoration(
                    labelText: 'Subject / Summary *',
                    hintText: 'e.g. Call dropped balance discrepancy',
                    hintStyle: const TextStyle(color: textMuted, fontSize: 12),
                    labelStyle: const TextStyle(color: textMuted, fontSize: 12.5),
                    filled: true,
                    fillColor: bgCream,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textDark),
                  decoration: InputDecoration(
                    labelText: 'Contact Email *',
                    hintText: 'your.email@example.com',
                    hintStyle: const TextStyle(color: textMuted, fontSize: 12),
                    labelStyle: const TextStyle(color: textMuted, fontSize: 12.5),
                    filled: true,
                    fillColor: bgCream,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: message,
                  minLines: 3,
                  maxLines: 6,
                  style: const TextStyle(fontSize: 13, color: textDark, height: 1.4),
                  decoration: InputDecoration(
                    labelText: 'Detailed Message *',
                    hintText: 'Describe what happened. Include session reference or time if applicable.',
                    hintStyle: const TextStyle(color: textMuted, fontSize: 12),
                    labelStyle: const TextStyle(color: textMuted, fontSize: 12.5),
                    filled: true,
                    fillColor: bgCream,
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                  ),
                ),
              ],
            ),
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final mail = email.text.trim();
                      if (!mail.contains('@')) {
                        setLocal(() => formError = 'A valid email is required for responses.');
                        return;
                      }
                      if (subject.text.trim().isEmpty || message.text.trim().isEmpty) {
                        setLocal(() => formError = 'Please fill out subject and message.');
                        return;
                      }
                      setLocal(() => isSubmitting = true);
                      try {
                        await context.read<AppController>().api.submitInquiry({
                              'subject': subject.text.trim(),
                              'message': message.text.trim(),
                              'category': category,
                              'contactEmail': mail,
                            });
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _load();
                        if (mounted) showSuccess(context, 'Support inquiry submitted successfully.');
                      } catch (e) {
                        setLocal(() {
                          formError = e.toString();
                          isSubmitting = false;
                        });
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit Ticket', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  List<dynamic> get filteredBlocks {
    final q = searchController.text.trim().toLowerCase();
    if (q.isEmpty) return blocks;
    return blocks.where((x) {
      if (x is String) return x.toLowerCase().contains(q);
      if (x is! Map) return false;
      final m = Map<String, dynamic>.from(x);
      return '${m['blockedName'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['reason'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  List<dynamic> get filteredHistory {
    final q = searchController.text.trim().toLowerCase();
    if (q.isEmpty) return history;
    return history.where((x) {
      if (x is! Map) return false;
      final m = Map<String, dynamic>.from(x);
      return '${m['listenerName'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['action'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['reason'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  List<dynamic> get filteredInquiries {
    final q = searchController.text.trim().toLowerCase();
    return inquiries.where((x) {
      if (x is! Map) return false;
      final m = Map<String, dynamic>.from(x);
      final status = '${m['status'] ?? 'PENDING'}';
      if (inquiryStatus != 'ALL' && status != inquiryStatus) return false;
      if (q.isEmpty) return true;
      return '${m['subject'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['message'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['category'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  Widget _buildTabPill(String label, int index, IconData icon) {
    final active = currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            currentTab = index;
            searchController.clear();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: active ? primaryOrange : textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: active ? textDark : textMuted,
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
    return Scaffold(
      backgroundColor: bgCream,
      body: Stack(
        children: [
          // Ambient soft glowing peach backdrop
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
                // Top Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
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
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Safety & Support',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: textDark,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            '24/7 Support Desk & Helpline Directory',
                            style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Segmented Pill Navigation
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4EDE4),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Row(
                      children: [
                        _buildTabPill('Help & Tickets', 0, Icons.help_outline_rounded),
                        _buildTabPill('Safety & Blocked', 1, Icons.shield_outlined),
                        _buildTabPill('Helplines', 2, Icons.phone_in_talk_rounded),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Main Content Body
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator(color: primaryOrange))
                      : currentTab == 0
                          ? _buildSupportTab()
                          : currentTab == 1
                              ? _buildSafetyTab()
                              : _buildHelplinesTab(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= TAB 0: SUPPORT & HELP =================
  Widget _buildSupportTab() {
    final list = filteredInquiries;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        // Hero Support Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF6EE), Color(0xFFFFECE5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFD8C7)),
            boxShadow: [
              BoxShadow(
                color: primaryOrange.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_user_rounded, color: primaryOrange, size: 13),
                        SizedBox(width: 4),
                        Text(
                          '24/7 SUPPORT ACTIVE',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: primaryOrange),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'SLA < 15m',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF2E7D32)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'How can we assist you today?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: textDark, letterSpacing: -0.3),
              ),
              const SizedBox(height: 4),
              const Text(
                'Have an issue with call audio, wallet recharge, or listener behavior? Submit a ticket or email our coordinators directly.',
                style: TextStyle(fontSize: 12, color: textDark, height: 1.35),
              ),
              const SizedBox(height: 14),

              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _newInquiry,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('New Ticket', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryOrange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _sendEmail('support@feelback.in'),
                      icon: const Icon(Icons.email_outlined, size: 16, color: textDark),
                      label: const Text('Email Us', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: textDark)),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: borderWarm),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Section Title: Your Tickets
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'YOUR SUPPORT TICKETS (${inquiries.length})',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: textMuted,
                letterSpacing: 0.5,
              ),
            ),
            if (inquiries.isNotEmpty)
              InkWell(
                onTap: _newInquiry,
                child: const Text(
                  '+ Raise Another',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: primaryOrange),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Search Bar
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderWarm),
          ),
          child: TextField(
            controller: searchController,
            style: const TextStyle(fontSize: 13, color: textDark),
            decoration: const InputDecoration(
              hintText: 'Search tickets by subject, message...',
              hintStyle: TextStyle(color: textMuted, fontSize: 12.5),
              prefixIcon: Icon(Icons.search_rounded, color: textMuted, size: 18),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Status Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['ALL', 'PENDING', 'IN_REVIEW', 'RESOLVED', 'CLOSED'].map((st) {
              final active = inquiryStatus == st;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  onTap: () => setState(() => inquiryStatus = st),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: active ? primaryOrange : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: active ? primaryOrange : borderWarm),
                    ),
                    child: Text(
                      st.replaceAll('_', ' '),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.white : textDark,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),

        // Inquiries List
        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderWarm),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 40, color: textMuted.withValues(alpha: 0.4)),
                const SizedBox(height: 10),
                const Text(
                  'No support inquiries logged',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textDark),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Need assistance? Tap "New Ticket" above to reach our support team.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: textMuted),
                ),
              ],
            ),
          )
        else
          ...list.map((item) {
            final m = Map<String, dynamic>.from(item as Map);
            final status = '${m['status'] ?? 'PENDING'}';
            final subject = '${m['subject'] ?? 'Support Inquiry'}';
            final message = '${m['message'] ?? ''}';
            final category = '${m['category'] ?? 'GENERAL'}';
            final adminResponse = m['adminResponse']?.toString();
            final createdAt = m['createdAt'] != null
                ? DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(m['createdAt'].toString()).toLocal())
                : '';

            Color chipColor = const Color(0xFFF59E0B);
            Color chipBg = const Color(0xFFFEF3C7);
            if (status == 'RESOLVED') {
              chipColor = const Color(0xFF10B981);
              chipBg = const Color(0xFFD1FAE5);
            } else if (status == 'IN_REVIEW') {
              chipColor = const Color(0xFF0284C7);
              chipBg = const Color(0xFFE0F2FE);
            } else if (status == 'CLOSED') {
              chipColor = const Color(0xFF6B7280);
              chipBg = const Color(0xFFF3F4F6);
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderWarm),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          subject,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textDark),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status.replaceAll('_', ' '),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: chipColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        category.replaceAll('_', ' '),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: primaryOrange),
                      ),
                      if (createdAt.isNotEmpty) ...[
                        const Text(' • ', style: TextStyle(color: textMuted)),
                        Text(createdAt, style: const TextStyle(fontSize: 10.5, color: textMuted)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: bgCream,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      message,
                      style: const TextStyle(fontSize: 12.5, color: textDark, height: 1.35),
                    ),
                  ),
                  if (adminResponse != null && adminResponse.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.shield_outlined, size: 14, color: Color(0xFF059669)),
                              SizedBox(width: 5),
                              Text(
                                'Support Coordinator Response',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF059669)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            adminResponse,
                            style: const TextStyle(fontSize: 12, color: textDark, height: 1.35),
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
    );
  }

  // ================= TAB 1: SAFETY & BLOCKED =================
  Widget _buildSafetyTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        // Safety Policy Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFECE5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFD8C7)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.security_rounded, color: primaryOrange, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zero Tolerance for Misconduct',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: textDark),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'FeelBack enforces strict emotional boundaries. Listeners who ask for off-platform contact or act inappropriately can be blocked instantly.',
                      style: TextStyle(fontSize: 11.5, color: textDark, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Sub Toggle: Blocked vs History
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => safetySubTab = 0),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: safetySubTab == 0 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: safetySubTab == 0 ? primaryOrange : borderWarm),
                  ),
                  child: Text(
                    'Blocked Users (${blocks.length})',
                    style: TextStyle(
                      fontWeight: safetySubTab == 0 ? FontWeight.w800 : FontWeight.w600,
                      color: safetySubTab == 0 ? primaryOrange : textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => safetySubTab = 1),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: safetySubTab == 1 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: safetySubTab == 1 ? primaryOrange : borderWarm),
                  ),
                  child: Text(
                    'Audit History (${history.length})',
                    style: TextStyle(
                      fontWeight: safetySubTab == 1 ? FontWeight.w800 : FontWeight.w600,
                      color: safetySubTab == 1 ? primaryOrange : textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Search Bar
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderWarm),
          ),
          child: TextField(
            controller: searchController,
            style: const TextStyle(fontSize: 13, color: textDark),
            decoration: InputDecoration(
              hintText: safetySubTab == 0 ? 'Search blocked users...' : 'Search audit history...',
              hintStyle: const TextStyle(color: textMuted, fontSize: 12.5),
              prefixIcon: const Icon(Icons.search_rounded, color: textMuted, size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
            ),
          ),
        ),
        const SizedBox(height: 14),

        if (safetySubTab == 0) ...[
          if (filteredBlocks.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderWarm),
              ),
              child: const Column(
                children: [
                  Icon(Icons.shield_outlined, size: 40, color: Color(0xFF10B981)),
                  SizedBox(height: 10),
                  Text(
                    'No Blocked Users',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textDark),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'You have not blocked any listeners. Your connections are clear.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: textMuted),
                  ),
                ],
              ),
            )
          else
            ...filteredBlocks.map((b) {
              final m = b is Map ? Map<String, dynamic>.from(b) : {'blockedName': '$b'};
              final name = '${m['blockedName'] ?? 'Listener'}';
              final id = '${m['blockedId'] ?? m['id'] ?? ''}';
              final reason = m['reason']?.toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderWarm),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: softPeach,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'L',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: primaryOrange, fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: textDark)),
                          if (reason != null && reason.isNotEmpty)
                            Text('Reason: $reason', style: const TextStyle(fontSize: 11, color: textMuted)),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF10B981)),
                        foregroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      onPressed: () => _unblock(id, name),
                      child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5)),
                    ),
                  ],
                ),
              );
            }),
        ] else ...[
          if (filteredHistory.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderWarm),
              ),
              child: const Text('No block audit records found.', style: TextStyle(color: textMuted, fontSize: 12)),
            )
          else
            ...filteredHistory.map((h) {
              final m = Map<String, dynamic>.from(h as Map);
              final action = '${m['action'] ?? 'BLOCKED'}';
              final name = '${m['listenerName'] ?? 'Listener'}';
              final reason = m['reason']?.toString();
              final isBlock = action == 'BLOCKED';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderWarm),
                ),
                child: Row(
                  children: [
                    Icon(
                      isBlock ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                      size: 20,
                      color: isBlock ? Colors.redAccent : const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$action: $name',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: textDark),
                          ),
                          if (reason != null && reason.isNotEmpty)
                            Text(reason, style: const TextStyle(fontSize: 11, color: textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ],
    );
  }

  // ================= TAB 2: CRISIS HELPLINES =================
  Widget _buildHelplinesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
      children: [
        // Helpline Emergency Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.phone_in_talk_rounded, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '24/7 National Emergency Helplines',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textDark),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                'FeelBack is a supportive peer listening platform, not an emergency psychiatric facility. If you or someone you know is in severe emotional distress or facing an emergency, please call these verified free helplines immediately.',
                style: TextStyle(fontSize: 11.5, color: textDark, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Helpline 1: Tele-MANAS
        _buildHelplineCard(
          title: 'Tele-MANAS',
          badge: 'GOVT OF INDIA (MoHFW)',
          badgeColor: const Color(0xFF0284C7),
          badgeBg: const Color(0xFFE0F2FE),
          description: '24x7 free tele-counseling across 20+ Indian languages with qualified mental health professionals.',
          number: '14416',
          secondaryNumber: '1800-891-4416',
        ),

        // Helpline 2: KIRAN
        _buildHelplineCard(
          title: 'KIRAN Helpline',
          badge: 'MINISTRY OF SOCIAL JUSTICE',
          badgeColor: const Color(0xFFD97706),
          badgeBg: const Color(0xFFFEF3C7),
          description: '24/7 national mental health helpline for psychological first aid, stress relief, and counseling in 13 languages.',
          number: '18005990019',
          displayNumber: '1800-599-0019',
        ),

        // Helpline 3: Vandrevala Foundation
        _buildHelplineCard(
          title: 'Vandrevala Foundation',
          badge: 'FREE CRISIS COUNSELING',
          badgeColor: const Color(0xFF059669),
          badgeBg: const Color(0xFFD1FAE5),
          description: 'Free, confidential crisis counseling and suicide prevention helpline active round the clock.',
          number: '9999666555',
          displayNumber: '9999 666 555',
        ),

        // Helpline 4: National Emergency 112
        _buildHelplineCard(
          title: 'National Emergency',
          badge: 'POLICE • AMBULANCE • FIRE',
          badgeColor: Colors.redAccent,
          badgeBg: const Color(0xFFFFECE5),
          description: 'All-in-one national emergency response system across all states and union territories in India.',
          number: '112',
        ),
      ],
    );
  }

  Widget _buildHelplineCard({
    required String title,
    required String badge,
    required Color badgeColor,
    required Color badgeBg,
    required String description,
    required String number,
    String? displayNumber,
    String? secondaryNumber,
  }) {
    final showNum = displayNumber ?? number;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: badgeColor),
                ),
              ),
              const Text(
                '24x7 Active',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: textDark)),
          const SizedBox(height: 3),
          Text(description, style: const TextStyle(fontSize: 11.5, color: textMuted, height: 1.35)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _callNumber(number),
                  icon: const Icon(Icons.phone_rounded, size: 15),
                  label: Text('Call $showNum', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryOrange,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (secondaryNumber != null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _callNumber(secondaryNumber),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: borderWarm),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  child: Text(
                    secondaryNumber,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textDark),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
