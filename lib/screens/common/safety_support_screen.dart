import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../main.dart';
import '../../widgets/common_widgets.dart';

class SafetySupportScreen extends StatefulWidget {
  final int initialTab;
  const SafetySupportScreen({super.key, this.initialTab = 0});

  @override
  State<SafetySupportScreen> createState() => _SafetySupportScreenState();
}

class _SafetySupportScreenState extends State<SafetySupportScreen> {
  int currentTab = 1; // 0: Blocked, 1: Block history (as in Image 3), 2: Support inquiries
  final searchController = TextEditingController();
  String inquiryStatus = 'ALL';

  List<dynamic> blocks = [];
  List<dynamic> history = [];
  List<dynamic> inquiries = [];
  bool loading = true;

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

  List<dynamic> get filteredBlocks {
    final q = searchController.text.trim().toLowerCase();
    if (q.isEmpty) return blocks;
    return blocks.where((x) {
      if (x is String) return x.toLowerCase().contains(q);
      if (x is! Map) return false;
      final m = Map<String, dynamic>.from(x);
      return '${m['blockedName'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['blockedRole'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['reason'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  List<dynamic> get filteredHistory {
    final q = searchController.text.trim().toLowerCase();
    if (q.isEmpty) return history;
    return history.where((x) {
      if (x is! Map) return false;
      final m = Map<String, dynamic>.from(x);
      return '${m['blockedName'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['blockerName'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['reason'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['action'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  List<dynamic> get filteredInquiries {
    final q = searchController.text.trim().toLowerCase();
    return inquiries.where((x) {
      if (x is! Map) return false;
      final m = Map<String, dynamic>.from(x);
      final statusOk = inquiryStatus == 'ALL' || '${m['status'] ?? ''}' == inquiryStatus;
      final qOk = q.isEmpty ||
          '${m['subject'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['message'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['category'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['adminReply'] ?? ''}'.toLowerCase().contains(q);
      return statusOk && qOk;
    }).toList();
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
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Contact Support', style: TextStyle(fontWeight: FontWeight.w800, color: textDark)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (formError != null)
                  FormErrorBanner(
                    message: formError,
                    onDismiss: () => setLocal(() => formError = null),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  items: const ['CALL_QUALITY', 'BILLING', 'LISTENER_BEHAVIOR', 'TECHNICAL', 'FEEDBACK', 'OTHER']
                      .map((x) => DropdownMenuItem(value: x, child: Text(x.replaceAll('_', ' '))))
                      .toList(),
                  onChanged: (v) => setLocal(() => category = v ?? 'OTHER'),
                  decoration: InputDecoration(
                    labelText: 'Category',
                    filled: true,
                    fillColor: bgCream,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: subject,
                  decoration: InputDecoration(
                    labelText: 'Subject / Summary',
                    filled: true,
                    fillColor: bgCream,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Contact Email *',
                    filled: true,
                    fillColor: bgCream,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderWarm)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: message,
                  minLines: 4,
                  maxLines: 7,
                  decoration: InputDecoration(
                    labelText: 'Detailed message',
                    filled: true,
                    fillColor: bgCream,
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
              ),
              onPressed: () async {
                final mail = email.text.trim();
                if (subject.text.trim().isEmpty || message.text.trim().isEmpty) {
                  setLocal(() => formError = 'Please provide a subject and detailed message.');
                  return;
                }
                if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(mail)) {
                  setLocal(() => formError = 'Enter a valid contact email.');
                  return;
                }
                setLocal(() => formError = null);
                try {
                  await context.read<AppController>().api.submitInquiry({
                    'subject': subject.text.trim(),
                    'category': category,
                    'message': message.text.trim(),
                    'contactEmail': mail,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _load();
                } catch (e) {
                  if (ctx.mounted) {
                    setLocal(() => formError = sanitizeErrorMessage(e));
                  }
                }
              },
              child: const Text('Submit', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    subject.dispose();
    message.dispose();
    email.dispose();
  }

  String _fmt(dynamic value) {
    if (value == null) return '';
    final dt = DateTime.tryParse('$value')?.toLocal();
    if (dt == null) return '$value';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = currentTab == 0
        ? 'Search blocked users'
        : currentTab == 1
            ? 'Search block history'
            : 'Search inquiries';

    return Scaffold(
      backgroundColor: bgCream,
      body: Stack(
        children: [
          // Top-right peach ambient glow orb
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
                // Top Header matching Image 3
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 18, 12),
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
                      const Text(
                        'Safety & Support',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),

                // 1. Segmented Pill Tabs matching Image 3
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
                        _buildTabPill('Blocked', 0),
                        _buildTabPill('Block history', 1),
                        _buildTabPill('Support inquiries', 2),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Search Bar matching Image 3
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
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
                      controller: searchController,
                      style: const TextStyle(color: textDark, fontSize: 14, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: placeholder,
                        hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                        prefixIcon: const Icon(Icons.search_rounded, color: primaryOrange, size: 22),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18, color: textMuted),
                                onPressed: () => searchController.clear(),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Content Views
                Expanded(
                  child: loading
                      ? const LoadingBody()
                      : RefreshIndicator(
                          color: primaryOrange,
                          onRefresh: _load,
                          child: currentTab == 1
                              ? _buildBlockHistoryList()
                              : currentTab == 0
                                  ? _buildBlockedList()
                                  : _buildInquiriesList(),
                        ),
                ),
              ],
            ),
          ),

          // Floating Support Pill Button at Bottom Right matching Image 3
          Positioned(
            right: 20,
            bottom: 24,
            child: Material(
              elevation: 4,
              shadowColor: primaryOrange.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(28),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryOrange, secondaryOrange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: _newInquiry,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.headset_mic_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Support',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(String title, int index) {
    final isSelected = currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            currentTab = index;
            searchController.clear();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [primaryOrange, secondaryOrange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: primaryOrange.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF6B7280),
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 1. Block History List matching Image 3
  Widget _buildBlockHistoryList() {
    final list = filteredHistory;

    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderWarm),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.history_rounded, size: 48, color: Color(0xFFD1D5DB)),
                  SizedBox(height: 12),
                  Text('No block history', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: textDark)),
                  SizedBox(height: 4),
                  Text('Audit records of blocks and unblocks will appear here.', style: TextStyle(color: textMuted, fontSize: 13), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 90),
      itemCount: list.length,
      itemBuilder: (context, idx) {
        final m = Map<String, dynamic>.from(list[idx] as Map);
        final action = '${m['action'] ?? ''}'.toUpperCase();
        final isUnblocked = action.contains('UNBLOCK');
        final targetName = '${m['blockedName'] ?? m['targetName'] ?? 'Anonymous'}';
        final reason = '${m['reason'] ?? (isUnblocked ? 'User unblocked connection' : 'Blocked by user')}';
        final timeStr = _fmt(m['createdAt']);
        final role = '${m['blockedRole'] ?? 'CUSTOMER'}'.toUpperCase();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon Container on left (Padlock for unblock, Red Ban for block)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isUnblocked ? softPeach : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(
                    isUnblocked ? Icons.lock_open_rounded : Icons.block_rounded,
                    color: isUnblocked ? primaryOrange : const Color(0xFFEF4444),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Center Column: You unblocked / blocked + Name + Reason + Timestamp
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: isUnblocked ? 'You unblocked ' : 'You blocked ',
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: targetName,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 13, color: textMuted),
                        const SizedBox(width: 5),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Right Column: Pill Badge "CUSTOMER" + 3-dots menu
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: softPeach,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      role.contains('EXPERT') || role.contains('LISTENER') ? 'LISTENER' : 'CUSTOMER',
                      style: const TextStyle(
                        color: primaryOrange,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.more_vert_rounded, color: textMuted, size: 18),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 2. Currently Blocked List
  Widget _buildBlockedList() {
    final list = filteredBlocks;

    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderWarm),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.shield_outlined, size: 48, color: Color(0xFFD1D5DB)),
                  SizedBox(height: 12),
                  Text('No blocked users', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: textDark)),
                  SizedBox(height: 4),
                  Text('Users you block will appear here. You can unblock them anytime.', style: TextStyle(color: textMuted, fontSize: 13), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 90),
      itemCount: list.length,
      itemBuilder: (context, idx) {
        final item = list[idx];
        String id = '';
        String name = 'User';
        String reason = 'Blocked user';
        String role = 'CUSTOMER';

        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          id = '${m['blockedUserId'] ?? m['id'] ?? ''}';
          name = '${m['blockedName'] ?? m['name'] ?? 'User'}';
          reason = '${m['reason'] ?? 'Blocked user'}';
          role = '${m['blockedRole'] ?? 'CUSTOMER'}';
        } else {
          id = item.toString();
          name = 'User $id';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Icon(Icons.block_rounded, color: Color(0xFFEF4444), size: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: textDark, fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: softPeach, borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            role.contains('EXPERT') || role.contains('LISTENER') ? 'LISTENER' : 'CUSTOMER',
                            style: const TextStyle(color: primaryOrange, fontSize: 9.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: textMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: softPeach,
                  foregroundColor: primaryOrange,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: () => _unblock(id, name),
                child: const Text('Unblock', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 3. Support Inquiries List
  Widget _buildInquiriesList() {
    final list = filteredInquiries;

    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderWarm),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.support_agent_rounded, size: 48, color: Color(0xFFD1D5DB)),
                  SizedBox(height: 12),
                  Text('No support inquiries', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: textDark)),
                  SizedBox(height: 4),
                  Text('Tap the Support button below to submit a help request.', style: TextStyle(color: textMuted, fontSize: 13), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 90),
      itemCount: list.length,
      itemBuilder: (context, idx) {
        final m = Map<String, dynamic>.from(list[idx] as Map);
        final status = '${m['status'] ?? 'OPEN'}'.toUpperCase();
        final isResolved = status == 'RESOLVED' || status == 'CLOSED';
        final subject = '${m['subject'] ?? 'Inquiry'}';
        final msg = '${m['message'] ?? ''}';
        final reply = '${m['adminReply'] ?? ''}'.trim();
        final timeStr = _fmt(m['createdAt']);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      subject,
                      style: const TextStyle(color: textDark, fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isResolved ? const Color(0xFFDEF7EC) : softPeach,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: isResolved ? const Color(0xFF03543F) : primaryOrange,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                msg,
                style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13, height: 1.35),
              ),
              if (reply.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: softPeach.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primaryOrange.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Support response:',
                        style: TextStyle(color: primaryOrange, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reply,
                        style: const TextStyle(color: textDark, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 13, color: textMuted),
                  const SizedBox(width: 5),
                  Text(timeStr, style: const TextStyle(color: textMuted, fontSize: 11.5)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
