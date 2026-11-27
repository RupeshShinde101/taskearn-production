import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../../models/task.dart';
import '../../models/grocery_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../services/storage_service.dart';
import '../../services/location_service.dart';
import '../../services/location_search_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_posted_success_dialog.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/profile_mode_switch_dialog.dart';
import '../../widgets/location_suggestions_dropdown.dart';
import 'grocery_item_picker_screen.dart';

class GroceryTaskDetailsScreen extends StatefulWidget {
  final List<SelectedGroceryItem> initialItems;
  final String taskTitle;
  final String? initialDropAddress;
  final LatLng? initialDropLocation;

  const GroceryTaskDetailsScreen({
    super.key,
    required this.initialItems,
    this.taskTitle = 'Grocery Delivery',
    this.initialDropAddress,
    this.initialDropLocation,
  });

  @override
  State<GroceryTaskDetailsScreen> createState() => _GroceryTaskDetailsScreenState();
}

class _GroceryTaskDetailsScreenState extends State<GroceryTaskDetailsScreen> {
  late List<SelectedGroceryItem> _items;

  final TextEditingController _dropAddrCtrl = TextEditingController();
  final FocusNode _dropFocus = FocusNode();
  LatLng? _dropLocation;
  List<LocationSearchResult> _dropSuggestions = [];
  bool _searchingDrop = false;
  bool _gettingDropGps = false;
  Timer? _dropDebounce;

  final TextEditingController _storeSearchCtrl = TextEditingController();
  final FocusNode _storeFocus = FocusNode();
  String? _selectedGroceryStoreName;
  final TextEditingController _pickupAddrCtrl = TextEditingController();
  LatLng? _pickupLocation;
  List<Map<String, dynamic>> _suggestedStores = [];
  List<Map<String, dynamic>> _storeSearchResults = [];
  bool _loadingNearbyStores = false;
  bool _searchingStoresByName = false;
  int _storeFetchSeq = 0;
  Timer? _storeSearchDebounce;

