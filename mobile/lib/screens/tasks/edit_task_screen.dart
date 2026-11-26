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

class EditTaskScreen extends StatefulWidget {
  final Task task;
  const EditTaskScreen({super.key, required this.task});

  @override
  State<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends State<EditTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _pickupAddrCtrl;
  late final TextEditingController _dropAddrCtrl;

  late final String _selectedCategory;
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

  static const _deliveryCats = {'delivery', 'pickup', 'transport', 'moving'};
  bool get _isDelivery => _deliveryCats.contains(_selectedCategory);

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleCtrl = TextEditingController(text: t.title);
    _selectedCategory = t.category;

    // Detect delivery vehicle from description or budget
    final desc = t.description.toLowerCase();
    if (desc.contains('rikshaw') || desc.contains('auto') || desc.contains('3 wheeler')) {
      _deliveryVehicle = 'rikshaw';
    } else {
      _deliveryVehicle = 'bike';
    }

    // Pre-fill location coordinates
    if (t.latitude != 0.0 && t.longitude != 0.0) {
      _location = LatLng(t.latitude, t.longitude);
      _locationLabel = t.address;
      if (_isDelivery) {
        _pickupLocation = _location;
      }
    }
    if (_isDelivery &&
        t.dropLatitude != null &&
        t.dropLongitude != null &&
        t.dropLatitude != 0.0 &&
        t.dropLongitude != 0.0) {
      _dropLocation = LatLng(t.dropLatitude!, t.dropLongitude!);
    }

    // Pre-fill address text fields using effective helper properties with fallback
    if (_isDelivery) {
      final pickup = t.effectivePickupAddress;
      final drop = t.effectiveDropAddress ?? '';
      _pickupAddrCtrl = TextEditingController(text: pickup);
      _dropAddrCtrl = TextEditingController(text: drop);
      _addressCtrl = TextEditingController();
    } else {
      _pickupAddrCtrl = TextEditingController();
      _dropAddrCtrl = TextEditingController();
      _addressCtrl = TextEditingController(text: t.address ?? '');
    }

    // Pre-fill distance directly from task or calculate immediately from coordinates
    if (t.distanceKm != null && t.distanceKm! > 0) {
      _calculatedDistanceKm = t.distanceKm;
    } else if (_pickupLocation != null && _dropLocation != null) {
      final meters = const Distance().distance(_pickupLocation!, _dropLocation!);
      _calculatedDistanceKm = (meters / 1000.0) * 1.25;
    }

    // Initialize effective budget notifier with exact task budget / distance fare
    _effectiveBudgetNotifier = ValueNotifier<double>(_computeEffectiveBudget());

    // Asynchronously refresh exact road distance via OSRM if delivery
    if (_isDelivery && _pickupLocation != null && _dropLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recalcDistance());
    }
  }

  @override
  void dispose() {
    _pickupDebounce?.cancel();
    _dropDebounce?.cancel();
    _addressDebounce?.cancel();
    _titleCtrl.dispose();
    _addressCtrl.dispose();
    _pickupAddrCtrl.dispose();
    _dropAddrCtrl.dispose();
    _effectiveBudgetNotifier.dispose();
    super.dispose();
  }

  double _computeEffectiveBudget() {
    final cat = Task.normalizeCategoryKey(_selectedCategory);
    if (_isDelivery || cat == 'moving') {
      if (_calculatedDistanceKm != null && _calculatedDistanceKm! > 0) {
        return Task.calculateDistancePrice(
          _calculatedDistanceKm!,
          _selectedCategory,
          vehicle: _deliveryVehicle,
        );
      }
      // If distance is not available yet, preserve the existing task budget
      if (widget.task.budget > 0) {
        return widget.task.budget;
      }
      return Task.minBudgetForCategory(_selectedCategory);
    }
    // For non-delivery tasks, always preserve the task budget from when it was posted
    if (widget.task.budget > 0) {
      return widget.task.budget;
    }
    return Task.minBudgetForCategory(_selectedCategory);
  }

  Future<void> _recalcDistance({bool force = false}) async {
    if (_pickupLocation != null && _dropLocation != null) {
      final seq = ++_distCalcSeq;
      // 1. Instant road estimate (aerial * 1.25 road factor) only if distance is unset or forced
      if (_calculatedDistanceKm == null || force) {
        final meters = const Distance().distance(
          _pickupLocation!,
          _dropLocation!,
        );
        final immediateKm = (meters / 1000.0) * 1.25;
        if (mounted) {
          setState(() => _calculatedDistanceKm = immediateKm);
          _effectiveBudgetNotifier.value = _computeEffectiveBudget();
        }
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
    _recalcDistance(force: true);
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
    _recalcDistance(force: true);
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
      _recalcDistance(force: true);
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
      _recalcDistance(force: true);
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
    _recalcDistance(force: true);
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
    _recalcDistance(force: true);
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
    final charge = widget.task.serviceCharge ??
        (_isDelivery ? Task.serviceChargeForCategory(_selectedCategory).toDouble() : 0.0);

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
      'description': widget.task.description,
      'category': _selectedCategory,
      'price': budget,
      'budget': budget,
      if (charge > 0) 'service_charge': charge,
      if (_isDelivery) 'vehicle': _deliveryVehicle,
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
              // ── 1. Task Title (Unified Card) ──────────────────────────
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

              // ── 2. Pickup and Drop Location with Distance ───────────────
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

              // ── 3. Price Breakdown Card Layout ───────────────────────────
              ValueListenableBuilder<double>(
                valueListenable: _effectiveBudgetNotifier,
                builder: (_, budget, __) {
                  final isDelivery = _isDelivery;
                  final charge = widget.task.serviceCharge ??
                      (isDelivery ? Task.serviceChargeForCategory(_selectedCategory).toDouble() : 0.0);
                  final isRepair = Task.isRepairCategory(_selectedCategory);
                  const posterFee = Task.posterPlatformFeeFlat;
                  final total = budget + charge + posterFee;
                  return TaskPriceBreakdownCard(
                    budget: budget,
                    serviceCharge: charge,
                    posterFee: posterFee,
                    totalCost: total,
                    isRepair: isRepair,
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
