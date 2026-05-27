import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../providers/task_provider.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/map_location_picker.dart';

class EditTaskScreen extends StatefulWidget {
  final Task task;
  const EditTaskScreen({super.key, required this.task});

  @override
  State<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends State<EditTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _budgetCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _pickupAddrCtrl;
  late final TextEditingController _dropAddrCtrl;

  late String _selectedCategory;
  LatLng? _location;
  String? _locationLabel;
  bool _loading = false;
  // Per-field lat/lng for delivery categories
  LatLng? _pickupLocation;
  LatLng? _dropLocation;
  bool _gettingPickupGps = false;
  bool _gettingDropGps = false;

  static const _deliveryCats = {'delivery', 'pickup', 'transport', 'moving'};
  bool get _isDelivery => _deliveryCats.contains(_selectedCategory);

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

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleCtrl      = TextEditingController(text: t.title);
    _descCtrl       = TextEditingController(text: t.description);
    _budgetCtrl     = TextEditingController(text: t.budget.toStringAsFixed(0));
    _selectedCategory = t.category;

    // Pre-fill address fields
    if (_isDelivery && t.address != null) {
      final addr = t.address!;
      // Try to split "Pickup: X\nDrop: Y" format
      final pickupMatch = RegExp(r'Pickup:\s*(.+?)(?:\n|$)', dotAll: true).firstMatch(addr);
      final dropMatch   = RegExp(r'Drop:\s*(.+?)(?:\n|$)', dotAll: true).firstMatch(addr);
      _pickupAddrCtrl = TextEditingController(text: pickupMatch?.group(1)?.trim() ?? '');
      _dropAddrCtrl   = TextEditingController(text: dropMatch?.group(1)?.trim() ?? '');
      _addressCtrl    = TextEditingController();
    } else {
      _pickupAddrCtrl = TextEditingController();
      _dropAddrCtrl   = TextEditingController();
      _addressCtrl    = TextEditingController(text: t.address ?? '');
    }

    _location = LatLng(t.latitude, t.longitude);
    _locationLabel = t.address;
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

  void _appendPrompt(String text) {
    final current = _descCtrl.text.trimRight();
    _descCtrl.text = current.isEmpty ? '$text: ' : '$current\n$text: ';
    _descCtrl.selection =
        TextSelection.fromPosition(TextPosition(offset: _descCtrl.text.length));
    setState(() {});
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
            .where((s) => s != null && s.isNotEmpty)
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
            .where((s) => s != null && s.isNotEmpty)
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set a location on the map')),
      );
      return;
    }

    final budget = double.tryParse(_budgetCtrl.text) ?? 0;
    final charge = Task.serviceChargeForCategory(_selectedCategory).toDouble();

    final String? combinedAddress;
    if (_isDelivery) {
      final pickup = _pickupAddrCtrl.text.trim();
      final drop   = _dropAddrCtrl.text.trim();
      combinedAddress = (pickup.isNotEmpty || drop.isNotEmpty)
          ? 'Pickup: $pickup\nDrop: $drop'
          : _locationLabel;
    } else {
      combinedAddress = _addressCtrl.text.isNotEmpty
          ? _addressCtrl.text.trim()
          : _locationLabel;
    }

    final data = {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'category': _selectedCategory,
      'price': budget,
      'budget': budget,
      if (charge > 0) 'service_charge': charge,
      'latitude': (_isDelivery ? (_pickupLocation ?? _location) : _location)!.latitude,
      'longitude': (_isDelivery ? (_pickupLocation ?? _location) : _location)!.longitude,
      'address': combinedAddress,
      if (_isDelivery && _pickupAddrCtrl.text.trim().isNotEmpty)
        'pickup_address': _pickupAddrCtrl.text.trim(),
      if (_isDelivery && _dropAddrCtrl.text.trim().isNotEmpty)
        'delivery_address': _dropAddrCtrl.text.trim(),
    };

    setState(() => _loading = true);
    final ok = await context.read<TaskProvider>().updateTask(widget.task.id, data);
    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task updated successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop(true); // signal caller to reload
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<TaskProvider>().error ?? 'Failed to update task'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Task')),
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
              _CategoryGrid(
                selected: _selectedCategory,
                onChanged: (c) => setState(() => _selectedCategory = c),
              ),
              const SizedBox(height: 14),

              // Description
              TextFormField(
                controller: _descCtrl,
                maxLines: 5,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe what needs to be done…',
                  prefixIcon: Icon(Icons.description_outlined),
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().length < 10)
                    ? 'Min 10 characters'
                    : null,
              ),
              // Prompt chips
              if ((_prompts[_selectedCategory] ?? []).isNotEmpty) ...[
                const SizedBox(height: 4),
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
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
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
                      isLoading: false,
                      accentColor: AppColors.primary,
                      onGps: () async {
                        final loc =
                            await LocationService.getCurrentLocation();
                        if (loc == null || !mounted) return;
                        setState(() {
                          _location = loc;
                          _locationLabel = null;
                        });
                      },
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

              // Cost breakdown (real-time via ValueListenableBuilder)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _budgetCtrl,
                builder: (_, value, __) {
                  final budget = double.tryParse(value.text) ?? 0;
                  final charge =
                      Task.serviceChargeForCategory(_selectedCategory).toDouble();
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
                        _CostRow(
                            'Total (pay after completion)',
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
              const SizedBox(height: 20),

              GradientButton(
                label: 'Update Task',
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

// ── Category grid ─────────────────────────────────────────────────────────────
class _CategoryGrid extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _CategoryGrid({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cats = TaskCategory.all;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (_, i) {
        final c = cats[i];
        final sel = selected == c.id;
        return GestureDetector(
          onTap: () => onChanged(c.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : AppColors.light,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: sel ? AppColors.primary : AppColors.border,
                width: sel ? 2 : 1,
              ),
              boxShadow: sel
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(c.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 4),
                Text(
                  c.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        sel ? FontWeight.w700 : FontWeight.w500,
                    color: sel ? Colors.white : AppColors.dark,
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
    );
  }
}

// ── Cost row helper ───────────────────────────────────────────────────────────
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
      children: [Text(label, style: style), Text(value, style: style)],
    );
  }
}

// ── Address action buttons (GPS + Map) ────────────────────────────────────────
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
