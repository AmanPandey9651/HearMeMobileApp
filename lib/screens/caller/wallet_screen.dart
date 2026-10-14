import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/app_controller.dart';
import '../../core/app_theme.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  WalletModel? wallet;
  List<dynamic> tx = [];
  bool loading = true;
  late final Razorpay razorpay;
  Map<String, dynamic>? pendingOrder;
  final search = TextEditingController();
  String type = 'ALL';
  String date = 'ALL';

  static const Color bgCream = AppTheme.bgCream;
  static const Color borderWarm = AppTheme.borderWarm;
  static const Color primaryOrange = AppTheme.primaryOrange;
  static const Color secondaryOrange = AppTheme.secondaryOrange;
  static const Color softPeach = AppTheme.softPeach;
  static const Color textDark = AppTheme.textDark;
  static const Color textMuted = AppTheme.textMuted;

  @override
  void initState() {
    super.initState();
    razorpay = Razorpay();
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _success);
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _failure);
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
    search.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    razorpay.clear();
    search.removeListener(_changed);
    search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final api = context.read<AppController>().api;
      final result = await Future.wait<dynamic>([api.wallet(), api.walletTransactions(page: 0, size: 100)]);
      if (mounted) {
        setState(() {
          wallet = result[0] as WalletModel;
          tx = List<dynamic>.from(result[1] as List);
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

  bool _dateOk(dynamic raw) {
    if (date == 'ALL') return true;
    final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (date == 'TODAY') return day == today;
    final n = date == '7_DAYS' ? 7 : 30;
    return !day.isBefore(today.subtract(Duration(days: n - 1))) && !day.isAfter(now);
  }

  List<Map<String, dynamic>> get filtered {
    final q = search.text.trim().toLowerCase();
    return tx.map((e) => Map<String, dynamic>.from(e as Map)).where((m) {
      final t = '${m['type'] ?? ''}';
      final qOk = q.isEmpty ||
          '${m['description'] ?? ''}'.toLowerCase().contains(q) ||
          '${m['referenceId'] ?? ''}'.toLowerCase().contains(q);
      return qOk && (type == 'ALL' || t == type) && _dateOk(m['createdAt']);
    }).toList();
  }

  Future<void> _recharge() async {
    final c = TextEditingController(text: '100');
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Recharge Wallet', style: TextStyle(fontWeight: FontWeight.bold, color: textDark)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select or enter amount in INR (minimum ₹10):',
              style: TextStyle(fontSize: 12.5, color: textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontWeight: FontWeight.bold, color: textDark),
              decoration: const InputDecoration(
                prefixText: '₹ ',
                prefixStyle: TextStyle(fontWeight: FontWeight.bold, color: textDark),
                labelText: 'Amount',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [50, 100, 200, 500].map((amt) {
                return ActionChip(
                  label: Text('₹$amt'),
                  backgroundColor: softPeach,
                  side: const BorderSide(color: Color(0xFFFCDFD5)),
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, color: primaryOrange, fontSize: 12),
                  onPressed: () => c.text = '$amt',
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: textMuted))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)),
            style: FilledButton.styleFrom(backgroundColor: primaryOrange),
            child: const Text('Continue to Pay'),
          ),
        ],
      ),
    );
    c.dispose();
    if (amount == null || amount < 10) return;
    try {
      final order = await context.read<AppController>().api.createRecharge(amount);
      pendingOrder = order;
      razorpay.open({
        'key': order['razorpayKeyId'],
        'amount': ((order['amount'] as num?)?.toDouble() ?? amount) * 100,
        'currency': order['currency'] ?? 'INR',
        'order_id': order['orderId'],
        'name': context.read<AppController>().activeBrandName,
        'description': 'Wallet recharge',
        'prefill': {
          'email': context.read<AppController>().user?.email ?? '',
          'contact': context.read<AppController>().user?.phoneNumber ?? '',
        },
        'theme': {'color': '#F95B3D'},
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _success(PaymentSuccessResponse r) async {
    final order = pendingOrder;
    if (order == null) return;
    try {
      await context.read<AppController>().api.verifyRecharge({
        'razorpayOrderId': r.orderId ?? order['orderId'],
        'razorpayPaymentId': r.paymentId,
        'razorpaySignature': r.signature,
        'amount': (order['amount'] as num).toDouble(),
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Recharge successful! Balance updated.'),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _failure(PaymentFailureResponse r) {
    if (mounted) showError(context, r.message ?? 'Payment failed');
  }

  String _fmt(dynamic raw) {
    final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    return d == null ? '${raw ?? ''}' : DateFormat('dd MMM yyyy, h:mm a').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final rows = filtered;

    if (loading) {
      return const Scaffold(
        backgroundColor: bgCream,
        body: Center(child: CircularProgressIndicator(color: primaryOrange)),
      );
    }

    return Scaffold(
      backgroundColor: bgCream,
      body: RefreshIndicator(
        color: primaryOrange,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 90),
          children: [
            // 1. Hero Balance Orange Gradient Card matching Screenshot 4
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF7A45), Color(0xFFFF5216)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5216).withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Left side content
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Available balance',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        wallet?.formattedBalance ?? '₹0.00',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if ((wallet?.bonusBalance ?? 0) > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Includes ₹${wallet!.bonusBalance.toStringAsFixed(2)} bonus',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFFFFECE5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // White pill button: Recharge with Razorpay
                      Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        child: InkWell(
                          onTap: _recharge,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.payment_rounded, color: primaryOrange, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  'Recharge with Razorpay',
                                  style: TextStyle(
                                    color: primaryOrange,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.chevron_right_rounded, color: primaryOrange, size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Right side: 3D stylized wallet graphic with rupee circle
                  Positioned(
                    top: -4,
                    right: 0,
                    child: _WalletHeroGraphic(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // 2. Section Header: "Transactions" & "98 of 98"
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Transactions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: textDark,
                  ),
                ),
                Text(
                  '${rows.length} of ${tx.length}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: primaryOrange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 3. Peach-tinted search bar matching Screenshot 4
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2EB),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFFCDFD5)),
              ),
              child: TextField(
                controller: search,
                style: const TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Search description or reference',
                  hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.normal),
                  prefixIcon: const Icon(Icons.search_rounded, color: primaryOrange, size: 20),
                  suffixIcon: search.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18, color: textMuted),
                          onPressed: () => search.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  filled: false,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 4. Filter Row: 2 Dropdown Cards matching Screenshot 4
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderWarm),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Type',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textMuted),
                        ),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            isDense: true,
                            value: type,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: primaryOrange, size: 20),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textDark),
                            items: const {
                              'ALL': 'All',
                              'RECHARGE': 'Recharge',
                              'CALL_DEBIT': 'Call debit',
                              'REFUND': 'Refund',
                              'GIFT_CREDIT': 'Gift credit',
                              'GIFT_DEBIT': 'Gift debit',
                            }.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                            onChanged: (v) => setState(() => type = v ?? 'ALL'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderWarm),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Date',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textMuted),
                        ),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            isDense: true,
                            value: date,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: primaryOrange, size: 20),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textDark),
                            items: const {
                              'ALL': 'All time',
                              'TODAY': 'Today',
                              '7_DAYS': '7 days',
                              '30_DAYS': '30 days',
                            }.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                            onChanged: (v) => setState(() => date = v ?? 'ALL'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            if (search.text.isNotEmpty || type != 'ALL' || date != 'ALL') ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    search.clear();
                    setState(() {
                      type = 'ALL';
                      date = 'ALL';
                    });
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 16, color: primaryOrange),
                  label: const Text('Reset filters', style: TextStyle(color: primaryOrange, fontWeight: FontWeight.w700)),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // 5. Transaction Cards matching Screenshot 4
            if (tx.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('No wallet transactions yet.', style: TextStyle(color: textMuted, fontWeight: FontWeight.w500)),
                ),
              ),
            if (tx.isNotEmpty && rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('No transactions match these filters.', style: TextStyle(color: textMuted, fontWeight: FontWeight.w500)),
                ),
              ),

            ...rows.map((m) {
              final rawAmt = m['amount'] is num ? (m['amount'] as num).toDouble() : double.tryParse('${m['amount'] ?? 0}') ?? 0;
              final desc = '${m['description'] ?? m['type'] ?? 'Transaction'}';
              final t = '${m['type'] ?? ''}'.toUpperCase();
              final ref = '${m['referenceId'] ?? ''}';
              final isCall = t.contains('CALL');
              final isGift = t.contains('GIFT');
              final isRecharge = t.contains('RECHARGE') || t.contains('CREDIT');
              final isNegative = rawAmt < 0 || (!isRecharge && !t.contains('REFUND'));
              final displayAmt = rawAmt.abs();

              // Icon & leading avatar matching Screenshot 4
              Widget leadingIcon;
              if (desc.toLowerCase().contains('coffee')) {
                leadingIcon = const Text('☕', style: TextStyle(fontSize: 22));
              } else if (desc.toLowerCase().contains('rose') || isGift) {
                leadingIcon = const Text('🎁', style: TextStyle(fontSize: 22));
              } else if (desc.toLowerCase().contains('video')) {
                leadingIcon = const Icon(Icons.videocam_rounded, color: primaryOrange, size: 20);
              } else if (isCall) {
                leadingIcon = const Icon(Icons.phone_rounded, color: primaryOrange, size: 20);
              } else {
                leadingIcon = Icon(
                  isNegative ? Icons.north_east_rounded : Icons.south_west_rounded,
                  color: isNegative ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                  size: 20,
                );
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderWarm),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.025),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isRecharge ? const Color(0xFFD1FAE5) : softPeach,
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: leadingIcon),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              desc,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: textDark,
                              ),
                            ),
                            if (isCall && m['durationMinutes'] != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '${m['durationMinutes']} mins',
                                style: const TextStyle(fontSize: 11.5, color: textMuted, fontWeight: FontWeight.w500),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              '${m['type'] ?? ''}${ref.isEmpty ? '' : ' • $ref'}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _fmt(m['createdAt']),
                              style: const TextStyle(
                                fontSize: 11,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${isNegative ? '-' : '+'} ₹${displayAmt.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: isNegative ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF), size: 18),
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
    );
  }
}

class _WalletHeroGraphic extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 95,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background soft angled card
          Transform.rotate(
            angle: -0.12,
            child: Container(
              width: 82,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          // Foreground glossy white wallet card
          Transform.rotate(
            angle: 0.05,
            child: Container(
              width: 86,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFF2EB),
                    border: Border.all(color: const Color(0xFFFCDFD5), width: 1.5),
                  ),
                  child: const Center(
                    child: Text(
                      '₹',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primaryOrange,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Shine sparkles
          Positioned(
            top: 2,
            right: 14,
            child: Icon(Icons.auto_awesome, color: Colors.white.withValues(alpha: 0.8), size: 14),
          ),
          Positioned(
            bottom: 6,
            left: 8,
            child: Icon(Icons.auto_awesome, color: Colors.white.withValues(alpha: 0.6), size: 10),
          ),
        ],
      ),
    );
  }
}