  double? _calculatedDistanceKm;
  List<Map<String, dynamic>> _savedLocations = [];
  String? _selectedSavedLocId;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.initialItems);
    if (widget.initialDropAddress != null && widget.initialDropAddress!.isNotEmpty) {
      _dropAddrCtrl.text = widget.initialDropAddress!;
      _dropLocation = widget.initialDropLocation;
    }
    _loadSavedLocations();
    if (_dropLocation != null) {
      _fetchStoresForLocation(_dropAddrCtrl.text, _dropLocation!);
    }
  }

  @override
  void dispose() {
    _dropDebounce?.cancel();
    _storeSearchDebounce?.cancel();
    _dropAddrCtrl.dispose();
    _dropFocus.dispose();
    _storeSearchCtrl.dispose();
    _storeFocus.dispose();
    _pickupAddrCtrl.dispose();
    super.dispose();
  }

  void _loadSavedLocations() {
    try {
      final locs = StorageService.getSavedLocations();
      if (mounted) {
        setState(() => _savedLocations = locs);
      }
    } catch (_) {}
  }

  double get _totalWeightKg => GroceryCatalog.calculateTotalWeightKg(_items);

  double? get _travelFare {
    if (_calculatedDistanceKm == null && _dropLocation == null) return null;
    final dist = _calculatedDistanceKm ?? 0.8;
    return Task.calculateDistancePrice(dist, 'groceries', vehicle: 'bike');
  }

  double? get _handlingCharges => _travelFare != null ? 40.0 : null;
  double? get _platformFee => _travelFare != null ? 12.0 : null;
  double? get _totalPay {
    final fare = _travelFare;
    final handling = _handlingCharges;
    final fee = _platformFee;
    if (fare == null || handling == null || fee == null) return null;
    return fare + handling + fee;
  }

  void _onDropAddrChanged(String query) {
    _dropDebounce?.cancel();
    final q = query.trim();
    if (q.length < 2) {
      if (_dropSuggestions.isNotEmpty) setState(() => _dropSuggestions = []);
      return;
    }
    _dropDebounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _searchingDrop = true);
      try {
        final results = await LocationSearchService.search(q);
        if (mounted && _dropAddrCtrl.text.trim() == q) {
          setState(() {
            _dropSuggestions = results;
            _searchingDrop = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searchingDrop = false);
      }
    });
  }

  void _selectDropSuggestion(LocationSearchResult s) {
    setState(() {
      _dropAddrCtrl.text = s.fullAddress;
      _dropLocation = s.toLatLng();
      _dropSuggestions = [];
      _selectedSavedLocId = null;
    });
    _fetchStoresForLocation(s.fullAddress, s.toLatLng());
  }

  Future<void> _getGpsForDrop() async {
    setState(() => _gettingDropGps = true);
    try {
      final loc = await LocationService.getCurrentLocation();
      if (loc == null || !mounted) {
        setState(() => _gettingDropGps = false);
        return;
      }
      _dropLocation = loc;
      _selectedSavedLocId = null;
      try {
        final places = await placemarkFromCoordinates(loc.latitude, loc.longitude)
            .timeout(const Duration(seconds: 6));
        if (mounted && places.isNotEmpty) {
          final p = places.first;
          final addr = [p.name, p.subLocality, p.locality, p.administrativeArea]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
          _dropAddrCtrl.text = addr.isNotEmpty
              ? addr
              : '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';
        } else {
          _dropAddrCtrl.text =
              'Current Location (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
        }
      } catch (_) {
        _dropAddrCtrl.text =
            'Current Location (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
      }
      _fetchStoresForLocation(_dropAddrCtrl.text, loc);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _gettingDropGps = false);
    }
  }

  Future<void> _pickMapForDrop() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(initialLocation: _dropLocation),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      final addr = result['address'] as String?;
      final loc = result['location'] as LatLng?;
      if (addr != null && loc != null) {
        setState(() {
          _dropAddrCtrl.text = addr;
          _dropLocation = loc;
          _dropSuggestions = [];
          _selectedSavedLocId = null;
        });
        _fetchStoresForLocation(addr, loc);
      }
    }
  }

  void _fetchStoresForLocation(String address, LatLng loc) {
    final seq = ++_storeFetchSeq;
    setState(() {
      _loadingNearbyStores = true;
      _suggestedStores = [];
      _selectedGroceryStoreName = null;
      _calculatedDistanceKm = null;
    });

    LocationSearchService.searchNearbyGroceryStores(
      loc,
      radiusKm: 10.0,
      areaFallback: address,
    ).then((stores) {
      if (!mounted || seq != _storeFetchSeq) return;
      setState(() {
        _loadingNearbyStores = false;
        _suggestedStores = stores.where((s) =>
          s['hasAllItems'] == true ||
          LocationSearchService.isAllItemsStore(
            s['name'] as String? ?? '',
            s['shopType'] as String? ?? '',
            s['amenity'] as String? ?? '',
          )
        ).toList();
      });
    }).catchError((_) {
      if (mounted && seq == _storeFetchSeq) {
        setState(() => _loadingNearbyStores = false);
      }
    });
  }

  void _onStoreSearchChanged(String raw) {
    _storeSearchDebounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      if (_storeSearchResults.isNotEmpty || _searchingStoresByName) {
        setState(() {
          _storeSearchResults = [];
          _searchingStoresByName = false;
        });
      }
      return;
    }
    final inMem = _suggestedStores.where((s) {
      final name = (s['name'] as String? ?? '').toLowerCase();
      final addr = (s['address'] as String? ?? '').toLowerCase();
      final qLower = q.toLowerCase();
      return name.contains(qLower) || addr.contains(qLower);
    }).toList();

    setState(() {
      _storeSearchResults = inMem;
      _searchingStoresByName = true;
    });

    final center = _dropLocation ?? LocationSearchService.defaultPuneCenter;
    _storeSearchDebounce = Timer(const Duration(milliseconds: 200), () async {
      final matches = await LocationSearchService.searchStoresByName(
        q,
        center,
        radiusKm: 10.0,
        areaFallback: _dropAddrCtrl.text,
      );
      if (!mounted || _storeSearchCtrl.text.trim() != q) return;

      final merged = <Map<String, dynamic>>[...inMem];
      for (final m in matches) {
        if (!merged.any((ex) => (ex['name'] as String).toLowerCase() == (m['name'] as String).toLowerCase())) {
          merged.add(m);
        }
      }
      setState(() {
        _storeSearchResults = merged;
        _searchingStoresByName = false;
      });
    });
  }

  void _selectGroceryStore(Map<String, dynamic> store) {
    final name = store['name'] as String? ?? 'Grocery Store';
    final addr = store['address'] as String? ?? name;
    final lat = (store['lat'] as num?)?.toDouble();
    final lon = (store['lon'] as num?)?.toDouble() ?? (store['lng'] as num?)?.toDouble();
    final storeLoc = lat != null && lon != null ? LatLng(lat, lon) : null;

    double distKm = (store['distanceKm'] as num?)?.toDouble() ?? 1.2;
    if (_dropLocation != null && storeLoc != null) {
      final m = Geolocator.distanceBetween(
        _dropLocation!.latitude,
        _dropLocation!.longitude,
        storeLoc.latitude,
        storeLoc.longitude,
      );
      distKm = double.parse(((m / 1000.0) * 1.2).toStringAsFixed(1));
    }

    setState(() {
      _selectedGroceryStoreName = name;
      _pickupAddrCtrl.text = addr;
      _pickupLocation = storeLoc;
      _calculatedDistanceKm = distKm;
    });
  }

  Future<void> _pickStoreFromMap() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(initialLocation: _pickupLocation ?? _dropLocation),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      final pickedLoc = result['location'] as LatLng?;
      final addr = (result['address'] as String?)?.trim() ?? '';
      if (pickedLoc == null) return;

      String storeName = addr.split(',').first.trim();
      if (storeName.isEmpty) storeName = 'Selected Grocery Store';

      double distKm = 1.2;
      if (_dropLocation != null) {
        final m = Geolocator.distanceBetween(
          pickedLoc.latitude,
          pickedLoc.longitude,
          _dropLocation!.latitude,
          _dropLocation!.longitude,
        );
        distKm = double.parse(((m / 1000.0) * 1.2).toStringAsFixed(1));
      }

      final storeMap = {
        'name': storeName,
        'address': addr,
        'lat': pickedLoc.latitude,
        'lon': pickedLoc.longitude,
        'distanceKm': distKm,
        'hasAllItems': true,
      };

      if (!_suggestedStores.any((s) => s['name'] == storeName)) {
        _suggestedStores.insert(0, storeMap);
      }
      _selectGroceryStore(storeMap);
      _storeSearchCtrl.text = storeName;
    }
  }

  Future<void> _showSavedLocationsModal() async {
    if (_savedLocations.isEmpty) {
      _showQuickSaveDialog();
      return;
    }
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text('Select Saved Location', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              ),
              const Divider(height: 16),
              ...List.generate(_savedLocations.length, (i) {
                final loc = _savedLocations[i];
                final label = loc['label']?.toString() ?? 'Location';
                final addr = loc['address']?.toString() ?? '';
                final isSel = loc['id']?.toString() == _selectedSavedLocId;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFEFF6FF),
                    child: Icon(
                      label.toLowerCase() == 'home'
                          ? Icons.home_rounded
                          : (label.toLowerCase() == 'work' ? Icons.work_rounded : Icons.place_rounded),
                      color: const Color(0xFF2563EB),
                      size: 18,
                    ),
                  ),
                  title: Text(label, style: TextStyle(fontWeight: isSel ? FontWeight.w800 : FontWeight.w600, fontSize: 14)),
                  subtitle: Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  trailing: isSel ? const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB)) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedSavedLocId = loc['id']?.toString();
                      _dropAddrCtrl.text = addr;
                      if (loc['lat'] != null && loc['lng'] != null) {
                        _dropLocation = LatLng(
                          (loc['lat'] as num).toDouble(),
                          (loc['lng'] as num).toDouble(),
                        );
                        _fetchStoresForLocation(addr, _dropLocation!);
                      }
                    });
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showQuickSaveDialog() async {
    final currentAddr = _dropAddrCtrl.text.trim();
    final addrInput = TextEditingController(text: currentAddr);
    String selectedLabel = 'Home';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Save Address', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: ['Home', 'Work', 'Other'].map((type) {
                  final isSel = selectedLabel == type;
                  return ChoiceChip(
                    label: Text(type),
                    selected: isSel,
                    selectedColor: const Color(0xFF2563EB),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelStyle: TextStyle(
                      color: isSel ? Colors.white : const Color(0xFF1E293B),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    onSelected: (_) => setDialogState(() => selectedLabel = type),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: addrInput,
                style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                decoration: InputDecoration(
                  hintText: 'Enter complete address to save',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final addrToSave = addrInput.text.trim();
                if (addrToSave.isEmpty) return;
                await StorageService.addSavedLocation({
                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                  'label': selectedLabel,
                  'address': addrToSave,
                  'lat': _dropLocation?.latitude,
                  'lng': _dropLocation?.longitude,
                });
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      _loadSavedLocations();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Address saved successfully!')),
      );
    }
  }

  Future<void> _editGroceryItems() async {
    final updated = await Navigator.of(context).push<List<SelectedGroceryItem>>(
      MaterialPageRoute(
        builder: (_) => GroceryItemPickerScreen(initialSelected: _items),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _items = updated);
    }
  }

  Future<void> _submitTask() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one grocery item.')),
      );
      return;
    }
    if (_dropAddrCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery address is required.')),
      );
      _dropFocus.requestFocus();
      return;
    }
    if (_selectedGroceryStoreName == null && _pickupAddrCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or search a store to buy from.')),
      );
      _storeFocus.requestFocus();
      return;
    }

    if (_totalWeightKg > GroceryCatalog.maxTwoWheelerWeightKg) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Weight Limit Exceeded'),
          content: Text('Total grocery weight (${_totalWeightKg.toStringAsFixed(1)} kg) exceeds the 20 kg limit for two-wheelers. Please remove some items.'),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    if (!auth.isPosterMode) {
      final switched = await showProfileModeSwitchDialog(
        context,
        targetMode: 'poster',
        title: 'Switch to Poster Profile',
        message: 'Posting tasks requires a Poster profile. Would you like to switch to Poster mode to post this task?',
        actionLabel: 'Switch to Poster & Continue',
      );
      if (switched != true || !mounted) return;
    }

    if (!(auth.user?.isKycVerified ?? false)) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('KYC Verification Required'),
          content: const Text('You need to complete KYC verification before posting a task.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (mounted) context.push('/kyc');
              },
              child: const Text('Verify KYC'),
            ),
          ],
        ),
      );
      return;
    }

    final travelFare = _travelFare ?? 40.0;
    const handling = 40.0;
    const platform = 12.0;
    final total = travelFare + handling + platform;

    // Review dialog before posting
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shopping_bag_rounded, color: Color(0xFF16A34A), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Post Grocery Task', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                        Text('Review delivery details', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text('Items: ${_items.length} (${_totalWeightKg.toStringAsFixed(1)} kg)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 6),
              Text('Store: ${_selectedGroceryStoreName ?? _pickupAddrCtrl.text}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569))),
              const SizedBox(height: 4),
              Text('Deliver to: ${_dropAddrCtrl.text}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569))),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Helper Pay:', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    Text('₹${total.round()}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF16A34A))),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B63F6),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Confirm & Post', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _posting = true);

    final taskDescription = '• Category: Groceries\n'
        '• Items (${_items.length}): ${_items.map((i) => '${i.name} (${i.requirementSummary})').join(', ')}\n'
        '• Store: ${_selectedGroceryStoreName ?? _pickupAddrCtrl.text}\n'
        '• Delivery: ${_dropAddrCtrl.text}\n'
        '• Item Costs: Paid separately on actual store bill';

    final taskData = {
      'title': widget.taskTitle.isNotEmpty ? widget.taskTitle : 'Grocery Delivery',
      'description': taskDescription,
      'category': 'groceries',
      'price': travelFare + handling,
      'budget': travelFare + handling,
      'service_charge': 0.0,
      'serviceCharge': 0.0,
      'location': {
        'lat': _dropLocation?.latitude,
        'lng': _dropLocation?.longitude,
        'address': _dropAddrCtrl.text.trim(),
      },
      'vehicle': 'bike',
      'pickup_address': _pickupAddrCtrl.text.trim().isNotEmpty ? _pickupAddrCtrl.text.trim() : (_selectedGroceryStoreName ?? 'Local Store'),
      'pickupAddress': _pickupAddrCtrl.text.trim().isNotEmpty ? _pickupAddrCtrl.text.trim() : (_selectedGroceryStoreName ?? 'Local Store'),
      'pickup_location': {
        'lat': _pickupLocation?.latitude,
        'lng': _pickupLocation?.longitude,
        'address': _pickupAddrCtrl.text.trim(),
      },
      'delivery_address': _dropAddrCtrl.text.trim(),
      'drop_location_address': _dropAddrCtrl.text.trim(),
      'drop_address': _dropAddrCtrl.text.trim(),
      'dropAddress': _dropAddrCtrl.text.trim(),
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
      'separate_costs': 'Grocery items cost (paid separately by poster directly to helper/store)',
      'grocery_items': _items.map((e) => e.toJson()).toList(),
      'groceryItems': _items.map((e) => e.toJson()).toList(),
    };

    final ok = await context.read<TaskProvider>().postTask(taskData);
    if (!mounted) return;
    setState(() => _posting = false);

    if (ok) {
      final provider = context.read<TaskProvider>();
      final createdTaskId = provider.lastCreatedTaskId;
      await TaskPostedSuccessDialog.show(
        context: context,
        title: taskData['title'] as String,
        category: 'groceries',
        budget: (taskData['budget'] as num).toDouble(),
        taskId: createdTaskId,
        onViewTasks: () {
          if (mounted) context.go('/my-tasks');
        },
        onGoHome: () {
          if (mounted) context.go('/home');
        },
      );
      if (mounted) {
        context.go('/my-tasks');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<TaskProvider>().error ?? 'Failed to post grocery task'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.taskTitle.isNotEmpty ? widget.taskTitle : 'Grocery Delivery',
          style: const TextStyle(
            fontSize: 17.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Grocery Items Policy Card
                _buildPolicyCard(),
                const SizedBox(height: 14),

                // 2. Bike / Scooty Capacity Limits Card
                _buildCapacityLimitsCard(),
                const SizedBox(height: 14),

                // 3. Grocery Items Added Card
                _buildGroceryItemsCard(),
                const SizedBox(height: 14),

                // 4. Pickup-to-Delivery Route Card
                _buildRouteCard(),
                const SizedBox(height: 14),

                // 5. Price Breakdown Card
                _buildPriceBreakdownCard(),
              ],
            ),
          ),

          // Bottom Continue Button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _posting ? null : _submitTask,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B63F6),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _posting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 20),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF16A34A), size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grocery Items Policy',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF166534),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Cost of grocery items is paid separately by the task poster directly to the helper/store and is NOT included in this delivery budget value.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF15803D),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityLimitsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.two_wheeler_rounded, color: Color(0xFF2563EB), size: 20),
              SizedBox(width: 8),
              Text(
                'Bike / Scooty Capacity Limits',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E3A8A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Max Weight', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('20kg', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Max Size', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('Standard Bags', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroceryItemsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shopping_bag_outlined, color: Color(0xFF16A34A), size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Grocery Items',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_items.length} Added',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF166534)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Items list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final item = _items[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: item.imageUrl.isNotEmpty
                            ? Image.network(
                                item.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Text(item.emoji, style: const TextStyle(fontSize: 20)),
                                ),
                              )
                            : Center(
                                child: Text(item.emoji, style: const TextStyle(fontSize: 20)),
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
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.requirementSummary,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF2563EB)),
                      onPressed: _editGroceryItems,
                      tooltip: 'Edit Items',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                      onPressed: () {
                        setState(() {
                          _items.removeAt(index);
                        });
                      },
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          // Two-Wheeler Capacity banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: [
                const Text('🛵', style: TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                const Text(
                  'Two-Wheeler Capacity:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF166534)),
                ),
                const Spacer(),
                Text(
                  '${_totalWeightKg.toStringAsFixed(1)} / 20.0 kg',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _totalWeightKg > 20.0 ? const Color(0xFFEF4444) : const Color(0xFF166534),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Add more button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _editGroceryItems,
              icon: const Icon(Icons.add_rounded, size: 18, color: Color(0xFF2563EB)),
              label: const Text(
                'Add More / Edit Grocery Items',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF2563EB), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard() {
    final dist = _calculatedDistanceKm;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pickup-to-Delivery Route',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                      ),
                      SizedBox(height: 2),
                      Text('Delivery address & store selection', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    dist != null ? '${dist.toStringAsFixed(1)} km' : '10 km Radius',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Delivery Address section
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Delivery Address', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                          Text('DELIVER TO HOME (DROP)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                        ],
                      ),
                    ),
                    Flexible(
                      child: InkWell(
                        onTap: _showQuickSaveDialog,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bookmark_add_outlined, size: 14, color: Color(0xFF2563EB)),
                                SizedBox(width: 4),
                                Text('Save Location', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Delivery Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Saved locations dropdown
                      InkWell(
                        onTap: _showSavedLocationsModal,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.bookmark_outline_rounded, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedSavedLocId != null
                                      ? _savedLocations.firstWhere(
                                          (l) => l['id']?.toString() == _selectedSavedLocId,
                                          orElse: () => {'label': 'Saved Location'},
                                        )['label']?.toString() ?? 'Choose from Home, Work, Other'
                                      : 'Choose from Home, Work, Other',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF64748B)),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Delivery address textfield
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _dropAddrCtrl,
                                focusNode: _dropFocus,
                                onChanged: _onDropAddrChanged,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                                decoration: const InputDecoration(
                                  hintText: 'Delivery Address *',
                                  hintStyle: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: _gettingDropGps
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.my_location_rounded, color: Color(0xFFDC2626), size: 19),
                              tooltip: 'Use GPS',
                              onPressed: _gettingDropGps ? null : _getGpsForDrop,
                            ),
                            IconButton(
                              icon: const Icon(Icons.map_outlined, color: Color(0xFFDC2626), size: 19),
                              tooltip: 'Pick on Map',
                              onPressed: _pickMapForDrop,
                            ),
                          ],
                        ),
                      ),

                      LocationSuggestionsDropdown(
                        suggestions: _dropSuggestions,
                        isLoading: _searchingDrop,
                        accentColor: AppColors.danger,
                        onSelect: _selectDropSuggestion,
                        onDismiss: () => setState(() => _dropSuggestions = []),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Route indicator banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    children: [
                      const Text('🛵', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _dropAddrCtrl.text.isNotEmpty
                              ? (dist != null ? '${dist.toStringAsFixed(1)} km bike transit • ~${(dist * 5 + 3).round()} mins' : 'Finding nearby stores within 10 km')
                              : 'Enter delivery address above to show nearby stores',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _dropAddrCtrl.text.isNotEmpty ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Store Address Section
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Store Address', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                          Text('BUY FROM STORE (PICKUP)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF15803D))),
                        ],
                      ),
                    ),
                    if (_selectedGroceryStoreName != null)
                      InkWell(
                        onTap: () {
                          _storeSearchCtrl.clear();
                          setState(() {
                            _selectedGroceryStoreName = null;
                            _storeSearchResults = [];
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                          child: const Text('Change Store', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                // Store search field
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      const Icon(Icons.search_rounded, size: 18, color: Color(0xFF2563EB)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _storeSearchCtrl,
                          focusNode: _storeFocus,
                          onChanged: _onStoreSearchChanged,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          decoration: const InputDecoration(
                            hintText: 'Enter shop name',
                            hintStyle: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            filled: false,
                            fillColor: Colors.transparent,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.map_rounded, size: 19, color: Color(0xFF16A34A)),
                        tooltip: 'Pick on Map',
                        onPressed: _pickStoreFromMap,
                      ),
                    ],
                  ),
                ),

                // Store suggestions list
                if (_loadingNearbyStores)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF16A34A))),
                          SizedBox(width: 8),
                          Text('Finding nearby stores within 10 km...', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final stores = _storeSearchCtrl.text.isNotEmpty ? _storeSearchResults : _suggestedStores;
                      if (stores.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _storeSearchCtrl.text.isNotEmpty
                                ? 'No store named "${_storeSearchCtrl.text}" found nearby. You can pick directly on map.'
                                : 'Set delivery address to see stores within 10 km.',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        );
                      }
                      return Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: stores.length > 5 ? 5 : stores.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          itemBuilder: (_, index) {
                            final s = stores[index];
                            final name = s['name'] as String? ?? 'Store';
                            final sDist = (s['distanceKm'] as num?)?.toDouble() ?? 1.2;
                            final isSel = _selectedGroceryStoreName == name;
                            return InkWell(
                              onTap: () => _selectGroceryStore(s),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                      size: 18,
                                      color: isSel ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                                          color: isSel ? const Color(0xFF15803D) : const Color(0xFF1E293B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE2E8F0),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('${sDist.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBreakdownCard() {
    final fare = _travelFare;
    final handling = _handlingCharges;
    final fee = _platformFee;
    final total = _totalPay;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF2563EB), size: 18),
              ),
              const SizedBox(width: 10),
              const Text('Price Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF16A34A)),
                    SizedBox(width: 4),
                    Text('Pay on Verification', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF166534))),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (total == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Set delivery address and select a store to calculate prices.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          _buildPriceRow('Task Value', fare != null ? '₹${fare.round()}' : '--'),
          const SizedBox(height: 8),
          _buildPriceRow('Handling Charges', handling != null ? '₹${handling.round()}' : '--'),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Platform Fee (GST included)', style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Flat ₹12', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
              ),
              const Spacer(),
              Text(fee != null ? '₹${fee.round()}' : '--', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Pay', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
                  SizedBox(height: 2),
                  Text('Pay only after work completion', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
              const Spacer(),
              Text(
                total != null ? '₹${total.round()}' : '--',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFF64748B)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'No payment needed upfront. Funds are released only after you verify the completed task.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
        Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
      ],
    );
  }
}
