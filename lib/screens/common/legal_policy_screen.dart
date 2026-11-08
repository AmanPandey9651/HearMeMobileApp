import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';

class LegalPolicyScreen extends StatefulWidget {
  final int initialTab; // 0: Privacy Policy, 1: Terms of Service, 2: Refund & Cancellation
  const LegalPolicyScreen({super.key, this.initialTab = 0});

  @override
  State<LegalPolicyScreen> createState() => _LegalPolicyScreenState();
}

class _LegalPolicyScreenState extends State<LegalPolicyScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _policiesData;

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _fetchPolicies();
  }

  void _fetchPolicies() async {
    try {
      final client = ApiClient();
      final res = await client.get('/config/legal-policies');
      if (res is Map && mounted) {
        setState(() {
          _policiesData = Map<String, dynamic>.from(res);
        });
      }
    } catch (e) {
      debugPrint('Failed to load dynamic policies: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openWebVersion(int tabIndex) async {
    String url = 'https://www.feelback.in/privacy-policy';
    if (tabIndex == 1) url = 'https://www.feelback.in/terms-of-service';
    if (tabIndex == 2) url = 'https://www.feelback.in/refund-policy';

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  IconData _resolveIcon(String? iconName) {
    switch (iconName?.toLowerCase()) {
      case 'lock': return Icons.lock_rounded;
      case 'eye-off': case 'eye_off': return Icons.visibility_off_rounded;
      case 'mic-off': case 'mic_off': return Icons.mic_off_rounded;
      case 'trash': return Icons.delete_forever_rounded;
      case 'alert': return Icons.warning_amber_rounded;
      case 'clock': return Icons.schedule_rounded;
      case 'refresh': return Icons.published_with_changes_rounded;
      case 'dollar': return Icons.account_balance_wallet_rounded;
      case 'scale': case 'gavel': return Icons.gavel_rounded;
      case 'heart': return Icons.favorite_rounded;
      case 'shield': default: return Icons.shield_rounded;
    }
  }

  Color _resolveColor(String? hex, [Color fallback = primaryOrange]) {
    if (hex == null || hex.isEmpty) return fallback;
    try {
      String cleanHex = hex.replaceAll('#', '');
      if (cleanHex.length == 6) cleanHex = 'FF$cleanHex';
      return Color(int.parse('0x$cleanHex'));
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgCream,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: textDark, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Legal & Compliance',
          style: TextStyle(
            color: textDark,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _openWebVersion(_tabController.index),
            icon: const Icon(Icons.open_in_browser_rounded, size: 18, color: primaryOrange),
            label: const Text(
              'Web View',
              style: TextStyle(color: primaryOrange, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: primaryOrange,
          unselectedLabelColor: textMuted,
          indicatorColor: primaryOrange,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Privacy Policy'),
            Tab(text: 'Terms of Service'),
            Tab(text: 'Refund Policy'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPrivacyTab(),
          _buildTermsTab(),
          _buildRefundTab(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 1: PRIVACY POLICY
  // -------------------------------------------------------------
  Widget _buildPrivacyTab() {
    final policy = _policiesData?['privacyPolicy'];
    final dynamicSections = policy != null && policy['sections'] is List ? policy['sections'] as List : null;

    if (dynamicSections != null && dynamicSections.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          _buildPillHeader(
            icon: Icons.shield_rounded,
            badge: policy['badge'] ?? 'DPDP Act 2023 Compliant',
            badgeColor: _resolveColor(policy['badgeColor'], const Color(0xFF10B981)),
            title: policy['title'] ?? 'Privacy Policy & Zero-PII Declaration',
            subtitle: policy['subtitle'] ?? 'Last updated: October 18, 2026 • GrimByte Technologies Private Limited',
          ),
          const SizedBox(height: 16),
          for (final sec in dynamicSections) ...[
            _buildCard(
              title: sec['title'] ?? '',
              icon: _resolveIcon(sec['icon']),
              iconColor: _resolveColor(sec['iconColor'], Colors.redAccent),
              content: sec['content'] ?? '',
            ),
            const SizedBox(height: 12),
          ],
          if (policy['grievance'] != null)
            _buildDynamicGrievanceCard(Map<String, dynamic>.from(policy['grievance']))
          else
            _buildGrievanceCard(),
        ],
      );
    }

    // Default Fallback
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildPillHeader(
          icon: Icons.shield_rounded,
          badge: 'DPDP Act 2023 Compliant',
          badgeColor: const Color(0xFF10B981),
          title: 'Privacy Policy & Zero-PII Declaration',
          subtitle: 'Last updated: October 18, 2026 • GrimByte Technologies Private Limited',
        ),
        const SizedBox(height: 16),

        _buildCard(
          title: '1. Strict Zero Call Recording Architecture',
          icon: Icons.mic_off_rounded,
          iconColor: Colors.redAccent,
          content: 'All voice and video sessions utilize transient peer-to-peer WebRTC connections secured with DTLS/SRTP encryption. Media streams flow directly in-flight between participants.\n\n'
              'FeelBack does NOT record, listen to, tap, analyze, transcribe, or store audio/video conversations on any server. Once your session ends, the transient media stream disappears permanently.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '2. 100% Zero-PII Caller Isolation',
          icon: Icons.visibility_off_rounded,
          iconColor: primaryOrange,
          content: 'Your privacy is protected by design:\n'
              '• Listeners never see your phone number, real name, email, or physical location.\n'
              '• You interact solely under a chosen pseudonym or nickname.\n'
              '• No GSM/PSTN telephony bridging is used, eliminating any risk of caller-ID exposure.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '3. Account & Data Deletion (Play Store SLA)',
          icon: Icons.delete_forever_rounded,
          iconColor: Colors.deepPurple,
          content: 'In compliance with Google Play Store & Apple App Store user data policies, you have the absolute right to delete your account.\n\n'
              'To purge all your data:\n'
              '1. Email feelback.help@gmail.com with subject "Request Account Deletion" stating your phone or email, OR\n'
              '2. Submit a request inside Safety & Support screen.\n\n'
              '✓ SLA Guarantee: Your account credentials, auth tokens, and profile will be permanently erased from our primary database within 48 hours.',
        ),
        const SizedBox(height: 12),

        _buildGrievanceCard(),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 2: TERMS OF SERVICE
  // -------------------------------------------------------------
  Widget _buildTermsTab() {
    final policy = _policiesData?['termsOfService'];
    final dynamicSections = policy != null && policy['sections'] is List ? policy['sections'] as List : null;

    if (dynamicSections != null && dynamicSections.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          _buildPillHeader(
            icon: Icons.gavel_rounded,
            badge: policy['badge'] ?? 'Legally Binding Agreement',
            badgeColor: _resolveColor(policy['badgeColor'], const Color(0xFF6366F1)),
            title: policy['title'] ?? 'Terms of Service & Community Rules',
            subtitle: policy['subtitle'] ?? 'Jurisdiction: Prayagraj, Uttar Pradesh, India',
          ),
          const SizedBox(height: 16),
          for (final sec in dynamicSections) ...[
            _buildCard(
              title: sec['title'] ?? '',
              icon: _resolveIcon(sec['icon']),
              iconColor: _resolveColor(sec['iconColor'], const Color(0xFF6366F1)),
              content: sec['content'] ?? '',
            ),
            const SizedBox(height: 12),
          ],
          if (policy['grievance'] != null)
            _buildDynamicGrievanceCard(Map<String, dynamic>.from(policy['grievance']))
          else
            _buildGrievanceCard(),
        ],
      );
    }

    // Default Fallback
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildPillHeader(
          icon: Icons.gavel_rounded,
          badge: 'Legally Binding Agreement',
          badgeColor: const Color(0xFF6366F1),
          title: 'Terms of Service & Community Rules',
          subtitle: 'Jurisdiction: Prayagraj, Uttar Pradesh, India',
        ),
        const SizedBox(height: 16),

        _buildCard(
          title: '1. Peer Support Only — Not Therapy or Medical Advice',
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.amber.shade800,
          content: 'FeelBack is a platform connecting users with compassionate peer listeners for venting, emotional companionship, and daily conversation.\n\n'
              '⚠️ IMPORTANT: Listeners on FeelBack are NOT licensed therapists, clinical psychologists, psychiatrists, medical doctors, or crisis emergency responders. If you are experiencing suicidal thoughts, self-harm impulses, or medical emergencies, please immediately call 112 or national emergency helplines.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '2. Zero Harassment & Prohibited Conduct',
          icon: Icons.block_rounded,
          iconColor: Colors.red,
          content: 'To ensure a safe environment for everyone, the following conduct will lead to immediate account termination:\n'
              '• No abusive, threatening, obscene, sexually explicit, or harassing language.\n'
              '• No sharing or solicitation of external contact numbers, social media handles, or offline meetings.\n'
              '• No financial solicitation or attempts to transact outside the FeelBack wallet.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '3. Pay-Per-Minute Transparent Billing',
          icon: Icons.account_balance_wallet_rounded,
          iconColor: const Color(0xFF10B981),
          content: 'Calls are billed per minute from your prepaid wallet at the listener\'s posted rate.\n'
              '• Billing begins only after call connection is established.\n'
              '• A 60-second grace window applies: calls ended within 60 seconds are not charged.\n'
              '• When your wallet balance depletes, the call automatically disconnects with zero negative balance.',
        ),
        const SizedBox(height: 12),

        _buildGrievanceCard(),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 3: REFUND POLICY
  // -------------------------------------------------------------
  Widget _buildRefundTab() {
    final policy = _policiesData?['refundPolicy'];
    final dynamicSections = policy != null && policy['sections'] is List ? policy['sections'] as List : null;

    if (dynamicSections != null && dynamicSections.isNotEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [
          _buildPillHeader(
            icon: Icons.account_balance_wallet_rounded,
            badge: policy['badge'] ?? 'Razorpay Gateway Compliant',
            badgeColor: _resolveColor(policy['badgeColor'], const Color(0xFF10B981)),
            title: policy['title'] ?? 'Refund, Cancellation & Billing Policy',
            subtitle: policy['subtitle'] ?? 'Payment Aggregator: Razorpay Software Pvt. Ltd.',
          ),
          const SizedBox(height: 16),
          for (final sec in dynamicSections) ...[
            _buildCard(
              title: sec['title'] ?? '',
              icon: _resolveIcon(sec['icon']),
              iconColor: _resolveColor(sec['iconColor'], const Color(0xFF0284C7)),
              content: sec['content'] ?? '',
            ),
            const SizedBox(height: 12),
          ],
          if (policy['grievance'] != null)
            _buildDynamicGrievanceCard(Map<String, dynamic>.from(policy['grievance']))
          else
            _buildGrievanceCard(),
        ],
      );
    }

    // Default Fallback
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildPillHeader(
          icon: Icons.account_balance_wallet_rounded,
          badge: 'Razorpay Gateway Compliant',
          badgeColor: const Color(0xFF10B981),
          title: 'Refund, Cancellation & Billing Policy',
          subtitle: 'Payment Aggregator: Razorpay Software Pvt. Ltd.',
        ),
        const SizedBox(height: 16),

        _buildCard(
          title: '1. 60-Second Automatic Call Drop Protection',
          icon: Icons.timer_rounded,
          iconColor: const Color(0xFF0284C7),
          content: 'If a call drops or is disconnected within the first 60 seconds due to network fluctuation, bad audio, or wrong connection, you are charged ₹0. Any held amount is instantly released back to your wallet.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '2. Unspent Wallet Top-up Refunds',
          icon: Icons.currency_rupee_rounded,
          iconColor: const Color(0xFF16A34A),
          content: 'Unspent funds in your FeelBack prepaid wallet can be refunded back to your original source of payment (UPI, Bank Account, Credit/Debit Card) upon request.\n\n'
              '• Simply contact feelback.help@gmail.com with your registered account details.\n'
              '• Refunds are processed through Razorpay payment gateway within 5 to 7 working days.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '3. Technical Glitches & Quality Disputes',
          icon: Icons.support_agent_rounded,
          iconColor: Colors.deepPurple,
          content: 'In rare cases of call degradation (e.g. one-way audio, silent listener, or server drop), users can submit a ticket directly under Safety & Support screen within 24 hours. Once verified against our telemetry logs, the spent session minutes will be re-credited to your wallet.',
        ),
        const SizedBox(height: 12),

        _buildGrievanceCard(),
      ],
    );
  }

  // -------------------------------------------------------------
  // REUSABLE BUILDERS
  // -------------------------------------------------------------
  Widget _buildPillHeader({
    required IconData icon,
    required String badge,
    required Color badgeColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderWarm),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: badgeColor),
                const SizedBox(width: 6),
                Text(
                  badge,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderWarm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicGrievanceCard(Map<String, dynamic> grievance) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 18),
              const SizedBox(width: 8),
              Text(
                grievance['title'] ?? 'Official Grievance Officer & Contact',
                style: const TextStyle(
                  color: Color(0xFF15803D),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Entity: GrimByte Technologies Private Limited\n'
            'Officer: ${grievance['officerName'] ?? 'Aman Pandey'}\n'
            'Address: ${grievance['address'] ?? 'Prayagraj, UP, India'}\n'
            'Email: ${grievance['email'] ?? 'feelback.help@gmail.com'}\n'
            'SLA: ${grievance['responseSla'] ?? 'Within 48 hours.'}',
            style: const TextStyle(
              color: Color(0xFF166534),
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrievanceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 18),
              SizedBox(width: 8),
              Text(
                'Official Grievance Officer & Contact',
                style: TextStyle(
                  color: Color(0xFF15803D),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Entity: GrimByte Technologies Private Limited\n'
            'Grievance Officer: Aman Pandey\n'
            'Address: Trivenipuram, Jhunsi, Prayagraj, UP 211019, India\n'
            'Email: feelback.help@gmail.com\n'
            'Website: https://www.feelback.in',
            style: TextStyle(
              color: Color(0xFF166534),
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}