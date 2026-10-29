import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

/// A modern, fintech-grade dialog for confirming task payment.
/// Displays an itemized price breakdown, wallet balance impact, and escrow protection badge.
/// Crucially, helper's internal payout is NOT displayed to task posters.
class ConfirmPaymentDialog extends StatefulWidget {
  final double budget;
  final double serviceCharge;
  final double posterFee;
  final double totalCost;
  final double currentWalletBalance;
  final Future<bool> Function() onConfirm;

  const ConfirmPaymentDialog({
    super.key,
    required this.budget,
    this.serviceCharge = 0,
    required this.posterFee,
    required this.totalCost,
    required this.currentWalletBalance,
    required this.onConfirm,
  });

  /// Helper to display the dialog
  static Future<bool?> show({
    required BuildContext context,
    required double budget,
    double serviceCharge = 0,
    required double posterFee,
    required double totalCost,
    required double currentWalletBalance,
    required Future<bool> Function() onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ConfirmPaymentDialog(
        budget: budget,
        serviceCharge: serviceCharge,
        posterFee: posterFee,
        totalCost: totalCost,
        currentWalletBalance: currentWalletBalance,
        onConfirm: onConfirm,
      ),
    );
  }

  /// Helper to display an insufficient balance dialog
  static Future<void> showInsufficientBalance({
    required BuildContext context,
    required double totalCost,
    required double currentBalance,
    required double budget,
    double serviceCharge = 0,
    required double posterFee,
  }) async {
    final shortfall = totalCost - currentBalance;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 8,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Color(0xFFD97706),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Insufficient Balance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You need ₹${totalCost.toStringAsFixed(0)} in your wallet to complete payment for this task.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _MiniRow('Current Balance', '₹${currentBalance.toStringAsFixed(0)}'),
                    const SizedBox(height: 6),
                    _MiniRow('Total Required', '₹${totalCost.toStringAsFixed(0)}'),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Divider(height: 1),
                    ),
                    _MiniRow(
                      'Shortfall Amount',
                      '₹${shortfall.ceil()}',
                      isDanger: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 18),
                          SizedBox(width: 4),
                          Text(
                            'Add Money',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (go == true && context.mounted) {
      context.push('/wallet');
    }
  }

  @override
  State<ConfirmPaymentDialog> createState() => _ConfirmPaymentDialogState();
}

class _ConfirmPaymentDialogState extends State<ConfirmPaymentDialog> {
  bool _paying = false;

  Future<void> _handleConfirm() async {
    setState(() => _paying = true);
    bool ok = false;
    try {
      ok = await widget.onConfirm();
    } catch (_) {
      ok = false;
    } finally {
      if (mounted) {
        setState(() => _paying = false);
        Navigator.of(context).pop(ok);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAfter = widget.currentWalletBalance - widget.totalCost;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      elevation: 10,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header Icon & Title ──
              Center(
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: AppColors.primary,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Center(
                child: Text(
                  'Confirm Payment',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'Escrow Protected • Funds released upon your approval',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Price Breakdown Card ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.receipt_long_rounded,
                          size: 15,
                          color: Color(0xFF64748B),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'PRICE BREAKDOWN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _DetailRow('Task Budget', '₹${widget.budget.toStringAsFixed(0)}'),
                    if (widget.serviceCharge > 0) ...[
                      const SizedBox(height: 8),
                      _DetailRow(
                        'Distance / Service Charge',
                        '₹${widget.serviceCharge.toStringAsFixed(0)}',
                      ),
                    ],
                    if (widget.posterFee > 0) ...[
                      const SizedBox(height: 8),
                      _DetailRow(
                        'Platform Fee & GST (20%)',
                        '₹${widget.posterFee.toStringAsFixed(0)}',
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        const Text(
                          'Total Payable',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          '₹${widget.totalCost.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Wallet Balance & Escrow Guarantee Box ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 16,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wallet: ₹${widget.currentWalletBalance.toStringAsFixed(0)}  →  ₹${walletAfter.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF14532D),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Deducted securely from your wallet',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFDCFCE7)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: Color(0xFF16A34A),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '100% Escrow Guarantee: Payment is released only after you verify task completion.',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF166534),
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // ── Action Buttons ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _paying ? null : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: _paying
                            ? null
                            : const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: _paying
                            ? null
                            : [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                      ),
                      child: ElevatedButton(
                        onPressed: _paying ? null : _handleConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _paying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_outline, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'Confirm & Pay',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

class _MiniRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDanger;
  const _MiniRow(this.label, this.value, {this.isDanger = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: isDanger ? const Color(0xFFDC2626) : const Color(0xFF64748B),
            fontWeight: isDanger ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDanger ? const Color(0xFFDC2626) : const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}
