import 'package:flutter/material.dart';

import '../../main.dart';
import 'safety_support_screen.dart';

class HowItWorksScreen extends StatefulWidget {
  const HowItWorksScreen({super.key});

  @override
  State<HowItWorksScreen> createState() => _HowItWorksScreenState();
}

class _HowItWorksScreenState extends State<HowItWorksScreen> {
  String audience = 'CALLER'; // 'CALLER' or 'LISTENER'

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);

  static const callerSteps = [
    (
      step: '1',
      title: 'Anonymous quick access',
      body: 'Sign in with Phone OTP or Google. The platform uses your anonymous caller profile so listeners do not need your real name, phone number, or email.',
      icon: Icons.phonelink_lock_rounded,
    ),
    (
      step: '2',
      title: 'Pick your ideal listener',
      body: 'Browse verified listeners, search by topic, language and profile details, then check live availability, ratings and transparent per-minute prices.',
      icon: Icons.person_search_rounded,
    ),
    (
      step: '3',
      title: 'Top up your prepaid wallet',
      body: 'Recharge securely, see your balance before connecting, and pay only according to the session billing rules enforced by the backend.',
      icon: Icons.account_balance_wallet_rounded,
    ),
    (
      step: '4',
      title: 'Speak freely',
      body: 'Choose private chat, audio or video. During a session you can use safety controls, in-call chat, gifts, icebreakers, privacy effects and mini-games.',
      icon: Icons.chat_bubble_rounded,
    ),
  ];

  static const listenerSteps = [
    (
      step: '1',
      title: 'Create your listener profile',
      body: 'Add your display photo, bio, languages, categories and per-minute consultation rates, then submit for swift admin approval.',
      icon: Icons.assignment_ind_rounded,
    ),
    (
      step: '2',
      title: 'Control your live availability',
      body: 'Switch Online when ready to take calls. You can configure scheduled availability and pause requests whenever you need a break.',
      icon: Icons.toggle_on_rounded,
    ),
    (
      step: '3',
      title: 'Accept calls, video & chat',
      body: 'Receive incoming 45-second call alerts with caller personas. Accept, connect seamlessly and offer compassionate, private listening.',
      icon: Icons.phone_in_talk_rounded,
    ),
    (
      step: '4',
      title: 'Earn & withdraw to UPI',
      body: 'Track your per-minute session earnings and caller gifts in real time. Request instant UPI payouts with complete ledger transparency.',
      icon: Icons.monetization_on_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isCaller = audience == 'CALLER';
    final steps = isCaller ? callerSteps : listenerSteps;

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
                // Top Header matching Image 4
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
                      const Text(
                        'How it works',
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

                Expanded(
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
                    children: [
                      // 1. Hero Banner matching Image 4
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFF9F2), Color(0xFFFFECE5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: borderWarm),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Text Left
                            Expanded(
                              flex: 13,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: const TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Transparent, safe\n',
                                          style: TextStyle(
                                            color: textDark,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            height: 1.25,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '& anonymous',
                                          style: TextStyle(
                                            color: primaryOrange,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w900,
                                            height: 1.25,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Connect with verified human listeners through private chat, voice and video while keeping the caller-facing identity anonymous.',
                                    style: TextStyle(
                                      color: Color(0xFF4B5563),
                                      fontSize: 12.5,
                                      height: 1.35,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Artwork Right (Shield with padlock & sparkles)
                            Expanded(
                              flex: 8,
                              child: _ShieldArtwork(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. Segmented Pill Toggle (Caller vs Listener) matching Image 4
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: borderWarm),
                        ),
                        child: Row(
                          children: [
                            // Caller Button
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => audience = 'CALLER'),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    gradient: isCaller
                                        ? const LinearGradient(
                                            colors: [primaryOrange, secondaryOrange],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null,
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: isCaller
                                        ? [
                                            BoxShadow(
                                              color: primaryOrange.withValues(alpha: 0.3),
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
                                        Icons.phone_rounded,
                                        size: 16,
                                        color: isCaller ? Colors.white : const Color(0xFF4B5563),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Caller',
                                        style: TextStyle(
                                          color: isCaller ? Colors.white : const Color(0xFF4B5563),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Listener Button
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => audience = 'LISTENER'),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    gradient: !isCaller
                                        ? const LinearGradient(
                                            colors: [primaryOrange, secondaryOrange],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null,
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: !isCaller
                                        ? [
                                            BoxShadow(
                                              color: primaryOrange.withValues(alpha: 0.3),
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
                                        Icons.headphones_rounded,
                                        size: 16,
                                        color: !isCaller ? Colors.white : const Color(0xFF4B5563),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Listener',
                                        style: TextStyle(
                                          color: !isCaller ? Colors.white : const Color(0xFF4B5563),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // 3. Section Title matching Image 4
                      Text(
                        isCaller ? '4 simple steps to connect' : '4 simple steps to listen & earn',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: textDark,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 4. Step Cards matching Image 4
                      ...steps.map((s) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderWarm),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.025),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Number Pill on left
                              Container(
                                width: 38,
                                height: 38,
                                decoration: const BoxDecoration(
                                  color: softPeach,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    s.step,
                                    style: const TextStyle(
                                      color: primaryOrange,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Title & Description Center
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.title,
                                      style: const TextStyle(
                                        color: textDark,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      s.body,
                                      style: const TextStyle(
                                        color: Color(0xFF4B5563),
                                        fontSize: 12.5,
                                        height: 1.35,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Right Illustration Badge
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF4EC),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Icon(
                                    s.icon,
                                    color: primaryOrange,
                                    size: 26,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),

                      // 5. Privacy & Safety Card matching Image 4 bottom
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SafetySupportScreen(initialTab: 0)),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: borderWarm),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.shield_rounded, color: primaryOrange, size: 24),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Privacy & safety',
                                  style: TextStyle(
                                    color: textDark,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, color: textDark, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
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

/// Artwork for the shield & padlock matching Image 4
class _ShieldArtwork extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background soft circle
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFD4BE).withValues(alpha: 0.5),
            ),
          ),
          // Shield Graphic
          Container(
            width: 58,
            height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9458), Color(0xFFF95B3D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF95B3D).withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.lock_rounded, color: Colors.white, size: 26),
            ),
          ),
          // Avatar bubble orb
          Positioned(
            right: 0,
            bottom: 4,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Color(0xFFFF8543),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 2,
            bottom: 12,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: const Color(0xFFFFAE80).withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Star Sparkle
          const Positioned(
            top: 2,
            right: 6,
            child: Icon(Icons.auto_awesome, color: Color(0xFFFFA05C), size: 16),
          ),
        ],
      ),
    );
  }
}
