import '../common/legal_policy_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'listener_register_screen.dart';

class LoginScreen extends StatefulWidget {
  final int initialTab;
  const LoginScreen({super.key, this.initialTab = 1});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _mobile = TextEditingController();
  final _otp = TextEditingController();
  bool _obscurePassword = true;
  bool _otpSent = false;
  String? _verificationId;
  int? _resendToken;
  bool _busy = false;

  static const Color bgCream = AppTheme.bgCream;
  static const Color borderWarm = AppTheme.borderWarm;
  static const Color primaryOrange = AppTheme.primaryOrange;
  static const Color secondaryOrange = AppTheme.secondaryOrange;
  static const Color textDark = AppTheme.textDark;
  static const Color textMuted = AppTheme.textMuted;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppController>().refreshAuthGovernance();
      }
    });
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
    } catch (e) {
      if (mounted) {
        showError(context, e);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _email.dispose();
    _password.dispose();
    _mobile.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();

    if (app.user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
      return const Scaffold(
        backgroundColor: bgCream,
        body: Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgCream,
      appBar: AppBar(
        backgroundColor: bgCream,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Image.asset(
          app.headerLogoAsset,
          height: 27,
          fit: BoxFit.contain,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),

            // Segmented pill tab switcher matching Screenshot 1
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
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
                  Expanded(
                    child: _TabPill(
                      label: 'Anonymous User',
                      icon: Icons.shield_rounded,
                      selected: _tabs.index == 0,
                      onTap: () => _tabs.animateTo(0),
                    ),
                  ),
                  Expanded(
                    child: _TabPill(
                      label: 'Listener Portal',
                      icon: Icons.headset_mic_rounded,
                      selected: _tabs.index == 1,
                      onTap: () => _tabs.animateTo(1),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildAnonymousUserTab(context, app),
                  _buildListenerTab(context, app),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: ANONYMOUS USER (Screenshot 1)
  // ==========================================
  Widget _buildAnonymousUserTab(BuildContext context, AppController app) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      children: [
        // 1. Hero Card: Soft peach gradient, glowing shield badge, 3 value pills
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF2EB), Color(0xFFFFE6D8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0xFFFCDFD5)),
            boxShadow: [
              BoxShadow(
                color: primaryOrange.withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Glowing shield icon container
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [primaryOrange, secondaryOrange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.shield_rounded, size: 36, color: Colors.white),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Talk Anonymously',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: textDark,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your public caller identity stays 100% private. No real names or numbers are ever shared.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),

              // 3 Value Pills matching screenshot
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MiniFeaturePill(icon: Icons.lock_outline_rounded, text: 'Encrypted'),
                  const SizedBox(width: 8),
                  _MiniFeaturePill(icon: Icons.visibility_off_outlined, text: 'No PII'),
                  const SizedBox(width: 8),
                  _MiniFeaturePill(icon: Icons.bolt_rounded, text: 'Instant'),
                ],
              ),
            ],
          ),
        ),

        if (app.phoneLoginEnabled) ...[
          const SizedBox(height: 20),

          // 2. White Card: "Quick Mobile Login"
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderWarm),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Mobile Login',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textDark),
                ),
                const SizedBox(height: 4),
                const Text(
                  'We use your number only for authentication. Listeners never see it.',
                  style: TextStyle(fontSize: 12.5, color: textMuted, height: 1.35),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: textDark),
                  decoration: InputDecoration(
                    hintText: 'Mobile number',
                    hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.normal),
                    prefixIcon: const Icon(Icons.phone_rounded, color: primaryOrange, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFFFFBF7),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
                if (_otpSent) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _otp,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: textDark),
                    decoration: InputDecoration(
                      hintText: 'Enter 6-digit OTP',
                      prefixIcon: const Icon(Icons.pin_rounded, color: primaryOrange, size: 20),
                      filled: true,
                      fillColor: const Color(0xFFFFFBF7),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
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
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _busy
                          ? null
                          : () => _run(() async {
                                final mobile = _mobile.text.replaceAll(RegExp(r'\D'), '');
                                if (mobile.length < 10) throw Exception('Enter a valid mobile number.');
                                if (!_otpSent) {
                                  final fullNumber = mobile.startsWith('91') && mobile.length == 12 ? '+$mobile' : '+91${mobile.substring(mobile.length - 10)}';
                                  try {
                                    await FirebaseAuth.instance.verifyPhoneNumber(
                                      phoneNumber: fullNumber,
                                      verificationCompleted: (PhoneAuthCredential credential) async {
                                        try {
                                          final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
                                          final idToken = await userCred.user?.getIdToken();
                                          if (idToken != null) {
                                            await app.firebaseOtpLogin(idToken, mobile);
                                          }
                                        } catch (_) {}
                                      },
                                      verificationFailed: (FirebaseAuthException e) {
                                        String msg = e.message ?? 'Firebase Phone verification failed.';
                                        if (e.code == 'billing-not-enabled') {
                                          msg = 'Firebase SMS requires Blaze billing plan. Please upgrade in Firebase Console or use a test phone number.';
                                        }
                                        showError(context, msg);
                                      },
                                      codeSent: (String verificationId, int? resendToken) {
                                        if (mounted) {
                                          setState(() {
                                            _verificationId = verificationId;
                                            _resendToken = resendToken;
                                            _otpSent = true;
                                          });
                                        }
                                      },
                                      codeAutoRetrievalTimeout: (String verificationId) {
                                        _verificationId = verificationId;
                                      },
                                    );
                                  } catch (e) {
                                    showError(context, e);
                                  }
                                } else {
                                  final code = _otp.text.trim();
                                  if (code.isEmpty) throw Exception('Enter the OTP.');

                                  if (_verificationId == null) {
                                    throw Exception('No active verification session. Please request a new OTP.');
                                  }

                                  final credential = PhoneAuthProvider.credential(
                                    verificationId: _verificationId!,
                                    smsCode: code,
                                  );
                                  final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
                                  final idToken = await userCred.user?.getIdToken();
                                  if (idToken == null) {
                                    throw Exception('Failed to obtain Firebase ID token.');
                                  }
                                  await app.firebaseOtpLogin(idToken, mobile);
                                }
                              }),
                      child: Center(
                        child: Text(
                          _busy ? 'Please wait…' : (_otpSent ? 'Verify OTP & Enter' : 'Send Verification OTP'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Divider: OR CONTINUE WITH
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                Expanded(child: Divider(color: borderWarm, thickness: 1)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    'OR CONTINUE WITH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
                Expanded(child: Divider(color: borderWarm, thickness: 1)),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 20),
        ],

        // High-End Google Sign-In Button
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderWarm),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _busy ? null : () => _run(app.googleLogin),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _GoogleGLogo(),
                    const SizedBox(width: 12),
                    Text(
                      _busy ? 'Signing in with Google…' : 'Continue with Google',
                      style: const TextStyle(
                        color: textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
              SizedBox(width: 6),
              Text(
                'One-tap secure Google verification',
                style: TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('By continuing, you agree to our ', style: TextStyle(fontSize: 11, color: textMuted)),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalPolicyScreen(initialTab: 1))),
              child: const Text('Terms of Service', style: TextStyle(fontSize: 11, color: primaryOrange, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
            ),
            const Text(' & ', style: TextStyle(fontSize: 11, color: textMuted)),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LegalPolicyScreen(initialTab: 0))),
              child: const Text('Privacy Policy', style: TextStyle(fontSize: 11, color: primaryOrange, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
            ),
          ],
        ),

        const SizedBox(height: 12),



        // Support Contact Button
        Center(
          child: TextButton.icon(
            onPressed: _busy ? null : () => _publicContact(context, app),
            icon: const Icon(Icons.headset_mic_rounded, size: 16, color: primaryOrange),
            label: const Text(
              'Need help? Contact Us & Safety Support',
              style: TextStyle(color: primaryOrange, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ),

        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Calls made are 100% anonymous and private.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: textMuted),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: LISTENER PORTAL (Warm Luxury Theme)
  // ==========================================
  Widget _buildListenerTab(BuildContext context, AppController app) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      children: [
        // Listener Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF2EB), Color(0xFFFFE6D8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0xFFFCDFD5)),
            boxShadow: [
              BoxShadow(
                color: primaryOrange.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [primaryOrange, secondaryOrange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.headphones_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Listener Sign In',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textDark),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Take calls, support callers, and earn.',
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                  ],
                ),
              ),
              const HeartBlushGraphic(size: 46),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Email & Password Fields
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderWarm),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontWeight: FontWeight.w700, color: textDark),
                decoration: InputDecoration(
                  labelText: 'Registered email address',
                  prefixIcon: const Icon(Icons.mail_outline_rounded, color: primaryOrange, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFFFFBF7),
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
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _obscurePassword,
                style: const TextStyle(fontWeight: FontWeight.w700, color: textDark),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, color: primaryOrange, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 20,
                      color: textMuted,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFFFBF7),
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
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _forgot(context, app),
                  child: const Text(
                    'Forgot password?',
                    style: TextStyle(color: primaryOrange, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
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
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _busy ? null : () => _run(() => app.login(_email.text.trim(), _password.text)),
                    child: Center(
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Sign In as Listener',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Join as Listener CTA Card
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderWarm),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFECE5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group_rounded, color: primaryOrange, size: 24),
              ),
              const SizedBox(height: 14),
              Text(
                'Want to become a listener on ${app.activeBrandName}?',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'Set your per-minute audio/video rates and earn rewards.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: textMuted),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ListenerRegisterScreen()),
                ),
                icon: const Icon(Icons.star_rounded, size: 18, color: primaryOrange),
                label: const Text('Apply / Register as Listener', style: TextStyle(fontWeight: FontWeight.w800, color: primaryOrange, fontSize: 13.5)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: primaryOrange, width: 1.3),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // FORGOT PASSWORD MODAL
  // ==========================================
  Future<void> _forgot(BuildContext context, AppController app) async {
    final identifier = TextEditingController();
    final code = TextEditingController();
    final password = TextEditingController();
    final confirmPassword = TextEditingController();
    var channel = 'EMAIL';
    var sent = false;
    var busy = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(22, 16, 22, 24 + MediaQuery.of(ctx).viewInsets.bottom),
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
              Text(
                sent ? 'Set New Password' : 'Reset Password',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: textDark),
              ),
              const SizedBox(height: 14),
              if (!sent) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'EMAIL', label: Text('Email'), icon: Icon(Icons.email_outlined, size: 16)),
                    ButtonSegment(value: 'MOBILE', label: Text('Mobile'), icon: Icon(Icons.sms_outlined, size: 16)),
                  ],
                  selected: {channel},
                  onSelectionChanged: busy ? null : (v) => setLocal(() => channel = v.first),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: identifier,
                  keyboardType: channel == 'EMAIL' ? TextInputType.emailAddress : TextInputType.phone,
                  decoration: InputDecoration(labelText: channel == 'EMAIL' ? 'Registered email' : 'Registered mobile'),
                ),
              ] else ...[
                Text(
                  'A verification code was sent to ${identifier.text.trim()}.',
                  style: const TextStyle(color: textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Verification code')),
                const SizedBox(height: 10),
                TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
                const SizedBox(height: 10),
                TextField(controller: confirmPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: textMuted))),
                  if (sent)
                    TextButton(onPressed: busy ? null : () => setLocal(() => sent = false), child: const Text('Back', style: TextStyle(color: textMuted))),
                  const Spacer(),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final id = identifier.text.trim();
                            if (id.isEmpty) {
                              showError(ctx, 'Enter your registered ${channel == 'EMAIL' ? 'email' : 'mobile number'}.');
                              return;
                            }
                            setLocal(() => busy = true);
                            try {
                              if (!sent) {
                                await app.api.forgotPassword(id);
                                setLocal(() => sent = true);
                              } else {
                                if (code.text.trim().isEmpty) throw Exception('Enter the verification code.');
                                if (password.text.length < 8) throw Exception('Password must be at least 8 characters.');
                                if (password.text != confirmPassword.text) throw Exception('Passwords do not match.');
                                await app.api.resetPassword(id, code.text.trim(), password.text);
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset successfully. You can sign in now.')));
                                }
                              }
                            } catch (e) {
                              if (ctx.mounted) showError(ctx, e);
                            } finally {
                              if (ctx.mounted) setLocal(() => busy = false);
                            }
                          },
                    style: FilledButton.styleFrom(backgroundColor: primaryOrange),
                    child: Text(busy ? 'Please wait…' : (sent ? 'Save Password' : 'Send Code')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    identifier.dispose();
    code.dispose();
    password.dispose();
    confirmPassword.dispose();
  }

  // ==========================================
  // CONTACT & SUPPORT MODAL
  // ==========================================
  Future<void> _publicContact(BuildContext context, AppController app) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final phone = TextEditingController();
    final state = TextEditingController();
    final country = TextEditingController(text: 'India');
    final subject = TextEditingController();
    final message = TextEditingController();
    var busy = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(22, 16, 22, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
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
                const Text('Contact Safety & Support', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: textDark)),
                const SizedBox(height: 4),
                const Text('Our team responds to all inquiries within a few hours.', style: TextStyle(color: textMuted, fontSize: 12)),
                const SizedBox(height: 16),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
                const SizedBox(height: 10),
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email *')),
                const SizedBox(height: 10),
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone *')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextField(controller: state, decoration: const InputDecoration(labelText: 'State *'))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: country, decoration: const InputDecoration(labelText: 'Country *'))),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: subject, decoration: const InputDecoration(labelText: 'Subject *')),
                const SizedBox(height: 10),
                TextField(controller: message, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Message *')),
                const SizedBox(height: 20),
                Row(
                  children: [
                    TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: textMuted))),
                    const Spacer(),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final fields = [name.text, email.text, phone.text, state.text, country.text, subject.text, message.text];
                              if (fields.any((v) => v.trim().isEmpty)) {
                                showError(ctx, 'Please complete all contact fields.');
                                return;
                              }
                              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
                                showError(ctx, 'Enter a valid email address.');
                                return;
                              }
                              setLocal(() => busy = true);
                              try {
                                final result = await app.api.submitContact({
                                  'name': name.text.trim(),
                                  'email': email.text.trim(),
                                  'phone': phone.text.trim(),
                                  'state': state.text.trim(),
                                  'country': country.text.trim(),
                                  'subject': subject.text.trim(),
                                  'message': message.text.trim(),
                                });
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${result['message'] ?? 'Message submitted.'}')));
                                }
                              } catch (e) {
                                if (ctx.mounted) showError(ctx, e);
                              } finally {
                                if (ctx.mounted) setLocal(() => busy = false);
                              }
                            },
                      style: FilledButton.styleFrom(backgroundColor: primaryOrange),
                      child: Text(busy ? 'Sending…' : 'Send Message'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    name.dispose();
    email.dispose();
    phone.dispose();
    state.dispose();
    country.dispose();
    subject.dispose();
    message.dispose();
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.icon,
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
                color: selected ? Colors.white : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniFeaturePill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniFeaturePill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderWarm),
        boxShadow: [
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
          Icon(icon, size: 12.5, color: AppTheme.primaryOrange),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textDark),
          ),
        ],
      ),
    );
  }
}

class _GoogleGLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'G',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              fontFamily: 'sans-serif',
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: [
                    Color(0xFF4285F4),
                    Color(0xFFEA4335),
                    Color(0xFFFBBC05),
                    Color(0xFF34A853),
                  ],
                ).createShader(const Rect.fromLTWH(0.0, 0.0, 20.0, 20.0)),
            ),
          ),
        ],
      ),
    );
  }
}

class HeartBlushGraphic extends StatelessWidget {
  final double size;
  const HeartBlushGraphic({super.key, this.size = 54});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 16,
      height: size + 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size + 10,
            height: size + 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFFFAB91).withValues(alpha: 0.38),
                  const Color(0xFFFFCCBC).withValues(alpha: 0.16),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Transform.rotate(
            angle: 0.16,
            child: Icon(
              Icons.favorite_rounded,
              color: const Color(0xFFFF8A65).withValues(alpha: 0.85),
              size: size * 0.65,
            ),
          ),
          Positioned(
            top: 2,
            right: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 2.8,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF7043).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 3),
                Transform.rotate(
                  angle: 0.38,
                  child: Container(
                    width: 2.8,
                    height: 7,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7043).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(2),
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



