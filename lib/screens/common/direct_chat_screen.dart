import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';

class DirectChatScreen extends StatefulWidget {
  final String? threadId;
  final String? otherUserId;
  final String? otherUserName;
  final String? otherUserAvatar;
  final String? otherUserRole;
  final double? ratePerMinute;

  const DirectChatScreen({
    super.key,
    this.threadId,
    this.otherUserId,
    this.otherUserName,
    this.otherUserAvatar,
    this.otherUserRole,
    this.ratePerMinute,
  });

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends State<DirectChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<DirectChatMessageModel> _messages = [];
  String? _currentThreadId;
  bool _loading = true;
  bool _sending = false;
  Timer? _refreshTimer;

  static const List<String> _presets = [
    "Dobara call kar sakte ho",
    "Call mee",
    "Ab idhar chat pe bhi bata sakte ho",
    "Busy ho msg me bta do",
    "Call krlo",
    "Sorry, call kat gaya",
    "Shayad apka network week tha,",
    "I am free now 😊"
  ];

  @override
  void initState() {
    super.initState();
    _currentThreadId = widget.threadId;
    _initChat();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollMessages());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    final api = context.read<AppController>().api;
    try {
      if (_currentThreadId == null && widget.otherUserId != null) {
        final threadData = await api.getOrCreateInboxThread(widget.otherUserId!);
        _currentThreadId = threadData['threadId']?.toString();
      }

      if (_currentThreadId != null) {
        await _fetchMessages();
        api.markInboxThreadRead(_currentThreadId!).catchError((_) {});
      }
    } catch (e) {
      debugPrint('Error init chat: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchMessages() async {
    if (_currentThreadId == null) return;
    final api = context.read<AppController>().api;
    try {
      final raw = await api.getInboxMessages(_currentThreadId!);
      final list = raw.map((e) => DirectChatMessageModel.fromJson(e)).toList().reversed.toList();
      if (mounted) {
        setState(() => _messages = list);
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _pollMessages() async {
    if (_currentThreadId == null) return;
    final api = context.read<AppController>().api;
    try {
      final raw = await api.getInboxMessages(_currentThreadId!);
      final list = raw.map((e) => DirectChatMessageModel.fromJson(e)).toList().reversed.toList();
      if (mounted && list.length != _messages.length) {
        setState(() => _messages = list);
        _scrollToBottom();
        api.markInboxThreadRead(_currentThreadId!).catchError((_) {});
      }
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = (presetText ?? _textController.text).trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _textController.clear();
    final api = context.read<AppController>().api;

    try {
      if (_currentThreadId != null) {
        final res = await api.sendInboxMessage(_currentThreadId!, text);
        _messages.add(DirectChatMessageModel.fromJson(res));
      } else if (widget.otherUserId != null) {
        final res = await api.sendInboxMessageDirect(widget.otherUserId!, text);
        final newMsg = DirectChatMessageModel.fromJson(res);
        _currentThreadId = newMsg.threadId;
        _messages.add(newMsg);
      }
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.read<AppController>().user?.id;
    final displayName = widget.otherUserName ?? 'Chat';

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: const Color(0xFFE5E7EB),
              backgroundImage: widget.otherUserAvatar != null && widget.otherUserAvatar!.isNotEmpty
                  ? NetworkImage(widget.otherUserAvatar!)
                  : null,
              child: widget.otherUserAvatar == null || widget.otherUserAvatar!.isEmpty
                  ? Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Online',
                    style: TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_in_talk, color: Color(0xFFF59E0B)),
            tooltip: 'Call Now',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Connecting call with $displayName...')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // MESSAGES LIST
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFF59E0B)))
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'No messages yet.\nSend a message to start talking!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[500], fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final msg = _messages[i];
                          final isMe = msg.senderId == myId;

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: isMe ? const Color(0xFFF59E0B) : const Color(0xFFE5E7EB),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(18),
                                  topRight: const Radius.circular(18),
                                  bottomLeft: Radius.circular(isMe ? 18 : 3),
                                  bottomRight: Radius.circular(isMe ? 3 : 18),
                                ),
                              ),
                              child: Text(
                                msg.text,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: isMe ? FontWeight.w600 : FontWeight.w500,
                                  color: isMe ? Colors.black87 : Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // QUICK PRESET PILLS BAR
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.white,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final preset = _presets[i];
                return ActionChip(
                  label: Text(preset, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
                  backgroundColor: const Color(0xFFF3F4F6),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _sendMessage(preset),
                );
              },
            ),
          ),

          // BOTTOM MESSAGE INPUT
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _textController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFFF59E0B),
                    child: IconButton(
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                            )
                          : const Icon(Icons.send, color: Colors.black87, size: 18),
                      onPressed: _sending ? null : () => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
