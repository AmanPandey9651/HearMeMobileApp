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

  // Tab & User Directory State
  int _selectedTabIndex = 0; // 0 = Messages, 1 = All Users
  String _statusFilter = 'ALL'; // ALL, ONLINE, BUSY, OFFLINE
  List<DiscoverUserModel> _discoverUsers = [];
  List<DiscoverUserModel> _filteredDiscoverUsers = [];
  bool _loadingDiscover = false;

  bool get _isExpertUser {
    if (widget.isListener) return true;
    try {
      final role = context.read<AppController>().user?.role;
      return role == 'EXPERT' || role == 'LISTENER';
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadThreads();
    _loadBalance();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_selectedTabIndex == 0) {
        _pollThreads();
      }
    });
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
      _filterThreads();
      _filterDiscoverUsers();
    });
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

  void _filterDiscoverUsers() {
    if (_searchQuery.isEmpty) {
      _filteredDiscoverUsers = _discoverUsers;
    } else {
      _filteredDiscoverUsers = _discoverUsers.where((u) {
        final name = u.name.toLowerCase();
        return name.contains(_searchQuery);
      }).toList();
    }
  }

  Future<void> _loadBalance() async {
    try {
      final app = context.read<AppController>();
      if (widget.isListener || _isExpertUser) {
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
      final list = raw
          .map((e) => ChatThreadModel.fromJson(e))
          .where((t) => t.lastMessageText != null && t.lastMessageText!.trim().isNotEmpty && t.lastMessageText != 'Conversation started')
          .toList();
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
      final list = raw
          .map((e) => ChatThreadModel.fromJson(e))
          .where((t) => t.lastMessageText != null && t.lastMessageText!.trim().isNotEmpty && t.lastMessageText != 'Conversation started')
          .toList();
      if (mounted) {
        setState(() {
          _threads = list;
          _filterThreads();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDiscoverUsers() async {
    final api = context.read<AppController>().api;
    if (mounted) setState(() => _loadingDiscover = true);
    try {
      final list = await api.getDiscoverUsers(
        status: _statusFilter,
        search: _searchQuery,
      );
      if (mounted) {
        setState(() {
          _discoverUsers = list;
          _filterDiscoverUsers();
          _loadingDiscover = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading discover users: $e');
      if (mounted) setState(() => _loadingDiscover = false);
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
    final isExpert = _isExpertUser;

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
            // SEGMENTED TAB SWITCHER (FOR BOTH LISTENERS AND USERS)
            _buildSegmentedTabBar(),

            // FILTER CHIPS ROW (WHEN DISCOVER TAB IS SELECTED)
            if (_selectedTabIndex == 1) _buildFilterChips(),

            // MAIN CONTENT VIEW (THREADS OR DISCOVER USERS)
            Expanded(
              child: _selectedTabIndex == 0
                  ? _buildThreadsView()
                  : _buildDiscoverUsersView(),
            ),

            // SEARCH BAR AT BOTTOM
            _buildSearchBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedTabIndex = 0);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _selectedTabIndex == 0 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedTabIndex == 0
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_rounded,
                      size: 16,
                      color: _selectedTabIndex == 0 ? const Color(0xFFD97706) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _threads.isNotEmpty ? 'Messages (${_threads.length})' : 'Messages',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: _selectedTabIndex == 0 ? FontWeight.w700 : FontWeight.w500,
                        color: _selectedTabIndex == 0 ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedTabIndex = 1);
                if (_discoverUsers.isEmpty) {
                  _loadDiscoverUsers();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: _selectedTabIndex == 1 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedTabIndex == 1
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_alt_rounded,
                      size: 16,
                      color: _selectedTabIndex == 1 ? const Color(0xFFD97706) : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isExpertUser ? 'All Users' : 'All Listeners',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: _selectedTabIndex == 1 ? FontWeight.w700 : FontWeight.w500,
                        color: _selectedTabIndex == 1 ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    const filters = ['ALL', 'ONLINE', 'BUSY', 'OFFLINE'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: filters.map((f) {
          final isSelected = _statusFilter == f;
          Color dotColor = Colors.grey;
          String label = 'All';
          if (f == 'ONLINE') {
            dotColor = const Color(0xFF10B981);
            label = 'Online';
          } else if (f == 'BUSY') {
            dotColor = const Color(0xFFF59E0B);
            label = 'Busy';
          } else if (f == 'OFFLINE') {
            dotColor = const Color(0xFF94A3B8);
            label = 'Offline';
          }

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () {
                  setState(() => _statusFilter = f);
                  _loadDiscoverUsers();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFFEF3C7) : const Color(0xFFF8FAFC),
                    border: Border.all(
                      color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.4 : 0.8,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (f != 'ALL') ...[
                        Container(
                          width: 6.5,
                          height: 6.5,
                          decoration: BoxDecoration(
                            color: dotColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4.5),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected ? const Color(0xFFB45309) : const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildThreadsView() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Color(0xFFF59E0B),
        ),
      );
    }

    if (_filteredThreads.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
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
    );
  }

  Widget _buildDiscoverUsersView() {
    if (_loadingDiscover) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Color(0xFFF59E0B),
        ),
      );
    }

    if (_filteredDiscoverUsers.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7).withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.people_outline_rounded,
                  size: 36,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No $_statusFilter ${_isExpertUser ? "callers" : "listeners"} found',
                style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Try selecting another filter or searching a different name.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFF59E0B),
      onRefresh: () async {
        await _loadDiscoverUsers();
      },
      child: ListView.separated(
        itemCount: _filteredDiscoverUsers.length,
        separatorBuilder: (ctx, i) => const Divider(
          height: 1,
          thickness: 0.6,
          indent: 74,
          endIndent: 16,
          color: Color(0xFFF1F5F9),
        ),
        itemBuilder: (ctx, i) {
          final user = _filteredDiscoverUsers[i];
          return _buildDiscoverUserTile(user);
        },
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
              widget.isListener || _isExpertUser
                  ? 'Switch to "All Users" to view all callers and message them to invite them to come online!'
                  : 'Send a message to your favorite listeners to connect and chat anytime.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            if (widget.isListener || _isExpertUser) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _selectedTabIndex = 1);
                  _loadDiscoverUsers();
                },
                icon: const Icon(Icons.people_alt_rounded, size: 16),
                label: const Text('Browse All Users'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ],
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
            // Avatar with online dot
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

            // Right side: "To reply" badge & timestamp
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

  Widget _buildDiscoverUserTile(DiscoverUserModel user) {
    Color statusColor = const Color(0xFF94A3B8);
    String statusText = 'Offline';
    if (user.status == 'ONLINE') {
      statusColor = const Color(0xFF10B981);
      statusText = 'Online';
    } else if (user.status == 'BUSY') {
      statusColor = const Color(0xFFF59E0B);
      statusText = 'In a call';
    }

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DirectChatScreen(
              threadId: user.threadId,
              otherUserId: user.userId,
              otherUserName: user.name,
              otherUserAvatar: user.avatar,
              otherUserRole: user.role ?? (_isExpertUser ? 'USER' : 'EXPERT'),
              ratePerMinute: user.ratePerMinute,
            ),
          ),
        );
        _loadThreads();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // User Avatar with status dot
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(0xFFF1F5F9),
                  backgroundImage: (user.avatar != null && user.avatar!.isNotEmpty)
                      ? NetworkImage(user.avatar!)
                      : null,
                  child: (user.avatar == null || user.avatar!.isEmpty)
                      ? Text(
                          user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF59E0B),
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),

            // User Name + [New User] badge + Status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.name,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isNewUser) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '[New User]',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: user.status == 'ONLINE'
                              ? const Color(0xFF059669)
                              : const Color(0xFF64748B),
                        ),
                      ),
                      if (user.ratePerMinute != null) ...[
                        const SizedBox(width: 5),
                        const Text('•', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        const SizedBox(width: 5),
                        Text(
                          '₹${user.ratePerMinute!.toStringAsFixed(0)}/min',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                      if (user.category != null && user.ratePerMinute == null) ...[
                        const SizedBox(width: 5),
                        const Text('•', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            user.category!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // "Message" button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A), width: 1),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 14,
                    color: Color(0xFFB45309),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Message',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
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
                decoration: InputDecoration(
                  hintText: _selectedTabIndex == 0
                      ? 'Search messages...'
                      : (_isExpertUser ? 'Search callers by name...' : 'Search listeners by name...'),
                  hintStyle: const TextStyle(
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
