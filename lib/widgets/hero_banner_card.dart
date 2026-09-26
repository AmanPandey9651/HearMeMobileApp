import 'package:flutter/material.dart';

class HeroBannerCard extends StatelessWidget {
  final VoidCallback? onChatTap;
  final VoidCallback? onVoiceTap;
  final VoidCallback? onVideoTap;

  const HeroBannerCard({
    super.key,
    this.onChatTap,
    this.onVoiceTap,
    this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFF2EB), // Warm light peach
            Color(0xFFFDE8DF), // Soft rose peach
            Color(0xFFFAF5EE), // Warm cream background
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFFCD7C8),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD6C7B8).withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFFF95B3D).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "You're Not Alone",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Real People. Real Support.',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFEA580C),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Connect with compassionate listeners over private chat, voice or video.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF6B7280),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),

                // 3 Action Pills
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _BannerPill(
                      icon: Icons.chat_bubble_rounded,
                      iconColor: const Color(0xFFF95B3D),
                      label: 'Chat',
                      onTap: onChatTap,
                    ),
                    _BannerPill(
                      icon: Icons.call_rounded,
                      iconColor: const Color(0xFFF95B3D),
                      label: 'Voice Call',
                      onTap: onVoiceTap,
                    ),
                    _BannerPill(
                      icon: Icons.videocam_rounded,
                      iconColor: const Color(0xFFF95B3D),
                      label: 'Video Call',
                      onTap: onVideoTap,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Right Graphic: 3D Glowing Orange Heart with Hands and "A kinder place to talk"
          SizedBox(
            width: 115,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer radial glow
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFF95B3D).withValues(alpha: 0.25),
                            const Color(0xFFFFECE5).withValues(alpha: 0.4),
                            Colors.transparent,
                          ],
                          radius: 0.7,
                        ),
                      ),
                    ),

                    // Cupped hands / pedestal support
                    Positioned(
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFECE5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFF95B3D).withValues(alpha: 0.2),
                            width: 0.8,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.front_hand_rounded,
                              size: 15,
                              color: Color(0xFFF97316),
                            ),
                            SizedBox(width: 2),
                            Icon(
                              Icons.front_hand_rounded,
                              size: 15,
                              color: Color(0xFFF97316),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Glowing 3D Heart
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF95B3D).withValues(alpha: 0.4),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Color(0xFFFF9E7A),
                            Color(0xFFF95B3D),
                            Color(0xFFEA580C),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ).createShader(bounds),
                        child: const Icon(
                          Icons.favorite_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    // Floating sparkles
                    Positioned(
                      top: 4,
                      right: 12,
                      child: Text(
                        '✨',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade600,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 10,
                      child: const Text(
                        '✦',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFF97316),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'A kinder\nplace to talk',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFC2410C),
                    letterSpacing: -0.1,
                    height: 1.15,
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

class _BannerPill extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  const _BannerPill({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFF1E6D8),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFC2410C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
