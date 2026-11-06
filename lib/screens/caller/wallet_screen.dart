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
  String? _appliedCouponCode;

  static const Color bgCream = AppTheme.bgCream;
  static const Color borderWarm = AppTheme.borderWarm;
  static const Color primaryOrange = AppTheme.primaryOrange;
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
    List<Map<String, dynamic>> availableOffers = [];
    try {
      availableOffers = await context.read<AppController>().api.availableCoupons();
    } catch (_) {}
    final c = TextEditingController(text: '100');
    final couponCtrl = TextEditingController();
    Map<String, dynamic>? appliedCoupon;
    bool isCheckingCoupon = false;
    String? couponFeedback;
    bool isCouponError = false;
    String? formError;
    bool isGlobalMode = false;
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentVal = double.tryParse(c.text.trim()) ?? 0;
          final isBelowMin = c.text.trim().isNotEmpty && (isGlobalMode ? currentVal < 5 : currentVal < 50);

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
            contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: primaryOrange, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Recharge Wallet',
                  style: TextStyle(fontWeight: FontWeight.w800, color: textDark, fontSize: 18),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (formError != null)
                    FormErrorBanner(
                      message: formError,
                      isWarning: true,
                      onDismiss: () => setDialogState(() => formError = null),
                    ),

                  // Domestic vs Global Switcher Segment
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (isGlobalMode) {
                                setDialogState(() {
                                  isGlobalMode = false;
                                  c.text = '100';
                                  formError = null;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              decoration: BoxDecoration(
                                color: !isGlobalMode ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: !isGlobalMode ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('🇮🇳', style: TextStyle(fontSize: 13)),
                                  const SizedBox(width: 5),
                                  Text(
                                    'India (INR ₹)',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: !isGlobalMode ? FontWeight.w800 : FontWeight.w600,
                                      color: !isGlobalMode ? primaryOrange : textMuted,
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
                              if (!isGlobalMode) {
                                setDialogState(() {
                                  isGlobalMode = true;
                                  c.text = '10';
                                  formError = null;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              decoration: BoxDecoration(
                                color: isGlobalMode ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: isGlobalMode ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('🌐', style: TextStyle(fontSize: 13)),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Global (USD \$)',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: isGlobalMode ? FontWeight.w800 : FontWeight.w600,
                                      color: isGlobalMode ? primaryOrange : textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Text(
                    isGlobalMode
                        ? 'Select or enter amount in USD (minimum \$5):'
                        : 'Select or enter amount in INR (minimum ₹50):',
                    style: const TextStyle(fontSize: 12.5, color: textMuted),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: c,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: textDark, fontSize: 18),
                    onChanged: (_) => setDialogState(() { formError = null; }),
                    decoration: InputDecoration(
                      prefixText: isGlobalMode ? '\$ ' : '₹ ',
                      prefixStyle: const TextStyle(fontWeight: FontWeight.w800, color: primaryOrange, fontSize: 18),
                      labelText: isGlobalMode ? 'Amount (Min \$5)' : 'Amount (Min ₹50)',
                      labelStyle: TextStyle(color: isBelowMin ? Colors.redAccent : textMuted, fontSize: 13),
                      filled: true,
                      fillColor: bgCream,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderWarm)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isBelowMin ? Colors.redAccent : borderWarm)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: isBelowMin ? Colors.redAccent : primaryOrange, width: 1.5)),
                    ),
                  ),
                  if (isBelowMin) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent),
                        const SizedBox(width: 4),
                        Text(
                          isGlobalMode ? 'Minimum international recharge is \$5 USD' : 'Minimum recharge amount is ₹50',
                          style: const TextStyle(fontSize: 11.5, color: Colors.redAccent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                  if (isGlobalMode) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Row(
                        children: [
                          const Text('💳', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Foreign cards (Visa/Master/Amex) accepted. Equivalent to ≈ ₹${((double.tryParse(c.text.trim()) ?? 10) * 85).round()} INR.',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (isGlobalMode)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        {'usd': 5, 'label': '\$5 (~₹425)'},
                        {'usd': 10, 'label': '\$10 (~₹850)'},
                        {'usd': 25, 'label': '\$25 (~₹2,125)'},
                        {'usd': 50, 'label': '\$50 (~₹4,250)'},
                      ].map((item) {
                        final val = item['usd'] as int;
                        final isSelected = c.text.trim() == '$val';
                        return InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            c.text = '$val';
                            setDialogState(() { formError = null; });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected ? primaryOrange : softPeach,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isSelected ? primaryOrange : const Color(0xFFFCDFD5)),
                            ),
                            child: Text(
                              '${item['label']}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : primaryOrange,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [50, 100, 200, 500, 1000].map((amt) {
                        final isSelected = c.text.trim() == '$amt';
                        return InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            c.text = '$amt';
                            setDialogState(() { formError = null; });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected ? primaryOrange : softPeach,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: isSelected ? primaryOrange : const Color(0xFFFCDFD5)),
                            ),
                            child: Text(
                              '₹$amt',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : primaryOrange,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 14),

                  // Available Offers Section
                  if (availableOffers.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9F5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFFD8C7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.auto_awesome_rounded, size: 15, color: primaryOrange),
                                  SizedBox(width: 6),
                                  Text(
                                    'AVAILABLE OFFERS',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: primaryOrange,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: primaryOrange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Save More',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: primaryOrange),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...availableOffers.map((offer) {
                            final code = '${offer['code'] ?? ''}';
                            final isApplied = appliedCoupon != null && (appliedCoupon!['code'] ?? '') == code;
                            final minAmt = (offer['minRechargeAmount'] as num?)?.toDouble() ?? 50.0;
                            final discountType = '${offer['discountType'] ?? ''}';
                            final discountVal = (offer['discountValue'] as num?)?.toInt() ?? 0;
                            final badgeText = discountType == 'PERCENTAGE_BONUS'
                                ? '+$discountVal% BONUS'
                                : discountType == 'FLAT_COINS'
                                    ? '+₹$discountVal EXTRA'
                                    : '$discountVal% OFF';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isApplied ? const Color(0xFFE8F5E9) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isApplied ? const Color(0xFF4CAF50) : borderWarm,
                                  width: isApplied ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF4EDE4),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                code,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 11,
                                                  letterSpacing: 0.5,
                                                  color: textDark,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isApplied ? const Color(0xFFC8E6C9) : softPeach,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                badgeText,
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: isApplied ? const Color(0xFF2E7D32) : primaryOrange,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${offer['description'] ?? ''}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10.5, color: textMuted),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Min recharge: ₹${minAmt.toInt()}',
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textDark),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: (isCheckingCoupon || isApplied)
                                        ? null
                                        : () async {
                                            final currentAmt = double.tryParse(c.text.trim()) ?? 0;
                                            if (currentAmt < minAmt) {
                                              c.text = '${minAmt.toInt()}';
                                            }
                                            final effectiveAmt = double.tryParse(c.text.trim()) ?? minAmt;
                                            couponCtrl.text = code;
                                            setDialogState(() => isCheckingCoupon = true);
                                            try {
                                              final res = await context.read<AppController>().api.estimateCoupon(code, effectiveAmt);
                                              final valid = res['valid'] == true;
                                              if (valid) {
                                                appliedCoupon = res;
                                                couponFeedback = res['message'] ?? 'Offer applied successfully!';
                                                isCouponError = false;
                                              } else {
                                                appliedCoupon = null;
                                                couponFeedback = res['message'] ?? 'Coupon not valid for this amount';
                                                isCouponError = true;
                                              }
                                            } catch (e) {
                                              appliedCoupon = null;
                                              couponFeedback = 'Failed to apply offer';
                                              isCouponError = true;
                                            } finally {
                                              setDialogState(() => isCheckingCoupon = false);
                                            }
                                          },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isApplied ? const Color(0xFF4CAF50) : primaryOrange,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: isApplied
                                          ? const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.check, size: 12, color: Colors.white),
                                                SizedBox(width: 2),
                                                Text(
                                                  'Applied',
                                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                                                ),
                                              ],
                                            )
                                          : const Text(
                                              'Apply',
                                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Promo / Coupon Code Section
                  Container(
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
                            const Row(
                              children: [
                                Icon(Icons.local_offer_outlined, size: 15, color: primaryOrange),
                                SizedBox(width: 6),
                                Text(
                                  'HAVE A PROMO CODE?',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textDark, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                            if (appliedCoupon != null)
                              InkWell(
                                onTap: () {
                                  appliedCoupon = null;
                                  couponCtrl.clear();
                                  couponFeedback = null;
                                  setDialogState(() {});
                                },
                                child: const Text(
                                  'Remove',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.redAccent),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: couponCtrl,
                                enabled: appliedCoupon == null,
                                textCapitalization: TextCapitalization.characters,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1),
                                decoration: InputDecoration(
                                  hintText: 'e.g. WELCOME50',
                                  hintStyle: const TextStyle(color: textMuted, fontSize: 12, fontWeight: FontWeight.normal),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: borderWarm)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: borderWarm)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: primaryOrange)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: (isCheckingCoupon || couponCtrl.text.trim().isEmpty || appliedCoupon != null)
                                  ? null
                                  : () async {
                                      final code = couponCtrl.text.trim().toUpperCase();
                                      final amt = double.tryParse(c.text.trim()) ?? 100;
                                      setDialogState(() => isCheckingCoupon = true);
                                      try {
                                        final res = await context.read<AppController>().api.estimateCoupon(code, amt);
                                        if (res['valid'] == true) {
                                          appliedCoupon = res;
                                          isCouponError = false;
                                          couponFeedback = res['message'] ?? 'Promo applied successfully!';
                                        } else {
                                          appliedCoupon = null;
                                          isCouponError = true;
                                          couponFeedback = res['message'] ?? 'Invalid coupon code';
                                        }
                                      } catch (err) {
                                        appliedCoupon = null;
                                        isCouponError = true;
                                        couponFeedback = err.toString();
                                      } finally {
                                        setDialogState(() => isCheckingCoupon = false);
                                      }
                                    },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: appliedCoupon != null ? const Color(0xFF16A34A) : primaryOrange,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: isCheckingCoupon
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Text(
                                        appliedCoupon != null ? '✓ Applied' : 'Apply',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                                      ),
                              ),
                            ),
                          ],
                        ),
                        if (couponFeedback != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                isCouponError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                                size: 13,
                                color: isCouponError ? Colors.redAccent : const Color(0xFF16A34A),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  couponFeedback!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isCouponError ? Colors.redAccent : const Color(0xFF16A34A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (appliedCoupon != null && appliedCoupon!['valid'] == true) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '🎉 Extra bonus coins: +₹${appliedCoupon!['bonusCoins'] ?? 0}! Total: ₹${appliedCoupon!['effectiveCoinsReceived'] ?? c.text}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.public_rounded, size: 16, color: Color(0xFF16A34A)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'International & Indian cards accepted. Foreign bank accounts are automatically charged in your local currency.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF15803D), height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: textMuted, fontWeight: FontWeight.w600)),
              ),
              FilledButton(
                onPressed: () {
                  final entered = double.tryParse(c.text.trim());
                  if (isGlobalMode) {
                    if (entered == null || entered < 5) {
                      setDialogState(() {
                        formError = 'Minimum international recharge is \$5 USD (~₹425).';
                      });
                      return;
                    }
                    _appliedCouponCode = (appliedCoupon != null && appliedCoupon!['valid'] == true)
                        ? '${appliedCoupon!['code']}'
                        : null;
                    final inrAmount = (entered * 85.0).roundToDouble();
                    Navigator.pop(ctx, inrAmount);
                  } else {
                    if (entered == null || entered < 50) {
                      setDialogState(() {
                        formError = 'Minimum recharge amount is ₹50. Please enter ₹50 or more.';
                      });
                      return;
                    }
                    _appliedCouponCode = (appliedCoupon != null && appliedCoupon!['valid'] == true)
                        ? '${appliedCoupon!['code']}'
                        : null;
                    Navigator.pop(ctx, entered);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: primaryOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                ),
                child: const Text('Continue to Pay', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
    c.dispose();
    couponCtrl.dispose();
    if (amount == null) return;
    if (amount < 50) {
      if (mounted) {
        showNotice(
          context,
          title: 'Minimum Recharge is ₹50',
          message: 'Please enter ₹50 or more to proceed.',
          isWarning: true,
        );
      }
      return;
    }
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
        if (_appliedCouponCode != null) 'couponCode': _appliedCouponCode,
      });
      await _load();
      if (mounted) {
        showSuccess(context, 'Recharge successful! Balance updated.', title: 'Payment Received');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _failure(PaymentFailureResponse r) {
    if (!mounted) return;
    final msg = r.message ?? '';
    final lower = msg.toLowerCase();
    if (lower.contains('cancelled') || lower.contains('processing cancelled') || r.code == Razorpay.PAYMENT_CANCELLED) {
      showNotice(
        context,
        title: 'Payment Cancelled',
        message: 'You cancelled the checkout. No amount was debited from your card or bank.',
        isWarning: true,
      );
    } else {
      showError(
        context,
        msg.isNotEmpty ? msg : 'Payment could not be completed. Please try again.',
        title: 'Payment Failed',
      );
    }
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            wallet?.formattedBalance ?? '₹0.00',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Builder(builder: (_) {
                            final inr = wallet?.totalBalance ?? (wallet?.balance ?? 0.0);
                            final usd = (inr / 85.0).toStringAsFixed(2);
                            return Text(
                              '(≈ \$$usd USD)',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFFECE5),
                              ),
                            );
                          }),
                        ],
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

            if ((wallet?.bonusBalance ?? 0) > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFDBA74), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEA580C).withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA580C).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('🎁', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₹${wallet!.bonusBalance.toStringAsFixed(2)} Free Trial Call Balance Active',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF9A3412),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Platform-sponsored welcome bonus. Call any compassionate listener directly — your initial minutes are free!',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFC2410C),
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

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
