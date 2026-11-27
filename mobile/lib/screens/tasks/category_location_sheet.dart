import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../models/task.dart';
import '../../services/location_search_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/map_location_picker.dart';

/// Category-specific location entering popup card matching the 6 designed variants:
/// - Repair Service (Sky Blue)
/// - Home Service (Mint/Teal)
/// - Grocery & Shopping (Lavender/Purple)
/// - Professional (Vibrant Blue)
/// - Care Services (Rose/Pink)
/// - Other (Royal Blue)
class CategoryLocationSheet extends StatefulWidget {
  final TaskCategoryGroup parentGroup;
  final TaskCategory? subCategory;
  final String? initialAddress;
  final String? initialFlat;
  final String? initialArea;
  final LatLng? initialLocation;
  final String? initialTitle;
  final ValueChanged<Map<String, dynamic>>? onLocationConfirmed;

  const CategoryLocationSheet({
    super.key,
    required this.parentGroup,
    this.subCategory,
    this.initialAddress,
    this.initialFlat,
    this.initialArea,
    this.initialLocation,
    this.initialTitle,
    this.onLocationConfirmed,
  });

  /// Opens the centered popup dialog with a smooth scale-and-fade transition,
  /// identical to DeliveryLocationSheet.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required TaskCategoryGroup parentGroup,
    TaskCategory? subCategory,
    String? initialAddress,
    String? initialFlat,
    String? initialArea,
    LatLng? initialLocation,
    String? initialTitle,
    ValueChanged<Map<String, dynamic>>? onLocationConfirmed,
  }) {
    return showGeneralDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.58),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.90, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: anim,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: CategoryLocationSheet(
          parentGroup: parentGroup,
          subCategory: subCategory,
          initialAddress: initialAddress,
          initialFlat: initialFlat,
          initialArea: initialArea,
          initialLocation: initialLocation,
          initialTitle: initialTitle,
          onLocationConfirmed: onLocationConfirmed,
        ),
      ),
    );
  }

  @override
  State<CategoryLocationSheet> createState() => _CategoryLocationSheetState();
}

class _CategoryLocationSheetState extends State<CategoryLocationSheet> {
  final _addressCtrl = TextEditingController();
  final _flatCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();

  final _addressFocus = FocusNode();

  LatLng? _location;

  Timer? _searchDebounce;
  List<LocationSearchResult> _suggestions = [];
  bool _searching = false;
  bool _gettingGps = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _savedLocations = [];
  String? _selectedSavedLocId;

  @override
  void initState() {
    super.initState();
    _loadSavedLocations();

    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      _addressCtrl.text = widget.initialAddress!;
    }
    if (widget.initialFlat != null && widget.initialFlat!.isNotEmpty) {
      _flatCtrl.text = widget.initialFlat!;
    }
    if (widget.initialArea != null && widget.initialArea!.isNotEmpty) {
      _areaCtrl.text = widget.initialArea!;
    }
    _location = widget.initialLocation;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _addressCtrl.dispose();
    _flatCtrl.dispose();
    _areaCtrl.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  void _loadSavedLocations() {
    final list = StorageService.getSavedLocations();
    if (mounted) {
      setState(() => _savedLocations = list);
    } else {
      _savedLocations = list;
    }
  }

