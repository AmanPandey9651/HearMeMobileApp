import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_controller.dart';
import '../models/app_models.dart';
import 'common_widgets.dart';

class ListenerCardItem extends StatelessWidget {
  final ListenerCardModel listener;
  final VoidCallback onTap;
  final void Function(String sessionType)? onDirectCall;
  final VoidCallback? onConnect;
  final bool isPublic;

  const ListenerCardItem({
    super.key,
    required this.listener,
    required this.onTap,
    this.onDirectCall,
    this.onConnect,
    this.isPublic = false,
  });

  static const List<String> _fallbackAvatars = [
    'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=300&fit=crop&crop=faces',
    'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=300&fit=crop&crop=faces',
    'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=300&fit=crop&crop=faces',
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300&fit=crop&crop=faces',
    'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=300&fit=crop&crop=faces',
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=300&fit=crop&crop=faces',
  ];

  String _getResolvedAvatar() {
    final clean = normalizeAvatarUrl(listener.avatarUrl);
    if (clean != null && clean.isNotEmpty) return clean;
    final idx = (listener.displayName.hashCode.abs()) % _fallbackAvatars.length;
    return _fallbackAvatars[idx];
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = listener.presence == 'ONLINE';
    final isBusy = listener.presence == 'BUSY_IN_CALL' || listener.presence == 'BUSY';

    final Color statusColor;
    final String statusLabel;
    if (isOnline) {
      statusColor = const Color(0xFF10B981);
      statusLabel = 'Online now';
    } else if (isBusy) {
      statusColor = const Color(0xFFF59E0B);
      statusLabel = 'Busy in Call';
    } else {
      statusColor = const Color(0xFF64748B);
      statusLabel = 'Offline';
    }

    final categories = listener.categories.isNotEmpty
        ? listener.categories
        : ['Anxiety', 'Life Transitions', 'Self-Esteem'];

    final headline = listener.professionalTitle.isNotEmpty
        ? listener.professionalTitle
        : 'Empathetic Listener & Guide';

    final bio = listener.bio.isNotEmpty
        ? listener.bio
        : 'Here to listen, without judgment. You deserve to be heard.';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF1E6D8),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E293B).withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. Left: Profile Image with top-left beacon dot and bottom "Online now" pill
                    SizedBox(
                      width: 68,
                      height: 68,
                      child: Stack(
                        children: [
                          // Square photo with rounded corners
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: buildAvatarImage(
                              _getResolvedAvatar(),
                              width: 68,
                              height: 68,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFF95B3D), Color(0xFFFF7A45)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Text(
                                    listener.displayName.isNotEmpty
                                        ? listener.displayName.substring(0, 1).toUpperCase()
                                        : 'L',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                      // Top-left status beacon dot
                      Positioned(
                        top: 5,
                        left: 5,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: isOnline
                                ? [
                                    BoxShadow(
                                      color: statusColor.withValues(alpha: 0.6),
                                      blurRadius: 5,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),

                      // Bottom "Online now" overlay pill
                      Positioned(
                        bottom: 4,
                        left: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.35),
                              width: 0.6,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  statusLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w700,
                                    color: isOnline ? Colors.white : const Color(0xFFCBD5E1),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // 2. Center: Details (Name + Verified + Rating, Headline, Topic Pills, Bio)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Line 1: Name + Verified Checkmark + Star Rating
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              listener.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                                color: Color(0xFF111827),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            size: 14,
                            color: Color(0xFFF95B3D),
                          ),
                          if (listener.isAdult) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF1F2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFFDA4AF),
                                  width: 0.8,
                                ),
                              ),
                              child: const Text(
                                '🔞 18+',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFE11D48),
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 13.5,
                                color: Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                listener.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              Text(
                                ' (${listener.reviewCount > 0 ? listener.reviewCount : 120})',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 2),

                      // Line 2: Headline
                      Text(
                        headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                        ),
                      ),

                      const SizedBox(height: 5),

                      // Line 3: Topic Pills (Take up to 3)
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: categories.take(3).map((cat) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F5F7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              cat,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 5),

                      // Line 4: Bio Quote Snippet
                      Text(
                        bio,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF6B7280),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 6),

                // 3. Right: Vertical 3-Button Stack (Chat, Call, Video) with Live Rates
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Top: Chat (Warm Peach + Orange Icon + Rate)
                    _ActionButton(
                      icon: Icons.chat_bubble_rounded,
                      rate: listener.chatRate,
                      isEnabled: listener.chatAvailable,
                      onTap: () {
                        if (isPublic) {
                          onConnect?.call();
                          return;
                        }
                        if (!listener.chatAvailable) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${listener.displayName} is currently not accepting chat sessions.')),
                          );
                          return;
                        }
                        if (onDirectCall != null) {
                          onDirectCall!('CHAT');
                        } else {
                          onTap();
                        }
                      },
                    ),

                    const SizedBox(height: 5),

                    // Middle: Voice Call (Warm Peach + Orange Icon + Rate)
                    _ActionButton(
                      icon: Icons.call_rounded,
                      rate: listener.audioRate,
                      isEnabled: listener.audioAvailable,
                      onTap: () {
                        if (isPublic) {
                          onConnect?.call();
                          return;
                        }
                        if (!listener.audioAvailable) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${listener.displayName} is currently not accepting audio calls.')),
                          );
                          return;
                        }
                        if (onDirectCall != null) {
                          onDirectCall!('AUDIO_CALL');
                        } else {
                          onTap();
                        }
                      },
                    ),

                    const SizedBox(height: 5),

                    // Bottom: Video Call (Warm Peach + Orange Icon + Rate)
                    _ActionButton(
                      icon: Icons.videocam_rounded,
                      rate: listener.videoRate,
                      isEnabled: listener.videoAvailable,
                      onTap: () {
                        if (isPublic) {
                          onConnect?.call();
                          return;
                        }
                        if (!listener.videoAvailable) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${listener.displayName} is currently not accepting video calls.')),
                          );
                          return;
                        }
                        if (onDirectCall != null) {
                          onDirectCall!('VIDEO_CALL');
                        } else {
                          onTap();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            if (!isOnline && !isBusy) ...[
              const SizedBox(height: 10),
              _OfflineNudgeBar(listener: listener),
            ],
          ],
        ),
      ),
    ),
  ),
);
  }
}

