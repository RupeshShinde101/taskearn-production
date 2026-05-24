import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/map_location_picker.dart';

class PostTaskScreen extends StatefulWidget {
  const PostTaskScreen({super.key});

  @override
  State<PostTaskScreen> createState() => _PostTaskScreenState();
}

class _PostTaskScreenState extends State<PostTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  // Delivery-specific: separate pickup & drop location fields
  final _pickupAddrCtrl = TextEditingController();
  final _dropAddrCtrl = TextEditingController();

  String _selectedCategory = 'delivery';
  LatLng? _location;
  String? _locationLabel; // reverse-geocoded address from map picker
  bool _loading = false;
  bool _gettingLocation = false;
  bool _showAllCategories = false;
  // Per-field lat/lng for delivery categories
  LatLng? _pickupLocation;
  LatLng? _dropLocation;
  bool _gettingPickupGps = false;
  bool _gettingDropGps = false;

  static const _deliveryCats = {'delivery', 'pickup', 'transport', 'moving'};
  bool get _isDelivery => _deliveryCats.contains(_selectedCategory);

  /// Per-category description prompt chips shown below the description field.
  static const Map<String, List<String>> _prompts = {
    'delivery':    ['What to deliver?', 'Pickup point?', 'Drop point?', 'Item size/weight?', 'Urgent?'],
    'pickup':      ['What to pick up?', 'From where?', 'Fragile?', 'Time constraint?'],
    'transport':   ['How many people/items?', 'From → To?', 'Vehicle type needed?', 'Luggage?'],
    'moving':      ['How many rooms?', 'Pickup floor?', 'Drop floor?', 'Need packing help?'],
    'groceries':   ['Which items?', 'Which store/area?', 'Grocery budget?', 'Brand preference?'],
    'cleaning':    ['How many rooms?', 'Type of cleaning?', 'Time slot?', 'Pets at home?'],
    'cooking':     ['How many people?', 'What cuisine/dishes?', 'Dietary restrictions?', 'Time needed?'],
    'laundry':     ['How many clothes?', 'Wash + fold or just fold?', 'Pick up from home?'],
    'electrician': ['What electrical work?', 'Specific fault/issue?', 'Urgent?'],
    'plumbing':    ['What plumbing issue?', 'Room affected?', 'Urgent?'],
    'repair':      ['What to repair?', 'Brand/model?', 'How long broken?'],
    'tutoring':    ['Which subject?', 'Grade/level?', 'Hours needed?', 'Online or in-person?'],
    'carpentry':   ['What carpentry work?', 'Materials needed?', 'Approximate dimensions?'],
    'painting':    ['What to paint?', 'Colour preference?', 'Area size?'],
    'pet_care':    ['Type of pet?', 'Care needed?', 'Duration?', 'Vaccinated?'],
    'child_care':  ['Age of child?', 'Duration?', 'Special needs?'],
    'elder_care':  ['Type of care?', 'Duration?', 'Medical needs?'],
    'photography': ['Type of shoot?', 'Duration?', 'Location?', 'Deliverables?'],
    'data_entry':  ['Type of data?', 'Volume/pages?', 'Format needed?', 'Deadline?'],
    'gardening':   ['Type of work?', 'Garden size?', 'Tools needed?'],
    'errands':     ['What errand?', 'Location?', 'Time constraint?'],
    'event_help':  ['Event type?', 'No. of guests?', 'Duration?', 'What help needed?'],
    'tech_support':['Device type?', 'What issue?', 'OS/software?'],
    'other':       ['Describe the task clearly?', 'Skills needed?', 'Expected duration?'],
  };

  void _appendPrompt(String text) {
    final current = _descCtrl.text.trimRight();
    _descCtrl.text = current.isEmpty ? '$text: ' : '$current\n$text: ';
    _descCtrl.selection =
        TextSelection.fromPosition(TextPosition(offset: _descCtrl.text.length));
    setState(() {});
  }

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
    _pickupAddrCtrl.dispose();
    _dropAddrCtrl.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() => _gettingLocation = true);
    final loc = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (loc == null) {
      setState(() => _gettingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not get GPS. Enable location permission.'),
        ),
      );
      return;
    }
    setState(() {
      _location = loc;
      _locationLabel = null;
      _gettingLocation = false;
    });
    try {
      final places = await placemarkFromCoordinates(loc.latitude, loc.longitude)
          .timeout(const Duration(seconds: 6));
      if (mounted && places.isNotEmpty) {
        final p = places.first;
        final parts = [p.name, p.subLocality, p.locality]
            .where((s) => s != null && s!.isNotEmpty)
            .map((s) => s!)
            .toList();
        final addr = parts.isEmpty ? null : parts.join(', ');
        if (mounted) {
          setState(() => _locationLabel = addr);
          if (!_isDelivery && _addressCtrl.text.isEmpty && addr != null) {
            _addressCtrl.text = addr;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _pickLocationFromMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(initialLocation: _location),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      final addr = result['address'] as String?;
      setState(() {
        _location = result['location'] as LatLng;
        _locationLabel = addr;
        if (!_isDelivery && addr != null) _addressCtrl.text = addr;
      });
    }
  }

  Future<void> _pickMapForPickup() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MapLocationPicker(initialLocation: _pickupLocation ?? _location),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      final addr = result['address'] as String?;
      setState(() {
        _pickupLocation = result['location'] as LatLng;
        _location ??= _pickupLocation;
        if (addr != null && addr.isNotEmpty) _pickupAddrCtrl.text = addr;
      });
    }
  }

  Future<void> _pickMapForDrop() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MapLocationPicker(initialLocation: _dropLocation ?? _location),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      final addr = result['address'] as String?;
      setState(() {
        _dropLocation = result['location'] as LatLng;
        if (addr != null && addr.isNotEmpty) _dropAddrCtrl.text = addr;
      });
    }
  }

  Future<void> _getGpsForPickup() async {
    setState(() => _gettingPickupGps = true);
    final loc = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (loc == null) {
      setState(() => _gettingPickupGps = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not get GPS. Enable location permission.')),
      );
      return;
    }
    setState(() {
      _pickupLocation = loc;
      _location ??= loc;
    });
    try {
      final places = await placemarkFromCoordinates(loc.latitude, loc.longitude)
          .timeout(const Duration(seconds: 6));
      if (mounted && places.isNotEmpty) {
        final p = places.first;
        final parts = [p.name, p.subLocality, p.locality]
            .where((s) => s != null && s!.isNotEmpty)
            .map((s) => s!)
            .toList();
        final addr = parts.isEmpty ? null : parts.join(', ');
        if (mounted) {
          setState(() => _gettingPickupGps = false);
          if (addr != null) _pickupAddrCtrl.text = addr;
        }
      } else {
        if (mounted) setState(() => _gettingPickupGps = false);
      }
    } catch (_) {
      if (mounted) setState(() => _gettingPickupGps = false);
    }
  }

  Future<void> _getGpsForDrop() async {
    setState(() => _gettingDropGps = true);
    final loc = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (loc == null) {
      setState(() => _gettingDropGps = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not get GPS. Enable location permission.')),
      );
      return;
    }
    setState(() => _dropLocation = loc);
    try {
      final places = await placemarkFromCoordinates(loc.latitude, loc.longitude)
          .timeout(const Duration(seconds: 6));
      if (mounted && places.isNotEmpty) {
        final p = places.first;
        final parts = [p.name, p.subLocality, p.locality]
            .where((s) => s != null && s!.isNotEmpty)
            .map((s) => s!)
            .toList();
        final addr = parts.isEmpty ? null : parts.join(', ');
        if (mounted) {
          setState(() => _gettingDropGps = false);
          if (addr != null) _dropAddrCtrl.text = addr;
        }
      } else {
        if (mounted) setState(() => _gettingDropGps = false);
      }
    } catch (_) {
      if (mounted) setState(() => _gettingDropGps = false);
    }
  }

  /// Returns a rejection reason string if content is flagged, or null if OK.
  static String? _checkBannedContent(String title, String description) {
    final text = '${title.toLowerCase()} ${description.toLowerCase()}';
    if (text.trim().isEmpty) return null;

    final patterns = <(RegExp, String)>[
      (RegExp(r'\b(create|make|open|register|sign[- ]?up|generate|bulk)\b.{0,40}\b(email|emails|gmail|yahoo|outlook|hotmail|account|accounts|id|ids|profile|profiles)\b', caseSensitive: false), 'Bulk account or email creation tasks are not allowed (anti-spam policy).'),
      (RegExp(r'\b(per|each|/)\s*(email|account|id|signup|sign[- ]?up|profile)\b', caseSensitive: false), 'Tasks paying per account/email creation are not allowed.'),
      (RegExp(r'\b(sell|buy|rent|hire)\b.{0,30}\b(account|accounts|gmail|whatsapp|instagram|facebook|telegram|otp|sim|number)\b', caseSensitive: false), 'Buying or selling accounts/credentials is prohibited.'),
      (RegExp(r'\b(receive|share|forward|read|provide|give|sell)\b.{0,30}\b(otp|otps|one[- ]time[- ]password|verification\s*code|sms\s*code)\b', caseSensitive: false), 'OTP/verification-code sharing tasks are prohibited.'),
      (RegExp(r'\botp\s*(work|task|job|earn)\b', caseSensitive: false), 'OTP-based earning tasks are prohibited.'),
      (RegExp(r'\b(use|share|rent|sell)\b.{0,30}\b(aadhaar|aadhar|pan\s*card|kyc|bank\s*account|upi\s*id)\b', caseSensitive: false), 'Sharing or renting personal KYC documents is prohibited.'),
      (RegExp(r'\b(fake|paid|bulk)\b.{0,20}\b(reviews?|ratings?|likes?|followers?|subscribers?|comments?|votes?)\b', caseSensitive: false), 'Fake review/engagement/follower tasks are prohibited.'),
      (RegExp(r'\b(click|watch)\s*(ads|advertisements|videos)\s*(bot|farm|loop)\b', caseSensitive: false), 'Click-fraud tasks are prohibited.'),
      (RegExp(r'\b(usdt|btc|bitcoin|crypto|forex)\b.{0,30}\b(investment|trade|trading|deposit|recharge|profit|earn)\b', caseSensitive: false), 'Crypto/forex investment tasks are not permitted on Workmate4u.'),
      (RegExp(r'\b(money\s*mule|transfer\s*money|launder|cash[- ]out)\b', caseSensitive: false), 'Money transfer/mule activity is strictly prohibited.'),
      (RegExp(r'\b(hack|crack|bypass|unlock)\b.{0,30}\b(password|account|server|whatsapp|instagram|facebook|gmail|wifi|otp)\b', caseSensitive: false), 'Hacking or unauthorized access tasks are prohibited.'),
      (RegExp(r'\b(escort|webcam\s*model|adult\s*content|nude|sex\s*chat|drugs?|weed|cocaine|heroin)\b', caseSensitive: false), 'Adult/illicit-content tasks are not allowed.'),
      (RegExp(r'\b(captcha\s*solving|typing\s*captcha)\b', caseSensitive: false), 'Captcha-solving/spam tasks are not allowed.'),
      (RegExp(r'\b(spam|spamming)\b.{0,20}\b(email|sms|whatsapp|message)\b', caseSensitive: false), 'Spam/bulk messaging tasks are not allowed.'),
      (RegExp(r'\b(registration|joining|training|security|refundable)\s*(fee|deposit|amount|charge)\b', caseSensitive: false), 'Charging registration/security/joining fees from helpers is prohibited.'),
      (RegExp(r'\b(pay|deposit|send|transfer)\b.{0,30}\b(first|upfront|in\s*advance|before\s*start)\b', caseSensitive: false), 'Tasks requiring upfront payment from the helper are not allowed.'),
      (RegExp(r'\b(gift\s*card|itunes\s*card|amazon\s*voucher|paytm\s*voucher|google\s*play\s*card)\b', caseSensitive: false), 'Gift-card/voucher purchase tasks are not allowed (common scam vector).'),
      (RegExp(r'\b(western\s*union|moneygram|wire\s*transfer)\b', caseSensitive: false), 'Wire-transfer/money-remittance tasks are not allowed.'),
      (RegExp(r'\b(double|2x|triple)\s*your\s*(money|investment|amount)\b', caseSensitive: false), 'Investment doubling/get-rich-quick tasks are prohibited.'),
      (RegExp(r'\b(guaranteed)\s*(returns?|profit|income|earning)\b', caseSensitive: false), 'Guaranteed-return investment tasks are prohibited.'),
      (RegExp(r'\b(mlm|multi[- ]level|pyramid|ponzi|chain\s*scheme|matrix\s*scheme)\b', caseSensitive: false), 'MLM/pyramid/chain schemes are prohibited.'),
      (RegExp(r'\b(recharge|deposit)\b.{0,20}\b(usdt|btc|trx|binance|crypto)\b', caseSensitive: false), 'Crypto recharge/deposit tasks are prohibited.'),
      (RegExp(r'\bshare\s*(your\s*)?(otp|cvv|pin|password|net[- ]?banking|atm\s*pin)\b', caseSensitive: false), 'Sharing of OTP/PIN/CVV/banking credentials is strictly prohibited.'),
      (RegExp(r'\b(give|tell|send)\s*(me\s*)?(your\s*)?(aadhaar|pan|bank|otp|cvv|pin)\b', caseSensitive: false), 'Asking helpers for Aadhaar/PAN/bank/OTP details is prohibited.'),
      (RegExp(r'\b(fake|duplicate|forged?)\s*(aadhaar|pan|certificate|degree|marksheet|id|licence|license|passport)\b', caseSensitive: false), 'Fake/forged document tasks are illegal and prohibited.'),
      (RegExp(r'\b(buy|sell)\s*(fake|stolen)\b', caseSensitive: false), 'Sale of fake/stolen goods is prohibited.'),
      (RegExp(r'\b(get\s*rich\s*quick|easy\s*money|no\s*work\s*required)\b', caseSensitive: false), 'Misleading earnings claims are not allowed.'),
      (RegExp(r'\b(pay|paid|payment)\b.{0,15}\b(outside|off)\b.{0,15}\b(app|platform|workmate)\b', caseSensitive: false), 'Tasks asking to pay outside the platform are not allowed.'),
      (RegExp(r'\b(skip|bypass|avoid)\b.{0,15}\b(commission|platform|service\s*charge)\b', caseSensitive: false), 'Bypassing platform commission is not allowed.'),
      (RegExp(r'\bcash\s*only\b.{0,30}\b(outside|hand|direct)\b', caseSensitive: false), 'Cash-only/off-platform payment tasks are not allowed.'),
      (RegExp(r'\b(gun|pistol|firearm|ammunition|country\s*made)\b', caseSensitive: false), 'Weapons-related tasks are prohibited.'),
      (RegExp(r'\b(mdma|lsd|ganja|hashish|opium|brown\s*sugar)\b', caseSensitive: false), 'Drug-related tasks are prohibited.'),
    ];

    for (final (rx, reason) in patterns) {
      if (rx.hasMatch(text)) return reason;
    }

    // Phone number in task content
    if (RegExp(r'(?:\+?91[\s\-]?)?[6-9]\d{9}').hasMatch(text)) {
      return 'Sharing phone numbers in the task is not allowed. Helpers can contact you through in-app chat.';
    }
    // Email address in task content
    if (RegExp(r'[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}', caseSensitive: false).hasMatch(text)) {
      return 'Sharing email addresses in the task is not allowed. Helpers can contact you through in-app chat.';
    }

    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // ── Client-side banned keyword check ────────────────────────────────────
    final _bannedResult = _checkBannedContent(_titleCtrl.text, _descCtrl.text);
    if (_bannedResult != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_bannedResult),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    // ────────────────────────────────────────────────────────────────────────

    final LatLng? taskLocation =
        _isDelivery ? (_pickupLocation ?? _location) : _location;
    if (taskLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please set a location — tap the map icon next to the address field'),
        ),
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
    final charge = Task.serviceChargeForCategory(_selectedCategory).toDouble();
    final total  = budget + charge;

    // Confirm posting — payment is collected AFTER the helper completes the task
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your task will be posted for helpers to accept.\n'
              'You will only be charged when the helper completes the work and you verify it.',
              style: TextStyle(color: AppColors.gray, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            _CostRow('Task Budget', '₹${budget.toStringAsFixed(0)}'),
            if (charge > 0) _CostRow('Service Charge', '₹${charge.toStringAsFixed(0)}'),
            const Divider(height: 20),
            _CostRow('Total (due on verification)', '₹${total.toStringAsFixed(0)}',
                bold: true),
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
            child: const Text('Post Task'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _loading = true);

    // Build the address field: for delivery categories combine pickup + drop.
    final String? combinedAddress;
    if (_isDelivery) {
      final pickup = _pickupAddrCtrl.text.trim();
      final drop   = _dropAddrCtrl.text.trim();
      combinedAddress = (pickup.isNotEmpty || drop.isNotEmpty)
          ? 'Pickup: $pickup\nDrop: $drop'
          : _locationLabel;
    } else {
      final typed = _addressCtrl.text.trim();
      combinedAddress = typed.isNotEmpty ? typed : _locationLabel;
    }

    final taskData = {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'category': _selectedCategory,
      'price': double.tryParse(_budgetCtrl.text) ?? 0,
      'budget': double.tryParse(_budgetCtrl.text) ?? 0,
      if (charge > 0) 'service_charge': charge,
      // Nested location object expected by the backend
      'location': {
        'lat': taskLocation.latitude,
        'lng': taskLocation.longitude,
        'address': combinedAddress ?? '',
      },
      if (_isDelivery && _pickupAddrCtrl.text.trim().isNotEmpty)
        'pickup_address': _pickupAddrCtrl.text.trim(),
      if (_isDelivery && _dropAddrCtrl.text.trim().isNotEmpty) ...{
        'delivery_address': _dropAddrCtrl.text.trim(),
        'drop_location_address': _dropAddrCtrl.text.trim(),
      },
      if (_isDelivery && _dropLocation != null) ...{
        'dropLocation': {
          'lat': _dropLocation!.latitude,
          'lng': _dropLocation!.longitude,
          'address': _dropAddrCtrl.text.trim(),
        },
      },
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

              // ── Category grid ───────────────────────────────────────
              const Text('Category',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.dark)),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (ctx, constraints) {
                final cats = _showAllCategories
                    ? TaskCategory.all
                    : TaskCategory.all.take(12).toList();
                const crossCount = 4;
                return Column(
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cats.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossCount,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 70 / 70,
                      ),
                      itemBuilder: (ctx, i) {
                        final c = cats[i];
                        final sel = _selectedCategory == c.id;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedCategory = c.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: sel
                                  ? AppColors.primary
                                  : AppColors.light,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: sel ? 2 : 1,
                              ),
                              boxShadow: sel
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.25),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(c.icon,
                                    style: const TextStyle(fontSize: 22)),
                                const SizedBox(height: 4),
                                Text(
                                  c.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: sel
                                        ? Colors.white
                                        : AppColors.dark,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showAllCategories = !_showAllCategories),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _showAllCategories
                                  ? 'Show fewer categories'
                                  : 'Show all categories',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _showAllCategories
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 14),

              // Description
              TextFormField(
                controller: _descCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe what needs to be done…',
                  prefixIcon: Icon(Icons.description_outlined),
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 10)
                        ? 'Min 10 characters'
                        : null,
              ),
              // Per-category prompt chips
              if ((_prompts[_selectedCategory] ?? []).isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Add details:',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.gray,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: (_prompts[_selectedCategory]!).map((p) {
                    return ActionChip(
                      label: Text(p,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.dark)),
                      onPressed: () => _appendPrompt(p),
                      backgroundColor: AppColors.light,
                      side:
                          const BorderSide(color: AppColors.border),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 14),

              // Budget
              TextFormField(
                controller: _budgetCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Budget (₹)',
                  hintText: _isDelivery ? 'Auto-filled from distance' : 'Minimum ₹100',
                  prefixIcon: const Icon(Icons.currency_rupee),
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Please enter a budget';
                  if (!_isDelivery && n < 100) return 'Minimum budget is ₹100';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── Address fields (each with GPS + Map inline buttons) ──────
              if (_isDelivery) ...[
                // Pickup Address
                TextFormField(
                  controller: _pickupAddrCtrl,
                  decoration: InputDecoration(
                    labelText: 'Pickup Address *',
                    hintText: 'Where to pick up from',
                    prefixIcon:
                        const Icon(Icons.location_on, color: AppColors.primary),
                    suffixIcon: _AddressActionButtons(
                      isLoading: _gettingPickupGps,
                      accentColor: AppColors.primary,
                      onGps: _getGpsForPickup,
                      onMap: _pickMapForPickup,
                    ),
                    suffixIconConstraints:
                        const BoxConstraints(maxHeight: 48),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Pickup address is required'
                      : null,
                ),
                if (_pickupLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, left: 12),
                    child: Text(
                      'Pinned: ${_pickupLocation!.latitude.toStringAsFixed(5)}, '
                      '${_pickupLocation!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: AppColors.success, fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 10),
                // Drop Address
                TextFormField(
                  controller: _dropAddrCtrl,
                  decoration: InputDecoration(
                    labelText: 'Drop / Delivery Address *',
                    hintText: 'Where to deliver / drop off',
                    prefixIcon:
                        const Icon(Icons.flag, color: AppColors.danger),
                    suffixIcon: _AddressActionButtons(
                      isLoading: _gettingDropGps,
                      accentColor: AppColors.danger,
                      onGps: _getGpsForDrop,
                      onMap: _pickMapForDrop,
                    ),
                    suffixIconConstraints:
                        const BoxConstraints(maxHeight: 48),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Drop address is required'
                      : null,
                ),
                if (_dropLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, left: 12),
                    child: Text(
                      'Pinned: ${_dropLocation!.latitude.toStringAsFixed(5)}, '
                      '${_dropLocation!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 11),
                    ),
                  ),
              ] else ...[
                // Single address for non-delivery tasks
                TextFormField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                    labelText: 'Address / Landmark (optional)',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    suffixIcon: _AddressActionButtons(
                      isLoading: _gettingLocation,
                      accentColor: AppColors.primary,
                      onGps: _getLocation,
                      onMap: _pickLocationFromMap,
                    ),
                    suffixIconConstraints:
                        const BoxConstraints(maxHeight: 48),
                  ),
                ),
                if (_location != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3, left: 12),
                    child: Text(
                      _locationLabel != null
                          ? 'Pinned: $_locationLabel'
                          : 'Pinned: ${_location!.latitude.toStringAsFixed(5)}, '
                              '${_location!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                          color: AppColors.success, fontSize: 11),
                    ),
                  ),
              ],

              const SizedBox(height: 14),

              // ── Cost breakdown — real-time via ValueListenableBuilder ──
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _budgetCtrl,
                builder: (_, value, __) {
                  final budget = double.tryParse(value.text) ?? 0;
                  final charge = Task.serviceChargeForCategory(_selectedCategory).toDouble();
                  final total = budget + charge;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: AppColors.primary),
                            SizedBox(width: 6),
                            Text(
                              'Payment due on verification',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _CostRow('Task Budget',
                            '₹${budget.toStringAsFixed(0)}'),
                        if (charge > 0) ...[
                          const SizedBox(height: 4),
                          _CostRow('Service Charge',
                              '₹${charge.toStringAsFixed(0)}'),
                        ],
                        const Divider(height: 14),
                        _CostRow('Total (pay after completion)',
                            '₹${total.toStringAsFixed(0)}',
                            bold: true),
                        const SizedBox(height: 6),
                        const Text(
                          'No payment needed now. You pay when the helper finishes and you verify the work.',
                          style: TextStyle(
                              color: AppColors.gray,
                              fontSize: 11,
                              height: 1.4),
                        ),
                      ],
                    ),
                  );
                },
              ),

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

/// Suffix widget for address text fields: two icon buttons — GPS + Map picker.
class _AddressActionButtons extends StatelessWidget {
  final bool isLoading;
  final Color accentColor;
  final VoidCallback onGps;
  final VoidCallback onMap;

  const _AddressActionButtons({
    required this.isLoading,
    required this.accentColor,
    required this.onGps,
    required this.onMap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLoading)
          const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          IconButton(
            icon: Icon(Icons.my_location, size: 20, color: accentColor),
            tooltip: 'Use GPS',
            onPressed: onGps,
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(),
          ),
        IconButton(
          icon: Icon(Icons.map_outlined, size: 20, color: accentColor),
          tooltip: 'Pick on map',
          onPressed: onMap,
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(),
        ),
      ],
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
