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
    final wallet = context.read<WalletProvider>();
    final ok = await wallet.verifyTopUp({
      'razorpay_order_id': response.orderId,
      'razorpay_payment_id': response.paymentId,
      'razorpay_signature': response.signature,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Payment successful! Wallet credited.'
            : (wallet.error ?? 'Payment verification failed.')),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
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
                  final options = <String, dynamic>{
                    'key': order['key'] ?? order['razorpay_key'] ?? '',
                    'order_id': order['order_id'] ?? order['id'],
                    'amount': order['amount'], // paise from backend
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
              controller: bankCtrl,
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
                      bankAccount: bankCtrl.text,
                      ifscCode: ifscCtrl.text,
                      accountHolder: holderCtrl.text,
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
    return Scaffold(
      appBar: AppBar(title: const Text('My Wallet')),
      body: Consumer<WalletProvider>(
        builder: (_, wallet, __) {
          if (wallet.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final b = wallet.balance;

          return Column(
            children: [
              // Balance card
              Container(
                margin: const EdgeInsets.all(16),
                child: GradientContainer(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Available Balance',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        '₹${b.balance.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _StatCol(
                              label: 'Earned',
                              value: '₹${b.totalEarned.toStringAsFixed(0)}'),
                          _StatCol(
                              label: 'Spent',
                              value: '₹${b.totalSpent.toStringAsFixed(0)}'),
                          _StatCol(
                              label: 'Cashback',
                              value:
                                  '₹${b.totalCashback.toStringAsFixed(0)}'),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _showAddMoney,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add Money'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.primary,
                                minimumSize: const Size(0, 42),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _showWithdraw,
                              icon: const Icon(Icons.arrow_upward, size: 18),
                              label: const Text('Withdraw'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white70),
                                minimumSize: const Size(0, 42),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Tabs
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
