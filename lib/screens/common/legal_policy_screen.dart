import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalPolicyScreen extends StatefulWidget {
  final int initialTab; // 0: Privacy Policy, 1: Terms of Service, 2: Refund & Cancellation
  const LegalPolicyScreen({super.key, this.initialTab = 0});

  @override
  State<LegalPolicyScreen> createState() => _LegalPolicyScreenState();
}

class _LegalPolicyScreenState extends State<LegalPolicyScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildPillHeader(
          icon: Icons.shield_rounded,
          badge: 'DPDP Act 2023 Compliant',
          badgeColor: const Color(0xFF10B981),
          title: 'Privacy Policy & Zero-PII Declaration',
          subtitle: 'Last updated: October 18, 2026 • FeelBack Technologies Inc.',
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
          title: '3. Data Storage & Indian Sovereignty',
          icon: Icons.cloud_done_rounded,
          iconColor: const Color(0xFF3B82F6),
          content: 'In strict compliance with India\'s Digital Personal Data Protection Act (DPDP Act 2023), all user account data, wallet ledgers, and database backups are hosted exclusively in Mumbai, India on AWS Lightsail datacenter servers with AES-256 encryption.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '4. Account & Data Deletion (Play Store SLA)',
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

        // Urgent medical disclaimer
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 22),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CRITICAL NOTICE: NOT A MEDICAL SERVICE',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'FeelBack is an emotional support and conversational venting platform. Peer listeners are NOT licensed doctors, psychologists, psychiatrists, or medical professionals. Sessions do not constitute medical advice or treatment.\n\n'
                '🚨 If you or someone you know is in crisis or having thoughts of self-harm, please contact 24/7 National Emergency Helplines immediately:\n'
                '• Tele-MANAS (Govt of India): 14416 (Toll-Free, 24/7)\n'
                '• Vandrevala Foundation: +91 9999 666 555\n'
                '• KIRAN Helpline: 1800-599-0019\n'
                '• National Emergency: 112',
                style: TextStyle(color: Color(0xFF991B1B), fontSize: 12.5, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _buildCard(
          title: '1. Eligibility & Age Requirement',
          icon: Icons.person_rounded,
          iconColor: primaryOrange,
          content: 'You must be at least 18 years of age to register or initiate calls on FeelBack. By continuing, you affirm you have the legal capacity to enter into this contract under the Indian Contract Act, 1872.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '2. Zero-Tolerance Prohibited Conduct',
          icon: Icons.block_rounded,
          iconColor: Colors.red,
          content: 'The following conduct results in immediate, permanent ban and device blocking:\n'
              '• Sexual harassment, nudity, or obscene verbal requests.\n'
              '• Screen-recording or audio-tapping calls.\n'
              '• Exchanging phone numbers, UPI IDs, or off-platform contact details.\n'
              '• Hate speech, blackmail, extortion, or intimidation.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '3. Intermediary Status under Section 79',
          icon: Icons.balance_rounded,
          iconColor: const Color(0xFF10B981),
          content: 'FeelBack acts purely as an intermediary communications platform under Section 79 of the Information Technology Act 2000. FeelBack is not liable for user-generated speech during transient calls.',
        ),
        const SizedBox(height: 12),

        _buildGrievanceCard(),
      ],
    );
  }

  // -------------------------------------------------------------
  // TAB 3: REFUND & CANCELLATION POLICY
  // -------------------------------------------------------------
  Widget _buildRefundTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      children: [
        _buildPillHeader(
          icon: Icons.account_balance_wallet_rounded,
          badge: 'Razorpay Gateway Compliant',
          badgeColor: const Color(0xFF10B981),
          title: 'Refund, Cancellation & Wallet Policy',
          subtitle: 'Operated by FeelBack Technologies Inc.',
        ),
        const SizedBox(height: 16),

        _buildCard(
          title: '1. Prepaid Wallet Billing Architecture',
          icon: Icons.payments_rounded,
          iconColor: primaryOrange,
          content: 'FeelBack operates on a transparent prepaid wallet model. Callers recharge their balance in INR via Razorpay (UPI, Cards, Netbanking). Calls are billed strictly per minute based on the listener\'s posted rate. When wallet balance reaches zero, the call ends automatically.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '2. 60-Second Call Drop Grace Period',
          icon: Icons.timer_rounded,
          iconColor: const Color(0xFF10B981),
          content: '✓ Automatic 60-Second Protection:\n'
              'If a call disconnects within the first 60 seconds (due to network failure, connection drop, or accidental dial), ZERO balance is deducted, or any deducted minute is automatically credited back to your wallet balance immediately.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '3. Unused Wallet Balance Refund',
          icon: Icons.replay_rounded,
          iconColor: const Color(0xFF3B82F6),
          content: 'If you have deposited funds and have unspent wallet balance:\n'
              '• You can request a 100% refund of unconsumed wallet funds within 14 days of recharge.\n'
              '• Email feelback.help@gmail.com with your transaction ID or mobile number.\n'
              '• Approved refunds are credited directly back to the original source (Bank/UPI/Card) within 5 to 7 business days via Razorpay.',
        ),
        const SizedBox(height: 12),

        _buildCard(
          title: '4. Non-Refundable Scenarios',
          icon: Icons.cancel_outlined,
          iconColor: Colors.grey,
          content: '• Completed talk minutes cannot be refunded as the peer listener dedicated live time to listen to you.\n'
              '• Accounts terminated for severe sexual harassment or abuse forfeit promotional balances.',
        ),
        const SizedBox(height: 12),

        _buildGrievanceCard(),
      ],
    );
  }

  // -------------------------------------------------------------
  // HELPER WIDGETS
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
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
                  style: TextStyle(color: badgeColor, fontWeight: FontWeight.w800, fontSize: 11),
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
            'Entity: FeelBack Technologies Inc.\n'
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
