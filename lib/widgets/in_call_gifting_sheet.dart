import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_controller.dart';
import '../models/app_models.dart';

class InCallGiftingSheet extends StatefulWidget {
  final String sessionId;
  final String listenerName;
  final VoidCallback? onRechargeRequested;
  final Function(Map<String, dynamic> gift)? onGiftSent;

  const InCallGiftingSheet({
    super.key,
    required this.sessionId,
    required this.listenerName,
    this.onRechargeRequested,
    this.onGiftSent,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String sessionId,
    required String listenerName,
    VoidCallback? onRechargeRequested,
    Function(Map<String, dynamic> gift)? onGiftSent,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InCallGiftingSheet(
        sessionId: sessionId,
        listenerName: listenerName,
        onRechargeRequested: onRechargeRequested,
        onGiftSent: onGiftSent,
      ),
    );
  }

  @override
  State<InCallGiftingSheet> createState() => _InCallGiftingSheetState();
}

class _InCallGiftingSheetState extends State<InCallGiftingSheet> {
  static const List<Map<String, dynamic>> defaultGifts = [
    {'id': 'ROSE', 'name': 'Rose', 'emoji': '🌹', 'price': 10, 'description': 'A sweet token of warmth & appreciation'},
    {'id': 'CHOCOLATE', 'name': 'Chocolate', 'emoji': '🍫', 'price': 20, 'description': 'Sweet treat to brighten the conversation'},
    {'id': 'COFFEE', 'name': 'Coffee', 'emoji': '☕', 'price': 25, 'description': 'Energizing comfort and good vibes'},
    {'id': 'HEART', 'name': 'Heart', 'emoji': '💖', 'price': 50, 'description': 'Deep appreciation and heartfelt thanks'},
    {'id': 'PIZZA', 'name': 'Pizza', 'emoji': '🍕', 'price': 75, 'description': 'Fun snack treat for an awesome listener'},
    {'id': 'CROWN', 'name': 'Crown', 'emoji': '👑', 'price': 100, 'description': 'For an exceptional, royal listener'},
    {'id': 'DIAMOND', 'name': 'Diamond', 'emoji': '💎', 'price': 150, 'description': 'Precious advice and priceless time'},
    {'id': 'LUCKY_BOX', 'name': 'Lucky Box', 'emoji': '🎁', 'price': 200, 'description': 'A bundle of gratitude and positive energy'},
    {'id': 'ROCKET', 'name': 'Super Star', 'emoji': '🚀', 'price': 250, 'description': 'Outstanding support that made my day'},
    {'id': 'UNICORN', 'name': 'Unicorn', 'emoji': '🦄', 'price': 350, 'description': 'Magical presence and truly rare connection'},
    {'id': 'TROPHY', 'name': 'Trophy', 'emoji': '🏆', 'price': 500, 'description': 'Ultimate champion listener & highest gratitude'},
  ];

  static const List<String> presetNotes = [
    'Thank you for listening! 🙏',
    'You made my day brighter ☀️',
    'Amazing conversation ✨',
    'Appreciate your advice 💡',
  ];

