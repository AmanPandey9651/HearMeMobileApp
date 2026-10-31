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
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFF2EB), // Warm light peach
            Color(0xFFFDE8DF), // Soft rose peach
            Color(0xFFFAF5EE), // Warm cream
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFCD7C8),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD6C7B8).withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left: Mini icon + title & tagline
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFF95B3D).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Color(0xFFF95B3D),
              size: 15,
            ),
          ),
          const SizedBox(width: 8),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "You're Not Alone",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  '🎁 1st Call Free • Real Support',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFEA580C),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          // Right: 3 compact micro-pills
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CompactBannerPill(
                icon: Icons.chat_bubble_rounded,
                label: 'Chat',
                onTap: onChatTap,
              ),
              const SizedBox(width: 4),
              _CompactBannerPill(
                icon: Icons.call_rounded,
                label: 'Voice',
                onTap: onVoiceTap,
              ),
              const SizedBox(width: 4),
              _CompactBannerPill(
                icon: Icons.videocam_rounded,
                label: 'Video',
                onTap: onVideoTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactBannerPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _CompactBannerPill({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFF1E6D8),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: const Color(0xFFF95B3D)),
              const SizedBox(width: 3),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
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