import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import 'direct_chat_screen.dart';

class ChatInboxScreen extends StatefulWidget {
  final bool isListener;

  const ChatInboxScreen({
    super.key,
    this.isListener = false,
  });

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ChatThreadModel> _threads = [];
  List<ChatThreadModel> _filteredThreads = [];
  bool _loading = true;
  Timer? _pollTimer;
  double _balance = 0.0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadThreads();
    _loadBalance();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollThreads());
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredThreads = _threads;
      } else {
        _filteredThreads = _threads.where((t) {
          final name = t.otherUserName.toLowerCase();
          final msg = (t.lastMessageText ?? '').toLowerCase();
          return name.contains(query) || msg.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadBalance() async {
    try {
      final app = context.read<AppController>();
      if (widget.isListener) {
        final profile = app.expertProfile;
        if (profile != null && profile['earnings'] != null) {
          final val = num.tryParse(profile['earnings'].toString()) ?? 0;
          if (mounted) setState(() => _balance = val.toDouble());
        }
      } else {
        final w = await app.api.wallet();
        if (mounted) setState(() => _balance = w.balance.toDouble());
      }
    } catch (_) {}
  }

  Future<void> _loadThreads() async {
    final api = context.read<AppController>().api;
    try {
      final raw = await api.getInboxThreads();
      final list = raw.map((e) => ChatThreadModel.fromJson(e)).toList();
      if (mounted) {
        setState(() {
          _threads = list;
          _filterThreads();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading inbox threads: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pollThreads() async {
    final api = context.read<AppController>().api;
    try {
      final raw = await api.getInboxThreads();
      final list = raw.map((e) => ChatThreadModel.fromJson(e)).toList();
      if (mounted) {
        setState(() {
          _threads = list;
          _filterThreads();
        });
      }
    } catch (_) {}
  }

  void _filterThreads() {
    if (_searchQuery.isEmpty) {
      _filteredThreads = _threads;
    } else {
      _filteredThreads = _threads.where((t) {
        final name = t.otherUserName.toLowerCase();
        final msg = (t.lastMessageText ?? '').toLowerCase();
        return name.contains(_searchQuery) || msg.contains(_searchQuery);
      }).toList();
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(timeStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inDays == 0 && dt.day == now.day) {
        final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
        final minute = dt.minute.toString().padLeft(2, '0');
        final period = dt.hour >= 12 ? 'PM' : 'AM';
        return '$hour:$minute $period';
      } else if (diff.inDays == 1 || (now.day - dt.day == 1 && diff.inDays < 2)) {
        return 'Yesterday';
      } else {
        return '${dt.day}/${dt.month}';
      }
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: const Text(
          'Chat',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '₹${_balance.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFFF59E0B),
                      ),
                    )
                  : _filteredThreads.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          color: const Color(0xFFF59E0B),
                          onRefresh: () async {
                            await _loadThreads();
                            await _loadBalance();
                          },
                          child: ListView.separated(
                            itemCount: _filteredThreads.length,
                            separatorBuilder: (ctx, i) => const Divider(
                              height: 1,
                              thickness: 0.6,
                              indent: 74,
                              endIndent: 16,
                              color: Color(0xFFF1F5F9),
                            ),
                            itemBuilder: (ctx, i) {
                              final thread = _filteredThreads[i];
                              return _buildThreadTile(thread);
                            },
                          ),
                        ),
            ),
            _buildSearchBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7).withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No conversations yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.isListener
                  ? 'Callers who talk with you or reply to your messages will appear here.'
                  : 'Send a message to your favorite listeners to connect and chat anytime.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadTile(ChatThreadModel thread) {
    final hasUnread = thread.unreadCount > 0;
    final timeStr = _formatTime(thread.lastMessageAt);

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DirectChatScreen(
              threadId: thread.threadId,
              otherUserId: thread.otherUserId,
              otherUserName: thread.otherUserName,
              otherUserAvatar: thread.otherUserAvatar,
              otherUserRole: thread.otherUserRole,
              ratePerMinute: thread.ratePerMinute,
            ),
          ),
        );
        _loadThreads();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(0xFFEFF6FF),
                  backgroundImage: (thread.otherUserAvatar != null && thread.otherUserAvatar!.isNotEmpty)
                      ? NetworkImage(thread.otherUserAvatar!)
                      : null,
                  child: (thread.otherUserAvatar == null || thread.otherUserAvatar!.isEmpty)
                      ? Text(
                          thread.otherUserName.isNotEmpty ? thread.otherUserName[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3B82F6),
                          ),
                        )
                      : null,
                ),
                if (thread.presenceStatus == 'ONLINE')
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),

            // Name + last message preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.otherUserName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                      color: const Color(0xFF0F172A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    thread.lastMessageText ?? 'Tap to chat',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
                      color: hasUnread ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Right side: "To reply 1" badge & timestamp
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasUnread) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      border: Border.all(color: const Color(0xFFF43F5E), width: 1.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'To reply ${thread.unreadCount}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE11D48),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              size: 22,
              color: Color(0xFF64748B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: Color(0xFF1E293B),
                ),
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(
                    fontSize: 14.5,
                    color: Color(0xFF94A3B8),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () => _searchController.clear(),
                child: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
              )
            else
              const Icon(
                Icons.tune_rounded,
                size: 20,
                color: Color(0xFF64748B),
              ),
          ],
        ),
      ),
    );
  }
}
