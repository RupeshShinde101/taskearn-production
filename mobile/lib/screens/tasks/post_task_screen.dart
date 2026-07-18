import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../models/task.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class PostTaskScreen extends StatefulWidget {
  const PostTaskScreen({super.key});

  @override
  State<PostTaskScreen> createState() => _PostTaskScreenState();
}

/// Returns the platform service charge in rupees for a given task category.
/// Ranges are taken from the Workmate4u Terms of Service (Section 6.2).
int _serviceChargeFor(String category) {
  const charges = <String, int>{
    // Quick errands
    'delivery': 30, 'pickup': 30, 'errands': 30, 'queue_standing': 30,
    // Standard
    'groceries': 45, 'cleaning': 45, 'cooking': 45, 'laundry': 45,
    'gardening': 45, 'transport': 45,
    // Skilled
    'repair': 60, 'tech_support': 60, 'pet_care': 60,
    'child_care': 60, 'elder_care': 60, 'data_entry': 60,
    // Time-intensive
    'tutoring': 75, 'photography': 75, 'painting': 75,
    'moving': 75, 'event_help': 75,
    // Professional
    'carpentry': 95, 'electrician': 95, 'plumbing': 95,
  };
  return charges[category] ?? 40;
}

class _PostTaskScreenState extends State<PostTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  String _selectedCategory = 'errands';
  LatLng? _location;
  bool _loading = false;
  bool _gettingLocation = false;

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() => _gettingLocation = true);
    final loc = await LocationService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _location = loc;
        _gettingLocation = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please allow location access')),
      );
      return;
    }

    // KYC must be verified to post a task
    final auth = context.read<AuthProvider>();
    if (!(auth.user?.isKycVerified ?? false)) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('KYC Verification Required'),
          content: const Text(
            'You need to complete KYC verification before posting a task.',
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

    final budget = double.tryParse(_budgetCtrl.text) ?? 0;
    final charge = _serviceChargeFor(_selectedCategory).toDouble();
    final total  = budget + charge;

    // Fetch current wallet balance and verify the poster has enough funds.
    final wallet = context.read<WalletProvider>();
    await wallet.fetchWallet();
    if (!mounted) return;

    if (wallet.balance.balance < total) {
      final shortfall = total - wallet.balance.balance;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Insufficient Wallet Balance'),
          content: Text(
            'You need ₹${total.toStringAsFixed(0)} to post this task '
            '(task ₹${budget.toStringAsFixed(0)} + service charge ₹${charge.toStringAsFixed(0)}).\n\n'
            'Current balance: ₹${wallet.balance.balance.toStringAsFixed(0)}\n'
            'Add at least ₹${shortfall.ceil()} to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Money'),
            ),
          ],
        ),
      );
      if (go == true && mounted) context.push('/wallet');
      return;
    }

    // Confirm deduction before posting
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Task Posting'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The following will be deducted from your wallet:'),
            const SizedBox(height: 12),
            _CostRow('Task Budget', '₹${budget.toStringAsFixed(0)}'),
            _CostRow('Service Charge', '₹${charge.toStringAsFixed(0)}'),
            const Divider(height: 20),
            _CostRow('Total Deduction', '₹${total.toStringAsFixed(0)}',
                bold: true),
            const SizedBox(height: 8),
            Text(
              'Wallet balance after posting: ₹${(wallet.balance.balance - total).toStringAsFixed(0)}',
              style: const TextStyle(color: AppColors.gray, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Post & Pay'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _loading = true);

    final taskData = {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'category': _selectedCategory,
      'price': double.tryParse(_budgetCtrl.text) ?? 0,
      'budget': double.tryParse(_budgetCtrl.text) ?? 0,
      'latitude': _location!.latitude,
      'longitude': _location!.longitude,
      'address': _addressCtrl.text.isNotEmpty ? _addressCtrl.text.trim() : null,
    };

    final ok = await context.read<TaskProvider>().postTask(taskData);

    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task posted successfully!')),
      );
      context.go('/my-tasks');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                context.read<TaskProvider>().error ?? 'Failed to post task')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post a Task')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  hintText: 'e.g. Pick up parcel from Bandra',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 5) ? 'Min 5 characters' : null,
              ),
              const SizedBox(height: 14),

              // Category
              const Text('Category',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.dark)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TaskCategory.all.map((c) {
                  final sel = _selectedCategory == c.id;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = c.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : AppColors.light,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? AppColors.primary : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '${c.icon} ${c.label}',
                        style: TextStyle(
                          color: sel ? Colors.white : AppColors.gray,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Description
              TextFormField(
                controller: _descCtrl,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Q: What needs to be done?\nA: Describe clearly...\n\n- Add requirements as bullets',
                  hintStyle: const TextStyle(color: Color(0xFFB0B8C8), fontSize: 12.5, height: 1.7),
                  prefixIcon: const Icon(Icons.description_outlined),
                  alignLabelWithHint: true,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 10) ? 'Min 10 characters' : null,
              ),
              const SizedBox(height: 14),

              // Budget
              TextFormField(
                controller: _budgetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Budget (₹)',
                  hintText: 'Minimum ₹100',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < 100) return 'Minimum budget is ₹100';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Address
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address / Landmark (optional)',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 14),

              // Location status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _location != null
                      ? AppColors.success.withValues(alpha: 0.08)
                      : AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _location != null
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _location != null ? Icons.my_location : Icons.location_off,
                      color: _location != null
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _location != null
                            ? 'Location detected (${_location!.latitude.toStringAsFixed(4)}, ${_location!.longitude.toStringAsFixed(4)})'
                            : 'Location not detected',
                        style: TextStyle(
                          color: _location != null
                              ? AppColors.success
                              : AppColors.warning,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (_gettingLocation)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      TextButton(
                        onPressed: _getLocation,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),


              // ── Cost breakdown ─────────────────────────────────────
              Builder(builder: (context) {
                final budget  = double.tryParse(_budgetCtrl.text) ?? 0;
                final charge  = _serviceChargeFor(_selectedCategory).toDouble();
                final total   = budget + charge;
                final walletBalance =
                    context.watch<WalletProvider>().balance.balance;
                final hasEnough = walletBalance >= total;
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: hasEnough
                        ? AppColors.success.withValues(alpha: 0.06)
                        : AppColors.danger.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasEnough
                          ? AppColors.success.withValues(alpha: 0.3)
                          : AppColors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 16,
                            color: hasEnough ? AppColors.success : AppColors.danger,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Payment Summary',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: hasEnough ? AppColors.success : AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _CostRow('Task Budget',
                          '₹${budget.toStringAsFixed(0)}'),
                      const SizedBox(height: 4),
                      _CostRow('Service Charge',
                          '₹${charge.toStringAsFixed(0)}'),
                      const Divider(height: 14),
                      _CostRow('Total Deducted from Wallet',
                          '₹${total.toStringAsFixed(0)}',
                          bold: true),
                      const SizedBox(height: 6),
                      Text(
                        'Wallet: ₹${walletBalance.toStringAsFixed(0)}${hasEnough
                            ? '  ✔ Sufficient'
                            : '  ⚠ Add ₹${(total - walletBalance).ceil()} more'}',
                        style: TextStyle(
                          color: hasEnough
                              ? AppColors.success
                              : AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 16),

              GradientButton(
                label: 'Post Task',
                loading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple two-column label + value row used in cost breakdown dialogs.
class _CostRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _CostRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: bold ? AppColors.dark : AppColors.gray,
      fontSize: bold ? 14 : 13,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}