  _CategoryLocationConfig _getConfig() {
    final label = widget.parentGroup.label.toLowerCase();

    if (label.contains('repair')) {
      return const _CategoryLocationConfig(
        title: 'Repair Service',
        subtitle: 'Add the service location for this task',
        breadcrumb: 'Workmate4u › Repair',
        badgeIcon: Icons.build_rounded,
        illustration: 'assets/images/cat_3d_repair.png',
        taskLocationSubtitle: 'Where the technician will visit',
        visitTypeIcon: Icons.home_outlined,
        visitTypeLabel: 'On-Site Visit',
        serviceAddressSubtitle: 'Add the complete service location',
        gradientColors: [Color(0xFFBAE6FD), Color(0xFF60A5FA), Color(0xFF2563EB)],
        primaryColor: Color(0xFF0B63F6),
        accentColor: Color(0xFF2563EB),
      );
    } else if (label.contains('home')) {
      return const _CategoryLocationConfig(
        title: 'Home Service',
        subtitle: 'Add the service location for this task',
        breadcrumb: 'Workmate4u › Home',
        badgeIcon: Icons.home_rounded,
        illustration: 'assets/images/cat_3d_home.png',
        taskLocationSubtitle: 'Where the helper will visit',
        visitTypeIcon: Icons.home_outlined,
        visitTypeLabel: 'On-Site Visit',
        serviceAddressSubtitle: 'Add the complete service location',
        gradientColors: [Color(0xFFA7F3D0), Color(0xFF34D399), Color(0xFF059669)],
        primaryColor: Color(0xFF059669),
        accentColor: Color(0xFF10B981),
      );
    } else if (label.contains('grocery') || label.contains('shopping')) {
      return const _CategoryLocationConfig(
        title: 'Grocery & Shopping',
        subtitle: 'Add the service location for this task',
        breadcrumb: 'Workmate4u › Grocery & Shopping',
        badgeIcon: Icons.shopping_cart_rounded,
        illustration: 'assets/images/cat_3d_shopping.png',
        taskLocationSubtitle: 'Where the helper will shop or deliver',
        visitTypeIcon: Icons.shopping_bag_outlined,
        visitTypeLabel: 'Shop & Deliver',
        serviceAddressSubtitle: 'Add the complete delivery location',
        gradientColors: [Color(0xFFEDE9FE), Color(0xFFA78BFA), Color(0xFF7C3AED)],
        primaryColor: Color(0xFF7C3AED),
        accentColor: Color(0xFF8B5CF6),
      );
    } else if (label.contains('professional')) {
      return const _CategoryLocationConfig(
        title: 'Professional',
        subtitle: 'Add the service location for this task',
        breadcrumb: 'Workmate4u › Professional',
        badgeIcon: Icons.work_rounded,
        illustration: 'assets/images/cat_3d_professional.png',
        taskLocationSubtitle: 'Where the professional will work',
        visitTypeIcon: Icons.laptop_mac_outlined,
        visitTypeLabel: 'On-Site Visit',
        serviceAddressSubtitle: 'Add the complete service location',
        gradientColors: [Color(0xFF93C5FD), Color(0xFF3B82F6), Color(0xFF1D4ED8)],
        primaryColor: Color(0xFF1D4ED8),
        accentColor: Color(0xFF2563EB),
      );
    } else if (label.contains('care')) {
      return const _CategoryLocationConfig(
        title: 'Care Services',
        subtitle: 'Add the service location for this task',
        breadcrumb: 'Workmate4u › Care Services',
        badgeIcon: Icons.favorite_rounded,
        illustration: 'assets/images/cat_3d_care.png',
        taskLocationSubtitle: 'Where the caregiver will visit',
        visitTypeIcon: Icons.home_outlined,
        visitTypeLabel: 'At Home Visit',
        serviceAddressSubtitle: 'Add the complete service location',
        gradientColors: [Color(0xFFFCE7F3), Color(0xFFF472B6), Color(0xFFDB2777)],
        primaryColor: Color(0xFFDB2777),
        accentColor: Color(0xFFEC4899),
      );
    } else {
      // Other
      return const _CategoryLocationConfig(
        title: 'Other',
        subtitle: 'Post a custom task or a service not listed in other categories',
        breadcrumb: 'Workmate4u › Other',
        badgeIcon: Icons.assignment_rounded,
        illustration: 'assets/images/cat_3d_other_skyline.png',
        taskLocationSubtitle: 'Where the helper will visit',
        visitTypeIcon: Icons.location_on_outlined,
        visitTypeLabel: 'On-Site Visit',
        serviceAddressSubtitle: 'Add the complete service location',
        gradientColors: [Color(0xFFBFDBFE), Color(0xFF60A5FA), Color(0xFF2563EB)],
        primaryColor: Color(0xFF0B63F6),
        accentColor: Color(0xFF2563EB),
      );
    }
  }

