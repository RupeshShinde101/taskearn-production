import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  String? _code;
  Map<String, dynamic>? _stats;
  bool _loading = true;
  bool _applying = false;
  final _applyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _applyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final codeData = await ApiService.get('/referral/code');
      final statsData = await ApiService.get('/referral/stats');
      if (mounted) {
        setState(() {
          _code = codeData['code'] ?? codeData['referral_code'];
          _stats = statsData;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyCode() async {
    if (_applyCtrl.text.trim().isEmpty) return;
    setState(() => _applying = true);

    try {
      await ApiService.post('/referral/apply',
          body: {'referral_code': _applyCtrl.text.trim()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Referral code applied! Cashback added.')),
      );
      _applyCtrl.clear();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }

    setState(() => _applying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Referral & Rewards')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Your code card
                  GradientContainer(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(Icons.card_giftcard,
                            color: Colors.white, size: 40),
                        const SizedBox(height: 12),
                        const Text(
                          'Your Referral Code',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _code ?? 'Loading…',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Share your code. Earn ₹50 cashback for each friend who joins!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  if (_code != null) {
                                    Clipboard.setData(
                                        ClipboardData(text: _code!));
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                            content:
                                                Text('Code copied!')));
                                  }
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copy'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.primary,
                                  minimumSize: const Size(0, 40),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Stats
                  if (_stats != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            _StatTile(
                                label: 'Referrals',
                                value:
                                    '${_stats!['total_referrals'] ?? 0}'),
                            _StatTile(
                                label: 'Earned',
                                value:
                                    '₹${_stats!['total_earned'] ?? 0}'),
                            _StatTile(
                                label: 'Pending',
                                value:
                                    '₹${_stats!['pending'] ?? 0}'),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Apply code
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Have a referral code?',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _applyCtrl,
                            textCapitalization:
                                TextCapitalization.characters,
                            decoration: const InputDecoration(
                              hintText: 'Enter code',
                              prefixIcon:
                                  Icon(Icons.confirmation_number_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GradientButton(
                            label: 'Apply Code',
                            loading: _applying,
                            onPressed: _applyCode,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppColors.primary)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.gray, fontSize: 11)),
        ],
      ),
    );
  }
}
