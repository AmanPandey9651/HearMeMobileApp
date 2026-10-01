import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../main.dart';
import '../../widgets/common_widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> items = [];
  bool loading = true;

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await context.read<AppController>().api.notifications();
      if (mounted) {
        setState(() {
          items = list;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _markAllRead() async {
    try {
      await context.read<AppController>().api.readAllNotifications();
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await confirm(
      context,
      'Clear all notifications?',
      'This will remove all notifications from your account.',
    );
    if (!confirmed) return;
    try {
      await context.read<AppController>().api.clearNotifications();
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String _fmt(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString();
    final d = DateTime.tryParse(s)?.toLocal();
    if (d == null) return s;
    return s; // Display original formatted or ISO as shown in screenshot
  }

  @override
  Widget build(BuildContext context) {
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
                // Top Header matching Image 2
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
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
                      const Expanded(
                        child: Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: textDark,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      // Double checkmark (mark all read)
                      IconButton(
                        tooltip: 'Mark all as read',
                        icon: const Icon(Icons.done_all_rounded, color: textDark, size: 22),
                        onPressed: _markAllRead,
                      ),
                      // Trash (clear all)
                      IconButton(
                        tooltip: 'Clear all',
                        icon: const Icon(Icons.delete_outline_rounded, color: textDark, size: 22),
                        onPressed: _clearAll,
                      ),
                    ],
                  ),
                ),

                // Notifications List
                Expanded(
                  child: loading
                      ? const LoadingBody()
                      : RefreshIndicator(
                          color: primaryOrange,
                          onRefresh: _load,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(18, 4, 18, 40),
                            children: [
                              if (items.isEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 40),
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: borderWarm),
                                  ),
                                  child: const Center(
                                    child: Column(
                                      children: [
                                        Icon(Icons.notifications_none_rounded, size: 48, color: Color(0xFFD1D5DB)),
                                        SizedBox(height: 12),
                                        Text(
                                          'No notifications yet',
                                          style: TextStyle(color: textDark, fontWeight: FontWeight.w700, fontSize: 16),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'You will be notified about incoming calls, requests and sessions.',
                                          style: TextStyle(color: textMuted, fontSize: 13),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              ...items.map((x) {
                                final m = Map<String, dynamic>.from(x as Map);
                                final isRead = m['isRead'] == true || m['readAt'] != null;
                                final title = '${m['title'] ?? 'Notification'}';
                                final body = '${m['content'] ?? m['body'] ?? m['message'] ?? ''}';
                                final timeStr = _fmt(m['createdAt']);

                                return InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () async {
                                    if (!isRead) {
                                      await context.read<AppController>().api.readNotification('${m['id']}');
                                      _load();
                                    }
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
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
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // Left Icon Badge with glowing peach rounded squircle
                                        _NotificationIconBadge(title: title),
                                        const SizedBox(width: 14),

                                        // Center Column: Title, Body, Timestamp
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                title,
                                                style: const TextStyle(
                                                  color: textDark,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: -0.2,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                body,
                                                style: const TextStyle(
                                                  color: Color(0xFF4B5563),
                                                  fontSize: 13,
                                                  height: 1.35,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  const Icon(Icons.access_time_rounded, size: 13.5, color: textMuted),
                                                  const SizedBox(width: 5),
                                                  Expanded(
                                                    child: Text(
                                                      timeStr,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: textMuted,
                                                        fontSize: 11.5,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),

                                        // Right Column: Unread orange dot + Chevron right
                                        Column(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            // Orange unread dot
                                            if (!isRead)
                                              Container(
                                                width: 9,
                                                height: 9,
                                                decoration: const BoxDecoration(
                                                  color: primaryOrange,
                                                  shape: BoxShape.circle,
                                                ),
                                              )
                                            else
                                              const SizedBox(height: 9),
                                            const SizedBox(height: 18),
                                            const Icon(
                                              Icons.chevron_right_rounded,
                                              color: textDark,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
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

/// Stylized orange icon badge matching Image 2
class _NotificationIconBadge extends StatelessWidget {
  final String title;
  const _NotificationIconBadge({required this.title});

  @override
  Widget build(BuildContext context) {
    final t = title.toUpperCase();
    IconData iconData = Icons.notifications_rounded;
    if (t.contains('VIDEO')) {
      iconData = Icons.videocam_rounded;
    } else if (t.contains('AUDIO') || t.contains('CALL') && !t.contains('REQUEST')) {
      iconData = Icons.phone_rounded;
    } else if (t.contains('CONCLUDED') || t.contains('COMPLETED')) {
      iconData = Icons.check_circle_outline_rounded;
    } else if (t.contains('CHAT')) {
      iconData = Icons.chat_bubble_rounded;
    } else if (t.contains('ONLINE') || t.contains('COME ONLINE') || t.contains('REQUEST:')) {
      iconData = Icons.group_add_rounded;
    }

    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft peach blurred glow aura behind icon
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFFECE5).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(18),
            ),
          ),

          // Little satellite dots
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFFF9E70),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 1,
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: Color(0xFFFF9E70),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // Main bright gradient squircle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF8543), Color(0xFFF95B3D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF95B3D).withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(iconData, color: Colors.white, size: 21),
            ),
          ),
        ],
      ),
    );
  }
}
