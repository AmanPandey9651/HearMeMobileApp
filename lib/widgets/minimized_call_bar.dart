import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/active_call_manager.dart';
import 'common_widgets.dart';

class MinimizedCallBar extends StatefulWidget {
  final ActiveCallManager callManager;
  final bool isDragging;

  const MinimizedCallBar({
    super.key,
    required this.callManager,
    this.isDragging = false,
  });

  @override
  State<MinimizedCallBar> createState() => _MinimizedCallBarState();
}

class _MinimizedCallBarState extends State<MinimizedCallBar> with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.callManager.activeSession;
    if (session == null || session.ended) return const SizedBox.shrink();

    final peerName = widget.callManager.isCaller
        ? session.listenerName
        : session.callerNickname;
    final avatarUrl = widget.callManager.isCaller
        ? session.listenerAvatarUrl
        : session.callerAvatarUrl;
    final isVideo = session.type == 'VIDEO_CALL';
    final isMuted = widget.callManager.isMuted;
    final isLive = widget.callManager.isLive;

    return Material(
      elevation: widget.isDragging ? 18 : 10,
      shadowColor: Colors.black.withValues(alpha: widget.isDragging ? 0.6 : 0.4),
      borderRadius: BorderRadius.circular(22),
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 68,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: widget.isDragging
                ? const [
                    Color(0xFF282538),
                    Color(0xFF161522),
                  ]
                : const [
                    Color(0xFF1E212B),
                    Color(0xFF12141A),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: widget.isDragging
                ? const Color(0xFFF95B3D).withValues(alpha: 0.7)
                : const Color(0xFFF95B3D).withValues(alpha: 0.3),
            width: widget.isDragging ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isDragging
                  ? const Color(0xFFF95B3D).withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.35),
              blurRadius: widget.isDragging ? 20 : 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // Top Drag Handle Indicator
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Center(
                child: Container(
                  width: 32,
                  height: 3.5,
                  decoration: BoxDecoration(
                    color: widget.isDragging
                        ? const Color(0xFFF95B3D)
                        : Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Main Bar Row
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    // Tappable Hero Content Area (Avatar + Name + Duration) -> Tapping maximizes call
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.callManager.maximize();
                        },
                        child: Row(
                          children: [
                            // Avatar with live status aura
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isLive
                                          ? const Color(0xFF10B981).withValues(alpha: 0.6)
                                          : Colors.white.withValues(alpha: 0.2),
                                      width: 1.8,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: RemoteAvatar(
                                      url: avatarUrl,
                                      radius: 20,
                                      fallback: peerName,
                                    ),
                                  ),
                                ),
                                // Live green or orange status pill dot
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: isLive
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFF59E0B),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF12141A),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                // Video indicator icon badge if video call
                                if (isVideo)
                                  Positioned(
                                    left: -2,
                                    top: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(2.5),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF8B5CF6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.videocam_rounded,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),

                            const SizedBox(width: 10),

                            // Peer Name & Call Status Row
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          peerName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: isVideo
                                              ? const Color(0xFF8B5CF6).withValues(alpha: 0.25)
                                              : const Color(0xFFF95B3D).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isVideo ? 'Video' : 'Audio',
                                          style: TextStyle(
                                            color: isVideo ? const Color(0xFFA78BFA) : const Color(0xFFFF8B73),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      // Animated Sound Wave bars when live
                                      if (isLive) ...[
                                        _buildAnimatedWave(),
                                        const SizedBox(width: 5),
                                      ],
                                      Text(
                                        widget.callManager.timeString,
                                        style: const TextStyle(
                                          color: Color(0xFF10B981),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                      Text(
                                        ' • ₹${session.ratePerMinute.toStringAsFixed(0)}/min',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.65),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Dedicated Action Controls: Mic, End Call, Maximize
                    // 1. Mic Mute / Unmute
                    _buildActionButton(
                      icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      iconColor: isMuted ? Colors.white : Colors.white,
                      backgroundColor: isMuted
                          ? const Color(0xFFEF4444)
                          : Colors.white.withValues(alpha: 0.12),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        widget.callManager.toggleMute();
                      },
                    ),

                    const SizedBox(width: 6),

                    // 2. End Call Button (Red accent circle)
                    _buildActionButton(
                      icon: Icons.call_end_rounded,
                      iconColor: Colors.white,
                      backgroundColor: const Color(0xFFEF4444),
                      onPressed: () {
                        HapticFeedback.heavyImpact();
                        widget.callManager.endCall();
                      },
                    ),

                    const SizedBox(width: 6),

                    // 3. Maximize Button
                    _buildActionButton(
                      icon: Icons.open_in_full_rounded,
                      iconColor: Colors.white.withValues(alpha: 0.85),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      iconSize: 17,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        widget.callManager.maximize();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedWave() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, _) {
        final val = _waveController.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _waveBar(4 + (val * 6)),
            const SizedBox(width: 2),
            _waveBar(9 - (val * 5)),
            const SizedBox(width: 2),
            _waveBar(5 + (val * 5)),
          ],
        );
      },
    );
  }

  Widget _waveBar(double height) {
    return Container(
      width: 2.2,
      height: height.clamp(3.0, 11.0),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981),
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required VoidCallback onPressed,
    double iconSize = 19,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: iconSize,
          color: iconColor,
        ),
      ),
    );
  }
}