  late List<Map<String, dynamic>> gifts = List.from(defaultGifts);
  String selectedGiftId = 'HEART';
  WalletModel? wallet;
  bool loadingWallet = true;
  bool sending = false;
  String? error;
  final TextEditingController noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _loadCatalog();
  }

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  void _loadWallet() {
    context.read<AppController>().api.wallet().then((w) {
      if (mounted) {
        setState(() {
          wallet = w;
          loadingWallet = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => loadingWallet = false);
    });
  }

  void _loadCatalog() {
    context.read<AppController>().api.gifts().then((list) {
      if (mounted && list.isNotEmpty) {
        setState(() {
          gifts = list.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    }).catchError((_) {});
  }

  Map<String, dynamic> get selectedGift {
    return gifts.firstWhere(
      (g) => '${g['id'] ?? g['giftType'] ?? g['name']}' == selectedGiftId,
      orElse: () => gifts.first,
    );
  }

  double get selectedPrice {
    final raw = selectedGift['price'];
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw') ?? 0.0;
  }

  bool get hasEnoughBalance {
    final balance = wallet?.totalBalance ?? 0.0;
    return balance >= selectedPrice;
  }

  Future<void> _handleSend() async {
    if (!hasEnoughBalance) {
      setState(() => error = 'Insufficient balance. You need at least ₹${selectedPrice.toStringAsFixed(0)}.');
      return;
    }

    setState(() {
      sending = true;
      error = null;
    });

    try {
      final note = noteController.text.trim();
      final giftType = '${selectedGift['id'] ?? selectedGift['giftType'] ?? selectedGift['name']}';
      final sent = await context.read<AppController>().api.sendGift(
        widget.sessionId,
        giftType,
        note: note.isNotEmpty ? note : null,
      );

      // Broadcast signal so listener receives immediate animated in-call gift alert
      await context.read<AppController>().api.sendSignal(
        widget.sessionId,
        {'type': 'gift_sent', 'gift': sent},
      );

      if (widget.onGiftSent != null) {
        widget.onGiftSent!(sent);
      }

      if (mounted) {
        Navigator.pop(context, sent);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString().replaceFirst('Exception: ', '');
          sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final totalBalance = wallet?.totalBalance ?? 0.0;
    final gift = selectedGift;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF131B2E), Color(0xFF0C1220)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.35), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFEC4899)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withOpacity(0.4),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Send a Virtual Gift',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Text(
                            'Express appreciation to ${widget.listenerName}',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // Wallet Balance Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFF59E0B), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Wallet Balance: ₹${totalBalance.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (!hasEnoughBalance)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.35)),
                          ),
                          child: const Text(
                            'Low Balance',
                            style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      if (widget.onRechargeRequested != null)
                        InkWell(
                          onTap: widget.onRechargeRequested,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.add_circle_outline_rounded, color: Color(0xFF38BDF8), size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Recharge',
                                  style: TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Scrollable Cards Grid & Notes
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Grid of Compact Gift Cards
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 1.05,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: gifts.length,
                        itemBuilder: (ctx, idx) {
                          final g = gifts[idx];
                          final id = '${g['id'] ?? g['giftType'] ?? g['name']}';
                          final isSelected = id == selectedGiftId;
                          final price = (g['price'] as num?)?.toDouble() ?? 0.0;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                selectedGiftId = id;
                                error = null;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF1E293B)
                                    : Colors.white.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFF59E0B)
                                      : Colors.white.withOpacity(0.08),
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFFF59E0B).withOpacity(0.3),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${g['emoji'] ?? '🎁'}',
                                    style: const TextStyle(fontSize: 24),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${g['name'] ?? 'Gift'}',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withOpacity(isSelected ? 0.25 : 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '₹${price.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: Color(0xFFFBBF24),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      // Selected Gift Description
                      if (gift['description'] != null && '${gift['description']}'.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Center(
                            child: Text(
                              '${gift['emoji']} ${gift['description']}',
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),

                      // Preset Notes Chips
                      const Text(
                        'QUICK NOTE',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: presetNotes.map((note) {
                            final isCurrent = noteController.text == note;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    noteController.text = isCurrent ? '' : note;
                                  });
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? const Color(0xFFEC4899).withOpacity(0.2)
                                        : Colors.white.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isCurrent
                                          ? const Color(0xFFEC4899)
                                          : Colors.white.withOpacity(0.1),
                                    ),
                                  ),
                                  child: Text(
                                    note,
                                    style: TextStyle(
                                      color: isCurrent ? const Color(0xFFF472B6) : const Color(0xFFCBD5E1),
                                      fontSize: 11,
                                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Custom Note Input
                      TextField(
                        controller: noteController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        maxLines: 1,
                        decoration: InputDecoration(
                          hintText: 'Add a personal note... (optional)',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.04),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                          ),
                        ),
                      ),

                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFFCA5A5), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  error!,
                                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Bottom Send Action Button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: (sending || !hasEnoughBalance) ? (hasEnoughBalance ? null : widget.onRechargeRequested) : _handleSend,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                      backgroundColor: Colors.transparent,
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: hasEnoughBalance
                            ? const LinearGradient(
                                colors: [Color(0xFFF59E0B), Color(0xFFEC4899)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              )
                            : LinearGradient(
                                colors: [Colors.grey.shade700, Colors.grey.shade800],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: hasEnoughBalance
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFF59E0B).withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                hasEnoughBalance
                                    ? 'Send ${gift['emoji'] ?? '🎁'} for ₹${selectedPrice.toStringAsFixed(0)}'
                                    : 'Insufficient Balance (Recharge ₹${selectedPrice.toStringAsFixed(0)})',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
