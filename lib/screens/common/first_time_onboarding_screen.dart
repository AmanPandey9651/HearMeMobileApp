import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_controller.dart';
import 'legal_policy_screen.dart';

class FirstTimeOnboardingScreen extends StatefulWidget {
  const FirstTimeOnboardingScreen({super.key});

  @override
  State<FirstTimeOnboardingScreen> createState() => _FirstTimeOnboardingScreenState();
}

class _FirstTimeOnboardingScreenState extends State<FirstTimeOnboardingScreen> {
  final TextEditingController _referralController = TextEditingController();
  bool _acceptedTerms = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _referralController.dispose();
    super.dispose();
  }

  Future<void> _submitOnboarding() async {
    if (!_acceptedTerms) {
      setState(() {
        _errorMessage = 'Please accept the Terms of Service & Privacy Policy to continue.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final app = context.read<AppController>();
    final code = _referralController.text.trim();

    try {
      final res = await app.completeOnboarding(
        acceptTerms: true,
        referralCode: code.isNotEmpty ? code : null,
      );

      if (!mounted) return;

      final bool referralApplied = res['referralApplied'] == true;
      final String msg = res['message']?.toString() ?? 'Welcome to FeelBack!';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                referralApplied ? Icons.celebration_rounded : Icons.check_circle_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  msg,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: referralApplied ? const Color(0xFF10B981) : const Color(0xFFF95B3D),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    // Safety guard: listeners and non-customers must never see customer onboarding
    if (app.user != null && app.user!.role != 'CUSTOMER') {
      return const SizedBox.shrink();
    }
    final userName = app.user?.fullName.isNotEmpty == true ? app.user!.fullName : 'Friend';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF9F5),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFFF8F3),
                Color(0xFFFFF1E8),
                Color(0xFFFFE8DB),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Official FeelBack Logo at Top (NOT Heart)
                      Center(
                        child: Image.asset(
                          'assets/images/feelback-logo.png',
                          height: 44,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.favorite_rounded, color: Color(0xFFF95B3D), size: 28),
                              SizedBox(width: 8),
                              Text(
                                'FeelBack',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 2. Greeting & Subtitle
                      Text(
                        'Welcome, $userName! 🎉',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Before you start confidential conversations on FeelBack,\nplease confirm community policy acceptance and claim any invite bonuses.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // In-Form Error Alert if any
                      if (_errorMessage != null) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // 3. The Main Form Card (Crisp White Card with Soft Warm Shadow)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFFFED7AA).withValues(alpha: 0.6),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF97316).withValues(alpha: 0.08),
                              blurRadius: 28,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Section: Referral / Invite Code Header
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Gift Badge
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E8),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFFFFD7B8),
                                      width: 1.2,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.card_giftcard_rounded,
                                      color: Color(0xFFEA580C),
                                      size: 26,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      RichText(
                                        text: const TextSpan(
                                          children: [
                                            TextSpan(
                                              text: 'Referral / Invite Code ',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1E293B),
                                              ),
                                            ),
                                            TextSpan(
                                              text: '(Optional)',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFFF95B3D),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      const Text(
                                        'Have a friend\'s code? Enter it to get ₹20 bonus coins on signup!',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Referral Code Input with Orange Tag Icon
                            TextFormField(
                              controller: _referralController,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                letterSpacing: 1.1,
                              ),
                              decoration: InputDecoration(
                                hintText: 'e.g. FEEL9K8X',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                prefixIcon: const Icon(
                                  Icons.local_offer_rounded,
                                  color: Color(0xFFF95B3D),
                                  size: 19,
                                ),
                                suffixIcon: _referralController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                                        onPressed: () {
                                          setState(() {
                                            _referralController.clear();
                                          });
                                        },
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFF95B3D), width: 1.8),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 18),

                            // Terms of Service & Privacy Policy Section
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _acceptedTerms
                                      ? const Color(0xFFF95B3D).withValues(alpha: 0.5)
                                      : const Color(0xFFE2E8F0),
                                  width: 1.2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _acceptedTerms = !_acceptedTerms;
                                        if (_acceptedTerms) _errorMessage = null;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Custom Orange Square Checkbox (matching image)
                                        Container(
                                          width: 22,
                                          height: 22,
                                          margin: const EdgeInsets.only(top: 2, right: 10),
                                          decoration: BoxDecoration(
                                            color: _acceptedTerms ? const Color(0xFFF95B3D) : Colors.white,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: _acceptedTerms ? const Color(0xFFF95B3D) : const Color(0xFFCBD5E1),
                                              width: 1.8,
                                            ),
                                          ),
                                          child: _acceptedTerms
                                              ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                                              : null,
                                        ),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'I accept the Terms of Service & Privacy Policy',
                                                style: TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF1E293B),
                                                ),
                                              ),
                                              SizedBox(height: 3),
                                              Text(
                                                'I certify that I am at least 18 years old and consent to FeelBack\'s community safety policies and data practices.',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  color: Color(0xFF64748B),
                                                  height: 1.35,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                  const SizedBox(height: 6),

                                  // Links row (📄 Terms of Service | 🔒 Privacy Policy)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const LegalPolicyScreen(initialTab: 1),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.description_outlined, size: 15, color: Color(0xFFF95B3D)),
                                        label: const Text(
                                          'Terms of Service',
                                          style: TextStyle(
                                            color: Color(0xFFF95B3D),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8),
                                        child: Text('|', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                                      ),
                                      TextButton.icon(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const LegalPolicyScreen(initialTab: 0),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.lock_outline_rounded, size: 15, color: Color(0xFFF95B3D)),
                                        label: const Text(
                                          'Privacy Policy',
                                          style: TextStyle(
                                            color: Color(0xFFF95B3D),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Agree & Enter FeelBack Button
                            Container(
                              height: 50,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(26),
                                gradient: _acceptedTerms && !_isLoading
                                    ? const LinearGradient(
                                        colors: [Color(0xFFFF6A00), Color(0xFFF95B3D)],
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                      )
                                    : null,
                                color: (!_acceptedTerms || _isLoading)
                                    ? const Color(0xFFF95B3D).withValues(alpha: 0.35)
                                    : null,
                                boxShadow: _acceptedTerms && !_isLoading
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFF95B3D).withValues(alpha: 0.35),
                                          blurRadius: 14,
                                          offset: const Offset(0, 5),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: ElevatedButton(
                                onPressed: (_acceptedTerms && !_isLoading) ? _submitOnboarding : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  disabledBackgroundColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                                      )
                                    : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Agree & Enter FeelBack',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // 4. Trust Badges Row (Below Card)
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFFF95B3D)),
                          SizedBox(width: 4),
                          Text(
                            '100% Anonymous',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('|', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                          ),
                          Icon(Icons.lock_rounded, size: 14, color: Color(0xFFF95B3D)),
                          SizedBox(width: 4),
                          Text(
                            'Safe & Secure',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('|', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
                          ),
                          Icon(Icons.favorite_rounded, size: 14, color: Color(0xFFF95B3D)),
                          SizedBox(width: 4),
                          Text(
                            'Your Feelings Matter',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Log out / Switch account
                      Center(
                        child: TextButton(
                          onPressed: _isLoading ? null : () => app.logout(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Log Out / Switch Account',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