  void _onAddressChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      if (_suggestions.isNotEmpty) {
        setState(() => _suggestions = []);
      }
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _searching = true);
      final results = await LocationSearchService.search(query);
      if (mounted) {
        setState(() {
          _suggestions = results;
          _searching = false;
        });
      }
    });
  }

  void _selectSuggestion(LocationSearchResult result) {
    setState(() {
      _addressCtrl.text = result.fullAddress;
      _location = result.toLatLng();
      _suggestions = [];
      _selectedSavedLocId = null;
      _errorMessage = null;
    });
    _addressFocus.unfocus();
  }

  Future<void> _fetchCurrentGps() async {
    setState(() => _gettingGps = true);
    try {
      final loc = await LocationService.getCurrentLocation();
      if (!mounted) return;
      if (loc == null) {
        setState(() => _gettingGps = false);
        _showSnack('Could not fetch GPS. Please enable location permissions.');
        return;
      }
      _location = loc;
      _selectedSavedLocId = null;
      try {
        final places = await placemarkFromCoordinates(loc.latitude, loc.longitude)
            .timeout(const Duration(seconds: 6));
        if (mounted && places.isNotEmpty) {
          final p = places.first;
          final addr = [p.name, p.subLocality, p.locality, p.administrativeArea]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
          _addressCtrl.text = addr.isNotEmpty
              ? addr
              : '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';
        } else {
          _addressCtrl.text =
              'Current Location (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
        }
      } catch (_) {
        _addressCtrl.text =
            'Current Location (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
      }
      setState(() {
        _gettingGps = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (mounted) setState(() => _gettingGps = false);
    }
  }

  Future<void> _pickOnMap() async {
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
        _selectedSavedLocId = null;
        _location = result['location'] as LatLng?;
        if (addr != null && addr.isNotEmpty) _addressCtrl.text = addr;
        _errorMessage = null;
      });
    }
  }

  void _showSavedLocationsModal() {
    if (_savedLocations.isEmpty) {
      _showSnack('No saved locations found. Use "Save Location" to add one.');
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose Saved Location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 12),
              ..._savedLocations.map((loc) {
                final label = loc['label']?.toString() ?? 'Saved Address';
                final addr = loc['address']?.toString() ?? '';
                final flat = loc['flat']?.toString() ?? '';
                final area = loc['area']?.toString() ?? '';
                final lat = (loc['lat'] as num?)?.toDouble();
                final lng = (loc['lng'] as num?)?.toDouble();

                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.bookmark_rounded, color: Color(0xFF2563EB), size: 20),
                  ),
                  title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text(
                    addr,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedSavedLocId = loc['id']?.toString();
                      _addressCtrl.text = addr;
                      if (flat.isNotEmpty) _flatCtrl.text = flat;
                      if (area.isNotEmpty) _areaCtrl.text = area;
                      if (lat != null && lng != null) {
                        _location = LatLng(lat, lng);
                      }
                      _errorMessage = null;
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

  Future<void> _openQuickSaveDialog() async {
    final currentAddr = _addressCtrl.text.trim();
    final currentFlat = _flatCtrl.text.trim();
    final currentArea = _areaCtrl.text.trim();

    final addrInput = TextEditingController(text: currentAddr);
    String selectedLabel = 'Home';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Save Address', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: ['Home', 'Work', 'Other'].map((type) {
                      final isSel = selectedLabel == type;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
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
                        ),
                      );
                    }).toList(),
                  ),
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
                  'flat': currentFlat,
                  'area': currentArea,
                  'lat': _location?.latitude,
                  'lng': _location?.longitude,
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
      _showSnack('Address saved successfully!');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _confirmLocation() {
    final addr = _addressCtrl.text.trim();
    if (addr.isEmpty) {
      setState(() => _errorMessage = 'Please enter an address or pick from map/GPS.');
      return;
    }

    final flat = _flatCtrl.text.trim();
    final area = _areaCtrl.text.trim();
    final full = [if (flat.isNotEmpty) flat, addr, if (area.isNotEmpty) area].join(', ');

    final locationData = <String, dynamic>{
      'address': full,
      'landmark': addr,
      'flat': flat,
      'area': area,
      'location': _location,
      'lat': _location?.latitude,
      'lng': _location?.longitude,
      'parentGroup': widget.parentGroup.label,
      'categoryId': widget.subCategory?.id ?? widget.parentGroup.categoryIds.first,
      'categoryLabel': widget.subCategory?.label ?? widget.parentGroup.label,
      'title': widget.initialTitle,
    };

    widget.onLocationConfirmed?.call(locationData);
    Navigator.of(context).pop(locationData);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _getConfig();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Top Illustrated Header ──────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: cfg.gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Background 3D Illustration on right
                    Positioned(
                      right: 0,
                      top: 10,
                      bottom: 0,
                      child: Image.asset(
                        cfg.illustration,
                        width: 120,
                        height: 100,
                        fit: BoxFit.contain,
                        alignment: Alignment.centerRight,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),

                    // Top Bar (Breadcrumb Pill + Close Button)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Breadcrumb Pill
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(cfg.badgeIcon, size: 14, color: cfg.primaryColor),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        cfg.breadcrumb,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: cfg.primaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Close Button (X)
                            InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF0F172A)),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Title
                        Text(
                          cfg.title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Subtitle
                        SizedBox(
                          width: MediaQuery.of(context).size.width * 0.52,
                          child: Text(
                            cfg.subtitle,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF334155),
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Scrollable Form Body ────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Task Location Row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: cfg.primaryColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.location_on_rounded, color: cfg.primaryColor, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Task Location',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    cfg.taskLocationSubtitle,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Color(0xFF64748B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: cfg.primaryColor.withValues(alpha: 0.3)),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(cfg.visitTypeIcon, size: 13, color: cfg.primaryColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        cfg.visitTypeLabel,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: cfg.primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 2. Service Address Header Row
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cfg.primaryColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.home_outlined, color: cfg.primaryColor, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Service Address',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  cfg.serviceAddressSubtitle,
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Save Location Button (Wrapped to prevent any horizontal overflow)
                          Flexible(
                            child: InkWell(
                              onTap: _openQuickSaveDialog,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: cfg.primaryColor.withValues(alpha: 0.35)),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.bookmark_outline_rounded, size: 13, color: cfg.primaryColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Save Location',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: cfg.primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // 3. Saved Locations Dropdown Field
                      InkWell(
                        onTap: _showSavedLocationsModal,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.bookmark_outline_rounded, color: Color(0xFF64748B), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'SAVED LOCATIONS',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF94A3B8),
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      _selectedSavedLocId != null
                                          ? _savedLocations.firstWhere(
                                              (l) => l['id']?.toString() == _selectedSavedLocId,
                                              orElse: () => {'label': 'Saved Location'},
                                            )['label']?.toString() ?? 'Choose from Home, Work, Other'
                                          : 'Choose from Home, Work, Other',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E293B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF64748B), size: 20),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 4. Address / Landmark * Input + GPS & Map Companion Buttons
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12, right: 8),
                                    child: Icon(Icons.place_rounded, color: cfg.primaryColor, size: 20),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: _addressCtrl,
                                      focusNode: _addressFocus,
                                      onChanged: _onAddressChanged,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF1E293B),
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: 'Address / Landmark *',
                                        hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w400),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        errorBorder: InputBorder.none,
                                        filled: false,
                                        fillColor: Colors.transparent,
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // GPS Button (Square companion button outside input)
                          InkWell(
                            onTap: _gettingGps ? null : _fetchCurrentGps,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Center(
                                child: _gettingGps
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: cfg.primaryColor),
                                      )
                                    : Icon(Icons.my_location_rounded, color: cfg.primaryColor, size: 20),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Map Button (Square companion button outside input)
                          InkWell(
                            onTap: _pickOnMap,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: Center(
                                child: Icon(Icons.map_outlined, color: cfg.primaryColor, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Autocomplete Suggestions Dropdown
                      if (_searching)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      else if (_suggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _suggestions.length > 4 ? 4 : _suggestions.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            itemBuilder: (_, i) {
                              final item = _suggestions[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(Icons.place_outlined, size: 16, color: cfg.primaryColor),
                                title: Text(item.fullAddress, style: const TextStyle(fontSize: 12.5)),
                                onTap: () => _selectSuggestion(item),
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 12),

                      // 5. Flat / House / Building name (Optional) Input
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 12, right: 8),
                              child: Icon(Icons.home_work_outlined, color: Color(0xFF64748B), size: 20),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _flatCtrl,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1E293B),
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Flat / House / Building name (Optional)',
                                  hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w400),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 6. Area / Sector / Locality Input
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(left: 12, right: 8),
                              child: Icon(Icons.map_outlined, color: Color(0xFF64748B), size: 20),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _areaCtrl,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1E293B),
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Area / Sector / Locality',
                                  hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w400),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  filled: false,
                                  fillColor: Colors.transparent,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // 7. Confirm Location -> Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _confirmLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cfg.primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Confirm Location',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryLocationConfig {
  final String title;
  final String subtitle;
  final String breadcrumb;
  final IconData badgeIcon;
  final String illustration;
  final String taskLocationSubtitle;
  final IconData visitTypeIcon;
  final String visitTypeLabel;
  final String serviceAddressSubtitle;
  final List<Color> gradientColors;
  final Color primaryColor;
  final Color accentColor;

  const _CategoryLocationConfig({
    required this.title,
    required this.subtitle,
    required this.breadcrumb,
    required this.badgeIcon,
    required this.illustration,
    required this.taskLocationSubtitle,
    required this.visitTypeIcon,
    required this.visitTypeLabel,
    required this.serviceAddressSubtitle,
    required this.gradientColors,
    required this.primaryColor,
    required this.accentColor,
  });
}
