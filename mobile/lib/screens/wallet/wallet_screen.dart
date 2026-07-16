import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../providers/wallet_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/wallet.dart';
import '../../theme/app_theme.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late Razorpay _razorpay;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
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
    _tabs.dispose();
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

  void _showWithdraw() {
    // KYC must be verified to withdraw
    final auth = context.read<AuthProvider>();
    if (!(auth.user?.isKycVerified ?? false)) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('KYC Verification Required'),
          content: const Text(
            'Complete KYC verification before withdrawing money.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/kyc');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Verify KYC'),
            ),
          ],
        ),
      );
      return;
    }

    final amtCtrl = TextEditingController();
    final bankNameCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    final ifscCtrl = TextEditingController();
    final holderCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Request Withdrawal',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bankNameCtrl,
              decoration: const InputDecoration(labelText: 'Bank Name (e.g. SBI, HDFC)'),
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
              controller: ifscCtrl,
              decoration: const InputDecoration(labelText: 'IFSC Code'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: holderCtrl,
              decoration:
                  const InputDecoration(labelText: 'Account Holder Name'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final amt = double.tryParse(amtCtrl.text);
                if (amt == null || amt < 1) return;
                Navigator.pop(ctx);
                final ok = await context.read<WalletProvider>().requestWithdrawal(
                      amount: amt,
                      bankName: bankNameCtrl.text.trim(),
                      bankAccount: bankCtrl.text.trim(),
                      ifscCode: ifscCtrl.text.trim(),
                      accountHolder: holderCtrl.text.trim(),
                    );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(ok
                          ? 'Withdrawal request submitted'
                          : 'Failed to submit request')),
                );
              },
              child: const Text('Submit Request'),
            ),
          ],
        ),
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
          // Responsive sizing
          final logoH  = sw * 0.13;
          final balFS  = (sw * 0.09).clamp(28.0, 44.0);
          final illW   = sw * 0.35;
          final illH   = sw * 0.32;

          return Column(
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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Left: logo + balance
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Logo + Secure badge row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // W4U Logo
                                  Image.asset(
                                    'assets/images/logo_light.png',
                                    height: logoH,
                                    fit: BoxFit.contain,
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
                        const SizedBox(width: 8),
                        // Right: 3D wallet illustration
                        SizedBox(
                          width: illW,
                          height: illH,
                          child: Image.asset(
                            'assets/images/wallet_illustration.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
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
                child: Row(
                  children: [
                    _ActionBtn(
                      icon: Icons.add_rounded,
                      label: 'Add Money',
                      color: const Color(0xFF3B82F6),
                      onTap: _showAddMoney,
                    ),
                    _ActionBtn(
                      icon: Icons.arrow_upward_rounded,
                      label: 'Withdraw',
                      color: const Color(0xFF7C3AED),
                      onTap: _showWithdraw,
                    ),
                    _ActionBtn(
                      icon: Icons.receipt_long_rounded,
                      label: 'History',
                      color: const Color(0xFF059669),
                      onTap: () => _tabs.animateTo(0),
                    ),
                    _ActionBtn(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'My Earnings',
                      color: const Color(0xFFF59E0B),
                      onTap: () => _tabs.animateTo(1),
                    ),
                  ],
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
                      value: '₹${b.totalEarned.toStringAsFixed(0)}',
                    ),
                    Container(width: 1, height: 34,
                        color: Colors.white.withValues(alpha: 0.3)),
                    _StatItem(
                      icon: Icons.trending_up_rounded,
                      label: 'Spent',
                      value: '₹${b.totalSpent.toStringAsFixed(0)}',
                    ),
                    Container(width: 1, height: 34,
                        color: Colors.white.withValues(alpha: 0.3)),
                    _StatItem(
                      icon: Icons.card_giftcard_rounded,
                      label: 'Cashback',
                      value: '₹${b.totalCashback.toStringAsFixed(0)}',
                    ),
                  ],
                ),
              ),

              // ── Tabs ─────────────────────────────────────────────────
              const SizedBox(height: 10),
              TabBar(
                controller: _tabs,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.gray,
                indicatorColor: AppColors.primary,
                tabs: const [
                  Tab(text: 'Transactions'),
                  Tab(text: 'Withdrawals'),
                ],
              ),

              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _TransactionList(transactions: wallet.transactions),
                    _WithdrawalList(withdrawals: wallet.withdrawals),
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
    return Expanded(
      child: GestureDetector(
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
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }
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

class _StatCol extends StatelessWidget {
  final String label;
  final String value;

  const _StatCol({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          Text(label,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  final List<Transaction> transactions;
  const _TransactionList({required this.transactions});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const Center(
        child: Text('No transactions yet',
            style: TextStyle(color: AppColors.gray)),
      );
    }

    return ListView.separated(
      itemCount: transactions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final t = transactions[i];
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
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}

class _WithdrawalList extends StatelessWidget {
  final List<WithdrawalRequest> withdrawals;
  const _WithdrawalList({required this.withdrawals});

  @override
  Widget build(BuildContext context) {
    if (withdrawals.isEmpty) {
      return const Center(
        child: Text('No withdrawal requests yet',
            style: TextStyle(color: AppColors.gray)),
      );
    }

    return ListView.separated(
      itemCount: withdrawals.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final w = withdrawals[i];
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
    );
  }

  String _fmt(DateTime dt) => '${dt.day}/${dt.month}/${dt.year}';
}
