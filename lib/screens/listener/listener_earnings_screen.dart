import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_controller.dart';
import '../../models/app_models.dart';
import '../../widgets/common_widgets.dart';

class ListenerEarningsScreen extends StatefulWidget {
  const ListenerEarningsScreen({super.key});

  @override
  State<ListenerEarningsScreen> createState() => _ListenerEarningsScreenState();
}

class _ListenerEarningsScreenState extends State<ListenerEarningsScreen> {
  WalletModel? wallet;
  List<dynamic> tx = [];
  List<dynamic> payouts = [];
  final search = TextEditingController();
  bool loading = true;

  String activeTab = 'TRANSACTIONS'; // TRANSACTIONS, CALLS, GIFTS
  String typeFilter = 'ALL'; // ALL, CALL_CREDIT, GIFT_CREDIT, PAYOUT
  String dateFilter = 'ALL'; // ALL, TODAY, YESTERDAY, 7_DAYS, 30_DAYS, THIS_MONTH, CUSTOM
  String sortFilter = 'NEWEST'; // NEWEST, OLDEST, HIGHEST, LOWEST
  DateTimeRange? customRange;

  static const Color bgCream = Color(0xFFFAF5EE);
  static const Color borderWarm = Color(0xFFF1E6D8);
  static const Color primaryOrange = Color(0xFFF95B3D);
  static const Color secondaryOrange = Color(0xFFFF7A45);
  static const Color softPeach = Color(0xFFFFECE5);
  static const Color textDark = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    search.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
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
      final values = await Future.wait<dynamic>([
        api.wallet(),
        api.walletTransactions(page: 0, size: 200),
        api.payoutHistory(),
      ]);
      if (!mounted) return;
      setState(() {
        wallet = values[0] as WalletModel;
        tx = List<dynamic>.from(values[1] as List);
        payouts = List<dynamic>.from(values[2] as List);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        showError(context, e);
      }
    }
  }

  bool _dateOk(dynamic raw) {
    if (dateFilter == 'ALL') return true;
    final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (dateFilter == 'TODAY') return day == today;
    if (dateFilter == 'YESTERDAY') return day == today.subtract(const Duration(days: 1));
    if (dateFilter == '7_DAYS') {
      return !day.isBefore(today.subtract(const Duration(days: 6))) && !day.isAfter(now);
    }
    if (dateFilter == '30_DAYS') {
      return !day.isBefore(today.subtract(const Duration(days: 29))) && !day.isAfter(now);
    }
    if (dateFilter == 'THIS_MONTH') {
      return d.year == now.year && d.month == now.month;
    }
    if (dateFilter == 'CUSTOM' && customRange != null) {
      final startDay = DateTime(customRange!.start.year, customRange!.start.month, customRange!.start.day);
      final endDay = DateTime(customRange!.end.year, customRange!.end.month, customRange!.end.day, 23, 59, 59);
      return !d.isBefore(startDay) && !d.isAfter(endDay);
    }
    return true;
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (picked != null) {
      setState(() {
        customRange = picked;
        dateFilter = 'CUSTOM';
      });
    }
  }

  double _amount(Map<String, dynamic> m) => (m['amount'] as num?)?.toDouble() ?? 0.0;

  List<Map<String, dynamic>> get filteredTransactions {
    final q = search.text.trim().toLowerCase();
    var list = tx.map((e) => Map<String, dynamic>.from(e as Map)).where((m) {
      if (!_dateOk(m['createdAt'])) return false;

      final type = '${m['type'] ?? ''}'.toUpperCase();

      // Tab filtering
      if (activeTab == 'CALLS') {
        if (!type.contains('CALL')) return false;
      } else if (activeTab == 'GIFTS') {
        if (!type.contains('GIFT')) return false;
      }

      // Dropdown type filtering
      if (typeFilter != 'ALL') {
        if (typeFilter == 'CALL_CREDIT' && !type.contains('CALL')) return false;
        if (typeFilter == 'GIFT_CREDIT' && !type.contains('GIFT')) return false;
        if (typeFilter == 'PAYOUT' && !type.contains('PAYOUT')) return false;
      }

      if (q.isEmpty) return true;
      final desc = '${m['description'] ?? ''}'.toLowerCase();
      final ref = '${m['referenceId'] ?? m['id'] ?? ''}'.toLowerCase();
      final t = type.toLowerCase();
      final amountStr = _amount(m).toStringAsFixed(2);
      return desc.contains(q) || ref.contains(q) || t.contains(q) || amountStr.contains(q);
    }).toList();

    list.sort((a, b) {
      if (sortFilter == 'OLDEST') {
        final ad = DateTime.tryParse('${a['createdAt'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = DateTime.tryParse('${b['createdAt'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return ad.compareTo(bd);
      }
      if (sortFilter == 'HIGHEST') {
        return _amount(b).compareTo(_amount(a));
      }
      if (sortFilter == 'LOWEST') {
        return _amount(a).compareTo(_amount(b));
      }
      final ad = DateTime.tryParse('${a['createdAt'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = DateTime.tryParse('${b['createdAt'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return list;
  }

  Future<void> _withdraw() async {
    final amount = TextEditingController();
    final vpa = TextEditingController();
    final notes = TextEditingController();
    bool isSubmitting = false;

    final totalBalance = (wallet?.totalBalance ?? 0).toDouble();

    await showDialog<void>(
      context: getSafeNavigatorContext(context),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final amtVal = double.tryParse(amount.text.trim()) ?? 0;
          final isBelowMin = amount.text.trim().isNotEmpty && amtVal < 50;
          final exceedsBalance = amtVal > totalBalance;
          final vpaVal = vpa.text.trim();
          final isVpaFormatIssue = vpaVal.isNotEmpty && (!vpaVal.contains('@') || vpaVal.startsWith('@') || vpaVal.endsWith('@'));

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            backgroundColor: Colors.white,
            titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
            contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_outlined, color: primaryOrange, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UPI Withdrawal',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: textDark),
                    ),
                    Text(
                      'Direct transfer to your bank account',
                      style: TextStyle(fontSize: 11.5, color: textMuted, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Available balance pill card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF10B981).withValues(alpha: 0.16),
                              ),
                              child: const Icon(Icons.wallet_rounded, color: Color(0xFF10B981), size: 15),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Available to Withdraw',
                              style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF166534), fontSize: 12),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: totalBalance >= 50
                              ? () {
                                  amount.text = totalBalance.toStringAsFixed(totalBalance.truncateToDouble() == totalBalance ? 0 : 2);
                                  setModalState(() {});
                                }
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Row(
                            children: [
                              Text(
                                wallet?.formattedBalance ?? '₹0.00',
                                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF15803D), fontSize: 14),
                              ),
                              if (totalBalance >= 50) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: primaryOrange.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'MAX',
                                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: primaryOrange),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Amount input
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: textDark, fontSize: 16),
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Amount (minimum ₹50)',
                      labelStyle: TextStyle(
                        color: (isBelowMin || exceedsBalance) ? Colors.redAccent : textMuted,
                        fontSize: 13,
                      ),
                      prefixText: '₹ ',
                      prefixStyle: const TextStyle(fontWeight: FontWeight.w800, color: primaryOrange, fontSize: 16),
                      filled: true,
                      fillColor: const Color(0xFFFFFBF7),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: borderWarm)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: (isBelowMin || exceedsBalance) ? Colors.redAccent : borderWarm),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: (isBelowMin || exceedsBalance) ? Colors.redAccent : primaryOrange, width: 1.5),
                      ),
                    ),
                  ),
                  if (isBelowMin) ...[
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent),
                        SizedBox(width: 4),
                        Text(
                          'Minimum withdrawal is ₹50.00',
                          style: TextStyle(fontSize: 11.5, color: Colors.redAccent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ] else if (exceedsBalance) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent),
                        const SizedBox(width: 4),
                        Text(
                          'Amount exceeds available balance (${wallet?.formattedBalance ?? '₹0.00'})',
                          style: const TextStyle(fontSize: 11.5, color: Colors.redAccent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),

                  // Quick Chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [50, 100, 200, 500].map((amt) {
                      final isSelected = amount.text.trim() == '$amt';
                      return InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          amount.text = '$amt';
                          setModalState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? primaryOrange : softPeach,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: isSelected ? primaryOrange : const Color(0xFFFCDFD5)),
                          ),
                          child: Text(
                            '₹$amt',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : primaryOrange,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // TDS & Net Payout Summary Card
                  Builder(
                    builder: (context) {
                      final user = context.read<AppController>().user;
                      final hasPan = user?.idType?.toUpperCase() == 'PAN' && (user?.idNumber?.trim().isNotEmpty ?? false);
                      final tdsRate = hasPan ? 1.0 : 20.0;
                      final val = double.tryParse(amount.text.trim()) ?? 0.0;
                      final tdsAmt = (val * tdsRate) / 100.0;
                      final netPay = val > tdsAmt ? val - tdsAmt : 0.0;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBF7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderWarm),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Gross Amount:', style: TextStyle(fontSize: 12, color: textMuted, fontWeight: FontWeight.w500)),
                                Text('₹${val.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textDark)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'TDS (${hasPan ? "1% Sec 194-O" : "20% Sec 206AA"}):',
                                  style: TextStyle(fontSize: 12, color: hasPan ? const Color(0xFFD97706) : Colors.redAccent, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '- ₹${tdsAmt.toStringAsFixed(2)}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: hasPan ? const Color(0xFFD97706) : Colors.redAccent),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Divider(height: 1, thickness: 0.8, color: borderWarm),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Net Transferred to UPI:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF16A34A))),
                                Text('₹${netPay.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF16A34A))),
                              ],
                            ),
                            if (!hasPan) ...[
                              const SizedBox(height: 6),
                              const Text(
                                '⚠️ Link PAN card in profile to reduce TDS from 20% to 1%.',
                                style: TextStyle(fontSize: 10.5, color: Colors.redAccent, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // UPI VPA input
                  TextField(
                    controller: vpa,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: textDark, fontSize: 14.5),
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      labelText: 'UPI ID / VPA',
                      hintText: 'e.g. 9876543210@paytm or name@okaxis',
                      prefixIcon: const Icon(Icons.alternate_email_rounded, size: 19, color: textMuted),
                      filled: true,
                      fillColor: const Color(0xFFFFFBF7),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: borderWarm)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: isVpaFormatIssue ? Colors.orangeAccent : borderWarm),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: isVpaFormatIssue ? Colors.orangeAccent : primaryOrange, width: 1.5),
                      ),
                    ),
                  ),
                  if (isVpaFormatIssue) ...[
                    const SizedBox(height: 6),
                    const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: Colors.orangeAccent),
                        SizedBox(width: 4),
                        Text(
                          'Include your provider handle (e.g. @okhdfcbank, @paytm)',
                          style: TextStyle(fontSize: 11, color: Colors.orangeAccent, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Notes input
                  TextField(
                    controller: notes,
                    style: const TextStyle(color: textDark, fontSize: 13.5),
                    decoration: InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: const Icon(Icons.edit_note_rounded, size: 20, color: textMuted),
                      filled: true,
                      fillColor: const Color(0xFFFFFBF7),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: borderWarm)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: borderWarm)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: primaryOrange)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: textMuted, fontWeight: FontWeight.bold)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: primaryOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final value = double.tryParse(amount.text.trim()) ?? 0;
                        final vpaClean = vpa.text.trim();

                        if (value < 50) {
                          showNotice(
                            ctx,
                            title: 'Minimum Withdrawal',
                            message: 'Minimum withdrawal amount is ₹50.00.',
                            isWarning: true,
                          );
                          return;
                        }
                        if (value > totalBalance) {
                          showNotice(
                            ctx,
                            title: 'Insufficient Balance',
                            message: 'Entered amount exceeds your available balance (${wallet?.formattedBalance ?? '₹0.00'}).',
                            isWarning: true,
                          );
                          return;
                        }
                        if (!RegExp(r'^[A-Za-z0-9._-]{2,256}@[A-Za-z0-9.-]{2,64}$').hasMatch(vpaClean)) {
                          showNotice(
                            ctx,
                            title: 'Invalid UPI ID',
                            message: 'Please enter a valid UPI handle (e.g. name@okhdfcbank or 9876543210@paytm).',
                            isWarning: true,
                          );
                          return;
                        }

                        setModalState(() => isSubmitting = true);
                        try {
                          final result = await context.read<AppController>().api.requestPayout(
                                value,
                                vpaClean,
                                notes: notes.text.trim(),
                              );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            showSuccess(
                              context,
                              'Payout requested: Net ₹${result['netDisbursedAmount'] ?? result['amount'] ?? value} (TDS ₹${result['tdsAmount'] ?? 0}) to ${result['destinationVpa'] ?? vpaClean}.',
                              title: 'Withdrawal Requested 🎉',
                            );
                          }
                          await _load();
                        } catch (e) {
                          if (ctx.mounted) {
                            setModalState(() => isSubmitting = false);
                            showError(ctx, e, title: 'Withdrawal Failed');
                          }
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Withdraw Now', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
    amount.dispose();
    vpa.dispose();
    notes.dispose();
  }

  String _fmt(dynamic raw) {
    final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    return d == null ? '${raw ?? ''}' : DateFormat('dd MMM yyyy, h:mm a').format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(backgroundColor: bgCream, body: LoadingBody());
    final entries = filteredTransactions;

    final callEarnings = tx
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) => {'CALL_CREDIT', 'CALL_EARNING'}.contains('${m['type']}'))
        .fold<double>(0, (sum, m) => sum + _amount(m));

    final giftEarnings = tx
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) => '${m['type']}' == 'GIFT_CREDIT')
        .fold<double>(0, (sum, m) => sum + _amount(m));

    return Scaffold(
      backgroundColor: bgCream,
      body: Stack(
        children: [
          // Top-right warm peach ambient glow orb
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
                    const Color(0xFFFAF5EE).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: RefreshIndicator(
              color: primaryOrange,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  // Title Header
                  const Text(
                    'Earnings & UPI',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 1. Main Available Payout Balance Card matching Screenshot 3
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: borderWarm),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: softPeach,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFFCDFD5), width: 0.8),
                              ),
                              child: const Center(
                                child: Icon(Icons.monetization_on_rounded, color: primaryOrange, size: 20),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Available payout balance',
                              style: TextStyle(
                                fontSize: 13,
                                color: textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          wallet?.formattedBalance ?? '₹0.00',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: textDark,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Sub stats row: Session earnings + Gift credits
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: softPeach,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFFFCDFD5), width: 0.8),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.sync_alt_rounded, color: primaryOrange, size: 16),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Session earnings',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w500)),
                                        Text('₹${callEarnings.toStringAsFixed(2)}',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textDark)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 32, color: borderWarm),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: softPeach,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFFFCDFD5), width: 0.8),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.card_giftcard_rounded, color: primaryOrange, size: 16),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Gift credits',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 11, color: textMuted, fontWeight: FontWeight.w500)),
                                        Text('₹${giftEarnings.toStringAsFixed(2)}',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textDark)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Large Solid Orange "Withdraw to UPI >" Button
                        Container(
                          width: double.infinity,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [primaryOrange, secondaryOrange],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primaryOrange.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _withdraw,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.account_balance_outlined, color: Colors.white, size: 19),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          'Withdraw to UPI',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 2. Tab Segment Switcher matching Screenshot 3
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
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
                      children: [
                        Expanded(
                          child: _buildTabPill(
                            title: 'Transactions',
                            icon: Icons.description_outlined,
                            isSelected: activeTab == 'TRANSACTIONS',
                            onTap: () => setState(() => activeTab = 'TRANSACTIONS'),
                          ),
                        ),
                        Expanded(
                          child: _buildTabPill(
                            title: 'Calls',
                            icon: Icons.call_outlined,
                            isSelected: activeTab == 'CALLS',
                            onTap: () => setState(() => activeTab = 'CALLS'),
                          ),
                        ),
                        Expanded(
                          child: _buildTabPill(
                            title: 'Gifts',
                            icon: Icons.card_giftcard_outlined,
                            isSelected: activeTab == 'GIFTS',
                            onTap: () => setState(() => activeTab = 'GIFTS'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 3. Search and 3 Dropdowns Filter Row
                  Container(
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
                    child: TextField(
                      controller: search,
                      style: const TextStyle(fontWeight: FontWeight.w600, color: textDark, fontSize: 13.5),
                      decoration: const InputDecoration(
                        hintText: 'Search reference, description, amount or ID',
                        hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.normal),
                        prefixIcon: Icon(Icons.search_rounded, color: primaryOrange, size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 3 Dropdown Pills in a row: Type, Date, Sort
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterDropdown(
                          label: 'Type',
                          value: typeFilter,
                          items: const [
                            DropdownMenuItem(value: 'ALL', child: Text('All')),
                            DropdownMenuItem(value: 'CALL_CREDIT', child: Text('Calls')),
                            DropdownMenuItem(value: 'GIFT_CREDIT', child: Text('Gifts')),
                            DropdownMenuItem(value: 'PAYOUT', child: Text('Payouts')),
                          ],
                          onChanged: (v) => setState(() => typeFilter = v ?? 'ALL'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFilterDropdown(
                          label: 'Date',
                          value: dateFilter == 'CUSTOM' ? 'CUSTOM' : dateFilter,
                          items: [
                            const DropdownMenuItem(value: 'ALL', child: Text('All time')),
                            const DropdownMenuItem(value: 'TODAY', child: Text('Today')),
                            const DropdownMenuItem(value: 'YESTERDAY', child: Text('Yesterday')),
                            const DropdownMenuItem(value: '7_DAYS', child: Text('7 days')),
                            const DropdownMenuItem(value: '30_DAYS', child: Text('30 days')),
                            const DropdownMenuItem(value: 'THIS_MONTH', child: Text('Month')),
                            DropdownMenuItem(
                              value: 'CUSTOM',
                              child: Text(customRange != null
                                  ? '${DateFormat('d/M').format(customRange!.start)}–${DateFormat('d/M').format(customRange!.end)}'
                                  : 'Custom…'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == 'CUSTOM') {
                              _pickCustomRange();
                            } else {
                              setState(() {
                                dateFilter = v ?? 'ALL';
                                customRange = null;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFilterDropdown(
                          label: 'Sort',
                          value: sortFilter,
                          items: const [
                            DropdownMenuItem(value: 'NEWEST', child: Text('Newest')),
                            DropdownMenuItem(value: 'OLDEST', child: Text('Oldest')),
                            DropdownMenuItem(value: 'HIGHEST', child: Text('Highest')),
                            DropdownMenuItem(value: 'LOWEST', child: Text('Lowest')),
                          ],
                          onChanged: (v) => setState(() => sortFilter = v ?? 'NEWEST'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 4. Transactions List
                  if (entries.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderWarm),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFFD1D5DB)),
                          SizedBox(height: 12),
                          Text(
                            'No transactions found',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textDark),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Completed sessions and gift credits will appear here.',
                            style: TextStyle(fontSize: 12.5, color: textMuted),
                          ),
                        ],
                      ),
                    )
                  else
                    ...entries.map((m) => _buildTransactionCard(m)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFF2EB) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: isSelected ? Border.all(color: const Color(0xFFFCDFD5), width: 1.0) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? primaryOrange : textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? primaryOrange : textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: textMuted, fontWeight: FontWeight.w600)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: textMuted, size: 18),
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: textDark),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> m) {
    final type = '${m['type'] ?? ''}'.toUpperCase();
    final description = '${m['description'] ?? 'Wallet Activity'}';
    final ref = '${m['referenceId'] ?? m['id'] ?? ''}';
    final amount = _amount(m);
    final isCredit = type.contains('CREDIT') || type.contains('EARNING');

    IconData iconData = Icons.call_rounded;
    if (type.contains('GIFT')) {
      if (description.toLowerCase().contains('coffee')) {
        iconData = Icons.local_cafe_rounded;
      } else {
        iconData = Icons.card_giftcard_rounded;
      }
    } else if (type.contains('PAYOUT') || type.contains('DEBIT')) {
      iconData = Icons.account_balance_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          // Round soft peach icon container
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: softPeach,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFCDFD5), width: 0.8),
            ),
            child: Center(
              child: Icon(
                iconData,
                color: primaryOrange,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Details column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: textDark,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  ref.isNotEmpty ? '$type • $ref' : type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmt(m['createdAt']),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Amount Text (+₹8.00 in bold red/orange)
          Text(
            isCredit ? '+₹${amount.toStringAsFixed(2)}' : '-₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isCredit ? primaryOrange : const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }
}
