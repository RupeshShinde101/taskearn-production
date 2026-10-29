import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../providers/task_provider.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import 'dart:async';
import '../../services/location_search_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/location_suggestions_dropdown.dart';
import '../../widgets/task_price_breakdown_card.dart';
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

  Future<void> _recalcDistance() async {
    if (_pickupLocation != null && _dropLocation != null) {
      final seq = ++_distCalcSeq;
      // 1. Instant road estimate (aerial * 1.25 road factor) for zero UI lag
      final meters = const Distance().distance(
        _pickupLocation!,
        _dropLocation!,
      );
      final immediateKm = (meters / 1000.0) * 1.25;
      final immediatePrice = Task.calculateDistancePrice(
        immediateKm,
        _selectedCategory,
        vehicle: _deliveryVehicle,
      );
      final current = double.tryParse(_budgetCtrl.text) ?? 0;
      if (current < immediatePrice) {
        _budgetCtrl.text = immediatePrice.toStringAsFixed(0);
      }
      if (mounted) setState(() => _calculatedDistanceKm = immediateKm);

      // 2. Fetch exact road driving route via OSRM (Google Maps parity)
      try {
        final roadKm = await LocationService.calculateRoadDistance(
          _pickupLocation!,
          _dropLocation!,
        );
        if (seq == _distCalcSeq && mounted) {
          final exactPrice = Task.calculateDistancePrice(
            roadKm,
            _selectedCategory,
            vehicle: _deliveryVehicle,
          );
          final currVal = double.tryParse(_budgetCtrl.text) ?? 0;
          if (currVal < exactPrice) {
            _budgetCtrl.text = exactPrice.toStringAsFixed(0);
          }
          setState(() => _calculatedDistanceKm = roadKm);
        }
      } catch (_) {}
    } else {
      if (mounted) setState(() => _calculatedDistanceKm = null);
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


  static const _deliveryCats = {'delivery', 'pickup', 'transport', 'moving'};
  bool get _isDelivery => _deliveryCats.contains(_selectedCategory);

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
    if (_isDelivery) {
      _pickupLocation = _location;
      if (t.dropLatitude != null && t.dropLongitude != null) {
        _dropLocation = LatLng(t.dropLatitude!, t.dropLongitude!);
      }
      final desc = t.description.toLowerCase();
      if (desc.contains('rikshaw') || desc.contains('auto')) {
        _deliveryVehicle = 'rikshaw';
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _recalcDistance());
    }
    _addressCtrl.addListener(_onLocationAreaChanged);
    _pickupAddrCtrl.addListener(_onLocationAreaChanged);
    _dropAddrCtrl.addListener(_onLocationAreaChanged);
  }

  @override
  void dispose() {
    _pickupDebounce?.cancel();
    _dropDebounce?.cancel();
    _addressDebounce?.cancel();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _addressCtrl.removeListener(_onLocationAreaChanged);
    _pickupAddrCtrl.removeListener(_onLocationAreaChanged);
    _dropAddrCtrl.removeListener(_onLocationAreaChanged);
    _addressCtrl.dispose();
    _pickupAddrCtrl.dispose();
    _dropAddrCtrl.dispose();
    super.dispose();
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
      _recalcDistance();
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
        const SnackBar(
            content: Text('Could not get GPS. Enable location permission.')),
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
        const SnackBar(
            content: Text('Could not get GPS. Enable location permission.')),
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

    final budget = double.tryParse(_budgetCtrl.text) ?? 0;
    if (_isDelivery) {
      if (_calculatedDistanceKm != null) {
        final distMin = Task.calculateDistancePrice(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle);
        if (budget < distMin) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Minimum budget for ${_calculatedDistanceKm!.toStringAsFixed(1)} km is ₹${distMin.toInt()}')),
          );
          return;
        }
      } else if (_selectedCategory != 'delivery') {
        final catMin = Task.minBudgetForCategory(_selectedCategory);
        if (catMin > 0 && budget < catMin) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Minimum budget for ${_selectedCategory.replaceAll('_', ' ')} is ₹${catMin.toInt()}')),
          );
          return;
        }
      }
    } else {
      final catMin = Task.minBudgetForCategory(_selectedCategory);
      if (budget < catMin) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Minimum budget for ${_selectedCategory.replaceAll('_', ' ')} is ₹${catMin.toInt()}')),
        );
        return;
      }
    }
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
      // Nest location as the backend update_task endpoint expects.
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

    void _onLocationAreaChanged() {
    if (mounted) setState(() {});
  }

  Widget _buildDeliveryVehicleSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.delivery_dining, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Delivery Vehicle Option',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.dark,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _deliveryVehicle == 'bike' ? '₹12 / km (Bike)' : '₹18 / km (Rikshaw)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildVehicleTile(
                  title: 'Bike',
                  rate: '₹12 / km',
                  desc: 'Small items / docs',
                  icon: Icons.two_wheeler_rounded,
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
                  title: 'Rikshaw',
                  rate: '₹18 / km',
                  desc: 'Auto / medium items',
                  icon: Icons.electric_rickshaw_rounded,
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
        ],
      ),
    );
  }

  Widget _buildVehicleTile({
    required String title,
    required String rate,
    required String desc,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.light,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: isSelected ? AppColors.primary : AppColors.gray),
                const Spacer(),
                if (isSelected)
                  const Icon(Icons.check_circle, size: 16, color: AppColors.primary),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isSelected ? AppColors.primary : AppColors.dark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              rate,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: isSelected ? AppColors.primary : AppColors.dark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: const TextStyle(fontSize: 11, color: AppColors.gray),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedBudgetCard() {
    final areaCandidate = _isDelivery
        ? (_dropAddrCtrl.text.trim().isNotEmpty
            ? _dropAddrCtrl.text.trim()
            : (_locationLabel ?? _pickupAddrCtrl.text.trim()))
        : (_addressCtrl.text.trim().isNotEmpty
            ? _addressCtrl.text.trim()
            : (_locationLabel ?? ''));

    final suggestion = Task.getBudgetSuggestion(
      _selectedCategory,
      areaText: areaCandidate,
      distanceKm: _calculatedDistanceKm,
      vehicle: _deliveryVehicle,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Suggested in ${suggestion.localityName}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1E293B)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  suggestion.localityTier,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF4338CA)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '₹${suggestion.suggestedBudget.toInt()}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF4338CA),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(Typical: ₹${suggestion.minBudget.toInt()}–₹${suggestion.maxBudget.toInt()})',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Average value users in this area pay for ${_selectedCategory.replaceAll('_', ' ')}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  _budgetCtrl.text = suggestion.suggestedBudget.toInt().toString();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: const Text('Apply', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
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
                onChanged: (c) {
                  setState(() => _selectedCategory = c);
                  _recalcDistance();
                },
              ),
              if (_selectedCategory == 'delivery') ...[
                const SizedBox(height: 14),
                _buildDeliveryVehicleSelector(),
              ],
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
              const SizedBox(height: 14),

              // Suggested budget card based on category + selected area
              _buildSuggestedBudgetCard(),

              // Budget
              TextFormField(
                controller: _budgetCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Budget (₹)',
                  hintText: _isDelivery
                      ? (_calculatedDistanceKm != null
                          ? 'Min ₹${Task.calculateDistancePrice(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle).toInt()} (${_calculatedDistanceKm!.toStringAsFixed(1)} km · ${Task.distancePriceDescription(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle)})'
                          : (_selectedCategory == 'delivery'
                              ? 'Enter budget (${_deliveryVehicle == 'bike' ? '₹12/km' : '₹18/km'})'
                              : 'Set locations to calculate (Min ₹${Task.minBudgetForCategory(_selectedCategory).toInt()})'))
                      : 'Minimum ₹${Task.minBudgetForCategory(_selectedCategory).toInt()}',
                  helperText: _isDelivery
                      ? (_selectedCategory == 'delivery'
                          ? (_calculatedDistanceKm != null
                              ? 'Rate: ${_deliveryVehicle == 'bike' ? '₹12/km (Bike)' : '₹18/km (Rikshaw)'} · Fare: ₹${Task.calculateDistancePrice(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle).toInt()} (${_calculatedDistanceKm!.toStringAsFixed(1)} km)'
                              : 'Rate: ${_deliveryVehicle == 'bike' ? '₹12/km (Bike)' : '₹18/km (Rikshaw)'}')
                          : (_calculatedDistanceKm != null
                              ? 'Rate: ${Task.distancePriceDescription(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle)} · Fare: ₹${Task.calculateDistancePrice(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle).toInt()} (${_calculatedDistanceKm!.toStringAsFixed(1)} km)'
                              : 'Rate: ${Task.distancePriceDescription(1.0, _selectedCategory, vehicle: _deliveryVehicle)}'))
                      : 'Market minimum for ${_selectedCategory.replaceAll('_', ' ')} is ₹${Task.minBudgetForCategory(_selectedCategory).toInt()}',
                  prefixIcon: const Icon(Icons.currency_rupee),
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Please enter a budget';
                  if (_isDelivery) {
                    if (_calculatedDistanceKm != null) {
                      final distMin = Task.calculateDistancePrice(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle);
                      if (n < distMin) {
                        return 'Minimum ₹${distMin.toInt()} for ${_calculatedDistanceKm!.toStringAsFixed(1)} km (${Task.distancePriceDescription(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle)})';
                      }
                    } else if (_selectedCategory != 'delivery') {
                      final catMin = Task.minBudgetForCategory(_selectedCategory);
                      if (catMin > 0 && n < catMin) {
                        return 'Minimum budget for ${_selectedCategory.replaceAll('_', ' ')} is ₹${catMin.toInt()}';
                      }
                    }
                  } else {
                    final catMin = Task.minBudgetForCategory(_selectedCategory);
                    if (n < catMin) {
                      return 'Minimum budget for ${_selectedCategory.replaceAll('_', ' ')} is ₹${catMin.toInt()}';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── Address fields (each with GPS + Map inline buttons) ──────
              if (_isDelivery) ...[
                // Pickup Address
                TextFormField(
                  controller: _pickupAddrCtrl,
                  onChanged: _onPickupAddrChanged,
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
                LocationSuggestionsDropdown(
                  suggestions: _pickupSuggestions,
                  isLoading: _searchingPickup,
                  accentColor: AppColors.primary,
                  onSelect: _selectPickupSuggestion,
                  onDismiss: () => setState(() => _pickupSuggestions = []),
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
                  onChanged: _onDropAddrChanged,
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
                LocationSuggestionsDropdown(
                  suggestions: _dropSuggestions,
                  isLoading: _searchingDrop,
                  accentColor: AppColors.danger,
                  onSelect: _selectDropSuggestion,
                  onDismiss: () => setState(() => _dropSuggestions = []),
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
                if (_calculatedDistanceKm != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.route,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Distance: ${_calculatedDistanceKm!.toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Calculated price: ₹${Task.calculateDistancePrice(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle).toInt()} (${Task.distancePriceDescription(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle)})',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.gray),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                // Single address for non-delivery tasks
                TextFormField(
                  controller: _addressCtrl,
                  onChanged: _onAddressChanged,
                  decoration: InputDecoration(
                    labelText: 'Address / Landmark (optional)',
                    hintText: 'Type locality, landmark or address',
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
                LocationSuggestionsDropdown(
                  suggestions: _addressSuggestions,
                  isLoading: _searchingAddress,
                  accentColor: AppColors.primary,
                  onSelect: _selectAddressSuggestion,
                  onDismiss: () => setState(() => _addressSuggestions = []),
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

              // Price breakdown (real-time via ValueListenableBuilder)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _budgetCtrl,
                builder: (_, value, __) {
                  final budget = double.tryParse(value.text) ?? 0;
                  final isDelivery = const {'delivery', 'pickup', 'transport', 'moving'}.contains(_selectedCategory);
                  final charge = isDelivery ? Task.serviceChargeForCategory(_selectedCategory).toDouble() : 0.0;
                  final posterFee = budget * 0.20;
                  final total = budget + charge + posterFee;
                  return TaskPriceBreakdownCard(
                    budget: budget,
                    serviceCharge: charge,
                    posterFee: posterFee,
                    totalCost: total,
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
    const cats = TaskCategory.all;
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