class _OfflineNudgeBar extends StatefulWidget {
  final ListenerCardModel listener;
  const _OfflineNudgeBar({required this.listener});

  @override
  State<_OfflineNudgeBar> createState() => _OfflineNudgeBarState();
}

class _OfflineNudgeBarState extends State<_OfflineNudgeBar> {
  bool _nudged = false;
  bool _loading = false;

  Future<void> _handleNudge() async {
    if (_nudged || _loading) return;
    setState(() => _loading = true);
    try {
      final app = context.read<AppController>();
      final result = await app.api.nudge(widget.listener.id);
      if (mounted) {
        final success = result['success'] != false;
        if (success) {
          setState(() => _nudged = true);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  success ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result['message']?.toString() ??
                        (success
                            ? 'Notification sent! ${widget.listener.displayName} has been alerted.'
                            : 'Could not notify listener.'),
                  ),
                ),
              ],
            ),
            backgroundColor: success ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_nudged) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF059669)),
            SizedBox(width: 6),
            Text(
              'Request Sent! Listener notified to come online',
              style: TextStyle(
                color: Color(0xFF065F46),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _loading ? null : _handleNudge,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFDE68A)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706)),
                )
              else
                const Icon(Icons.notifications_active_rounded, size: 15, color: Color(0xFFD97706)),
              const SizedBox(width: 6),
              Text(
                _loading ? 'Sending notification…' : 'Notify Listener to Come Online',
                style: const TextStyle(
                  color: Color(0xFF92400E),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final double rate;
  final bool isEnabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.rate,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rateLabel = rate > 0 ? '₹${rate.toStringAsFixed(0)}/m' : 'Free';
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.35,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFECE5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFCDFD5),
                width: 0.8,
              ),
              boxShadow: isEnabled
                  ? [
                      BoxShadow(
                        color: const Color(0xFFF95B3D).withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 1.5),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: const Color(0xFFF95B3D),
                ),
                const SizedBox(width: 3.5),
                Text(
                  rateLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFE04F2E),
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
