import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../models/grocery_item.dart';
import '../../providers/task_provider.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import 'dart:async';
import '../../services/location_search_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/location_suggestions_dropdown.dart';
import '../../widgets/task_price_breakdown_card.dart';
import '../../widgets/map_location_picker.dart';
import 'grocery_item_picker_screen.dart';

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
  final _budgetFieldKey = GlobalKey<FormFieldState<String>>();
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
  String? _lastAutoBudgetText;
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

  // Grocery task state
  List<SelectedGroceryItem> _selectedGroceryItems = [];
  String? _selectedGroceryStoreName;
  bool _isStoreDropdownOpen = false;
  bool _showCustomStoreInput = false;
  final TextEditingController _customStoreCtrl = TextEditingController();
  final TextEditingController _storeSearchCtrl = TextEditingController();
  Timer? _storeSearchDebounce;
  List<Map<String, dynamic>> _storeSearchResults = [];
  bool _searchingStoresByName = false;
  bool _hasFetchedNearbyStores = false;
  bool _isOpeningGroceryPicker = false;
  int _storeFetchSeq = 0;
  bool _loadingNearbyStores = false;
  bool _userPickedStoreManually = false;
  List<Map<String, dynamic>> _suggestedGroceryStoresList = [];

  void _syncAutoBudget(double fare) {
    final formatted = fare.toStringAsFixed(0);
    _budgetCtrl.text = formatted;
    _lastAutoBudgetText = formatted;
    _budgetFieldKey.currentState?.validate();
  }

  Future<void> _recalcDistance() async {
    if (!_isDelivery) {
      if (_calculatedDistanceKm != null && mounted) {
        setState(() => _calculatedDistanceKm = null);
      }
      return;
    }
    if (_pickupLocation != null && _dropLocation != null) {
      final seq = ++_distCalcSeq;
      // 1. Instant road estimate (aerial * 1.25 road factor) for zero UI lag
      final meters = const Distance().distance(
        _pickupLocation!,
        _dropLocation!,
      );
      final immediateKm = double.parse(((meters / 1000.0) * 1.25).toStringAsFixed(1));
      final isGrocery = _isGrocery;
      final groceryHandling = isGrocery ? 30.0 : 0.0;
      final immediatePrice = Task.calculateDistancePrice(
        immediateKm,
        _selectedCategory,
        vehicle: _deliveryVehicle,
      ) + groceryHandling;
      final current = double.tryParse(_budgetCtrl.text) ?? 0;
      if (isGrocery || current < immediatePrice || (_lastAutoBudgetText != null && _budgetCtrl.text.trim() == _lastAutoBudgetText)) {
        _syncAutoBudget(immediatePrice);
      }
      if (mounted) setState(() => _calculatedDistanceKm = immediateKm);

      // 2. Fetch exact road driving route via OSRM (Google Maps parity)
      try {
        final roadKmRaw = await LocationService.calculateRoadDistance(
          _pickupLocation!,
          _dropLocation!,
        );
        final roadKm = double.parse(roadKmRaw.toStringAsFixed(1));
        if (seq == _distCalcSeq && mounted) {
          final exactPrice = Task.calculateDistancePrice(
            roadKm,
            _selectedCategory,
            vehicle: _deliveryVehicle,
          ) + groceryHandling;
          final currVal = double.tryParse(_budgetCtrl.text) ?? 0;
          if (isGrocery || currVal < exactPrice || (_lastAutoBudgetText != null && _budgetCtrl.text.trim() == _lastAutoBudgetText)) {
            _syncAutoBudget(exactPrice);
          }
          setState(() {
            _calculatedDistanceKm = roadKm;
            if (isGrocery && _selectedGroceryStoreName != null) {
              for (final s in _suggestedGroceryStoresList) {
                if (s['name'] == _selectedGroceryStoreName) {
                  s['distanceKm'] = roadKm;
                  break;
                }
              }
            }
          });
        }
      } catch (_) {}
    } else {
      if (!_isGrocery && mounted) setState(() => _calculatedDistanceKm = null);
    }
  }

  // ── Location Autocomplete Handlers ──────────────────────────────────────
  void _onPickupAddrChanged(String text) {
    _pickupDebounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      if (q.isEmpty && (_pickupLocation != null || _calculatedDistanceKm != null)) {
        setState(() {
          _pickupLocation = null;
          _calculatedDistanceKm = null;
          _pickupSuggestions = [];
          _searchingPickup = false;
        });
      }
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
      if (q.isEmpty && (_dropLocation != null || _calculatedDistanceKm != null)) {
        setState(() {
          _dropLocation = null;
          _calculatedDistanceKm = null;
          _dropSuggestions = [];
          _searchingDrop = false;
        });
      }
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

  String _currentAreaCandidate() {
    if (_isDelivery) {
      return [
        _dropAddrCtrl.text.trim(),
        _pickupAddrCtrl.text.trim(),
        (_locationLabel ?? '').trim(),
      ].where((s) => s.isNotEmpty).join(', ');
    }
    return [
      _addressCtrl.text.trim(),
      (_locationLabel ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(', ');
  }

  void _syncAreaBudgetIfAuto() {
    final wasAutoOrEmpty = _budgetCtrl.text.trim().isEmpty ||
        (_lastAutoBudgetText != null && _budgetCtrl.text.trim() == _lastAutoBudgetText);
    if (!wasAutoOrEmpty || _isDelivery) return;
    if (Task.isRepairCategory(_selectedCategory)) {
      _syncAutoBudget(Task.fixedVisitPriceForRepairCategory(_selectedCategory));
      return;
    }
    final suggestion = Task.getBudgetSuggestion(
      _selectedCategory,
      areaText: _isFreelancer ? null : _currentAreaCandidate(),
      vehicle: _deliveryVehicle,
      title: _titleCtrl.text,
      description: _descCtrl.text,
    );
    _syncAutoBudget(suggestion.suggestedBudget);
  }

  void _selectAddressSuggestion(LocationSearchResult s) {
    _addressCtrl.text = s.fullAddress;
    _location = s.toLatLng();
    _locationLabel = s.fullAddress;
    _addressSuggestions = [];
    _searchingAddress = false;
    _syncAreaBudgetIfAuto();
    FocusScope.of(context).unfocus();
    setState(() {});
  }


  static const _deliveryCats = {'delivery', 'pickup', 'transport', 'moving', 'groceries', 'grocery'};
  bool get _isDelivery => _deliveryCats.contains(_selectedCategory);
  bool get _isGrocery => Task.isGroceryCategory(_selectedCategory);
  bool get _isFreelancer => Task.isFreelancerCategory(_selectedCategory);

  void _onFreelancerDetailsChanged() {
    if (!mounted || !_isFreelancer) return;
    _syncAreaBudgetIfAuto();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleCtrl      = TextEditingController(text: t.title);
    _descCtrl       = TextEditingController(text: t.description);
    _selectedCategory = t.category;
    final initialBudget = Task.isRepairCategory(_selectedCategory)
        ? Task.fixedVisitPriceForRepairCategory(_selectedCategory).toStringAsFixed(0)
        : t.budget.toStringAsFixed(0);
    _budgetCtrl     = TextEditingController(text: initialBudget);

    _suggestedGroceryStoresList = [];
    if (_isGrocery) {
      _selectedGroceryItems = (t.groceryItems != null && t.groceryItems!.isNotEmpty)
          ? List<SelectedGroceryItem>.from(t.groceryItems!)
          : GroceryCatalog.parseGroceryItems(null, t.description);
    }

    // Pre-fill address fields
    if (_isGrocery) {
      final pickupText = t.effectivePickupAddress;
      final dropText = t.effectiveDropAddress ?? '';
      _pickupAddrCtrl = TextEditingController(text: pickupText);
      _dropAddrCtrl   = TextEditingController(text: dropText);
      _addressCtrl    = TextEditingController();
      if (pickupText.isNotEmpty) {
        _selectedGroceryStoreName = pickupText.split(',').first.trim();
        _userPickedStoreManually = true;
      }
    } else if (_isDelivery && t.address != null) {
      final addr = t.address!;
      // Try to split "Pickup: X\nDrop: Y" format
      final pickupMatch = RegExp(r'Pickup:\s*(.+?)(?:\n|$)', dotAll: true).firstMatch(addr);
      final dropMatch   = RegExp(r'Drop:\s*(.+?)(?:\n|$)', dotAll: true).firstMatch(addr);
      _pickupAddrCtrl = TextEditingController(text: pickupMatch?.group(1)?.trim() ?? t.effectivePickupAddress);
      _dropAddrCtrl   = TextEditingController(text: dropMatch?.group(1)?.trim() ?? (t.effectiveDropAddress ?? ''));
      _addressCtrl    = TextEditingController();
    } else {
      _pickupAddrCtrl = TextEditingController();
      _dropAddrCtrl   = TextEditingController();
      _addressCtrl    = TextEditingController(text: t.address ?? '');
    }

    _location = (t.latitude == 0 && t.longitude == 0) ? null : LatLng(t.latitude, t.longitude);
    _locationLabel = t.address;
    if (_isDelivery) {
      _pickupLocation = _location;
      if (t.dropLatitude != null && t.dropLongitude != null && (t.dropLatitude != 0 || t.dropLongitude != 0)) {
        _dropLocation = LatLng(t.dropLatitude!, t.dropLongitude!);
      }
      final desc = t.description.toLowerCase();
      if (!_isGrocery && (desc.contains('rikshaw') || desc.contains('auto'))) {
        _deliveryVehicle = 'rikshaw';
      }
      if (_isGrocery) {
        _deliveryVehicle = 'bike';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_dropLocation != null || _dropAddrCtrl.text.trim().isNotEmpty) {
            _updateSuggestedStoresForDrop(_dropAddrCtrl.text.trim(), _dropLocation);
          }
          _recalcDistance();
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _recalcDistance());
      }
    }
    _titleCtrl.addListener(_onFreelancerDetailsChanged);
    _descCtrl.addListener(_onFreelancerDetailsChanged);
    _addressCtrl.addListener(_onLocationAreaChanged);
    _pickupAddrCtrl.addListener(_onLocationAreaChanged);
    _dropAddrCtrl.addListener(_onLocationAreaChanged);
  }

  @override
  void dispose() {
    _pickupDebounce?.cancel();
    _dropDebounce?.cancel();
    _addressDebounce?.cancel();
    _storeSearchDebounce?.cancel();
    _titleCtrl.removeListener(_onFreelancerDetailsChanged);
    _descCtrl.removeListener(_onFreelancerDetailsChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _customStoreCtrl.dispose();
    _storeSearchCtrl.dispose();
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

  String _compileGroceryDescription() {
    final lines = <String>[];
    final totalWeight = GroceryCatalog.calculateTotalWeightKg(_selectedGroceryItems);
    lines.add('• Vehicle: Bike / Scooty (Max Weight: 20kg, Cart: ${totalWeight.toStringAsFixed(1)}kg)');
    if (_selectedGroceryStoreName != null && _selectedGroceryStoreName!.trim().isNotEmpty) {
      lines.add('• Store / Supermarket: ${_selectedGroceryStoreName!.trim()}');
    }
    lines.add('• Handling & Shopping Charge: ₹30 included in delivery budget');
    lines.add('• Grocery Items Cost: Paid separately by task poster on actual bill (excluded from delivery budget)');
    if (_selectedGroceryItems.isNotEmpty) {
      lines.add('• Selected Grocery Items (${_selectedGroceryItems.length} items):');
      for (final item in _selectedGroceryItems) {
        lines.add('  - ${item.formattedDescription}');
      }
      lines.add(GroceryCatalog.encodeGroceryItemsJson(_selectedGroceryItems));
    }
    return lines.join('\n');
  }

  Future<void> _openGroceryItemPicker() async {
    if (_isOpeningGroceryPicker || !mounted) return;
    _isOpeningGroceryPicker = true;
    try {
      final result = await Navigator.of(context).push<List<SelectedGroceryItem>>(
        MaterialPageRoute(
          builder: (_) => GroceryItemPickerScreen(
            initialSelected: _selectedGroceryItems,
          ),
        ),
      );
      if (result != null && mounted) {
        setState(() {
          _selectedGroceryItems = result;
        });
      }
    } finally {
      _isOpeningGroceryPicker = false;
    }
  }

  String _extractAreaName(String dropAddr) {
    if (dropAddr.trim().isEmpty) return 'Nearby Area';
    final parts = dropAddr.split(',');
    var area = parts.first.trim();
    if (area.length > 25 && parts.length > 1) {
      area = parts[1].trim();
    }
    return area.isEmpty ? 'Nearby Area' : area;
  }

  void _updateSuggestedStoresForDrop(String dropAddr, LatLng? dropLoc) {
    final area = _extractAreaName(dropAddr);
    if (dropLoc == null) {
      if (mounted) {
        setState(() {
          _loadingNearbyStores = false;
          _hasFetchedNearbyStores = false;
          if (!_userPickedStoreManually) {
            _suggestedGroceryStoresList = [];
            _selectedGroceryStoreName = null;
          }
        });
      }
      return;
    }

    final seq = ++_storeFetchSeq;
    if (mounted) {
      setState(() {
        _loadingNearbyStores = true;
        _storeSearchResults = [];
        _storeSearchCtrl.clear();
        if (!_userPickedStoreManually) {
          _suggestedGroceryStoresList = [];
          _selectedGroceryStoreName = null;
        }
      });
    }

    LocationSearchService.searchNearbyGroceryStores(
      dropLoc,
      radiusKm: 10.0,
      areaFallback: area,
    ).then((realStores) {
      if (!mounted || seq != _storeFetchSeq) return;
      setState(() {
        _loadingNearbyStores = false;
        _hasFetchedNearbyStores = true;
        _suggestedGroceryStoresList = realStores;
        if (realStores.isNotEmpty &&
            (!_userPickedStoreManually ||
                _selectedGroceryStoreName == null ||
                _selectedGroceryStoreName!.trim().isEmpty)) {
          final chosen = realStores.first;
          _selectedGroceryStoreName = chosen['name'] as String;
          _pickupAddrCtrl.text = '${chosen['name']}, ${chosen['address']}';
          _calculatedDistanceKm = (chosen['distanceKm'] as num).toDouble();
          _pickupLocation = LatLng(chosen['lat'] as double, chosen['lng'] as double);
          _syncAutoBudget(Task.calculateDistancePrice(_calculatedDistanceKm ?? 1.0, 'groceries') + 30.0);
        }
      });
      if (realStores.isNotEmpty && !_userPickedStoreManually) {
        _recalcDistance();
      }
    }).catchError((_) {
      if (mounted && seq == _storeFetchSeq) {
        setState(() {
          _loadingNearbyStores = false;
          _hasFetchedNearbyStores = true;
        });
      }
    });
  }

  void _onStoreSearchChanged(String raw) {
    _storeSearchDebounce?.cancel();
    final q = raw.trim();
    if (q.length < 2) {
      if (_storeSearchResults.isNotEmpty || _searchingStoresByName) {
        setState(() {
          _storeSearchResults = [];
          _searchingStoresByName = false;
        });
      }
      return;
    }
    final center = _dropLocation ?? _location;
    if (center == null) return;

    setState(() => _searchingStoresByName = true);
    _storeSearchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final area = _extractAreaName(_dropAddrCtrl.text);
      final matches = await LocationSearchService.searchStoresByName(
        q,
        center,
        radiusKm: 10.0,
        areaFallback: area,
      );
      if (!mounted) return;
      if (_storeSearchCtrl.text.trim() != q) return;
      setState(() {
        _storeSearchResults = matches;
        _searchingStoresByName = false;
      });
    });
  }

  Future<void> _pickStoreFromGoogleMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(
          initialLocation: _pickupLocation ?? _dropLocation ?? _location,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      final picked = result['location'] as LatLng?;
      final addr = (result['address'] as String?)?.trim() ?? '';
      if (picked == null) return;
      String storeName = addr.split(',').first.trim();
      if (storeName.isEmpty) storeName = 'Selected Grocery Store';
      double distKm = 1.5;
      if (_dropLocation != null) {
        final m = Geolocator.distanceBetween(
          picked.latitude,
          picked.longitude,
          _dropLocation!.latitude,
          _dropLocation!.longitude,
        );
        distKm = double.parse(((m / 1000.0) * 1.25).clamp(0.2, 50.0).toStringAsFixed(1));
      }
      final customStore = {
        'name': storeName,
        'tag': 'Selected on Map',
        'distanceKm': distKm,
        'address': addr.isNotEmpty ? addr : 'Selected Map Location',
        'icon': Icons.pin_drop_rounded,
        'color': const Color(0xFF16A34A),
        'lat': picked.latitude,
        'lng': picked.longitude,
      };
      setState(() {
        _userPickedStoreManually = true;
        _pickupLocation = picked;
        _location ??= picked;
        _pickupAddrCtrl.text = addr.isNotEmpty ? '$storeName, $addr' : storeName;
        _selectedGroceryStoreName = storeName;
        _calculatedDistanceKm = distKm;
        _suggestedGroceryStoresList.removeWhere((s) => s['name'] == storeName);
        _suggestedGroceryStoresList.insert(0, customStore);
        _isStoreDropdownOpen = false;
      });
      _syncAutoBudget(Task.calculateDistancePrice(distKm, 'groceries') + 30.0);
      _recalcDistance();
    }
  }

  void _selectGroceryStore(Map<String, dynamic> store) {
    final dist = (store['distanceKm'] as num).toDouble();
    setState(() {
      _userPickedStoreManually = true;
      _selectedGroceryStoreName = store['name'] as String;
      _calculatedDistanceKm = dist;
      _pickupAddrCtrl.text = '${store['name']}, ${store['address']}';
      if (store['lat'] != null && store['lng'] != null) {
        _pickupLocation = LatLng(store['lat'] as double, store['lng'] as double);
        _location ??= _pickupLocation;
      }
      _isStoreDropdownOpen = false;
    });
    _syncAutoBudget(Task.calculateDistancePrice(dist, 'groceries') + 30.0);
    if (_dropLocation != null && _pickupLocation != null) {
      _recalcDistance();
    }
  }

  Future<void> _setCustomGroceryStore(String storeName) async {
    final trimmed = storeName.trim();
    if (trimmed.isEmpty) return;

    final center = _dropLocation ?? _location;
    if (center != null) {
      final matches = await LocationSearchService.searchStoresByName(
        trimmed,
        center,
        radiusKm: 10.0,
        areaFallback: _extractAreaName(_dropAddrCtrl.text),
      );
      if (mounted && matches.isNotEmpty) {
        final best = matches.first;
        if (!_suggestedGroceryStoresList.any((s) => s['name'] == best['name'])) {
          _suggestedGroceryStoresList.insert(0, best);
        }
        _selectGroceryStore(best);
        setState(() => _showCustomStoreInput = false);
        return;
      }
    }

    if (!mounted) return;
    const dist = 2.0;
    setState(() {
      _userPickedStoreManually = true;
      _selectedGroceryStoreName = trimmed;
      _calculatedDistanceKm = dist;
      _pickupAddrCtrl.text = trimmed;
      _pickupLocation = null;
      _isStoreDropdownOpen = false;
      _showCustomStoreInput = false;
    });
    _syncAutoBudget(Task.calculateDistancePrice(dist, 'groceries') + 30.0);
  }

  Future<void> _submit() async {
    if (_isGrocery) {
      if (_selectedGroceryItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select at least 1 grocery item'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      final totalW = GroceryCatalog.calculateTotalWeightKg(_selectedGroceryItems);
      if (totalW > GroceryCatalog.maxTwoWheelerWeightKg) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Total grocery weight (${totalW.toStringAsFixed(1)} kg) exceeds 20 kg two-wheeler limit.'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      final dist = _calculatedDistanceKm ?? 0.8;
      _syncAutoBudget(Task.calculateDistancePrice(dist, 'groceries') + 30.0);
      _descCtrl.text = _compileGroceryDescription();
    }

    if (!_formKey.currentState!.validate()) return;
    if (!_isFreelancer && !_isGrocery && _location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set a location on the map')),
      );
      return;
    }

    final isRepair = Task.isRepairCategory(_selectedCategory);
    final budget = isRepair
        ? Task.fixedVisitPriceForRepairCategory(_selectedCategory)
        : (double.tryParse(_budgetCtrl.text) ?? 0);
    if (!_isGrocery && !isRepair) {
      if (_isDelivery) {
        if (_calculatedDistanceKm != null) {
          final distMin = Task.calculateDistancePrice(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle);
          if (budget < distMin) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Minimum budget for ${_calculatedDistanceKm!.toStringAsFixed(1)} km is ₹${distMin.toInt()}')),
            );
            return;
          }
        } else {
          final catMin = Task.minBudgetForCategory(_selectedCategory, vehicle: _deliveryVehicle);
          if (catMin > 0 && budget < catMin) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Minimum budget for ${_selectedCategory.replaceAll('_', ' ')} is ₹${catMin.toInt()}')),
            );
            return;
          }
        }
      } else {
        final catMin = Task.minBudgetForCategory(_selectedCategory, vehicle: _deliveryVehicle);
        if (budget < catMin) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Minimum budget for ${_selectedCategory.replaceAll('_', ' ')} is ₹${catMin.toInt()}')),
          );
          return;
        }
      }
    }
    final isDeliveryChargeCat = const {'delivery', 'pickup', 'transport', 'moving'}.contains(_selectedCategory);
    final charge = isDeliveryChargeCat ? Task.serviceChargeForCategory(_selectedCategory).toDouble() : 0.0;

    final String? combinedAddress;
    if (_isFreelancer) {
      combinedAddress = 'Remote / Online';
    } else if (_isGrocery) {
      final pickup = _pickupAddrCtrl.text.trim();
      final drop = _dropAddrCtrl.text.trim();
      combinedAddress = pickup.isNotEmpty ? pickup : (drop.isNotEmpty ? drop : _locationLabel);
    } else if (_isDelivery) {
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

    final effectiveLoc = _isFreelancer
        ? null
        : (_isDelivery ? (_pickupLocation ?? _dropLocation ?? _location) : _location);

    final data = {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'category': _selectedCategory,
      'price': budget,
      'budget': budget,
      'service_charge': charge,
      'serviceCharge': charge,
      'location': {
        'lat': effectiveLoc?.latitude,
        'lng': effectiveLoc?.longitude,
        'address': combinedAddress ?? '',
      },
      if (_isFreelancer) 'is_remote': true,
      if (_isGrocery) ...{
        'grocery_items': _selectedGroceryItems.map((e) => e.toCompactJson()).toList(),
        'vehicle': 'bike',
      },
      if (_isDelivery) ...{
        if (_pickupAddrCtrl.text.trim().isNotEmpty) 'pickup_address': _pickupAddrCtrl.text.trim(),
        if (!_isGrocery) 'vehicle': _selectedCategory == 'delivery' ? _deliveryVehicle : 'auto',
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
    if (!_isDelivery) {
      _syncAreaBudgetIfAuto();
    }
    if (mounted) setState(() {});
  }

  Widget _buildDistanceCategoryRateBanner() {
    final isMoving = _selectedCategory == 'moving';
    final isPickup = _selectedCategory == 'pickup';
    final title = isMoving
        ? 'Moving & Packing Rate'
        : (isPickup ? 'Pick & Drop Rate' : 'Transport Rate');
    final rateBadge = isMoving
        ? '₹400 base + ₹35 / km'
        : (isPickup ? 'Min ₹30 · ₹18 / km' : 'Min ₹50 · ₹18 / km');
    final icon = isMoving
        ? Icons.local_shipping_rounded
        : (isPickup
            ? Icons.electric_rickshaw_rounded
            : Icons.directions_car_rounded);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.dark,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        rateBadge,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Distance fare is included in your budget (₹0 extra service charge)',
                  style: TextStyle(fontSize: 11, color: AppColors.gray),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
                      WidgetsBinding.instance.addPostFrameCallback((_) { if (_budgetCtrl.text.trim().isNotEmpty) _budgetFieldKey.currentState?.validate(); });
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
                      WidgetsBinding.instance.addPostFrameCallback((_) { if (_budgetCtrl.text.trim().isNotEmpty) _budgetFieldKey.currentState?.validate(); });
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

    bool get _isLocationSet {
    if (_isDelivery) {
      if (_calculatedDistanceKm != null && _calculatedDistanceKm! > 0) {
        return true;
      }
      final hasPickup = _pickupLocation != null ||
          _pickupAddrCtrl.text.trim().isNotEmpty;
      final hasDrop = _dropLocation != null ||
          _dropAddrCtrl.text.trim().isNotEmpty;
      return hasPickup && hasDrop;
    } else {
      return _location != null ||
          (_locationLabel != null && _locationLabel!.trim().isNotEmpty) ||
          _addressCtrl.text.trim().isNotEmpty;
    }
  }

  Widget _buildSuggestedBudgetCard() {
    if (_isGrocery || Task.isRepairCategory(_selectedCategory)) return const SizedBox.shrink();
    if (!_isLocationSet && !_isFreelancer) return const SizedBox.shrink();
    final areaCandidate = _currentAreaCandidate();

    final suggestion = Task.getBudgetSuggestion(
      _selectedCategory,
      areaText: _isFreelancer ? null : areaCandidate,
      distanceKm: _calculatedDistanceKm,
      vehicle: _deliveryVehicle,
      title: _titleCtrl.text,
      description: _descCtrl.text,
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
                  _isFreelancer
                      ? 'Suggested by ${suggestion.localityName}'
                      : 'Suggested in ${suggestion.localityName}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF1E293B)),
                ),
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E7FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    suggestion.localityTier,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF4338CA)),
                    overflow: TextOverflow.ellipsis,
                  ),
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
                      _isFreelancer
                          ? 'Based on task details for ${_selectedCategory.replaceAll('_', ' ')} (no location needed)'
                          : 'Average value users in this area pay for ${_selectedCategory.replaceAll('_', ' ')}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final suggestedText = suggestion.suggestedBudget.toInt().toString();
                  _budgetCtrl.text = suggestedText;
                  _lastAutoBudgetText = suggestedText;
                  _budgetFieldKey.currentState?.validate();
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

  Widget _buildRepairVisitingFeeCard() {
    final visitPrice = Task.fixedVisitPriceForRepairCategory(_selectedCategory).toInt();
    final visitTitle = Task.repairVisitTitle(_selectedCategory);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A56).withValues(alpha: 0.04),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.handyman_rounded,
                  color: Color(0xFF4F46E5),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      visitTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFC7D2FE)),
                ),
                child: Text(
                  '₹$visitPrice',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4338CA),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Flat ₹20 platform fee incl. GST (no 20% commission on repairs).',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Spare parts & major labor are quoted after inspection and paid directly to technician.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5EDF7), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A56).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF102A56),
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildGroceryItemsBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: const Icon(Icons.shopping_basket_rounded, color: Color(0xFF16A34A), size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grocery Items Policy',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF15803D),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Cost of grocery items is paid separately by the task poster directly to the helper/store and is NOT included in this delivery budget value.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF166534),
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroceryItemsSection() {
    final hasItems = _selectedGroceryItems.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.shopping_basket_rounded,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          title: 'Grocery Items',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: hasItems ? const Color(0xFFDCFCE7) : const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              hasItems ? '${_selectedGroceryItems.length} Added' : 'Required',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: hasItems ? const Color(0xFF166534) : const Color(0xFF2563EB),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!hasItems) ...[
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _openGroceryItemPicker,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.playlist_add_rounded, size: 20),
              label: const Text(
                'Select Items from Catalog',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ] else ...[
          // One card per row with ALL its info
          ..._selectedGroceryItems.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            final pkg = item.package.trim();
            final qty = item.qty.trim();
            final kg = item.kg.trim();
            final gram = item.gram.trim();
            final litr = item.litr.trim();
            final brand = item.brand.trim();
            final rupee = item.rupee.trim();

            final tags = <Widget>[
              if (pkg.isNotEmpty) _groceryTag(pkg, const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
              if (qty.isNotEmpty) _groceryTag('Qty: $qty', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
              if (kg.isNotEmpty) _groceryTag('$kg kg', const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
              if (gram.isNotEmpty) _groceryTag('$gram g', const Color(0xFFF0FDF4), const Color(0xFF15803D)),
              if (litr.isNotEmpty) _groceryTag('$litr L', const Color(0xFFE0F2FE), const Color(0xFF0284C7)),
              if (brand.isNotEmpty) _groceryTag('Brand: $brand', const Color(0xFFFAF5FF), const Color(0xFF9333EA)),
              if (rupee.isNotEmpty) _groceryTag('Est. ₹$rupee', const Color(0xFFFFFBEB), const Color(0xFFD97706)),
            ];

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF102A56).withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: item.imageUrl.isNotEmpty
                          ? Image.network(
                              item.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(item.emoji, style: const TextStyle(fontSize: 24)),
                              ),
                            )
                          : Center(
                              child: Text(item.emoji, style: const TextStyle(fontSize: 24)),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFF102A56),
                          ),
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.category.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.category.trim(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 4, children: tags),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 19, color: Color(0xFF2563EB)),
                        onPressed: _openGroceryItemPicker,
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(height: 6),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Color(0xFFDC2626)),
                        onPressed: () {
                          setState(() => _selectedGroceryItems.removeAt(idx));
                        },
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _openGroceryItemPicker,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF2563EB),
                side: const BorderSide(color: Color(0xFFBFDBFE), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Add More / Edit Grocery Items',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _groceryTag(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textCol.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: textCol),
      ),
    );
  }

  Widget _buildGroceryLocationSection() {
    if (_selectedGroceryStoreName == null && _suggestedGroceryStoresList.isNotEmpty) {
      _selectedGroceryStoreName = _suggestedGroceryStoresList.first['name'] as String;
    }

    final hasSelectedStore = _selectedGroceryStoreName != null &&
        _selectedGroceryStoreName!.trim().isNotEmpty;

    final currentStore = _suggestedGroceryStoresList.firstWhere(
      (s) => s['name'] == _selectedGroceryStoreName,
      orElse: () => {
        'name': hasSelectedStore
            ? _selectedGroceryStoreName!
            : (_dropLocation == null
                ? 'Set Delivery Address first'
                : (_loadingNearbyStores
                    ? 'Finding real stores within 10 km...'
                    : 'Search or Pick a Store')),
        'tag': 'Grocery Store',
        'distanceKm': _calculatedDistanceKm ?? 0.0,
        'address': hasSelectedStore
            ? (_pickupAddrCtrl.text.trim().isNotEmpty
                ? _pickupAddrCtrl.text.trim()
                : 'Selected Store')
            : (_dropLocation == null
                ? 'Real nearby stores load automatically once you set Delivery Address'
                : (_loadingNearbyStores
                    ? 'Fetching verified map stores near your delivery location'
                    : 'Tap Select to search by store name or pick on map')),
        'icon': Icons.storefront_rounded,
        'color': const Color(0xFF2563EB),
      },
    );

    final dist = (_calculatedDistanceKm ?? (currentStore['distanceKm'] as num).toDouble());
    final isSearchingQuery = _storeSearchCtrl.text.trim().length >= 2;
    final displayedStores = isSearchingQuery ? _storeSearchResults : _suggestedGroceryStoresList;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Separate Delivery Address Header
        _buildSectionHeader(
          icon: Icons.home_rounded,
          iconColor: AppColors.danger,
          iconBg: const Color(0xFFFEE2E2),
          title: 'Delivery Address',
        ),
        const SizedBox(height: 12),

        TextFormField(
          controller: _dropAddrCtrl,
          onChanged: _onDropAddrChanged,
          decoration: InputDecoration(
            labelText: 'Delivery Address *',
            prefixIcon: const Icon(Icons.home_rounded, color: AppColors.danger),
            suffixIcon: _AddressActionButtons(
              isLoading: _gettingDropGps,
              accentColor: AppColors.danger,
              onGps: () async {
                await _getGpsForDrop();
                if (mounted && _dropAddrCtrl.text.isNotEmpty) {
                  _userPickedStoreManually = false;
                  _updateSuggestedStoresForDrop(_dropAddrCtrl.text, _dropLocation);
                }
              },
              onMap: () async {
                await _pickMapForDrop();
                if (mounted && _dropAddrCtrl.text.isNotEmpty) {
                  _userPickedStoreManually = false;
                  _updateSuggestedStoresForDrop(_dropAddrCtrl.text, _dropLocation);
                }
              },
            ),
            suffixIconConstraints: const BoxConstraints(maxHeight: 48),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Delivery address is required' : null,
        ),
        LocationSuggestionsDropdown(
          suggestions: _dropSuggestions,
          isLoading: _searchingDrop,
          accentColor: AppColors.danger,
          onSelect: (s) {
            _selectDropSuggestion(s);
            _userPickedStoreManually = false;
            _updateSuggestedStoresForDrop(s.fullAddress, s.toLatLng());
          },
          onDismiss: () => setState(() => _dropSuggestions = []),
        ),

        const SizedBox(height: 18),

        // 2. Separate Store Address Header
        _buildSectionHeader(
          icon: Icons.storefront_rounded,
          iconColor: const Color(0xFF15803D),
          iconBg: const Color(0xFFDCFCE7),
          title: 'Store Address',
          trailing: _loadingNearbyStores
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF15803D)),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: const Text(
                    '10 km Radius',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                  ),
                ),
        ),
        const SizedBox(height: 12),

        // Store Selection Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5EDF7), width: 1.2),
          ),
          child: !_isStoreDropdownOpen
              ? Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2563EB), width: 1.4),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: (currentStore['color'] as Color? ?? const Color(0xFF2563EB)).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          currentStore['icon'] as IconData? ?? Icons.storefront_rounded,
                          size: 22,
                          color: currentStore['color'] as Color? ?? const Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentStore['name'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Color(0xFF102A56),
                              ),
                              maxLines: 2,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (hasSelectedStore && dist > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${dist.toStringAsFixed(1)} km',
                                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                                    ),
                                  ),
                                Text(
                                  currentStore['address'] as String? ?? 'Store Address',
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                  maxLines: 2,
                                  softWrap: true,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _isStoreDropdownOpen = true),
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size.zero,
                            foregroundColor: const Color(0xFF2563EB),
                            side: const BorderSide(color: Color(0xFF93C5FD)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
                          label: Text(
                            hasSelectedStore ? 'Change' : 'Select',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Nearby Stores (10 km Radius)',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF102A56)),
                          ),
                        ),
                        if (_dropLocation != null && !_loadingNearbyStores)
                          IconButton(
                            onPressed: () => _updateSuggestedStoresForDrop(_dropAddrCtrl.text, _dropLocation),
                            tooltip: 'Refresh nearby stores',
                            icon: const Icon(Icons.refresh_rounded, size: 19, color: Color(0xFF2563EB)),
                            padding: const EdgeInsets.only(right: 6),
                            constraints: const BoxConstraints(),
                          ),
                        IconButton(
                          onPressed: () => setState(() => _isStoreDropdownOpen = false),
                          icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _storeSearchCtrl,
                      onChanged: _onStoreSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search real store (DMart, Reliance, Kirana...)',
                        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF2563EB)),
                        suffixIcon: _searchingStoresByName
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : (_storeSearchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF64748B)),
                                    onPressed: () {
                                      _storeSearchCtrl.clear();
                                      setState(() {
                                        _storeSearchResults = [];
                                        _searchingStoresByName = false;
                                      });
                                    },
                                  )
                                : null),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickStoreFromGoogleMap,
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size.zero,
                          foregroundColor: const Color(0xFF15803D),
                          side: const BorderSide(color: Color(0xFF86EFAC), width: 1.2),
                          backgroundColor: const Color(0xFFF0FDF4),
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.map_rounded, size: 18, color: Color(0xFF15803D)),
                        label: const Text('Pick Store on Map', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_dropLocation == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Set your Delivery Address above to automatically load real nearby stores within 10 km.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      )
                    else if ((!isSearchingQuery && _loadingNearbyStores && displayedStores.isEmpty) ||
                        (isSearchingQuery && _searchingStoresByName && displayedStores.isEmpty))
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Searching verified stores within 10 km...',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                          ],
                        ),
                      )
                    else if (displayedStores.isEmpty && (_hasFetchedNearbyStores || isSearchingQuery))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          isSearchingQuery
                              ? 'No matching mapped store found within 10 km for "${_storeSearchCtrl.text.trim()}". Try another keyword or Pick Store on Map.'
                              : 'No mapped stores found within 10 km of this address. Search by store name above or tap Pick Store on Map.',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ),
                    ...displayedStores.map((store) {
                      final isSel = _selectedGroceryStoreName == store['name'];
                      final sDist = (store['distanceKm'] as num).toDouble();
                      final addrText = (store['address'] as String? ?? '').trim();
                      final tagText = (store['tag'] as String? ?? '').trim();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSel ? const Color(0xFFEFF6FF) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSel ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                            width: isSel ? 1.4 : 1.0,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            if (!_suggestedGroceryStoresList.any((s) => s['name'] == store['name'])) {
                              _suggestedGroceryStoresList.insert(0, store);
                            }
                            _selectGroceryStore(store);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: (store['color'] as Color? ?? const Color(0xFF2563EB)).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    store['icon'] as IconData? ?? Icons.storefront_rounded,
                                    size: 18,
                                    color: store['color'] as Color? ?? const Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        store['name'] as String,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w700,
                                          color: isSel ? const Color(0xFF1E3A8A) : const Color(0xFF1E293B),
                                        ),
                                        maxLines: 2,
                                        softWrap: true,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 3,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDCFCE7),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${sDist.toStringAsFixed(1)} km',
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF15803D)),
                                            ),
                                          ),
                                          if (tagText.isNotEmpty)
                                            Text(
                                              tagText,
                                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                            ),
                                        ],
                                      ),
                                      if (addrText.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          addrText,
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                          maxLines: 2,
                                          softWrap: true,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  isSel ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                  color: isSel ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    if (!_showCustomStoreInput)
                      TextButton.icon(
                        onPressed: () => setState(() => _showCustomStoreInput = true),
                        icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                        label: const Text('Enter another store name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customStoreCtrl,
                              decoration: InputDecoration(
                                hintText: 'Store name',
                                hintStyle: const TextStyle(fontSize: 12),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 36,
                            child: ElevatedButton(
                              onPressed: () {
                                if (_customStoreCtrl.text.trim().isNotEmpty) {
                                  _setCustomGroceryStore(_customStoreCtrl.text.trim());
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                minimumSize: Size.zero,
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Select', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
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
      appBar: AppBar(title: const Text('Edit Task')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Task Title Header (Bigger)
              _buildSectionHeader(
                icon: Icons.edit_note_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEAF2FF),
                title: 'Task Title',
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 5) ? 'Min 5 characters' : null,
              ),
              const SizedBox(height: 18),

              // Category Header (Bigger)
              _buildSectionHeader(
                icon: Icons.grid_view_rounded,
                iconColor: const Color(0xFF2563EB),
                iconBg: const Color(0xFFEAF2FF),
                title: 'Select Category',
              ),
              const SizedBox(height: 10),
              _CategoryGrid(
                selected: _selectedCategory,
                onChanged: (c) {
                  setState(() => _selectedCategory = c);
                  if (_isGrocery) {
                    _deliveryVehicle = 'bike';
                    _updateSuggestedStoresForDrop(_dropAddrCtrl.text.trim(), _dropLocation);
                  } else if (Task.isRepairCategory(c)) {
                    _syncAutoBudget(Task.fixedVisitPriceForRepairCategory(c));
                  }
                  _recalcDistance();
                  _syncAreaBudgetIfAuto();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_isGrocery && !Task.isRepairCategory(_selectedCategory) && _budgetCtrl.text.trim().isNotEmpty) {
                      _budgetFieldKey.currentState?.validate();
                    }
                  });
                },
              ),

              if (_isGrocery) ...[
                const SizedBox(height: 16),
                _buildGroceryItemsBanner(),
                const SizedBox(height: 16),
                _buildGroceryItemsSection(),
                const SizedBox(height: 18),
                _buildGroceryLocationSection(),
              ] else ...[
                if (_selectedCategory == 'delivery') ...[
                  const SizedBox(height: 14),
                  _buildDeliveryVehicleSelector(),
                ] else if (_isDelivery) ...[
                  const SizedBox(height: 14),
                  _buildDistanceCategoryRateBanner(),
                ],
                const SizedBox(height: 18),

                // Description (Non-grocery only)
                _buildSectionHeader(
                  icon: Icons.description_outlined,
                  iconColor: const Color(0xFF2563EB),
                  iconBg: const Color(0xFFEAF2FF),
                  title: 'Description',
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 5,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.description_outlined),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v == null || v.trim().length < 10)
                      ? 'Min 10 characters'
                      : null,
                ),
                const SizedBox(height: 14),

                // Budget & Visiting Fee
                if (Task.isRepairCategory(_selectedCategory)) ...[
                  _buildRepairVisitingFeeCard(),
                  const SizedBox(height: 16),
                ] else if (!_isGrocery) ...[
                  // Suggested budget card based on category + selected area
                  _buildSuggestedBudgetCard(),

                  // Budget (Non-grocery only)
                  _buildSectionHeader(
                    icon: Icons.account_balance_wallet_rounded,
                    iconColor: const Color(0xFF4F46E5),
                    iconBg: const Color(0xFFEEF2FF),
                    title: 'Task Budget',
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    key: _budgetFieldKey,
                    controller: _budgetCtrl,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Budget (₹)',
                      prefixIcon: const Icon(Icons.currency_rupee),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Please enter a budget';
                      if (_isDelivery) {
                        if (_calculatedDistanceKm != null) {
                          final distMin = Task.calculateDistancePrice(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle);
                          if (n < distMin) {
                            return 'Minimum ₹${distMin.toInt()} for ${_calculatedDistanceKm!.toStringAsFixed(1)} km';
                          }
                        } else {
                          final catMin = Task.minBudgetForCategory(_selectedCategory, vehicle: _deliveryVehicle);
                          if (catMin > 0 && n < catMin) {
                            return 'Minimum budget for ${_selectedCategory.replaceAll('_', ' ')} is ₹${catMin.toInt()}';
                          }
                        }
                      } else {
                        final catMin = Task.minBudgetForCategory(_selectedCategory, vehicle: _deliveryVehicle);
                        if (n < catMin) {
                          return 'Minimum budget for ${_selectedCategory.replaceAll('_', ' ')} is ₹${catMin.toInt()}';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Address fields for non-grocery categories ──────
                if (_isFreelancer) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.public_rounded, size: 18, color: Color(0xFF2563EB)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Remote Freelancer Service — No location needed.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_isDelivery) ...[
                  _buildSectionHeader(
                    icon: Icons.location_on,
                    iconColor: AppColors.primary,
                    iconBg: const Color(0xFFEAF2FF),
                    title: 'Pickup & Drop Location',
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _pickupAddrCtrl,
                    onChanged: _onPickupAddrChanged,
                    decoration: InputDecoration(
                      labelText: 'Pickup Address *',
                      prefixIcon: const Icon(Icons.location_on, color: AppColors.primary),
                      suffixIcon: _AddressActionButtons(
                        isLoading: _gettingPickupGps,
                        accentColor: AppColors.primary,
                        onGps: _getGpsForPickup,
                        onMap: _pickMapForPickup,
                      ),
                      suffixIconConstraints: const BoxConstraints(maxHeight: 48),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Pickup address is required' : null,
                  ),
                  LocationSuggestionsDropdown(
                    suggestions: _pickupSuggestions,
                    isLoading: _searchingPickup,
                    accentColor: AppColors.primary,
                    onSelect: _selectPickupSuggestion,
                    onDismiss: () => setState(() => _pickupSuggestions = []),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _dropAddrCtrl,
                    onChanged: _onDropAddrChanged,
                    decoration: InputDecoration(
                      labelText: 'Drop / Delivery Address *',
                      prefixIcon: const Icon(Icons.flag, color: AppColors.danger),
                      suffixIcon: _AddressActionButtons(
                        isLoading: _gettingDropGps,
                        accentColor: AppColors.danger,
                        onGps: _getGpsForDrop,
                        onMap: _pickMapForDrop,
                      ),
                      suffixIconConstraints: const BoxConstraints(maxHeight: 48),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Drop address is required' : null,
                  ),
                  LocationSuggestionsDropdown(
                    suggestions: _dropSuggestions,
                    isLoading: _searchingDrop,
                    accentColor: AppColors.danger,
                    onSelect: _selectDropSuggestion,
                    onDismiss: () => setState(() => _dropSuggestions = []),
                  ),
                  if (_calculatedDistanceKm != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.route, size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Distance: ${_calculatedDistanceKm!.toStringAsFixed(1)} km',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.primary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  Task.distanceFareSummary(_calculatedDistanceKm!, _selectedCategory, vehicle: _deliveryVehicle),
                                  style: const TextStyle(fontSize: 12, color: AppColors.gray),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  _buildSectionHeader(
                    icon: Icons.location_on_outlined,
                    iconColor: AppColors.primary,
                    iconBg: const Color(0xFFEAF2FF),
                    title: 'Location',
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _addressCtrl,
                    onChanged: _onAddressChanged,
                    decoration: InputDecoration(
                      labelText: 'Address / Landmark (optional)',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      suffixIcon: _AddressActionButtons(
                        isLoading: false,
                        accentColor: AppColors.primary,
                        onGps: () async {
                          final loc = await LocationService.getCurrentLocation();
                          if (loc == null || !mounted) return;
                          setState(() {
                            _location = loc;
                            _locationLabel = null;
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
                                setState(() => _locationLabel = addr);
                                if (!_isDelivery && _addressCtrl.text.isEmpty && addr != null) {
                                  _addressCtrl.text = addr;
                                }
                                _syncAreaBudgetIfAuto();
                              }
                            }
                          } catch (_) {}
                        },
                        onMap: _pickLocationFromMap,
                      ),
                      suffixIconConstraints: const BoxConstraints(maxHeight: 48),
                    ),
                  ),
                  LocationSuggestionsDropdown(
                    suggestions: _addressSuggestions,
                    isLoading: _searchingAddress,
                    accentColor: AppColors.primary,
                    onSelect: _selectAddressSuggestion,
                    onDismiss: () => setState(() => _addressSuggestions = []),
                  ),
                ],
              ],
              const SizedBox(height: 16),

              // Price breakdown (real-time via ValueListenableBuilder)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _budgetCtrl,
                builder: (_, value, __) {
                  final rawBudget = double.tryParse(value.text) ?? 0;
                  final isRepair = Task.isRepairCategory(_selectedCategory);
                  final budget = isRepair
                      ? Task.fixedVisitPriceForRepairCategory(_selectedCategory)
                      : (_isGrocery && rawBudget <= 0
                          ? (Task.calculateDistancePrice(_calculatedDistanceKm ?? 0.8, 'groceries') + 30.0)
                          : rawBudget);
                  final isDelivery = const {'delivery', 'pickup', 'transport', 'moving'}.contains(_selectedCategory);
                  final charge = isDelivery ? Task.serviceChargeForCategory(_selectedCategory).toDouble() : 0.0;
                  final posterFee = _isGrocery ? 12.0 : (isRepair ? 20.0 : (budget * 0.20));
                  final total = budget + charge + posterFee;
                  return TaskPriceBreakdownCard(
                    budget: budget,
                    serviceCharge: charge,
                    posterFee: posterFee,
                    totalCost: total,
                    isRepair: isRepair,
                    isGrocery: _isGrocery,
                    distanceKm: _calculatedDistanceKm,
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
