import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/wallet.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const String _savedPaymentDetailsKey = 'taskearn_payment_details';
  late Razorpay _razorpay;

  void _openWalletPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final w = context.read<WalletProvider>();
      w.fetchWallet();
      w.fetchTransactions();
      w.fetchWithdrawals();
    });

    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    // Show a non-dismissible loading dialog while we verify with the backend.
    // This prevents the user from navigating away and losing the context.
    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Verifying payment…'),
            ],
          ),
        ),
      );
    }

    final wallet = context.read<WalletProvider>();
    final ok = await wallet.verifyTopUp(
      paymentId: response.paymentId ?? '',
      orderId: response.orderId ?? '',
      signature: response.signature ?? '',
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Payment successful! Wallet credited.'
            : (wallet.error ?? 'Payment verification failed.')),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message ?? "Try again"}'),
        backgroundColor: AppColors.danger,
      ),
    );
  }

  void _onExternalWallet(ExternalWalletResponse response) {}

  void _showAddMoney() {
    final amtCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Money to Wallet',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            // Quick amounts
            Wrap(
              spacing: 8,
              children: [100, 200, 500, 1000].map((amt) {
                return GestureDetector(
                  onTap: () => amtCtrl.text = '$amt',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.light,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text('₹$amt',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                prefixIcon: Icon(Icons.currency_rupee),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final amt = double.tryParse(amtCtrl.text);
                  if (amt == null || amt < 1) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter a valid amount')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);

                  final wallet = context.read<WalletProvider>();
                  final auth = context.read<AuthProvider>();
                  final order = await wallet.createTopUpOrder(amt);
                  if (order == null) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(wallet.error ?? 'Failed to create order'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                    return;
                  }

                  final user = auth.user;
                  // Backend returns 'orderId' (camelCase) and 'amount' in paise.
                  final options = <String, dynamic>{
                    'key': order['key'] ?? order['razorpay_key'] ?? '',
                    'order_id': order['orderId'] ?? order['order_id'] ?? order['id'],
                    'amount': order['amount'], // already in paise from backend
                    'currency': order['currency'] ?? 'INR',
                    'name': 'WorkMate4U',
                    'description': 'Wallet Top-up',
                    'prefill': {
                      'contact': user?.phone ?? '',
                      'email': user?.email ?? '',
                    },
                    'theme': {'color': '#6366F1'},
                  };
                  try {
                    _razorpay.open(options);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not open payment: $e')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('Proceed to Pay'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWithdraw() async {
    final auth = context.read<AuthProvider>();
    final wallet = context.read<WalletProvider>();
    final user = auth.user;
    final suspendedUntil = user?.suspendedUntil;
    if ((user?.isSuspended ?? false) &&
        suspendedUntil != null &&
        suspendedUntil.isAfter(DateTime.now())) {
      final endTime =
          '${suspendedUntil.day}/${suspendedUntil.month}/${suspendedUntil.year} ${TimeOfDay.fromDateTime(suspendedUntil).format(context)}';
      _showWalletAlert(
        title: 'Withdrawals Blocked',
        message:
            'Your account is suspended until $endTime. You cannot withdraw during suspension.',
      );
      return;
    }

    final kycStatus = (user?.kycStatus ?? 'none').toLowerCase();
    if (!(user?.isKycVerified ?? false)) {
      final message = kycStatus == 'pending'
          ? 'Your KYC is under review. You can withdraw once it is approved.'
          : kycStatus == 'rejected'
              ? 'Your previous KYC was rejected. Please re-submit valid documents.'
              : 'Complete KYC verification before withdrawing.';
      final goToKyc = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('KYC Verification Required'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Go to KYC'),
            ),
          ],
        ),
      );
      if (goToKyc == true && mounted) {
        context.push('/kyc');
      }
      return;
    }

    final savedDetails = _loadSavedPaymentDetails();
    final amtCtrl = TextEditingController();
    final bankNameCtrl = TextEditingController(text: savedDetails?.bankName ?? '');
    final bankCtrl = TextEditingController(text: savedDetails?.accountNumber ?? '');
    final confirmBankCtrl = TextEditingController(text: savedDetails?.accountNumber ?? '');
    final ifscCtrl = TextEditingController(text: savedDetails?.ifscCode ?? '');
    final holderCtrl = TextEditingController(text: savedDetails?.accountHolder ?? '');
    bool useSavedDetails = savedDetails != null;
    String? errorText;
    bool submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final availableBalance = wallet.balance.balance;

          Future<void> submit() async {
            await auth.refreshUser();
            await wallet.fetchWallet();
            if (!mounted) return;

            final latestUser = auth.user;
            final latestSuspendedUntil = latestUser?.suspendedUntil;
            if ((latestUser?.isSuspended ?? false) &&
                latestSuspendedUntil != null &&
                latestSuspendedUntil.isAfter(DateTime.now())) {
              final endTime =
                  '${latestSuspendedUntil.day}/${latestSuspendedUntil.month}/${latestSuspendedUntil.year} ${TimeOfDay.fromDateTime(latestSuspendedUntil).format(context)}';
              setSheetState(() {
                errorText =
                    'Your account is suspended until $endTime. You cannot withdraw during suspension.';
              });
              return;
            }

            final latestKycStatus = (latestUser?.kycStatus ?? 'none').toLowerCase();
            if (!(latestUser?.isKycVerified ?? false)) {
              setSheetState(() {
                errorText = latestKycStatus == 'pending'
                    ? 'Your KYC is under review. You can withdraw once it is approved.'
                    : latestKycStatus == 'rejected'
                        ? 'Your previous KYC was rejected. Please re-submit valid documents.'
                        : 'Complete KYC verification before withdrawing.';
              });
              return;
            }

            final amt = double.tryParse(amtCtrl.text.trim());
            if (amt == null || amt < 100) {
              setSheetState(() => errorText = 'Minimum withdrawal amount is ₹100');
              return;
            }
            if (wallet.balance.balance < amt) {
              setSheetState(() => errorText =
                  'Insufficient balance. Available: ₹${wallet.balance.balance.toStringAsFixed(2)}');
              return;
            }

            final bankName = bankNameCtrl.text.trim();
            final accountHolder = holderCtrl.text.trim();
            final accountNumber = bankCtrl.text.trim();
            final confirmAccountNumber = confirmBankCtrl.text.trim();
            final ifscCode = ifscCtrl.text.trim().toUpperCase();

            if (!bankName.isNotEmpty) {
              setSheetState(() => errorText = 'Please enter your bank name');
              return;
            }
            if (accountHolder.length < 3) {
              setSheetState(() => errorText =
                  'Please enter account holder name (min 3 characters)');
              return;
            }
            if (!RegExp(r'^\d{9,18}$').hasMatch(accountNumber)) {
              setSheetState(() => errorText = 'Account number must be 9-18 digits');
              return;
            }
            if (accountNumber != confirmAccountNumber) {
              setSheetState(() => errorText = 'Account numbers do not match');
              return;
            }
            if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifscCode)) {
              setSheetState(() => errorText =
                  'Invalid IFSC code format (e.g. HDFC0001234)');
              return;
            }

            setSheetState(() {
              errorText = null;
              submitting = true;
            });

            final ok = await wallet.requestWithdrawal(
                  amount: amt,
                  bankName: bankName,
                  bankAccount: accountNumber,
                  ifscCode: ifscCode,
                  accountHolder: accountHolder,
                );
            if (!mounted) return;

            setSheetState(() => submitting = false);
            if (!ok) {
              setSheetState(() => errorText =
                  wallet.error ?? 'Withdrawal failed. Please try again.');
              return;
            }

            await _savePaymentDetails(_SavedPaymentDetails(
              bankName: bankName,
              accountHolder: accountHolder,
              accountNumber: accountNumber,
              ifscCode: ifscCode,
            ));
            if (!mounted || !ctx.mounted) return;
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '₹${amt.toStringAsFixed(2)} withdrawal request submitted! Amount will be transferred to your bank account within 24 hours.',
                ),
                backgroundColor: AppColors.success,
              ),
            );
          }

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Withdraw Funds',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'Available balance: ₹${availableBalance.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppColors.gray, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    helperText: 'Minimum withdrawal amount is ₹100',
                  ),
                ),
                const SizedBox(height: 12),
                if (savedDetails != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.account_balance_rounded,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 8),
                            const Text('Saved bank details',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const Spacer(),
                            Switch.adaptive(
                              value: useSavedDetails,
                              onChanged: (value) =>
                                  setSheetState(() => useSavedDetails = value),
                            ),
                          ],
                        ),
                        Text(
                          '${savedDetails.bankName} • **** ${savedDetails.accountNumber.substring(savedDetails.accountNumber.length - 4)}',
                          style: const TextStyle(fontSize: 13, color: AppColors.gray),
                        ),
                        Text(
                          savedDetails.ifscCode,
                          style: const TextStyle(fontSize: 12, color: AppColors.gray),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!useSavedDetails) ...[
                  TextField(
                    controller: bankNameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Bank Name (e.g. SBI, HDFC)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: holderCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Account Holder Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bankCtrl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Bank Account Number'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmBankCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Confirm Account Number'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ifscCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'IFSC Code'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (useSavedDetails && savedDetails != null) ...[
                  TextField(
                    controller: bankNameCtrl,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'Bank Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: holderCtrl,
                    enabled: false,
                    decoration:
                        const InputDecoration(labelText: 'Account Holder Name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bankCtrl,
                    enabled: false,
                    decoration:
                        const InputDecoration(labelText: 'Bank Account Number'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ifscCtrl,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'IFSC Code'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (errorText != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(
                      errorText!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: submitting ? null : submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Request Withdrawal'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Withdrawal requests are reviewed by admin and processed within 24–48 hours via NEFT/IMPS.',
                  style: TextStyle(fontSize: 11, color: AppColors.gray),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _savePaymentDetails(_SavedPaymentDetails details) {
    return StorageService.setString(
      _savedPaymentDetailsKey,
      jsonEncode(details.toJson()),
    );
  }

  _SavedPaymentDetails? _loadSavedPaymentDetails() {
    final raw = StorageService.getString(_savedPaymentDetailsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return _SavedPaymentDetails.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  void _showWalletAlert({required String title, required String message}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Consumer<WalletProvider>(
        builder: (_, wallet, __) {
          if (wallet.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final b = wallet.balance;
          final totalEarned = b.totalEarned > 0
              ? b.totalEarned
              : wallet.transactions
                  .where((t) => t.isCredit)
                  .fold<double>(0, (sum, t) => sum + t.amount);
          final totalSpent = b.totalSpent > 0
              ? b.totalSpent
              : wallet.transactions
                  .where((t) => t.isDebit)
                  .fold<double>(0, (sum, t) => sum + t.amount);
          // Responsive sizing
          final logoH = sw * 0.18;
          final logoW = sw * 0.22;
          final balFS = (sw * 0.09).clamp(28.0, 44.0);
          final illW = sw * 0.40;
          final illH = sw * 0.40;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
              // ── Dark gradient header ──────────────────────────────────
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0B1630), Color(0xFF1A3870)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Stack(
                    children: [
                      // Right: 3D wallet illustration (behind content)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Image.asset(
                          'assets/images/wallet_illustration.png',
                          width: illW,
                          height: illH,
                          fit: BoxFit.contain,
                        ),
                      ),
                      // Foreground: logo + balance (full width — no overflow risk)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo + Secure badge row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // W4U Logo
                                SizedBox(
                                  width: logoW,
                                  height: logoH,
                                  child: Image.asset(
                                    'assets/images/logo_light.png',
                                    fit: BoxFit.contain,
                                    alignment: Alignment.centerLeft,
                                  ),
                                ),
                                // Secure Wallet badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified_rounded,
                                          color: Colors.white, size: 13),
                                      SizedBox(width: 4),
                                      Text('Secure Wallet',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Text('Available Balance',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '₹${b.balance.toStringAsFixed(2)}',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: balFS,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── White action buttons card ─────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                transform: Matrix4.translationValues(0, -1, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                    vertical: 18, horizontal: 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 16) / 3;

                    return Wrap(
                      spacing: 8,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: _ActionBtn(
                            icon: Icons.add_rounded,
                            label: 'Add Money',
                            color: const Color(0xFF3B82F6),
                            onTap: _showAddMoney,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _ActionBtn(
                            icon: Icons.arrow_upward_rounded,
                            label: 'Withdraw',
                            color: const Color(0xFF7C3AED),
                            onTap: _showWithdraw,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _ActionBtn(
                            icon: Icons.receipt_long_rounded,
                            label: 'History',
                            color: const Color(0xFF0EA5E9),
                            onTap: () => _openWalletPage(const _HistoryPage()),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _ActionBtn(
                            icon: Icons.swap_horiz_rounded,
                            label: 'Transactions',
                            color: const Color(0xFF059669),
                            onTap: () => _openWalletPage(const _TransactionsPage()),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _ActionBtn(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'Withdrawals',
                            color: const Color(0xFFF59E0B),
                            onTap: () => _openWalletPage(const _WithdrawalsPage()),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _ActionBtn(
                            icon: Icons.trending_up_rounded,
                            label: 'Earnings',
                            color: const Color(0xFF10B981),
                            onTap: () => _openWalletPage(const _EarningsPage()),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: _ActionBtn(
                            icon: Icons.trending_down_rounded,
                            label: 'Spent',
                            color: const Color(0xFFEF4444),
                            onTap: () => _openWalletPage(const _SpentPage()),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // ── Blue stats bar ────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4ED8),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(
                    vertical: 14, horizontal: 8),
                child: Row(
                  children: [
                    _StatItem(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Earned',
                      value: '₹${totalEarned.toStringAsFixed(0)}',
                    ),
                    Container(width: 1, height: 34,
                        color: Colors.white.withValues(alpha: 0.3)),
                    _StatItem(
                      icon: Icons.trending_up_rounded,
                      label: 'Spent',
                      value: '₹${totalSpent.toStringAsFixed(0)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
        },
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}

class _SavedPaymentDetails {
  final String bankName;
  final String accountHolder;
  final String accountNumber;
  final String ifscCode;

  const _SavedPaymentDetails({
    required this.bankName,
    required this.accountHolder,
    required this.accountNumber,
    required this.ifscCode,
  });

  factory _SavedPaymentDetails.fromJson(Map<String, dynamic> json) {
    return _SavedPaymentDetails(
      bankName: json['bankName']?.toString() ?? '',
      accountHolder: json['accountHolder']?.toString() ?? '',
      accountNumber: json['accountNumber']?.toString() ?? '',
      ifscCode: json['ifscCode']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'bankName': bankName,
        'accountHolder': accountHolder,
        'accountNumber': accountNumber,
        'ifscCode': ifscCode,
      };
}

// ── Stats item widget ─────────────────────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15)),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

class _TransactionList extends StatefulWidget {
  final List<Transaction> transactions;
  const _TransactionList({required this.transactions});

  @override
  State<_TransactionList> createState() => _TransactionListState();
}

class _TransactionListState extends State<_TransactionList> {
  static const int _pageSize = 10;
  int _page = 0;

  int get _pageCount =>
      widget.transactions.isEmpty ? 1 : ((widget.transactions.length - 1) ~/ _pageSize) + 1;

  List<Transaction> get _visibleTransactions {
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.transactions.length);
    return widget.transactions.sublist(start, end);
  }

  @override
  void didUpdateWidget(covariant _TransactionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= _pageCount) {
      _page = _pageCount - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.transactions.isEmpty) {
      return const Center(
        child: Text('No transactions yet',
            style: TextStyle(color: AppColors.gray)),
      );
    }

    final visibleTransactions = _visibleTransactions;
    final start = (_page * _pageSize) + 1;
    final end = (_page * _pageSize) + visibleTransactions.length;

    return Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: ListView.separated(
              key: ValueKey(_page),
              itemCount: visibleTransactions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final t = visibleTransactions[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        (t.isCredit ? AppColors.success : AppColors.danger)
                            .withValues(alpha: 0.1),
                    child: Icon(
                      t.isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                      color: t.isCredit ? AppColors.success : AppColors.danger,
                      size: 18,
                    ),
                  ),
                  title: Text(t.description,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                      '${t.typeLabel} · ${_fmt(t.createdAt)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.gray)),
                  trailing: Text(
                    '${t.isCredit ? '+' : '-'}₹${t.amount.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: t.isCredit ? AppColors.success : AppColors.danger,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _PaginationBar(
          page: _page,
          pageCount: _pageCount,
          rangeLabel: '$start-$end of ${widget.transactions.length}',
          onPrevious: _page == 0 ? null : () => setState(() => _page--),
          onNext: _page >= _pageCount - 1 ? null : () => setState(() => _page++),
        ),
      ],
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}

class _WithdrawalList extends StatefulWidget {
  final List<WithdrawalRequest> withdrawals;
  const _WithdrawalList({required this.withdrawals});

  @override
  State<_WithdrawalList> createState() => _WithdrawalListState();
}

class _WithdrawalListState extends State<_WithdrawalList> {
  static const int _pageSize = 10;
  int _page = 0;

  int get _pageCount =>
      widget.withdrawals.isEmpty ? 1 : ((widget.withdrawals.length - 1) ~/ _pageSize) + 1;

  List<WithdrawalRequest> get _visibleWithdrawals {
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.withdrawals.length);
    return widget.withdrawals.sublist(start, end);
  }

  @override
  void didUpdateWidget(covariant _WithdrawalList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= _pageCount) {
      _page = _pageCount - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.withdrawals.isEmpty) {
      return const Center(
        child: Text('No withdrawal requests yet',
            style: TextStyle(color: AppColors.gray)),
      );
    }

    final visibleWithdrawals = _visibleWithdrawals;
    final start = (_page * _pageSize) + 1;
    final end = (_page * _pageSize) + visibleWithdrawals.length;

    return Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: ListView.separated(
              key: ValueKey(_page),
              itemCount: visibleWithdrawals.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final w = visibleWithdrawals[i];
                final isPending = w.status == 'pending';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (isPending ? AppColors.warning : AppColors.success)
                        .withValues(alpha: 0.1),
                    child: Icon(
                      isPending ? Icons.hourglass_empty : Icons.check_circle_outline,
                      color: isPending ? AppColors.warning : AppColors.success,
                      size: 18,
                    ),
                  ),
                  title: Text('₹${w.amount.toStringAsFixed(0)} withdrawal',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                      '${w.bankAccount} · ${_fmt(w.requestedAt)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.gray)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isPending ? AppColors.warning : AppColors.success)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      w.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isPending ? AppColors.warning : AppColors.success,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _PaginationBar(
          page: _page,
          pageCount: _pageCount,
          rangeLabel: '$start-$end of ${widget.withdrawals.length}',
          onPrevious: _page == 0 ? null : () => setState(() => _page--),
          onNext: _page >= _pageCount - 1 ? null : () => setState(() => _page++),
        ),
      ],
    );
  }

  String _fmt(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}

class _PaginationBar extends StatelessWidget {
  final int page;
  final int pageCount;
  final String rangeLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _PaginationBar({
    required this.page,
    required this.pageCount,
    required this.rangeLabel,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          _PagerIconButton(
            icon: Icons.chevron_left_rounded,
            onTap: onPrevious,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rangeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Page ${page + 1} of $pageCount',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          _PagerIconButton(
            icon: Icons.chevron_right_rounded,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _PagerIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _PagerIconButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? const Color(0xFFC7D2FE) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Icon(
          icon,
          color: enabled ? AppColors.primary : const Color(0xFFCBD5E1),
        ),
      ),
    );
  }
}

// ── Transactions page ─────────────────────────────────────────────────────────
class _TransactionsPage extends StatelessWidget {
  const _TransactionsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Transaction History'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.dark,
        elevation: 0,
      ),
      body: Consumer<WalletProvider>(
        builder: (_, wallet, __) {
          if (wallet.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return _TransactionList(transactions: wallet.transactions);
        },
      ),
    );
  }
}

// ── Withdrawals page ──────────────────────────────────────────────────────────
class _WithdrawalsPage extends StatelessWidget {
  const _WithdrawalsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Withdrawal Requests'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.dark,
        elevation: 0,
      ),
      body: Consumer<WalletProvider>(
        builder: (_, wallet, __) {
          if (wallet.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return _WithdrawalList(withdrawals: wallet.withdrawals);
        },
      ),
    );
  }
}

// ── My Earnings page ──────────────────────────────────────────────────────────
class _EarningsPage extends StatelessWidget {
  const _EarningsPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('My Earnings'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.dark,
        elevation: 0,
      ),
      body: Consumer<WalletProvider>(
        builder: (_, wallet, __) {
          if (wallet.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final credits = wallet.transactions.where((t) => t.isCredit).toList();
          return _TransactionList(transactions: credits);
        },
      ),
    );
  }
}

// ── Spent page ────────────────────────────────────────────────────────────────
class _SpentPage extends StatelessWidget {
  const _SpentPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Spent'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.dark,
        elevation: 0,
      ),
      body: Consumer<WalletProvider>(
        builder: (_, wallet, __) {
          if (wallet.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final debits = wallet.transactions.where((t) => !t.isCredit).toList();
          return _TransactionList(transactions: debits);
        },
      ),
    );
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Wallet History'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.dark,
        elevation: 0,
      ),
      body: Consumer<WalletProvider>(
        builder: (_, wallet, __) {
          if (wallet.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = <_HistoryEntry>[
            ...wallet.transactions.map(
              (t) => _HistoryEntry(
                title: t.description,
                subtitle: '${t.typeLabel} · ${_fmtDate(t.createdAt)}',
                amountLabel: '${t.isCredit ? '+' : '-'}₹${t.amount.toStringAsFixed(0)}',
                date: t.createdAt,
                color: t.isCredit ? AppColors.success : AppColors.danger,
                icon: t.isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              ),
            ),
            ...wallet.withdrawals.map(
              (w) => _HistoryEntry(
                title: 'Withdrawal Request',
                subtitle: '${w.status.toUpperCase()} · ${_fmtDate(w.requestedAt)}',
                amountLabel: '-₹${w.amount.toStringAsFixed(0)}',
                date: w.requestedAt,
                color: w.status == 'pending' ? AppColors.warning : AppColors.primary,
                icon: w.status == 'pending'
                    ? Icons.hourglass_bottom_rounded
                    : Icons.account_balance_wallet_rounded,
              ),
            ),
          ]..sort((a, b) => b.date.compareTo(a.date));

          return _HistoryList(entries: entries);
        },
      ),
    );
  }
}

class _HistoryEntry {
  final String title;
  final String subtitle;
  final String amountLabel;
  final DateTime date;
  final Color color;
  final IconData icon;

  const _HistoryEntry({
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.date,
    required this.color,
    required this.icon,
  });
}

class _HistoryList extends StatefulWidget {
  final List<_HistoryEntry> entries;

  const _HistoryList({required this.entries});

  @override
  State<_HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<_HistoryList> {
  static const int _pageSize = 10;
  int _page = 0;

  int get _pageCount =>
      widget.entries.isEmpty ? 1 : ((widget.entries.length - 1) ~/ _pageSize) + 1;

  List<_HistoryEntry> get _visibleEntries {
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.entries.length);
    return widget.entries.sublist(start, end);
  }

  @override
  void didUpdateWidget(covariant _HistoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page >= _pageCount) {
      _page = _pageCount - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return const Center(
        child: Text('No wallet history yet',
            style: TextStyle(color: AppColors.gray)),
      );
    }

    final visibleEntries = _visibleEntries;
    final start = (_page * _pageSize) + 1;
    final end = (_page * _pageSize) + visibleEntries.length;

    return Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: ListView.separated(
              key: ValueKey(_page),
              itemCount: visibleEntries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final entry = visibleEntries[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: entry.color.withValues(alpha: 0.1),
                    child: Icon(entry.icon, color: entry.color, size: 18),
                  ),
                  title: Text(entry.title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    entry.subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.gray),
                  ),
                  trailing: Text(
                    entry.amountLabel,
                    style: TextStyle(
                      color: entry.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _PaginationBar(
          page: _page,
          pageCount: _pageCount,
          rangeLabel: '$start-$end of ${widget.entries.length}',
          onPrevious: _page == 0 ? null : () => setState(() => _page--),
          onNext: _page >= _pageCount - 1 ? null : () => setState(() => _page++),
        ),
      ],
    );
  }
}

String _fmtDate(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
