import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/active_call_manager.dart';
import 'common_widgets.dart';

class MinimizedCallBar extends StatelessWidget {
  final ActiveCallManager callManager;
  final bool isDragging;

  const MinimizedCallBar({
    super.key,
    required this.callManager,
    this.isDragging = false,
  });

  @override
  Widget build(BuildContext context) {
    final session = callManager.activeSession;
    if (session == null || session.ended) return const SizedBox.shrink();

    final peerName = callManager.isCaller
        ? session.listenerName
        : session.callerNickname;
    final avatarUrl = callManager.isCaller
        ? session.listenerAvatarUrl
        : session.callerAvatarUrl;
    final isVideo = session.type == 'VIDEO_CALL';

    return Material(
      elevation: isDragging ? 18 : 10,
      shadowColor: Colors.black.withValues(alpha: isDragging ? 0.65 : 0.45),
      borderRadius: BorderRadius.circular(18),
      color: Colors.transparent,
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: isDragging
                ? const [
                    Color(0xFF1E1B4B),
                    Color(0xFF0F172A),
                  ]
                : const [
                    Color(0xFF0F172A),
                    Color(0xFF1E293B),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: isDragging
                ? const Color(0xFF818CF8)
                : const Color(0xFF10B981).withValues(alpha: 0.35),
            width: isDragging ? 1.6 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isDragging
                  ? const Color(0xFF6366F1).withValues(alpha: 0.35)
                  : const Color(0xFF10B981).withValues(alpha: 0.12),
              blurRadius: isDragging ? 22 : 16,
              spreadRadius: isDragging ? 3 : 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Subtle Drag Handle Indicator
            Center(
              child: Container(
                width: 34,
                height: 3.5,
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: isDragging
                      ? const Color(0xFF818CF8)
                      : Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Content Row
            Expanded(
              child: Row(
                children: [
                  // Avatar with Live Pulsing Dot
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: RemoteAvatar(
                            url: avatarUrl,
                            radius: 20,
                            fallback: peerName,
                          ),
                        ),
                      ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF0F172A), width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 10),

                  // Peer Name & Elapsed Time
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              isVideo ? Icons.videocam_rounded : Icons.phone_in_talk_rounded,
                              size: 12,
                              color: const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${callManager.timeString} • ₹${session.ratePerMinute.toStringAsFixed(0)}/min',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 6),

                  // Quick Mic Toggle
                  IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: callManager.isMuted
                          ? Colors.redAccent.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.12),
                    ),
                    icon: Icon(
                      callManager.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: callManager.isMuted ? Colors.redAccent : Colors.white,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      callManager.toggleMute();
                    },
                    tooltip: callManager.isMuted ? 'Unmute' : 'Mute',
                  ),

                  const SizedBox(width: 4),

                  // End Call Button
                  IconButton(
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                    icon: const Icon(
                      Icons.call_end_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      callManager.endCall();
                    },
                    tooltip: 'End Call',
                  ),

                  const SizedBox(width: 2),

                  // Expand Indicator
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                    icon: const Icon(
                      Icons.open_in_full_rounded,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      callManager.maximize();
                    },
                    tooltip: 'Expand',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
