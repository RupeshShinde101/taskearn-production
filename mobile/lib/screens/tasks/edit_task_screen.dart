import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../providers/task_provider.dart';
import '../../services/location_search_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/location_suggestions_dropdown.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/task_price_breakdown_card.dart';

/// Parent Category grouping configuration for the Edit Task screen,
/// aligned with Browse Tasks and Category standards.
class _ParentCategoryConfig {
  final String label;
  final String subtitle;
  final String imageAsset;
  final List<String> subcategories;

  const _ParentCategoryConfig({
    required this.label,
    required this.subtitle,
    required this.imageAsset,
    required this.subcategories,
  });
}

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
  late final TextEditingController _addressCtrl;
  late final TextEditingController _pickupAddrCtrl;
  late final TextEditingController _dropAddrCtrl;

  late String _selectedCategory;
  late String _selectedParentGroup;
  late final ValueNotifier<double> _effectiveBudgetNotifier;

  LatLng? _location;
  String? _locationLabel;
  bool _loading = false;

  // Per-field lat/lng for delivery categories
  LatLng? _pickupLocation;
  LatLng? _dropLocation;
  double? _calculatedDistanceKm;
  String _deliveryVehicle = 'bike'; // 'bike' (₹12/km) or 'rikshaw' (₹18/km)
  int _distCalcSeq = 0;
  bool _gettingPickupGps = false;
  bool _gettingDropGps = false;

  // Search autocomplete state
  Timer? _pickupDebounce;
  Timer? _dropDebounce;
  Timer? _addressDebounce;
  List<LocationSearchResult> _pickupSuggestions = [];
  List<LocationSearchResult> _dropSuggestions = [];
  List<LocationSearchResult> _addressSuggestions = [];
  bool _searchingPickup = false;
  bool _searchingDrop = false;
  bool _searchingAddress = false;

  static const List<_ParentCategoryConfig> _parentGroups = [
    _ParentCategoryConfig(
      label: 'Delivery & Moving',
      subtitle: 'Moving, delivery, parcel transport',
      imageAsset: 'assets/images/cat_3d_delivery.png',
      subcategories: ['delivery', 'moving', 'transport', 'pickup'],
    ),
    _ParentCategoryConfig(
      label: 'Repair',
      subtitle: 'Plumbing, electrical, appliance, auto',
      imageAsset: 'assets/images/cat_3d_repair.png',
      subcategories: [
        'repair',
        'electrician',
        'plumbing',
        'carpentry',
        'vehicle',
        'tech_support',
      ],
    ),
    _ParentCategoryConfig(
      label: 'Home & Lifestyle',
      subtitle: 'Cleaning, cooking, household chores',
      imageAsset: 'assets/images/cat_3d_home.png',
      subcategories: [
        'cleaning',
        'household',
        'cooking',
        'laundry',
        'gardening',
        'beauty',
      ],
    ),
    _ParentCategoryConfig(
      label: 'Shopping & Errands',
      subtitle: 'Groceries, purchase, errands',
      imageAsset: 'assets/images/cat_3d_shopping.png',
      subcategories: [
        'shopping',
        'groceries',
        'errands',
        'queue_standing',
        'event_help',
      ],
    ),
    _ParentCategoryConfig(
      label: 'Professional',
      subtitle: 'Freelance, IT, design, tutoring',
      imageAsset: 'assets/images/cat_3d_professional.png',
      subcategories: [
        'freelancer',
        'data_entry',
        'photography',
        'tutoring',
        'painting',
        'drawing',
        'graphic_design',
        'web_app_tech',
        'video_audio_editing',
        'digital_marketing',
        'business_admin',
      ],
    ),
    _ParentCategoryConfig(
      label: 'Care Services',
      subtitle: 'Child care, elder care, pet care',
      imageAsset: 'assets/images/cat_3d_care.png',
      subcategories: ['child_care', 'elder_care', 'pet_care'],
    ),
    _ParentCategoryConfig(
      label: 'Other',
      subtitle: 'Custom & miscellaneous tasks',
      imageAsset: 'assets/images/cat_3d_other_skyline.png',
      subcategories: ['other'],
    ),
  ];

  static const _deliveryCats = {'delivery', 'pickup', 'transport', 'moving'};
  bool get _isDelivery => _deliveryCats.contains(_selectedCategory);

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleCtrl = TextEditingController(text: t.title);
    _descCtrl = TextEditingController(text: t.description);
    _selectedCategory = t.category;

    // Resolve parent group from current category
    _selectedParentGroup = _parentGroups.firstWhere(
      (p) => p.subcategories.contains(_selectedCategory),
      orElse: () => _parentGroups.first,
    ).label;

    // Pre-fill address fields
    if (_isDelivery && t.address != null) {
      final addr = t.address!;
      final pickupMatch = RegExp(r'Pickup:\s*(.+?)(?:\n|$)', dotAll: true).firstMatch(addr);
      final dropMatch = RegExp(r'Drop:\s*(.+?)(?:\n|$)', dotAll: true).firstMatch(addr);
      _pickupAddrCtrl = TextEditingController(text: pickupMatch?.group(1)?.trim() ?? '');
      _dropAddrCtrl = TextEditingController(text: dropMatch?.group(1)?.trim() ?? '');
      _addressCtrl = TextEditingController();
    } else {
      _pickupAddrCtrl = TextEditingController();
      _dropAddrCtrl = TextEditingController();
      _addressCtrl = TextEditingController(text: t.address ?? '');
    }

    _location = LatLng(t.latitude, t.longitude);
    _locationLabel = t.address;
    if (_isDelivery) {
      _pickupLocation = _location;
      if (t.dropLatitude != null && t.dropLongitude != null) {
        _dropLocation = LatLng(t.dropLatitude!, t.dropLongitude!);
      }
      final desc = t.description.toLowerCase();
      if (desc.contains('rikshaw') || desc.contains('auto')) {
        _deliveryVehicle = 'rikshaw';
      }
    }

    _effectiveBudgetNotifier = ValueNotifier<double>(_computeEffectiveBudget());

    if (_isDelivery) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recalcDistance());
    }
  }

  @override
  void dispose() {
    _pickupDebounce?.cancel();
    _dropDebounce?.cancel();
    _addressDebounce?.cancel();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _pickupAddrCtrl.dispose();
    _dropAddrCtrl.dispose();
    _effectiveBudgetNotifier.dispose();
    super.dispose();
  }

  double _computeEffectiveBudget() {
    final cat = Task.normalizeCategoryKey(_selectedCategory);
    if (cat == 'moving') {
      if (_calculatedDistanceKm != null && _calculatedDistanceKm! > 0) {
        return Task.calculateDistancePrice(_calculatedDistanceKm!, 'moving', vehicle: _deliveryVehicle);
      }
      return Task.minBudgetForCategory('moving');
    }
    if (_isDelivery) {
      if (_calculatedDistanceKm != null && _calculatedDistanceKm! > 0) {
        return Task.calculateDistancePrice(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle);
      }
      return Task.minBudgetForCategory(_selectedCategory);
    }
    return Task.minBudgetForCategory(_selectedCategory);
  }

  Future<void> _recalcDistance() async {
    if (_pickupLocation != null && _dropLocation != null) {
      final seq = ++_distCalcSeq;
      // 1. Instant road estimate (aerial * 1.25 road factor) for zero UI lag
      final meters = const Distance().distance(
        _pickupLocation!,
        _dropLocation!,
      );
      final immediateKm = (meters / 1000.0) * 1.25;
      if (mounted) {
        setState(() => _calculatedDistanceKm = immediateKm);
        _effectiveBudgetNotifier.value = _computeEffectiveBudget();
      }

      // 2. Fetch exact road driving route via OSRM (Google Maps parity)
      try {
        final roadKm = await LocationService.calculateRoadDistance(
          _pickupLocation!,
          _dropLocation!,
        );
        if (seq == _distCalcSeq && mounted) {
          setState(() => _calculatedDistanceKm = roadKm);
          _effectiveBudgetNotifier.value = _computeEffectiveBudget();
        }
      } catch (_) {}
    } else {
      if (mounted) {
        setState(() => _calculatedDistanceKm = null);
        _effectiveBudgetNotifier.value = _computeEffectiveBudget();
      }
    }
  }

  // ── Location Autocomplete Handlers ──────────────────────────────────────
  void _onPickupAddrChanged(String text) {
    _pickupDebounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      if (_pickupSuggestions.isNotEmpty || _searchingPickup) {
        setState(() {
          _pickupSuggestions = [];
          _searchingPickup = false;
        });
      }
      return;
    }
    setState(() => _searchingPickup = true);
    _pickupDebounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await LocationSearchService.search(
          q,
          userLocation: _pickupLocation ?? _location,
        );
        if (!mounted) return;
        setState(() {
          _pickupSuggestions = results;
          _searchingPickup = false;
        });
      } catch (_) {
        if (mounted) setState(() => _searchingPickup = false);
      }
    });
  }

  void _selectPickupSuggestion(LocationSearchResult s) {
    _pickupAddrCtrl.text = s.fullAddress;
    _pickupLocation = s.toLatLng();
    _location ??= _pickupLocation;
    _pickupSuggestions = [];
    _searchingPickup = false;
    _recalcDistance();
    FocusScope.of(context).unfocus();
    setState(() {});
  }

  void _onDropAddrChanged(String text) {
    _dropDebounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      if (_dropSuggestions.isNotEmpty || _searchingDrop) {
        setState(() {
          _dropSuggestions = [];
          _searchingDrop = false;
        });
      }
      return;
    }
    setState(() => _searchingDrop = true);
    _dropDebounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await LocationSearchService.search(
          q,
          userLocation: _dropLocation ?? _location,
        );
        if (!mounted) return;
        setState(() {
          _dropSuggestions = results;
          _searchingDrop = false;
        });
      } catch (_) {
        if (mounted) setState(() => _searchingDrop = false);
      }
    });
  }

  void _selectDropSuggestion(LocationSearchResult s) {
    _dropAddrCtrl.text = s.fullAddress;
    _dropLocation = s.toLatLng();
    _dropSuggestions = [];
    _searchingDrop = false;
    _recalcDistance();
    FocusScope.of(context).unfocus();
    setState(() {});
  }

  void _onAddressChanged(String text) {
    _addressDebounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      if (_addressSuggestions.isNotEmpty || _searchingAddress) {
        setState(() {
          _addressSuggestions = [];
          _searchingAddress = false;
        });
      }
      return;
    }
    setState(() => _searchingAddress = true);
    _addressDebounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await LocationSearchService.search(
          q,
          userLocation: _location,
        );
        if (!mounted) return;
        setState(() {
          _addressSuggestions = results;
          _searchingAddress = false;
        });
      } catch (_) {
        if (mounted) setState(() => _searchingAddress = false);
      }
    });
  }

  void _selectAddressSuggestion(LocationSearchResult s) {
    _addressCtrl.text = s.fullAddress;
    _location = s.toLatLng();
    _locationLabel = s.title;
    _addressSuggestions = [];
    _searchingAddress = false;
    FocusScope.of(context).unfocus();
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
        builder: (_) => MapLocationPicker(initialLocation: _pickupLocation ?? _location),
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
      _recalcDistance();
    }
  }

  Future<void> _pickMapForDrop() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(initialLocation: _dropLocation ?? _location),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      final addr = result['address'] as String?;
      setState(() {
        _dropLocation = result['location'] as LatLng;
        if (addr != null && addr.isNotEmpty) _dropAddrCtrl.text = addr;
      });
      _recalcDistance();
    }
  }

  Future<void> _getGpsForPickup() async {
    setState(() => _gettingPickupGps = true);
    final loc = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (loc == null) {
      setState(() => _gettingPickupGps = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get GPS. Enable location permission.')),
      );
      return;
    }
    setState(() {
      _pickupLocation = loc;
      _location ??= loc;
    });
    _recalcDistance();
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
        const SnackBar(content: Text('Could not get GPS. Enable location permission.')),
      );
      return;
    }
    setState(() => _dropLocation = loc);
    _recalcDistance();
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

    final budget = _computeEffectiveBudget();
    final charge = Task.serviceChargeForCategory(_selectedCategory).toDouble();

    final String? combinedAddress;
    if (_isDelivery) {
      final pickup = _pickupAddrCtrl.text.trim();
      final drop = _dropAddrCtrl.text.trim();
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
      'location': {
        'lat': (_isDelivery ? (_pickupLocation ?? _location) : _location)!.latitude,
        'lng': (_isDelivery ? (_pickupLocation ?? _location) : _location)!.longitude,
        'address': combinedAddress ?? '',
      },
      if (_isDelivery) ...{
        if (_pickupAddrCtrl.text.trim().isNotEmpty)
          'pickup_address': _pickupAddrCtrl.text.trim(),
        if (_dropAddrCtrl.text.trim().isNotEmpty) ...{
          'delivery_address': _dropAddrCtrl.text.trim(),
          'drop_location_address': _dropAddrCtrl.text.trim(),
          'drop_address': _dropAddrCtrl.text.trim(),
        },
        'drop_location': {
          'lat': _dropLocation?.latitude,
          'lng': _dropLocation?.longitude,
          'address': _dropAddrCtrl.text.trim(),
        },
        'dropLocation': {
          'lat': _dropLocation?.latitude,
          'lng': _dropLocation?.longitude,
          'address': _dropAddrCtrl.text.trim(),
        },
      },
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
      context.pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.read<TaskProvider>().error ?? 'Failed to update task',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  String _getCategoryLabel(String categoryId) {
    final match = TaskCategory.all.firstWhere(
      (c) => c.id == categoryId,
      orElse: () => TaskCategory(id: categoryId, label: categoryId.replaceAll('_', ' '), icon: '📋'),
    );
    return match.label;
  }

  // ── Unified Card Container ──────────────────────────────────────────────
  Widget _buildCardSection({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
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
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── High Quality Category Artwork Icons ─────────────────────────────────
  Widget _buildSubcatIcon(String categoryId, {double size = 28}) {
    final assetPath = 'assets/images/subcats/$categoryId.png';
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        final cat = TaskCategory.all.firstWhere(
          (c) => c.id == categoryId,
          orElse: () => TaskCategory(id: categoryId, label: categoryId, icon: '📋'),
        );
        return Text(cat.icon, style: TextStyle(fontSize: size * 0.8));
      },
    );
  }

  // ── Delivery Vehicle Selector ───────────────────────────────────────────
  Widget _buildDeliveryVehicleSelector() {
    return _buildCardSection(
      icon: Icons.two_wheeler_rounded,
      iconColor: const Color(0xFF2563EB),
      iconBg: const Color(0xFFEFF6FF),
      title: 'Delivery Vehicle Option',
      subtitle: 'Select vehicle capacity matching package weight and size',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Text(
          _deliveryVehicle == 'bike' ? '₹12 / km (Bike)' : '₹18 / km (Rikshaw)',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
            color: Color(0xFF2563EB),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildVehicleTile(
              title: 'Bike / 2-Wheeler',
              rate: '₹12 / km',
              capacity: 'Max 20kg • 40×40cm',
              desc: 'Small items, parcels, docs',
              imageAsset: 'assets/images/vehicle_bike.png',
              isSelected: _deliveryVehicle == 'bike',
              onTap: () {
                if (_deliveryVehicle != 'bike') {
                  setState(() => _deliveryVehicle = 'bike');
                  _recalcDistance();
                }
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildVehicleTile(
              title: 'Auto / Rikshaw',
              rate: '₹18 / km',
              capacity: 'Max 80kg • Bulky cargo',
              desc: 'Medium boxes, rain safe',
              imageAsset: 'assets/images/vehicle_rikshaw.png',
              isSelected: _deliveryVehicle == 'rikshaw',
              onTap: () {
                if (_deliveryVehicle != 'rikshaw') {
                  setState(() => _deliveryVehicle = 'rikshaw');
                  _recalcDistance();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleTile({
    required String title,
    required String rate,
    required String capacity,
    required String desc,
    required String imageAsset,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset(
                  imageAsset,
                  height: 38,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    title.contains('Bike') ? Icons.two_wheeler : Icons.electric_rickshaw,
                    size: 32,
                    color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? const Color(0xFF2563EB) : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              rate,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                capacity,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Reusable Address Field with Inline GPS + Map Actions ────────────────
  Widget _buildAddressField({
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required String label,
    required String hint,
    required IconData prefixIcon,
    required Color prefixColor,
    required bool isLoading,
    required VoidCallback onGps,
    required VoidCallback onMap,
    LatLng? pinnedLocation,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          onChanged: onChanged,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            prefixIcon: Icon(prefixIcon, color: prefixColor, size: 20),
            suffixIcon: _AddressActionButtons(
              isLoading: isLoading,
              accentColor: prefixColor,
              onGps: onGps,
              onMap: onMap,
            ),
            suffixIconConstraints: const BoxConstraints(maxHeight: 48),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: prefixColor, width: 1.5),
            ),
          ),
          validator: (v) {
            if (label.contains('*') && (v == null || v.trim().isEmpty)) {
              return '$label is required';
            }
            return null;
          },
        ),
        if (pinnedLocation != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 10),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF10B981)),
                const SizedBox(width: 4),
                Text(
                  'Pinned: ${pinnedLocation.latitude.toStringAsFixed(4)}, ${pinnedLocation.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeParent = _parentGroups.firstWhere(
      (p) => p.label == _selectedParentGroup,
      orElse: () => _parentGroups.first,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Color(0xFF0F172A), size: 24),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Edit Task',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
            letterSpacing: -0.3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Task Title (Unified Single Card) ──────────────────────
              _buildCardSection(
                icon: Icons.edit_note_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
                title: 'Task Title',
                subtitle: 'Give your task a clear, descriptive title',
                child: TextFormField(
                  controller: _titleCtrl,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. Deliver cookies to office',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    prefixIcon: const Icon(Icons.title_rounded, color: Color(0xFF2563EB), size: 20),
                    suffixIcon: _titleCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                            onPressed: () {
                              _titleCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().length < 5)
                      ? 'Title must be at least 5 characters'
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
              ),

              const SizedBox(height: 14),

              // ── 2. Category Selection (Enhanced High-Res 3D Artwork) ───
              _buildCardSection(
                icon: Icons.grid_view_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
                title: 'Select Category',
                subtitle: 'Choose the service type that best matches your task',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF2563EB)),
                      const SizedBox(width: 4),
                      Text(
                        _getCategoryLabel(_selectedCategory),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Primary Groups (Browse Tasks Reference)
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _parentGroups.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final group = _parentGroups[i];
                          final isGroupSelected = group.label == _selectedParentGroup;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedParentGroup = group.label;
                                if (!group.subcategories.contains(_selectedCategory) &&
                                    group.subcategories.isNotEmpty) {
                                  _selectedCategory = group.subcategories.first;
                                  _recalcDistance();
                                  _effectiveBudgetNotifier.value = _computeEffectiveBudget();
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 112,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              decoration: BoxDecoration(
                                color: isGroupSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isGroupSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                                  width: isGroupSelected ? 2 : 1,
                                ),
                                boxShadow: isGroupSelected
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    group.imageAsset,
                                    height: 40,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.category_rounded,
                                      size: 32,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    group.label,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isGroupSelected ? FontWeight.w800 : FontWeight.w600,
                                      color: isGroupSelected ? const Color(0xFF1E3A8A) : const Color(0xFF334155),
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    const SizedBox(height: 12),

                    // Subcategory Chips Grid
                    Text(
                      '${activeParent.label} Services',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: activeParent.subcategories.map((subcatId) {
                        final isSubSelected = _selectedCategory == subcatId;
                        final label = _getCategoryLabel(subcatId);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedCategory = subcatId;
                              _recalcDistance();
                              _effectiveBudgetNotifier.value = _computeEffectiveBudget();
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: isSubSelected ? const Color(0xFF2563EB) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSubSelected ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                                width: isSubSelected ? 1.5 : 1,
                              ),
                              boxShadow: isSubSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildSubcatIcon(subcatId, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSubSelected ? FontWeight.w700 : FontWeight.w600,
                                    color: isSubSelected ? Colors.white : const Color(0xFF1E293B),
                                  ),
                                ),
                                if (isSubSelected) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              // ── 3. Vehicle Option (for Delivery & Moving) ────────────────
              if (_selectedCategory == 'delivery' || _selectedCategory == 'moving') ...[
                const SizedBox(height: 14),
                _buildDeliveryVehicleSelector(),
              ],

              const SizedBox(height: 14),

              // ── 4. Task Description (Unified Single Card) ────────────────
              _buildCardSection(
                icon: Icons.description_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEFF6FF),
                title: 'Description',
                subtitle: 'Detail instructions, requirements, and items needed',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_descCtrl.text.length}/1000',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _descCtrl.text.length > 900
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
                child: TextFormField(
                  controller: _descCtrl,
                  maxLines: 4,
                  maxLength: 1000,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Describe what needs to be done, location instructions, specific items…',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().length < 10)
                      ? 'Description must be at least 10 characters'
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
              ),

              const SizedBox(height: 14),

              // ── 5 & 6. Pickup and Drop Location with Distance ────────────
              if (_isDelivery) ...[
                _buildCardSection(
                  icon: Icons.route_rounded,
                  iconColor: const Color(0xFF2563EB),
                  iconBg: const Color(0xFFEFF6FF),
                  title: 'Pickup & Drop Location',
                  subtitle: 'Set addresses for route calculation and distance fare',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pickup
                      _buildAddressField(
                        controller: _pickupAddrCtrl,
                        onChanged: _onPickupAddrChanged,
                        label: 'Pickup Address *',
                        hint: 'Where to pick up from',
                        prefixIcon: Icons.trip_origin_rounded,
                        prefixColor: const Color(0xFF10B981),
                        isLoading: _gettingPickupGps,
                        onGps: _getGpsForPickup,
                        onMap: _pickMapForPickup,
                        pinnedLocation: _pickupLocation,
                      ),
                      LocationSuggestionsDropdown(
                        suggestions: _pickupSuggestions,
                        isLoading: _searchingPickup,
                        accentColor: const Color(0xFF10B981),
                        onSelect: _selectPickupSuggestion,
                        onDismiss: () => setState(() => _pickupSuggestions = []),
                      ),

                      const SizedBox(height: 12),

                      // Drop
                      _buildAddressField(
                        controller: _dropAddrCtrl,
                        onChanged: _onDropAddrChanged,
                        label: 'Drop / Delivery Address *',
                        hint: 'Where to deliver / drop off',
                        prefixIcon: Icons.location_on_rounded,
                        prefixColor: const Color(0xFFEF4444),
                        isLoading: _gettingDropGps,
                        onGps: _getGpsForDrop,
                        onMap: _pickMapForDrop,
                        pinnedLocation: _dropLocation,
                      ),
                      LocationSuggestionsDropdown(
                        suggestions: _dropSuggestions,
                        isLoading: _searchingDrop,
                        accentColor: const Color(0xFFEF4444),
                        onSelect: _selectDropSuggestion,
                        onDismiss: () => setState(() => _dropSuggestions = []),
                      ),

                      // Integrated Distance & Route Fare Card
                      if (_calculatedDistanceKm != null && _calculatedDistanceKm! > 0) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.alt_route_rounded, color: Color(0xFF2563EB), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Distance: ${_calculatedDistanceKm!.toStringAsFixed(1)} km',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: Color(0xFF1E3A8A),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDBEAFE),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            _deliveryVehicle == 'bike' ? 'Bike @ ₹12/km' : 'Rikshaw @ ₹18/km',
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1D4ED8),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Calculated fare: ₹${Task.calculateDistancePrice(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle).toInt()} (${Task.distancePriceDescription(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle)})',
                                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                // Single Address for non-delivery tasks
                _buildCardSection(
                  icon: Icons.location_on_rounded,
                  iconColor: const Color(0xFF2563EB),
                  iconBg: const Color(0xFFEFF6FF),
                  title: 'Task Location',
                  subtitle: 'Where this task needs to be performed',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAddressField(
                        controller: _addressCtrl,
                        onChanged: _onAddressChanged,
                        label: 'Address / Landmark (optional)',
                        hint: 'Type locality, landmark or address',
                        prefixIcon: Icons.place_rounded,
                        prefixColor: const Color(0xFF2563EB),
                        isLoading: false,
                        onGps: () async {
                          final loc = await LocationService.getCurrentLocation();
                          if (loc == null || !mounted) return;
                          setState(() {
                            _location = loc;
                            _locationLabel = null;
                          });
                        },
                        onMap: _pickLocationFromMap,
                        pinnedLocation: _location,
                      ),
                      LocationSuggestionsDropdown(
                        suggestions: _addressSuggestions,
                        isLoading: _searchingAddress,
                        accentColor: const Color(0xFF2563EB),
                        onSelect: _selectAddressSuggestion,
                        onDismiss: () => setState(() => _addressSuggestions = []),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // ── 7. Price Breakdown Card Layout ───────────────────────────
              ValueListenableBuilder<double>(
                valueListenable: _effectiveBudgetNotifier,
                builder: (_, budget, __) {
                  final isDelivery = _isDelivery;
                  final charge = isDelivery ? Task.serviceChargeForCategory(_selectedCategory).toDouble() : 0.0;
                  final posterFee = budget * 0.20;
                  final total = budget + charge + posterFee;
                  return TaskPriceBreakdownCard(
                    budget: budget,
                    serviceCharge: charge,
                    posterFee: posterFee,
                    totalCost: total,
                    isRepair: Task.isRepairCategory(_selectedCategory),
                    distanceKm: _calculatedDistanceKm,
                    category: _selectedCategory,
                    vehicle: _deliveryVehicle,
                  );
                },
              ),

              const SizedBox(height: 20),

              // ── Action Button ───────────────────────────────────────────
              GradientButton(
                label: 'Update Task',
                loading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Suffix widget for address text fields: GPS + Map picker buttons.
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
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            icon: Icon(Icons.my_location_rounded, size: 20, color: accentColor),
            tooltip: 'Use GPS',
            onPressed: onGps,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
          ),
        IconButton(
          icon: Icon(Icons.map_outlined, size: 20, color: accentColor),
          tooltip: 'Pick on map',
          onPressed: onMap,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
