import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import 'dart:async';
import '../../services/location_search_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/location_suggestions_dropdown.dart';
import '../../widgets/task_price_breakdown_card.dart';
import '../../widgets/map_location_picker.dart';
import '../../widgets/profile_mode_switch_dialog.dart';

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

  // FocusNodes so we can jump cursor to the first invalid field
  final _titleFocus   = FocusNode();
  final _descFocus    = FocusNode();
  final _budgetFocus  = FocusNode();
  final _pickupFocus  = FocusNode();
  final _dropFocus    = FocusNode();
  final _addressFocus = FocusNode();
  final _addressCtrl = TextEditingController();

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
  final _flatNameCtrl = TextEditingController();
  final _areaCtrl    = TextEditingController();
  // Delivery-specific: separate pickup & drop location fields
  final _pickupAddrCtrl = TextEditingController();
  final _pickupFlatCtrl = TextEditingController();
  final _pickupAreaCtrl = TextEditingController();
  final _dropAddrCtrl   = TextEditingController();
  final _dropFlatCtrl   = TextEditingController();
  final _dropAreaCtrl   = TextEditingController();

  String _selectedCategory = 'delivery';
  String _deliveryVehicle = 'bike'; // 'bike' (₹12/km) or 'rikshaw' (₹18/km)
  int _distCalcSeq = 0;
  final _categorySearchCtrl = TextEditingController();
  String _categorySearch = '';
  LatLng? _location;
  String? _locationLabel; // reverse-geocoded address from map picker
  bool _loading = false;
  bool _gettingLocation = false;
  // _showAllCategories removed (unused)
  // Per-field lat/lng for delivery categories
  LatLng? _pickupLocation;
  LatLng? _dropLocation;
  bool _gettingPickupGps = false;
  bool _gettingDropGps = false;
  double? _calculatedDistanceKm;

  // ─── Saved locations ────────────────────────────────────
  List<Map<String, dynamic>> _savedLocations = [];
  bool _showSavePrompt       = false; // non-delivery
  bool _showPickupSavePrompt = false; // pickup
  bool _showDropSavePrompt   = false; // drop

  final _scrollCtrl = ScrollController();

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
    'household':   ['What chores needed?', 'How many rooms?', 'Duration?', 'Supplies provided?'],
    'shopping':    ['What items to buy?', 'Which store/area?', 'Item budget?', 'Urgent?'],
    'electrician': ['What electrical work?', 'Specific fault/issue?', 'Urgent?'],
    'plumbing':    ['What plumbing issue?', 'Room affected?', 'Urgent?'],
    'repair':      ['What to repair?', 'Brand/model?', 'How long broken?'],
    'vehicle':     ['Vehicle type?', 'Service needed?', 'Make/model?', 'At-home or garage?'],
    'tutoring':    ['Which subject?', 'Grade/level?', 'Hours needed?', 'Online or in-person?'],
    'freelancer':  ['What service do you need?', 'Skill level required?', 'Deadline?', 'Remote or in-person?', 'Tools/software needed?'],
    'carpentry':   ['What carpentry work?', 'Materials needed?', 'Approximate dimensions?'],
    'painting':    ['What to paint?', 'Colour preference?', 'Area size?'],
    'beauty':      ['What treatment/service?', 'At-home or salon?', 'Duration?', 'Gender preference?'],
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

  /// Quick-tap suggestion chips for common question patterns.
  static const Map<String, List<String>> _quickChips = {
    'urgent': ['Yes, urgent', 'Within 2 hours', 'Flexible today'],
    'time constraint': ['Urgent', 'Morning', 'Evening', 'Flexible'],
    'time slot': ['Morning (9am-12pm)', 'Afternoon (12pm-4pm)', 'Evening (4pm-8pm)', 'Flexible'],
    'time needed': ['Morning', 'Lunch time', 'Evening / Dinner', 'Flexible'],
    'fragile': ['Yes, fragile', 'No, not fragile'],
    'need packing help': ['Yes, need packing', 'No, already packed'],
    'pets at home': ['No pets', 'Dog', 'Cat', 'Other pet'],
    'dietary restrictions': ['Pure Veg', 'Non-Veg', 'Jain', 'No restrictions'],
    'wash + fold': ['Wash + Fold', 'Wash + Iron', 'Only Fold'],
    'pick up from home': ['Yes, pick up from home', 'I will drop off'],
    'at-home or garage': ['At my home', 'Take to garage / workshop'],
    'online or in-person': ['In-person', 'Online', 'Either'],
    'remote or in-person': ['Remote / Online', 'In-person'],
    'vaccinated': ['Yes, vaccinated', 'Not vaccinated'],
    'supplies provided': ['Supplies provided', 'Helper bring supplies'],
    'tools needed': ['Have own tools', 'Helper bring tools'],
    'gender preference': ['No preference', 'Female helper', 'Male helper'],
  };


  static const Map<String, LatLng> _knownLocalityCoords = {
    'hinjewadi': LatLng(18.5913, 73.7389),
    'baner': LatLng(18.5590, 73.7868),
    'wakad': LatLng(18.5987, 73.7660),
    'balewadi': LatLng(18.5750, 73.7712),
    'aundh': LatLng(18.5602, 73.8031),
    'bavdhan': LatLng(18.5143, 73.7684),
    'pashan': LatLng(18.5385, 73.7929),
    'kothrud': LatLng(18.5074, 73.8077),
    'shivajinagar': LatLng(18.5314, 73.8446),
    'shivaji nagar': LatLng(18.5314, 73.8446),
    'deccan': LatLng(18.5167, 73.8417),
    'swargate': LatLng(18.5018, 73.8636),
    'camp': LatLng(18.5140, 73.8780),
    'koregaon': LatLng(18.5362, 73.8940),
    'koregaon park': LatLng(18.5362, 73.8940),
    'kalyani': LatLng(18.5477, 73.9034),
    'kalyani nagar': LatLng(18.5477, 73.9034),
    'viman': LatLng(18.5679, 73.9143),
    'viman nagar': LatLng(18.5679, 73.9143),
    'kharadi': LatLng(18.5516, 73.9349),
    'magarpatta': LatLng(18.5089, 73.9260),
    'hadapsar': LatLng(18.5089, 73.9260),
    'pimpri': LatLng(18.6279, 73.8009),
    'chinchwad': LatLng(18.6298, 73.7997),
    'bhosari': LatLng(18.6247, 73.8468),
    'wagholi': LatLng(18.5808, 73.9804),
    'nigdi': LatLng(18.6548, 73.7684),
    'akurdi': LatLng(18.6493, 73.7707),
    'moshi': LatLng(18.6750, 73.8436),
    'ambegaon': LatLng(18.4575, 73.8508),
    'katraj': LatLng(18.4575, 73.8508),
    'warje': LatLng(18.4816, 73.7963),
    'ravet': LatLng(18.6310, 73.7350),
    'punawale': LatLng(18.6250, 73.7380),
    'tathawade': LatLng(18.6180, 73.7480),
    'kondhwa': LatLng(18.4746, 73.8860),
    'bibvewadi': LatLng(18.4770, 73.8640),
    'dhayari': LatLng(18.4480, 73.8180),
    'sinhagad': LatLng(18.4480, 73.8180),
  };

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
    _pickupFocus.unfocus();
    _recalcDistance();
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
    _dropFocus.unfocus();
    _recalcDistance();
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
    _addressFocus.unfocus();
    setState(() {});
  }

  LatLng? _lookupKnownLocality(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return null;
    for (final entry in _knownLocalityCoords.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  void _checkAndEstimateDistance() {
    if (!_isDelivery) return;
    if (_pickupLocation == null) {
      final pText = '${_pickupAddrCtrl.text} ${_pickupAreaCtrl.text}'.trim();
      final pLoc = _lookupKnownLocality(pText);
      if (pLoc != null) {
        _pickupLocation = pLoc;
        _location ??= pLoc;
      }
    }
    if (_dropLocation == null) {
      final dText = '${_dropAddrCtrl.text} ${_dropAreaCtrl.text}'.trim();
      final dLoc = _lookupKnownLocality(dText);
      if (dLoc != null) {
        _dropLocation = dLoc;
      }
    }
    _recalcDistance();
  }

  /// Recalculates exact road distance (km) between pickup and drop matching Google Maps,
  /// then auto-fills budget with category- and vehicle-specific distance fare.
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

  /// Show a bottom sheet with the sub-categories of [group] as square grid boxes.
  void _showSubCategorySheet(TaskCategoryGroup group) {
    FocusScope.of(context).unfocus();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (ctx, anim, _, child) {
        final curved =
            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.90, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) {
        final maxH = MediaQuery.of(ctx).size.height - 48;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
              constraints: BoxConstraints(maxWidth: 440, maxHeight: maxH),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Text(group.icon,
                            style: const TextStyle(fontSize: 26)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(group.label,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                              const Text('Select a specific category',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: group.subCategories.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            mainAxisExtent: 68,
                          ),
                          itemBuilder: (_, i) {
                            final c = group.subCategories[i];
                            final sel = _selectedCategory == c.id;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = c.id;
                                  _autoFillDescription();
                                });
                                _recalcDistance();
                                Navigator.pop(ctx);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? const Color(0xFFEEF2FF)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: sel
                                        ? AppColors.primary
                                        : const Color(0xFFE2E8F0),
                                    width: sel ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.04),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: sel
                                            ? Colors.white
                                            : const Color(0xFFF8FAFC),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                          color: sel
                                              ? AppColors.primary
                                                  .withValues(alpha: 0.25)
                                              : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Text(c.icon,
                                          style: const TextStyle(
                                              fontSize: 20)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          c.label,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: sel
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: sel
                                                ? AppColors.primaryDark
                                                : AppColors.dark,
                                            letterSpacing: -0.2,
                                          ),
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                    if (sel) ...[
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        size: 16,
                                        color: AppColors.primary,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Auto-fill description with category-specific prompts/questions.
  /// Only fills if description is empty or still contains the previous template.
  void _autoFillDescription() {
    _compileDescriptionFromForm();
  }

  @override
  void initState() {
    super.initState();
    _savedLocations = StorageService.getSavedLocations();
    _areaCtrl.addListener(_onLocationAreaChanged);
    _pickupAreaCtrl.addListener(_onLocationAreaChanged);
    _dropAreaCtrl.addListener(_onLocationAreaChanged);
    _addressCtrl.addListener(_onLocationAreaChanged);
    _pickupAddrCtrl.addListener(_onLocationAreaChanged);
    _dropAddrCtrl.addListener(_onLocationAreaChanged);
    // Auto-fill description with prompts for the default category on first open
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _autoFillDescription();
      if (!mounted) return;
      // auth reference
      final auth = context.read<AuthProvider>();
    if (!auth.isPosterMode) {
        final switched = await showProfileModeSwitchDialog(
          context,
          targetMode: 'poster',
          title: 'Switch to Poster Profile',
          message:
              'Posting tasks requires a Poster profile. Would you like to switch to Poster mode to post this task?',
          actionLabel: 'Switch to Poster & Continue',
        );
        if (switched != true && mounted) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  void dispose() {
    _areaCtrl.removeListener(_onLocationAreaChanged);
    _pickupAreaCtrl.removeListener(_onLocationAreaChanged);
    _dropAreaCtrl.removeListener(_onLocationAreaChanged);
    _addressCtrl.removeListener(_onLocationAreaChanged);
    _pickupAddrCtrl.removeListener(_onLocationAreaChanged);
    _dropAddrCtrl.removeListener(_onLocationAreaChanged);
    for (final ctrl in _descFormControllers.values) {
      ctrl.dispose();
    }
    for (final fn in _descFormFocusNodes.values) {
      fn.dispose();
    }
    _additionalNotesCtrl.dispose();
    _additionalNotesFocus.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _titleFocus.dispose();
    _descFocus.dispose();
    _budgetFocus.dispose();
    _pickupDebounce?.cancel();
    _dropDebounce?.cancel();
    _addressDebounce?.cancel();
    _pickupFocus.dispose();
    _dropFocus.dispose();
    _addressFocus.dispose();
    _addressCtrl.dispose();
    _flatNameCtrl.dispose();
    _areaCtrl.dispose();
    _pickupAddrCtrl.dispose();
    _pickupFlatCtrl.dispose();
    _pickupAreaCtrl.dispose();
    _dropAddrCtrl.dispose();
    _dropFlatCtrl.dispose();
    _dropAreaCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── Saved Locations helpers ──────────────────────────────────
  void _loadSavedLocations() {
    setState(() => _savedLocations = StorageService.getSavedLocations());
  }

  void _fillFromSaved(Map<String, dynamic> loc) {
    final lat = (loc['lat'] as num?)?.toDouble();
    final lng = (loc['lng'] as num?)?.toDouble();
    setState(() {
      _location = (lat != null && lng != null) ? LatLng(lat, lng) : null;
      _locationLabel = loc['address'] as String?;
      _addressCtrl.text = (loc['address'] as String?) ?? '';
      _flatNameCtrl.text = (loc['flat'] as String?) ?? '';
      _areaCtrl.text = (loc['area'] as String?) ?? '';
      _showSavePrompt = false;
    });
  }

  IconData _iconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('home') || l.contains('house')) return Icons.home_rounded;
    if (l.contains('work') || l.contains('office')) return Icons.work_rounded;
    return Icons.location_on_rounded;
  }

  Future<void> _showSaveDialog() async {
    // Require at least one text field to have content
    final hasText = _addressCtrl.text.trim().isNotEmpty ||
        _flatNameCtrl.text.trim().isNotEmpty ||
        _areaCtrl.text.trim().isNotEmpty;
    if (!hasText) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Please fill in at least the address or area before saving.'),
          duration: Duration(seconds: 2)));
      return;
    }
    final nameCtrl = TextEditingController();
    String selectedType = 'Home';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Save Address',
              style:
                  TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Quick labels:',
                  style: TextStyle(fontSize: 12, color: AppColors.gray)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Home', 'Work', 'Other'].map((t) {
                  final sel = selectedType == t;
                  return GestureDetector(
                    onTap: () => setDlg(() {
                      selectedType = t;
                      if (t != 'Other') nameCtrl.text = t;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.primary.withValues(
                                alpha: sel ? 1.0 : 0.3)),
                      ),
                      child: Text(t,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : AppColors.primary)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address name',
                  hintText: 'e.g. Home, Office, Mom\'s place',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final label =
        nameCtrl.text.trim().isEmpty ? 'Saved' : nameCtrl.text.trim();
    await StorageService.addSavedLocation({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'label': label,
      'address': _addressCtrl.text.trim(),
      'flat': _flatNameCtrl.text.trim(),
      'area': _areaCtrl.text.trim(),
      'lat': _location?.latitude,
      'lng': _location?.longitude,
    });
    _loadSavedLocations();
    setState(() => _showSavePrompt = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('\u201c$label\u201d saved!'),
          duration: const Duration(seconds: 2)));
    }
  }

  // ─── Generic save helper used by pickup / drop ───────────────────────────

  // ─── Long-press options (Edit / Remove) for any saved address chip ────────
  Future<void> _addressOptions(Map<String, dynamic> loc) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(children: [
                const Icon(Icons.bookmark_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(loc['label'] as String? ?? 'Saved',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF1E293B))),
                ),
              ]),
            ),
            if ((loc['address'] as String?)?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(loc['address'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B))),
              ),
            const Divider(height: 20),
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: AppColors.primary),
              title: const Text('Edit address',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger),
              title: const Text('Remove',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      await _editSavedLocation(loc);
    } else if (action == 'delete') {
      await StorageService.deleteSavedLocation(loc['id'] as String);
      _loadSavedLocations();
    }
  }

  Future<void> _editSavedLocation(Map<String, dynamic> loc) async {
    final labelCtrl =
        TextEditingController(text: loc['label'] as String? ?? '');
    final addrCtrl =
        TextEditingController(text: loc['address'] as String? ?? '');
    final flatCtrl =
        TextEditingController(text: loc['flat'] as String? ?? '');
    final areaCtrl =
        TextEditingController(text: loc['area'] as String? ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Edit Address',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'e.g. Home, Office',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addrCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address / Landmark',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: flatCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Flat / House / Building',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: areaCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Area / Sector / Locality',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    await StorageService.addSavedLocation({
      'id': loc['id'],
      'label': labelCtrl.text.trim().isEmpty
          ? 'Saved'
          : labelCtrl.text.trim(),
      'address': addrCtrl.text.trim(),
      'flat': flatCtrl.text.trim(),
      'area': areaCtrl.text.trim(),
      'lat': loc['lat'],
      'lng': loc['lng'],
    });
    _loadSavedLocations();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Address updated!'),
          duration: Duration(seconds: 2)));
    }
  }

  // ─── Generic save helper used by pickup / drop ────────────────────────
  Future<void> _saveAddressEntry({
    required String address,
    required String flat,
    required String area,
    required double? lat,
    required double? lng,
    required VoidCallback onSaved,
  }) async {
    // Require at least one text field to have content
    if (address.isEmpty && flat.isEmpty && area.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Please fill in at least the address or area before saving.'),
          duration: Duration(seconds: 2)));
      return;
    }
    final nameCtrl = TextEditingController();
    String selectedType = 'Home';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Save Address',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Quick labels:',
                  style: TextStyle(fontSize: 12, color: AppColors.gray)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Home', 'Work', 'Other'].map((t) {
                  final sel = selectedType == t;
                  return GestureDetector(
                    onTap: () => setDlg(() {
                      selectedType = t;
                      if (t != 'Other') nameCtrl.text = t;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primary.withValues(alpha: sel ? 1.0 : 0.3)),
                      ),
                      child: Text(t,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : AppColors.primary)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address name',
                  hintText: 'e.g. Home, Office, Mom\'s place',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final label = nameCtrl.text.trim().isEmpty ? 'Saved' : nameCtrl.text.trim();
    await StorageService.addSavedLocation({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'label': label,
      'address': address,
      'flat': flat,
      'area': area,
      'lat': lat,
      'lng': lng,
    });
    _loadSavedLocations();
    onSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('\u201c$label\u201d saved!'),
          duration: const Duration(seconds: 2)));
    }
  }

  void _fillPickupFromSaved(Map<String, dynamic> loc) {
    final lat = (loc['lat'] as num?)?.toDouble();
    final lng = (loc['lng'] as num?)?.toDouble();
    setState(() {
      if (lat != null && lng != null) {
        _pickupLocation = LatLng(lat, lng);
        _location ??= _pickupLocation;
      }
      _pickupAddrCtrl.text = (loc['address'] as String?) ?? '';
      _pickupFlatCtrl.text = (loc['flat'] as String?) ?? '';
      _pickupAreaCtrl.text = (loc['area'] as String?) ?? '';
      _showPickupSavePrompt = false;
    });
    _recalcDistance();
  }

  void _fillDropFromSaved(Map<String, dynamic> loc) {
    final lat = (loc['lat'] as num?)?.toDouble();
    final lng = (loc['lng'] as num?)?.toDouble();
    setState(() {
      if (lat != null && lng != null) _dropLocation = LatLng(lat, lng);
      _dropAddrCtrl.text = (loc['address'] as String?) ?? '';
      _dropFlatCtrl.text = (loc['flat'] as String?) ?? '';
      _dropAreaCtrl.text = (loc['area'] as String?) ?? '';
      _showDropSavePrompt = false;
    });
    _recalcDistance();
  }

  Future<void> _getLocation() async {
    setState(() => _gettingLocation = true);
    final loc = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (loc == null) {
      setState(() => _gettingLocation = false);
      if (!mounted) return;
      // Distinguish: permission denied vs GPS signal unavailable
      final perm = await Geolocator.checkPermission();
      if (!mounted) return;
      final msg = (perm == LocationPermission.denied || perm == LocationPermission.deniedForever)
          ? 'Location permission denied. Please allow in Settings.'
          : 'Unable to get GPS. Make sure location is ON and try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          action: (perm == LocationPermission.deniedForever)
              ? const SnackBarAction(
                  label: 'Settings',
                  onPressed: Geolocator.openAppSettings,
                )
              : null,
        ),
      );
      return;
    }
    setState(() {
      _location = loc;
      _locationLabel = null;
      _gettingLocation = false;
      _showSavePrompt = true; // offer to save
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
          // Auto-fill Area field with subLocality + locality
          // (intentionally removed — area stays empty for user to fill)
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
        _showSavePrompt = true; // offer to save
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
        _showPickupSavePrompt = true;
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
        _showDropSavePrompt = true;
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
          setState(() { _gettingPickupGps = false; _showPickupSavePrompt = true; });
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
          setState(() { _gettingDropGps = false; _showDropSavePrompt = true; });
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
  // ─── Task title validation: ban gibberish + bad/illegal words ──────────────
  static String? _validateTaskTitle(String? value) {
    if (value == null) return 'Min 5 characters';
    final v = value.trim();
    if (v.length < 5) return 'Min 5 characters';

    final lower = v.toLowerCase();

    // 1. Bad / illegal / offensive words
    const badWords = [
      'fuck', 'shit', 'bitch', 'bastard', 'asshole', 'dick', 'pussy',
      'cunt', 'whore', 'slut', 'nigger', 'faggot', 'retard', 'sex',
      'porn', 'nude', 'rape', 'kill', 'murder', 'bomb', 'drug',
      'cocaine', 'heroin', 'weed', 'ganja', 'terrorist', 'jihad',
      'chutiya', 'madarchod', 'bhenchod', 'bhosdike', 'randi',
      'gaandu', 'harami', 'saala', 'kamina', 'kutte',
    ];
    for (final word in badWords) {
      if (lower.contains(word)) {
        return 'Task name contains inappropriate words. Please use a proper title.';
      }
    }

    // 1b. Scam / fraud / crypto / loan keywords — not allowed as task titles
    const scamWords = [
      // Cryptocurrency & Bitcoin scams
      'crypto', 'bitcoin', 'btc', 'usdt', 'ethereum', 'eth',
      'litecoin', 'dogecoin', 'doge', 'nft', 'binance', 'tether',
      'xrp', 'bnb', 'shiba', 'solana', 'altcoin', 'defi', 'web3',
      'blockchain invest', 'coin invest', 'token invest',
      'rug pull', 'crypto doubler', 'recovery agent',
      'airdrop claim', 'airdrop', 'pump and dump', 'pump dump',
      'wallet validation', 'seed phrase', 'mining pool',
      'crypto recovery', 'bitcoin recovery', 'wallet recovery',
      // Loans & financial scams
      'loan', 'earn', 'earning', 'loans', 'instant loan', 'quick loan', 'easy loan',
      'personal loan', 'business loan', 'money lend', 'lending money',
      'no credit check', 'guaranteed approval', 'upfront deposit',
      'payday relief', 'debt erasure', 'pre-approved offer',
      'processing fee', 'pre approved',
      // Fraud / scam indicators
      'fraud', 'scam', 'phishing', 'phishing link', 'ponzi', 'pyramid scheme',
      'mlm', 'cheat', 'cheating', 'black money', 'money double',
      'double money', 'invest now', 'guaranteed return', 'guaranteed profit',
      'guaranteed returns', 'get rich quick', 'easy money', 'fast money',
      'make money fast', 'earn money fast', 'money mule', 'money transfer fraud',
      'advance fee', 'lottery win', 'prize money',
      'spoofed website', 'identity theft', 'impersonation',
      'social engineering', 'malware attachment', 'credential stuffing',
      'account takeover', 'unauthorized charge',
      // High-urgency & manipulation
      'act immediately', 'account suspended', 'legal action',
      'arrest warrant', 'irs penalty', 'compromised ssn', 'secure vault',
      // Cyber scams & hacking
      'hack', 'hacking', 'hacker', 'ddos', 'ransomware', 'spyware',
      'keylogger', 'trojan', 'botnet', 'dark web', 'darkweb',
      'deepweb', 'deep web', 'tor browser', 'exploit kit',
      'zero day', 'remote access tool', 'rat tool',
      'sim swap', 'sim swapping', 'vishing', 'smishing',
      'fake invoice', 'invoice scam', 'business email compromise',
      'tech support scam', 'remote desktop scam',
      // Network marketing & MLM
      'network marketing', 'direct selling', 'downline', 'upline',
      'referral income', 'passive income scheme', 'matrix plan',
      'binary plan', 'chain letter', 'referral chain',
      'join my team', 'work from home scheme', 'be your own boss scheme',
      'unlimited earning', 'residual income scheme',
      // Drugs & narcotics
      'marijuana', 'cannabis', 'hash', 'hashish', 'ganja', 'charas',
      'smack', 'brown sugar', 'opium', 'afeem', 'meth', 'methamphetamine',
      'amphetamine', 'ecstasy', 'mdma', 'lsd', 'acid trip',
      'coke', 'crack cocaine', 'crystal meth', 'ice drug',
      'tramadol', 'ketamine', 'fentanyl', 'xanax dealer',
      'weed dealer', 'drug dealer', 'narcotic', 'narcotics',
      'substance abuse', 'buy weed', 'sell weed', 'buy drugs', 'sell drugs',
    ];
    for (final word in scamWords) {
      if (lower.contains(word)) {
        return 'Task titles related to crypto, loans, fraud, or financial scams are not allowed.';
      }
    }

    // 2. Keyboard gibberish patterns
    const gibberishPatterns = [
      'qwerty', 'asdf', 'zxcv', 'qwer', 'asdfgh', 'zxcvbn',
      'qazwsx', 'aaaa', 'bbbb', 'cccc', 'dddd', 'eeee', 'ffff',
      'gggg', 'hhhh', 'iiii', 'jjjj', 'kkkk', 'llll', 'mmmm',
      'nnnn', 'oooo', 'pppp', 'rrrr', 'ssss', 'tttt', 'uuuu',
      'vvvv', 'wwww', 'xxxx', 'yyyy', 'zzzz', 'abcd', 'abcde',
      '1234', '12345', '123456',
    ];
    for (final p in gibberishPatterns) {
      if (lower.contains(p)) {
        return 'Task name looks like gibberish. Please enter a meaningful title.';
      }
    }

    // 3. Excessive repeated single character (≥4 in a row)
    if (RegExp(r'(.)\1{3,}').hasMatch(lower)) {
      return 'Task name contains repeated characters. Please enter a meaningful title.';
    }

    // 4. Must contain at least one vowel (real words have vowels)
    final lettersOnly = lower.replaceAll(RegExp(r'[^a-z]'), '');
    if (lettersOnly.length >= 5) {
      final vowelCount = lettersOnly.split('').where((c) => 'aeiou'.contains(c)).length;
      final vowelRatio = vowelCount / lettersOnly.length;
      if (vowelRatio < 0.10) {
        return 'Task name does not look like a valid title. Please use real words.';
      }
    }

    return null;
  }

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
    _compileDescriptionFromForm();

    // Always re-check title on every submit click (not relying on form cache)
    final titleErr = _validateTaskTitle(_titleCtrl.text);
    if (titleErr != null) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _titleFocus.requestFocus());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(titleErr),
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    if (!_formKey.currentState!.validate()) {
      // Scroll to top and jump cursor to the first invalid field
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      final missing = <String>[];
      FocusNode? firstInvalidFocus;
      if (_titleCtrl.text.trim().length < 5) {
        missing.add('Task Title');
        firstInvalidFocus ??= _titleFocus;
      }
      if (_descCtrl.text.trim().length < 10) {
        missing.add('Task Details Form (min 10 characters)');
        final prompts = _prompts[_selectedCategory] ?? _prompts['other']!;
        for (final p in prompts) {
          final ctrl = _descFormControllers[p];
          if (ctrl == null || ctrl.text.trim().isEmpty) {
            firstInvalidFocus ??= _getDescQuestionFocus(p);
            break;
          }
        }
      }
      final budget = double.tryParse(_budgetCtrl.text);
      if (budget == null || budget <= 0) {
        missing.add('Budget');
        firstInvalidFocus ??= _budgetFocus;
      }
      if (_isDelivery) {
        if (_pickupAddrCtrl.text.trim().isEmpty) {
          missing.add('Pickup Address');
          firstInvalidFocus ??= _pickupFocus;
        }
        if (_dropAddrCtrl.text.trim().isEmpty) {
          missing.add('Drop Address');
          firstInvalidFocus ??= _dropFocus;
        }
      }
      // Request focus on the first invalid field after next frame
      if (firstInvalidFocus != null) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => firstInvalidFocus!.requestFocus());
      }
      final msg = missing.isEmpty
          ? 'Please fix the highlighted fields before posting.'
          : 'Required: ${missing.join(', ')}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }

    // ── Client-side banned keyword check ────────────────────────────────────
    final bannedResult = _checkBannedContent(_titleCtrl.text, _descCtrl.text);
    if (bannedResult != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(bannedResult),
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

    // auth reference
    final auth = context.read<AuthProvider>();
    if (!auth.isPosterMode) {
      final switched = await showProfileModeSwitchDialog(
        context,
        targetMode: 'poster',
        title: 'Switch to Poster Profile',
        message:
            'Posting tasks requires a Poster profile. Would you like to switch to Poster mode to post this task?',
        actionLabel: 'Switch to Poster & Continue',
      );
      if (switched != true) return;
      if (!mounted) return;
    }
    if (!mounted) return;

    // KYC must be verified to post a task
    // auth reference
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
                if (mounted) context.push('/kyc');
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
    final isDelivery = const {'delivery', 'pickup', 'transport', 'moving'}.contains(_selectedCategory);
    final charge = isDelivery ? Task.serviceChargeForCategory(_selectedCategory).toDouble() : 0.0;
    final posterFee = budget * 0.20;
    final total  = budget + charge + posterFee;

    // Confirm posting — payment is collected AFTER the helper completes the task
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: SingleChildScrollView(
          child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon + Title row
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.rocket_launch_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Post Your Task',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1E293B),
                              letterSpacing: -0.4)),
                      Text('Review before posting',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Info banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E7FF)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: Color(0xFF6366F1)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You only pay after the helper finishes and you verify the work. No upfront charge.',
                        style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF6366F1).withValues(alpha: 0.85),
                            height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TaskPriceBreakdownCard(
                budget: budget,
                serviceCharge: charge,
                posterFee: posterFee,
                totalCost: total,
              ),
              const SizedBox(height: 24),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF4338CA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        icon: const Icon(Icons.rocket_launch_rounded, size: 16),
                        label: const Text('Post Task',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ),
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
      final typed    = _addressCtrl.text.trim();
      final flatName  = _flatNameCtrl.text.trim();
      final area      = _areaCtrl.text.trim();
      final addrParts = <String>[
        if (flatName.isNotEmpty) flatName,
        if (area.isNotEmpty) area,
        if (typed.isNotEmpty) typed,
      ];
      combinedAddress = addrParts.isNotEmpty
          ? addrParts.join(', ')
          : _locationLabel;
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
      if (_isDelivery) ...{
        'vehicle': _selectedCategory == 'delivery' ? _deliveryVehicle : 'auto',
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

    /// Controllers for each question in the description form.
  final Map<String, TextEditingController> _descFormControllers = {};

  /// Focus nodes for each question in the description form.
  final Map<String, FocusNode> _descFormFocusNodes = {};

  /// Controller for optional special instructions / additional notes.
  final _additionalNotesCtrl = TextEditingController();
  final _additionalNotesFocus = FocusNode();

  TextEditingController _getDescQuestionCtrl(String question) {
    return _descFormControllers.putIfAbsent(
      question,
      () => TextEditingController()..addListener(_compileDescriptionFromForm),
    );
  }

  FocusNode _getDescQuestionFocus(String question) {
    return _descFormFocusNodes.putIfAbsent(question, () => FocusNode());
  }

  List<String> _getChipsForQuestion(String q) {
    final cleanQ = q.toLowerCase().replaceAll('?', '').trim();
    for (final entry in _quickChips.entries) {
      if (cleanQ.contains(entry.key)) {
        return entry.value;
      }
    }
    return const [];
  }

  String _getHintForQuestion(String q) {
    final lower = q.toLowerCase();
    if (lower.contains('what') && lower.contains('deliver')) return 'e.g. Documents, food tiffin, small parcel';
    if (lower.contains('pickup point')) return 'e.g. 3rd floor, Flat 301, near elevator';
    if (lower.contains('drop point')) return 'e.g. Office reception, security desk';
    if (lower.contains('item size') || lower.contains('weight')) return 'e.g. Fits in backpack, ~2 kg';
    if (lower.contains('urgent')) return 'e.g. Yes within 1 hour / flexible';
    if (lower.contains('electrical')) return 'e.g. Ceiling fan installation, switchboard sparking';
    if (lower.contains('plumbing')) return 'e.g. Kitchen tap leaking, bathroom drain blocked';
    if (lower.contains('repair')) return 'e.g. Washing machine not draining, AC cooling low';
    if (lower.contains('how many rooms')) return 'e.g. 2 BHK, 1 kitchen, 2 bathrooms';
    if (lower.contains('cuisine') || lower.contains('dishes')) return 'e.g. North Indian: 4 Rotis, Dal, Sabzi';
    if (lower.contains('how many people')) return 'e.g. 2 adults, 1 child';
    if (lower.contains('how many clothes')) return 'e.g. Around 15-20 clothes (daily wear)';
    if (lower.contains('subject')) return 'e.g. Mathematics, Class 10 CBSE';
    if (lower.contains('service do you need')) return 'e.g. WordPress website customization, logo design';
    if (lower.contains('materials needed')) return 'e.g. Plywood provided / helper to bring screws';
    if (lower.contains('colour')) return 'e.g. Off-white emulsion, 1 bedroom wall';
    if (lower.contains('garden')) return 'e.g. Lawn mowing, trimming bushes, watering';
    return 'Type your answer here...';
  }

  void _compileDescriptionFromForm() {
    final prompts = _prompts[_selectedCategory] ?? _prompts['other']!;
    final lines = <String>[];
    for (final p in prompts) {
      final ctrl = _descFormControllers[p];
      final val = ctrl?.text.trim() ?? '';
      if (val.isNotEmpty) {
        lines.add('• $p $val');
      }
    }
    final notes = _additionalNotesCtrl.text.trim();
    if (notes.isNotEmpty) {
      lines.add('Special Instructions: $notes');
    }
    _descCtrl.text = lines.join('\n');
  }

  Widget _buildDescriptionFormSection() {
    final prompts = _prompts[_selectedCategory] ?? _prompts['other']!;
    final categoryLabel = TaskCategory.all
        .firstWhere((c) => c.id == _selectedCategory,
            orElse: () => TaskCategory(id: _selectedCategory, label: _selectedCategory, icon: '📋'))
        .label;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.assignment_outlined,
                      size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Task Details Form',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.dark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                categoryLabel,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Answer these questions so helpers understand your task',
                        style: TextStyle(fontSize: 11, color: AppColors.gray),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Form Body (Form only)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Render each question field
                ...prompts.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final q = entry.value;
                  final ctrl = _getDescQuestionCtrl(q);
                  final fn = _getDescQuestionFocus(q);
                  final chips = _getChipsForQuestion(q);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Question Label with index badge
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE2E8F0),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dark,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                q,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.dark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Question Input
                        TextFormField(
                          controller: ctrl,
                          focusNode: fn,
                          decoration: InputDecoration(
                            hintText: _getHintForQuestion(q),
                            hintStyle: const TextStyle(fontSize: 12, color: AppColors.grayLight),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                          ),
                        ),
                        // Quick suggestion chips if available
                        if (chips.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: chips.map((chipText) {
                              final isSelected = ctrl.text == chipText;
                              return InkWell(
                                onTap: () {
                                  setState(() {
                                    if (ctrl.text == chipText) {
                                      ctrl.clear();
                                    } else {
                                      ctrl.text = chipText;
                                    }
                                    _compileDescriptionFromForm();
                                  });
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                        : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Text(
                                    chipText,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isSelected ? Colors.white : const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  );
                }),

                // Additional notes / special instructions
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notes_rounded, size: 16, color: AppColors.gray),
                        SizedBox(width: 6),
                        Text(
                          'Special Instructions / Other Notes (Optional)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: AppColors.dark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _additionalNotesCtrl,
                      focusNode: _additionalNotesFocus,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Any specific instructions, parking info, access codes, etc.',
                        hintStyle: const TextStyle(fontSize: 12, color: AppColors.grayLight),
                        contentPadding: const EdgeInsets.all(12),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
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

  void _onLocationAreaChanged() {
    if (_isDelivery) {
      _checkAndEstimateDistance();
    }
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

    bool get _isLocationSet {
    if (_isDelivery) {
      if (_calculatedDistanceKm != null && _calculatedDistanceKm! > 0) {
        return true;
      }
      final hasPickup = _pickupLocation != null ||
          _pickupAddrCtrl.text.trim().isNotEmpty ||
          _pickupAreaCtrl.text.trim().isNotEmpty;
      final hasDrop = _dropLocation != null ||
          _dropAddrCtrl.text.trim().isNotEmpty ||
          _dropAreaCtrl.text.trim().isNotEmpty;
      return hasPickup && hasDrop;
    } else {
      return _location != null ||
          (_locationLabel != null && _locationLabel!.trim().isNotEmpty) ||
          _addressCtrl.text.trim().isNotEmpty ||
          _areaCtrl.text.trim().isNotEmpty;
    }
  }

  Widget _buildSuggestedBudgetCard() {
    if (!_isLocationSet) return const SizedBox.shrink();
    final areaCandidate = _isDelivery
        ? (_dropAreaCtrl.text.trim().isNotEmpty
            ? _dropAreaCtrl.text.trim()
            : (_locationLabel ?? _pickupAddrCtrl.text.trim()))
        : (_areaCtrl.text.trim().isNotEmpty
            ? _areaCtrl.text.trim()
            : (_locationLabel ?? _addressCtrl.text.trim()));

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
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
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
                        Flexible(
                          child: Text(
                            '(Typical: ₹${suggestion.minBudget.toInt()}–₹${suggestion.maxBudget.toInt()})',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
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
      appBar: AppBar(title: const Text('Post a Task')),
      body: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              TextFormField(
                controller: _titleCtrl,
                focusNode: _titleFocus,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  hintText: 'e.g. Pick up parcel from Bandra',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: _validateTaskTitle,
              ),
              const SizedBox(height: 14),

  // ── Category picker (hierarchical) ──────────────────────
              const Text('Category',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.dark)),
              const SizedBox(height: 4),
              // Selected category pill
              if (_selectedCategory.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Selected: ${TaskCategory.all.firstWhere((c) => c.id == _selectedCategory, orElse: () => TaskCategory(id: '', label: _selectedCategory, icon: '')).label}',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              // Category search bar
              TextField(
                controller: _categorySearchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search category\u2026',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _categorySearch.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() {
                            _categorySearchCtrl.clear();
                            _categorySearch = '';
                          }),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (v) => setState(() {
                  _categorySearch = v.trim().toLowerCase();
                }),
              ),
              const SizedBox(height: 10),
              // Show search results OR parent category groups
              if (_categorySearch.isNotEmpty) ...[
                // ── Flat search results ───────────────────────────────
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: TaskCategory.all
                      .where((c) => c.label.toLowerCase().contains(_categorySearch) ||
                                    c.id.contains(_categorySearch))
                      .map((c) {
                    final sel = _selectedCategory == c.id;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = c.id;
                          _categorySearchCtrl.clear();
                          _categorySearch = '';
                          _autoFillDescription();
                        });
                        _recalcDistance();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary,
                            width: sel ? 2 : 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(c.icon, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            Text(c.label,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : AppColors.dark)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ] else ...[
                // ── Parent category grid ──────────────────────────────
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: TaskCategoryGroup.all.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.0,
                  ),
                  itemBuilder: (ctx, i) {
                    final group = TaskCategoryGroup.all[i];
                    // Check if current selection belongs to this group
                    final groupActive = group.categoryIds.contains(_selectedCategory);
                    return GestureDetector(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        _showSubCategorySheet(group);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: groupActive ? AppColors.primary : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: groupActive ? AppColors.primary : AppColors.border,
                            width: groupActive ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: groupActive
                                  ? AppColors.primary.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(group.icon, style: const TextStyle(fontSize: 26)),
                            const SizedBox(height: 6),
                            Text(
                              group.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: groupActive ? Colors.white : AppColors.dark,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (groupActive) ...[
                              const SizedBox(height: 3),
                              Text(
                                TaskCategory.all.firstWhere(
                                  (c) => c.id == _selectedCategory,
                                  orElse: () => const TaskCategory(id: '', label: '', icon: ''),
                                ).label,
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 14),

              // ── Delivery Vehicle Selector (Bike vs Rikshaw) ──
              if (_selectedCategory == 'delivery') ...[
                _buildDeliveryVehicleSelector(),
                const SizedBox(height: 14),
              ],

              // Description Form (replaces single raw textarea)
              _buildDescriptionFormSection(),
              const SizedBox(height: 14),

              // Suggested budget card based on category + selected area
              _buildSuggestedBudgetCard(),

              // Budget
              TextFormField(
                controller: _budgetCtrl,
                focusNode: _budgetFocus,
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
                // ── Pickup ─────────────────────────────────────────────
                // Saved chips for pickup
                if (_savedLocations.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Saved:',
                            style: TextStyle(fontSize: 12, color: AppColors.gray, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        ..._savedLocations.map((loc) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => _fillPickupFromSaved(loc),
                            onLongPress: () => _addressOptions(loc),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.09),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_iconForLabel(loc['label'] as String), size: 14, color: AppColors.primary),
                                  const SizedBox(width: 5),
                                  Text(loc['label'] as String, style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // Pickup Address
                TextFormField(
                  controller: _pickupAddrCtrl,
                  focusNode: _pickupFocus,
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
                      style: const TextStyle(color: AppColors.success, fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _pickupFlatCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Pickup: Flat / House / Building name',
                    hintText: 'e.g. Flat 2B, Sunrise Apartments',
                    prefixIcon: Icon(Icons.home_outlined, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _pickupAreaCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Pickup: Area / Sector / Locality',
                    hintText: 'e.g. Baner, Pune',
                    prefixIcon: Icon(Icons.map_outlined, color: AppColors.primary),
                  ),
                ),
                // Save pickup prompt
                if (_showPickupSavePrompt && _pickupLocation != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark_add_outlined, size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Save pickup address for later?', style: TextStyle(fontSize: 12, color: AppColors.primary))),
                        GestureDetector(
                          onTap: () => _saveAddressEntry(
                            address: _pickupAddrCtrl.text.trim(),
                            flat: _pickupFlatCtrl.text.trim(),
                            area: _pickupAreaCtrl.text.trim(),
                            lat: _pickupLocation?.latitude,
                            lng: _pickupLocation?.longitude,
                            onSaved: () => setState(() => _showPickupSavePrompt = false),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                            child: const Text('SAVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() => _showPickupSavePrompt = false),
                          child: const Icon(Icons.close, size: 16, color: AppColors.gray),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // ── Drop ───────────────────────────────────────────────
                // Saved chips for drop
                if (_savedLocations.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Saved:', style: TextStyle(fontSize: 12, color: AppColors.gray, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        ..._savedLocations.map((loc) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => _fillDropFromSaved(loc),
                            onLongPress: () => _addressOptions(loc),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_iconForLabel(loc['label'] as String), size: 14, color: AppColors.danger),
                                  const SizedBox(width: 5),
                                  Text(loc['label'] as String, style: const TextStyle(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // Drop Address
                TextFormField(
                  controller: _dropAddrCtrl,
                  focusNode: _dropFocus,
                  onChanged: _onDropAddrChanged,
                  decoration: InputDecoration(
                    labelText: 'Drop / Delivery Address *',
                    hintText: 'Where to deliver / drop off',
                    prefixIcon: const Icon(Icons.flag, color: AppColors.danger),
                    suffixIcon: _AddressActionButtons(
                      isLoading: _gettingDropGps,
                      accentColor: AppColors.danger,
                      onGps: _getGpsForDrop,
                      onMap: _pickMapForDrop,
                    ),
                    suffixIconConstraints: const BoxConstraints(maxHeight: 48),
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
                const SizedBox(height: 8),
                TextFormField(
                  controller: _dropFlatCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Drop: Flat / House / Building name',
                    hintText: 'e.g. Flat 2B, Sunrise Apartments',
                    prefixIcon: Icon(Icons.home_outlined, color: AppColors.danger),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _dropAreaCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Drop: Area / Sector / Locality',
                    hintText: 'e.g. Baner, Pune',
                    prefixIcon: Icon(Icons.map_outlined, color: AppColors.danger),
                  ),
                ),
                // Save drop prompt
                if (_showDropSavePrompt && _dropLocation != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark_add_outlined, size: 18, color: AppColors.danger),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Save drop address for later?', style: TextStyle(fontSize: 12, color: AppColors.danger))),
                        GestureDetector(
                          onTap: () => _saveAddressEntry(
                            address: _dropAddrCtrl.text.trim(),
                            flat: _dropFlatCtrl.text.trim(),
                            area: _dropAreaCtrl.text.trim(),
                            lat: _dropLocation?.latitude,
                            lng: _dropLocation?.longitude,
                            onSaved: () => setState(() => _showDropSavePrompt = false),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(8)),
                            child: const Text('SAVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() => _showDropSavePrompt = false),
                          child: const Icon(Icons.close, size: 16, color: AppColors.gray),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Distance + minimum price card ────────────────────────
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
                // ── Saved addresses chips ───────────────────────────────
                if (_savedLocations.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Saved:',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.gray,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        ..._savedLocations.map((loc) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => _fillFromSaved(loc),
                                onLongPress: () => _addressOptions(loc),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.09),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.35)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                          _iconForLabel(
                                              loc['label'] as String),
                                          size: 14,
                                          color: AppColors.primary),
                                      const SizedBox(width: 5),
                                      Text(loc['label'] as String,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                // ── Address / Landmark ──────────────────────────────────────
                TextFormField(
                  controller: _addressCtrl,
                  focusNode: _addressFocus,
                  readOnly: false,
                  onChanged: _onAddressChanged,
                  decoration: InputDecoration(
                    labelText: 'Address / Landmark (optional)',
                    hintText: 'Type locality, landmark or address',
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

                // ── Flat / House / Building name ───────────────────────
                const SizedBox(height: 10),
                TextFormField(
                  controller: _flatNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Flat / House / Building name',
                    hintText: 'e.g. Flat 2B, Sunrise Apartments',
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                ),

                // ── Area / Sector / Locality ───────────────────────────
                const SizedBox(height: 10),
                TextFormField(
                  controller: _areaCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Area / Sector / Locality',
                    hintText: 'e.g. Baner, Pune',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                ),

                // ── Save address prompt ────────────────────────────────
                if (_showSavePrompt && _location != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bookmark_add_outlined,
                            size: 18, color: AppColors.success),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Save this address for future tasks?',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.success)),
                        ),
                        GestureDetector(
                          onTap: _showSaveDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('SAVE',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _showSavePrompt = false),
                          child: const Icon(Icons.close,
                              size: 16, color: AppColors.gray),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 14),

              // ── Price breakdown — real-time via ValueListenableBuilder ──
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
