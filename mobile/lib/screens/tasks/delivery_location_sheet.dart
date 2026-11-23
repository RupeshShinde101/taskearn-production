import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../services/location_search_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/location_suggestions_dropdown.dart';
import '../../widgets/map_location_picker.dart';
import 'vehicle_selection_screen.dart';

/// Centered popup dialog for Pickup & Drop Location input in "Delivery and Transport".
///
/// Designed to match Image 1:
/// - Green pin for Pickup, Red waving flag for Drop.
/// - Detailed modern sedan car traveling on a curved dashed route.
/// - Ticket-style side notches and dashed divider.
/// - Two square action buttons per row: [GPS Locator] and [Map Picker].
/// - Dedicated input boxes below each location for exact details (Flat / House no. / Landmark).
/// - Smooth scale-and-fade popup dialog presentation (no bottom-sheet slide).
class DeliveryLocationSheet extends StatefulWidget {
  final String? initialPickupAddress;
  final LatLng? initialPickupLocation;
  final String? initialDropAddress;
  final LatLng? initialDropLocation;
  final String? initialTitle;

  const DeliveryLocationSheet({
    super.key,
    this.initialPickupAddress,
    this.initialPickupLocation,
    this.initialDropAddress,
    this.initialDropLocation,
    this.initialTitle,
  });

  /// Opens the centered popup dialog with a smooth scale-and-fade transition.
  static Future<void> show(
    BuildContext context, {
    String? initialPickupAddress,
    LatLng? initialPickupLocation,
    String? initialDropAddress,
    LatLng? initialDropLocation,
    String? initialTitle,
  }) {
    return showGeneralDialog<void>(
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
        child: DeliveryLocationSheet(
          initialPickupAddress: initialPickupAddress,
          initialPickupLocation: initialPickupLocation,
          initialDropAddress: initialDropAddress,
          initialDropLocation: initialDropLocation,
          initialTitle: initialTitle,
        ),
      ),
    );
  }

  @override
  State<DeliveryLocationSheet> createState() => _DeliveryLocationSheetState();
}

class _DeliveryLocationSheetState extends State<DeliveryLocationSheet> {
  final _pickupCtrl = TextEditingController();
  final _pickupDetailCtrl = TextEditingController();
  final _dropCtrl = TextEditingController();
  final _dropDetailCtrl = TextEditingController();

  final _pickupFocus = FocusNode();
  final _dropFocus = FocusNode();

  LatLng? _pickupLocation;
  LatLng? _dropLocation;

  Timer? _pickupDebounce;
  Timer? _dropDebounce;

  List<LocationSearchResult> _pickupSuggestions = [];
  List<LocationSearchResult> _dropSuggestions = [];

  bool _searchingPickup = false;
  bool _searchingDrop = false;

  bool _gettingPickupGps = false;
  bool _gettingDropGps = false;

  bool _calculatingRoute = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _savedLocations = [];
  String? _selectedPickupSavedLocId;
  String? _selectedDropSavedLocId;

  @override
  void initState() {
    super.initState();
    _loadSavedLocations();
    if (widget.initialPickupAddress != null && widget.initialPickupAddress!.isNotEmpty) {
      _pickupCtrl.text = widget.initialPickupAddress!;
    }
    _pickupLocation = widget.initialPickupLocation;

    if (widget.initialDropAddress != null && widget.initialDropAddress!.isNotEmpty) {
      _dropCtrl.text = widget.initialDropAddress!;
    }
    _dropLocation = widget.initialDropLocation;
  }

  void _loadSavedLocations() {
    final list = StorageService.getSavedLocations();
    if (mounted) {
      setState(() => _savedLocations = list);
    } else {
      _savedLocations = list;
    }
  }

  IconData _iconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('home')) return Icons.home_rounded;
    if (l.contains('work') || l.contains('office')) return Icons.work_rounded;
    return Icons.location_on_rounded;
  }

  Color _colorForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('home')) return const Color(0xFF2563EB);
    if (l.contains('work') || l.contains('office')) return const Color(0xFF0D9488);
    return const Color(0xFFE11D48);
  }

  bool _isAddressSaved(String address) {
    final clean = address.trim().toLowerCase();
    if (clean.isEmpty) return false;
    return _savedLocations.any((l) => (l['address'] as String? ?? '').trim().toLowerCase() == clean);
  }

  void _selectSavedLocation(Map<String, dynamic> loc, {required bool isPickup}) {
    final id = loc['id']?.toString();
    final addr = loc['address'] as String? ?? '';
    final flat = loc['flat'] as String? ?? '';
    final lat = (loc['lat'] as num?)?.toDouble();
    final lng = (loc['lng'] as num?)?.toDouble();

    setState(() {
      if (isPickup) {
        _selectedPickupSavedLocId = id;
        _pickupCtrl.text = addr;
        _pickupDetailCtrl.text = flat;
        if (lat != null && lng != null) {
          _pickupLocation = LatLng(lat, lng);
        }
        _pickupSuggestions = [];
        _pickupFocus.unfocus();
      } else {
        _selectedDropSavedLocId = id;
        _dropCtrl.text = addr;
        _dropDetailCtrl.text = flat;
        if (lat != null && lng != null) {
          _dropLocation = LatLng(lat, lng);
        }
        _dropSuggestions = [];
        _dropFocus.unfocus();
      }
      _errorMessage = null;
    });

    if (lat == null || lng == null) {
      if (addr.isNotEmpty) {
        LocationSearchService.geocodeAddress(addr).then((coords) {
          if (coords != null && mounted) {
            setState(() {
              if (isPickup) {
                _pickupLocation = coords;
              } else {
                _dropLocation = coords;
              }
            });
          }
        });
      }
    }
  }

  void _clearSavedLocationSelection({required bool isPickup}) {
    setState(() {
      if (isPickup) {
        _selectedPickupSavedLocId = null;
      } else {
        _selectedDropSavedLocId = null;
      }
    });
  }

  Future<void> _openSaveLocationDialog({required bool isPickup}) async {
    final currentAddr = isPickup ? _pickupCtrl.text.trim() : _dropCtrl.text.trim();
    final currentDetail = isPickup ? _pickupDetailCtrl.text.trim() : _dropDetailCtrl.text.trim();

    final addrCtrl = TextEditingController(text: currentAddr);
    final detailCtrl = TextEditingController(text: currentDetail);
    String selectedType = 'Home';
    final nameCtrl = TextEditingController(text: 'Home');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bookmark_rounded, color: Color(0xFF2563EB), size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                isPickup ? 'Save Pickup Location' : 'Save Drop Location',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Label as:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['Home', 'Work', 'Other'].map((t) {
                    final sel = selectedType == t;
                    final icon = t == 'Home'
                        ? Icons.home_rounded
                        : (t == 'Work' ? Icons.work_rounded : Icons.location_on_rounded);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () {
                            setDlgState(() {
                              selectedType = t;
                              if (t != 'Other') {
                                nameCtrl.text = t;
                              } else if (nameCtrl.text == 'Home' || nameCtrl.text == 'Work') {
                                nameCtrl.clear();
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: sel ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(icon, size: 14, color: sel ? Colors.white : const Color(0xFF475569)),
                                const SizedBox(width: 4),
                                Text(
                                  t,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: sel ? Colors.white : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Address Name',
                    labelStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    hintText: selectedType == 'Other' ? 'e.g. Warehouse, Gym, Mom\'s' : selectedType,
                    hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.label_outline_rounded, size: 18, color: Color(0xFF64748B)),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addrCtrl,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Address',
                    labelStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    hintText: 'Enter complete address...',
                    hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 18),
                      child: Icon(Icons.place_outlined, size: 18, color: Color(0xFF64748B)),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: detailCtrl,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    labelText: 'Flat / Building / Landmark (Optional)',
                    labelStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    hintText: 'e.g. Flat 402, B Wing, Near Metro',
                    hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.apartment_rounded, size: 18, color: Color(0xFF64748B)),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () {
                if (addrCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              ),
              child: const Text('Save Location', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;
    final label = nameCtrl.text.trim().isEmpty ? selectedType : nameCtrl.text.trim();
    final finalAddr = addrCtrl.text.trim();
    final finalDetail = detailCtrl.text.trim();

    if (isPickup) {
      _pickupCtrl.text = finalAddr;
      _pickupDetailCtrl.text = finalDetail;
    } else {
      _dropCtrl.text = finalAddr;
      _dropDetailCtrl.text = finalDetail;
    }

    LatLng? coords = isPickup ? _pickupLocation : _dropLocation;
    if (coords == null && finalAddr.isNotEmpty) {
      try {
        final geocoded = await LocationSearchService.geocodeAddress(finalAddr);
        if (geocoded != null) {
          coords = geocoded;
          if (isPickup) {
            _pickupLocation = coords;
          } else {
            _dropLocation = coords;
          }
        }
      } catch (_) {}
    }

    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newLoc = {
      'id': newId,
      'label': label,
      'address': finalAddr,
      'flat': finalDetail,
      'area': '',
      'lat': coords?.latitude,
      'lng': coords?.longitude,
    };

    await StorageService.addSavedLocation(newLoc);
    _loadSavedLocations();
    if (mounted) {
      setState(() {
        if (isPickup) {
          _selectedPickupSavedLocId = newId;
        } else {
          _selectedDropSavedLocId = newId;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('“$label” saved to locations!'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF0F1E36),
        ),
      );
    }
  }

  void _showManageSavedLocationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Manage Saved Locations',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Select or remove your saved addresses',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: _savedLocations.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text('No saved locations', style: TextStyle(color: Color(0xFF94A3B8))),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _savedLocations.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, idx) {
                            final loc = _savedLocations[idx];
                            final id = loc['id']?.toString() ?? '';
                            final label = loc['label'] as String? ?? 'Saved';
                            final addr = loc['address'] as String? ?? '';
                            final flat = loc['flat'] as String?;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _colorForLabel(label).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(_iconForLabel(label), size: 18, color: _colorForLabel(label)),
                              ),
                              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              subtitle: Text(
                                [if (flat != null && flat.isNotEmpty) flat, addr].join(', '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                                onPressed: () async {
                                  await StorageService.deleteSavedLocation(id);
                                  _loadSavedLocations();
                                  setSheetState(() {});
                                  if (mounted) setState(() {});
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSavedLocationsDropdown({required bool isPickup}) {
    final selectedId = isPickup ? _selectedPickupSavedLocId : _selectedDropSavedLocId;
    Map<String, dynamic>? selectedLoc;
    if (selectedId != null) {
      try {
        selectedLoc = _savedLocations.firstWhere((l) => l['id']?.toString() == selectedId);
      } catch (_) {}
    }
    final hasSaved = _savedLocations.isNotEmpty;

    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Saved Locations',
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        elevation: 6,
        color: Colors.white,
        offset: const Offset(0, 6),
        onSelected: (val) async {
          if (val == '__save_new__') {
            await _openSaveLocationDialog(isPickup: isPickup);
          } else if (val == '__manage__') {
            _showManageSavedLocationsSheet();
          } else {
            try {
              final loc = _savedLocations.firstWhere((l) => l['id']?.toString() == val);
              _selectSavedLocation(loc, isPickup: isPickup);
            } catch (_) {}
          }
        },
        itemBuilder: (context) {
          final List<PopupMenuEntry<String>> items = [];

          // Header
          items.add(
            const PopupMenuItem<String>(
              enabled: false,
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.bookmark_rounded, size: 15, color: Color(0xFF2563EB)),
                  SizedBox(width: 8),
                  Text(
                    'SAVED LOCATIONS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          );
          items.add(const PopupMenuDivider(height: 1));

          if (!hasSaved) {
            items.add(
              const PopupMenuItem<String>(
                enabled: false,
                height: 44,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    'No saved locations yet.\nTap below to save current address.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                  ),
                ),
              ),
            );
          } else {
            for (final loc in _savedLocations) {
              final id = loc['id']?.toString() ?? '';
              final label = loc['label'] as String? ?? 'Saved';
              final addr = loc['address'] as String? ?? '';
              final isSelected = selectedLoc != null && selectedLoc['id']?.toString() == id;

              final icon = _iconForLabel(label);
              final iconColor = _colorForLabel(label);

              items.add(
                PopupMenuItem<String>(
                  value: id,
                  height: 48,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, size: 16, color: iconColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF334155),
                              ),
                            ),
                            if (addr.isNotEmpty)
                              Text(
                                addr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF16A34A)),
                    ],
                  ),
                ),
              );
            }
          }

          items.add(const PopupMenuDivider(height: 1));

          // Save current address action
          items.add(
            PopupMenuItem<String>(
              value: '__save_new__',
              height: 44,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.add_location_alt_rounded, size: 16, color: Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '+ Save Address (Home, Work, Other)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );

          if (hasSaved) {
            items.add(
              PopupMenuItem<String>(
                value: '__manage__',
                height: 40,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.settings_outlined, size: 15, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Manage Saved Locations...',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return items;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selectedLoc != null ? const Color(0xFFF8FAFC) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selectedLoc != null ? const Color(0xFF93C5FD) : const Color(0xFFCBD5E1),
              width: selectedLoc != null ? 1.3 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selectedLoc != null
                    ? _iconForLabel(selectedLoc['label'] as String? ?? 'Other')
                    : Icons.bookmark_outline_rounded,
                size: 18,
                color: selectedLoc != null ? const Color(0xFF2563EB) : const Color(0xFF475569),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            selectedLoc != null ? 'SAVED LOCATION' : 'SAVED LOCATIONS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF64748B),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                        if (selectedLoc != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Text(
                                selectedLoc['label'] as String? ?? 'Saved',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selectedLoc != null
                          ? (selectedLoc['address'] as String? ?? selectedLoc['label'] as String? ?? '')
                          : (hasSaved
                              ? 'Choose from Home, Work, Other'
                              : 'Tap to save delivery location'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selectedLoc != null ? FontWeight.w700 : FontWeight.w500,
                        color: selectedLoc != null ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (selectedLoc != null)
                GestureDetector(
                  onTap: () {
                    _clearSavedLocationSelection(isPickup: isPickup);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF64748B)),
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down_rounded, size: 22, color: Color(0xFF475569)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pickupDebounce?.cancel();
    _dropDebounce?.cancel();
    _pickupCtrl.dispose();
    _pickupDetailCtrl.dispose();
    _dropCtrl.dispose();
    _dropDetailCtrl.dispose();
    _pickupFocus.dispose();
    _dropFocus.dispose();
    super.dispose();
  }

  void _onPickupChanged(String query) {
    _pickupDebounce?.cancel();
    if (_selectedPickupSavedLocId != null) {
      setState(() => _selectedPickupSavedLocId = null);
    }
    final q = query.trim();
    if (q.length < 2) {
      setState(() {
        _pickupSuggestions = [];
        _searchingPickup = false;
        if (q.isEmpty) _pickupLocation = null;
      });
      return;
    }
    setState(() => _searchingPickup = true);
    _pickupDebounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await LocationSearchService.search(q, userLocation: _pickupLocation);
        if (mounted) {
          setState(() {
            _pickupSuggestions = results;
            _searchingPickup = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _searchingPickup = false);
      }
    });
  }

  void _onDropChanged(String query) {
    _dropDebounce?.cancel();
    if (_selectedDropSavedLocId != null) {
      setState(() => _selectedDropSavedLocId = null);
    }
    final q = query.trim();
    if (q.length < 2) {
      setState(() {
        _dropSuggestions = [];
        _searchingDrop = false;
        if (q.isEmpty) _dropLocation = null;
      });
      return;
    }
    setState(() => _searchingDrop = true);
    _dropDebounce = Timer(const Duration(milliseconds: 280), () async {
      try {
        final results = await LocationSearchService.search(q, userLocation: _dropLocation ?? _pickupLocation);
        if (mounted) {
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

  void _selectPickupSuggestion(LocationSearchResult result) {
    _pickupCtrl.text = result.fullAddress;
    _pickupLocation = result.toLatLng();
    setState(() {
      _selectedPickupSavedLocId = null;
      _pickupSuggestions = [];
      _searchingPickup = false;
      _errorMessage = null;
    });
    _pickupFocus.unfocus();
  }

  void _selectDropSuggestion(LocationSearchResult result) {
    _dropCtrl.text = result.fullAddress;
    _dropLocation = result.toLatLng();
    setState(() {
      _selectedDropSavedLocId = null;
      _dropSuggestions = [];
      _searchingDrop = false;
      _errorMessage = null;
    });
    _dropFocus.unfocus();
  }

  Future<void> _getGpsForPickup() async {
    setState(() => _gettingPickupGps = true);
    try {
      final loc = await LocationService.getCurrentLocation();
      if (!mounted) return;
      if (loc == null) {
        setState(() => _gettingPickupGps = false);
        _showSnack('Could not fetch GPS. Please enable location permissions.');
        return;
      }
      _pickupLocation = loc;
      _selectedPickupSavedLocId = null;
      try {
        final places = await placemarkFromCoordinates(loc.latitude, loc.longitude).timeout(const Duration(seconds: 6));
        if (mounted && places.isNotEmpty) {
          final p = places.first;
          final addr = [p.name, p.subLocality, p.locality, p.administrativeArea]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
          _pickupCtrl.text = addr.isNotEmpty ? addr : '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';
        } else {
          _pickupCtrl.text = 'Current Location (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
        }
      } catch (_) {
        _pickupCtrl.text = 'Current Location (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
      }
      setState(() {
        _gettingPickupGps = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (mounted) setState(() => _gettingPickupGps = false);
    }
  }

  Future<void> _getGpsForDrop() async {
    setState(() => _gettingDropGps = true);
    try {
      final loc = await LocationService.getCurrentLocation();
      if (!mounted) return;
      if (loc == null) {
        setState(() => _gettingDropGps = false);
        _showSnack('Could not fetch GPS. Please enable location permissions.');
        return;
      }
      _dropLocation = loc;
      _selectedDropSavedLocId = null;
      try {
        final places = await placemarkFromCoordinates(loc.latitude, loc.longitude).timeout(const Duration(seconds: 6));
        if (mounted && places.isNotEmpty) {
          final p = places.first;
          final addr = [p.name, p.subLocality, p.locality, p.administrativeArea]
              .where((s) => s != null && s.isNotEmpty)
              .join(', ');
          _dropCtrl.text = addr.isNotEmpty ? addr : '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';
        } else {
          _dropCtrl.text = 'Current Location (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
        }
      } catch (_) {
        _dropCtrl.text = 'Current Location (${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)})';
      }
      setState(() {
        _gettingDropGps = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (mounted) setState(() => _gettingDropGps = false);
    }
  }

  Future<void> _pickMapForPickup() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(initialLocation: _pickupLocation),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      final addr = result['address'] as String?;
      setState(() {
        _selectedPickupSavedLocId = null;
        _pickupLocation = result['location'] as LatLng?;
        if (addr != null && addr.isNotEmpty) _pickupCtrl.text = addr;
        _errorMessage = null;
      });
    }
  }

  Future<void> _pickMapForDrop() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapLocationPicker(initialLocation: _dropLocation ?? _pickupLocation),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      final addr = result['address'] as String?;
      setState(() {
        _selectedDropSavedLocId = null;
        _dropLocation = result['location'] as LatLng?;
        if (addr != null && addr.isNotEmpty) _dropCtrl.text = addr;
        _errorMessage = null;
      });
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _confirmAndProceed() async {
    final pickupText = _pickupCtrl.text.trim();
    final dropText = _dropCtrl.text.trim();
    final pickupDetail = _pickupDetailCtrl.text.trim();
    final dropDetail = _dropDetailCtrl.text.trim();

    if (pickupText.isEmpty) {
      setState(() => _errorMessage = 'Please enter a pickup location');
      return;
    }
    if (dropText.isEmpty) {
      setState(() => _errorMessage = 'Please enter a drop location');
      return;
    }
    if (pickupText.toLowerCase() == dropText.toLowerCase()) {
      setState(() => _errorMessage = 'Drop location must be different from pickup location');
      return;
    }

    setState(() {
      _errorMessage = null;
      _calculatingRoute = true;
    });

    try {
      // Resolve coordinates if entered manually without clicking a suggestion
      if (_pickupLocation == null) {
        final matches = await LocationSearchService.search(pickupText);
        if (matches.isNotEmpty) {
          _pickupLocation = matches.first.toLatLng();
        } else {
          _pickupLocation = const LatLng(18.5204, 73.8567);
        }
      }

      if (_dropLocation == null) {
        final matches = await LocationSearchService.search(dropText, userLocation: _pickupLocation);
        if (matches.isNotEmpty) {
          _dropLocation = matches.first.toLatLng();
        } else {
          _dropLocation = LatLng(_pickupLocation!.latitude + 0.03, _pickupLocation!.longitude + 0.03);
        }
      }

      // Calculate accurate road distance
      double roadDistanceKm;
      try {
        final dist = await LocationService.calculateRoadDistance(_pickupLocation!, _dropLocation!);
        roadDistanceKm = double.parse(dist.toStringAsFixed(1));
        if (roadDistanceKm <= 0.1) {
          final meters = const Distance().distance(_pickupLocation!, _dropLocation!);
          roadDistanceKm = double.parse(((meters / 1000.0) * 1.25).toStringAsFixed(1));
        }
      } catch (_) {
        final meters = const Distance().distance(_pickupLocation!, _dropLocation!);
        roadDistanceKm = double.parse(((meters / 1000.0) * 1.25).toStringAsFixed(1));
      }

      if (roadDistanceKm < 0.5) roadDistanceKm = 1.0;

      if (!mounted) return;
      setState(() => _calculatingRoute = false);

      // Build combined comprehensive address strings
      final fullPickup = pickupDetail.isNotEmpty ? '$pickupDetail, $pickupText' : pickupText;
      final fullDrop = dropDetail.isNotEmpty ? '$dropDetail, $dropText' : dropText;

      final nav = Navigator.of(context, rootNavigator: true);
      nav.pop(); // Close dialog

      nav.push(
        MaterialPageRoute(
          builder: (_) => VehicleSelectionScreen(
            pickupAddress: fullPickup,
            pickupLocation: _pickupLocation!,
            dropAddress: fullDrop,
            dropLocation: _dropLocation!,
            distanceKm: roadDistanceKm,
            initialTitle: widget.initialTitle,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _calculatingRoute = false;
          _errorMessage = 'Could not calculate route: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x3D000000),
                blurRadius: 28,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header Card with Green Pin, Sedan Car, Red Flag & Close button
              Stack(
                children: [
                  const SizedBox(
                    height: 115,
                    width: double.infinity,
                    child: _RouteHeaderIllustration(),
                  ),

                  // Close button (X) at top right
                  Positioned(
                    top: 10,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 19,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Dashed separator line with coupon ticket notches on sides
              const _TicketNotchDivider(),

              // Input cards area
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Error message banner if any
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // 1. Pickup Location Input Section (Green Pin)
                      _buildLocationSection(
                        isPickup: true,
                        title: 'Pickup Location',
                        hintText: 'Search pickup location...',
                        mainController: _pickupCtrl,
                        detailController: _pickupDetailCtrl,
                        focusNode: _pickupFocus,
                        onMainChanged: _onPickupChanged,
                        isLoadingGps: _gettingPickupGps,
                        onGpsTap: _getGpsForPickup,
                        onMapTap: _pickMapForPickup,
                      ),

                      // Inline autocomplete dropdown for Pickup
                      if (_pickupSuggestions.isNotEmpty || _searchingPickup)
                        LocationSuggestionsDropdown(
                          suggestions: _pickupSuggestions,
                          isLoading: _searchingPickup,
                          accentColor: const Color(0xFF10B981),
                          onSelect: _selectPickupSuggestion,
                          onDismiss: () => setState(() => _pickupSuggestions = []),
                        ),

                      const SizedBox(height: 12),

                      // 2. Drop Location Input Section (Red Flag)
                      _buildLocationSection(
                        isPickup: false,
                        title: 'Drop Location',
                        hintText: 'Search drop location...',
                        mainController: _dropCtrl,
                        detailController: _dropDetailCtrl,
                        focusNode: _dropFocus,
                        onMainChanged: _onDropChanged,
                        isLoadingGps: _gettingDropGps,
                        onGpsTap: _getGpsForDrop,
                        onMapTap: _pickMapForDrop,
                      ),

                      // Inline autocomplete dropdown for Drop
                      if (_dropSuggestions.isNotEmpty || _searchingDrop)
                        LocationSuggestionsDropdown(
                          suggestions: _dropSuggestions,
                          isLoading: _searchingDrop,
                          accentColor: const Color(0xFFEF4444),
                          onSelect: _selectDropSuggestion,
                          onDismiss: () => setState(() => _dropSuggestions = []),
                        ),

                      const SizedBox(height: 16),

                      // Confirm Button
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _calculatingRoute ? null : _confirmAndProceed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F1E36),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            disabledBackgroundColor: const Color(0xFF94A3B8),
                          ),
                          child: _calculatingRoute
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Confirm',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Icon(Icons.chevron_right_rounded, size: 22),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Checkered Taxi strip footer
              const _CheckeredTaxiPattern(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSection({
    required bool isPickup,
    required String title,
    required String hintText,
    required TextEditingController mainController,
    required TextEditingController detailController,
    required FocusNode focusNode,
    required ValueChanged<String> onMainChanged,
    required bool isLoadingGps,
    required VoidCallback onGpsTap,
    required VoidCallback onMapTap,
  }) {
    final themeColor = isPickup ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final themeBg = isPickup ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focusNode.hasFocus ? themeColor : const Color(0xFFE2E8F0),
          width: focusNode.hasFocus ? 1.6 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Row: Saved Locations Dropdown Card (matching user reference image) ──
          _buildSavedLocationsDropdown(isPickup: isPickup),

          const SizedBox(height: 10),

          // Top Row: Icon + Title + Action buttons (GPS and Map)
          Row(
            children: [
              // Icon Badge (Green Pin or Red Flag)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: themeBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPickup ? Icons.location_on_rounded : Icons.flag_rounded,
                  color: themeColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),

              // Title
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.1,
                  ),
                ),
              ),

              // Action button 1: GPS Target (square button)
              _buildSquareActionButton(
                icon: Icons.my_location_rounded,
                tooltip: 'Current GPS',
                isLoading: isLoadingGps,
                loadingColor: themeColor,
                onTap: isLoadingGps ? null : onGpsTap,
              ),

              const SizedBox(width: 6),

              // Action button 2: Map Picker (square button)
              _buildSquareActionButton(
                icon: Icons.map_outlined,
                tooltip: 'Pick on Map',
                onTap: onMapTap,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Main Address input row (clean, no inner border box)
          Row(
            children: [
              const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: mainController,
                  focusNode: focusNode,
                  onChanged: onMainChanged,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w400,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              if (mainController.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    mainController.clear();
                    setState(() {
                      if (isPickup) {
                        _pickupLocation = null;
                        _pickupSuggestions = [];
                      } else {
                        _dropLocation = null;
                        _dropSuggestions = [];
                      }
                    });
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.close_rounded, size: 16, color: Color(0xFF94A3B8)),
                  ),
                ),
            ],
          ),

          // Subtle hairline separator between main search and exact location
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
          ),

          // Exact location detail row (Flat / House No. / Building, clean, no inner border box)
          Row(
            children: [
              const Icon(Icons.home_outlined, size: 18, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: detailController,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1E293B),
                  ),
                  decoration: InputDecoration(
                    hintText: isPickup
                        ? 'Flat / House No., Floor, Building (Optional)'
                        : 'Flat / House No., Landmark / Contact person (Optional)',
                    hintStyle: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w400,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),

          // ── Quick Save Address Prompt if text entered and not yet in saved locations ──
          if (mainController.text.trim().isNotEmpty &&
              !_isAddressSaved(mainController.text.trim())) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bookmark_outline_rounded, size: 18, color: Color(0xFF2563EB)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Save as Home, Work, or Other for next time?',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E40AF),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _openSaveLocationDialog(isPickup: isPickup),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSquareActionButton({
    required IconData icon,
    required String tooltip,
    bool isLoading = false,
    Color? loadingColor,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: loadingColor ?? const Color(0xFF2563EB),
                  ),
                )
              : Icon(
                  icon,
                  size: 17,
                  color: const Color(0xFF475569),
                ),
        ),
      ),
    );
  }
}

/// Ticket notch separator with inward semi-circle cutouts on left and right,
/// and a dashed divider across the middle.
class _TicketNotchDivider extends StatelessWidget {
  const _TicketNotchDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      width: double.infinity,
      child: CustomPaint(
        painter: _TicketNotchPainter(),
      ),
    );
  }
}

class _TicketNotchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const notchRadius = 7.0;

    // Draw dashed line across middle (between notches)
    final dashPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double x = notchRadius + 4;
    final endX = size.width - notchRadius - 4;
    final y = size.height / 2;

    while (x < endX) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), dashPaint);
      x += dashWidth + dashSpace;
    }

    // Inward semi-circle notches on left and right border
    final notchPaint = Paint()..color = const Color(0xFF1E293B).withValues(alpha: 0.15);
    final fillPaint = Paint()..color = const Color(0xFFE2E8F0);

    // Left notch
    canvas.drawCircle(Offset(0, y), notchRadius + 1, notchPaint);
    canvas.drawCircle(Offset(0, y), notchRadius, fillPaint);

    // Right notch
    canvas.drawCircle(Offset(size.width, y), notchRadius + 1, notchPaint);
    canvas.drawCircle(Offset(size.width, y), notchRadius, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painted route illustration matching Image 1:
/// - Green location pin on the left (Pickup)
/// - Red waving flag on the right (Drop)
/// - Modern sedan car traveling on the dashed curved road in the middle
class _RouteHeaderIllustration extends StatelessWidget {
  const _RouteHeaderIllustration();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SedanRoutePainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _SedanRoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Soft subtle background
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF1F8FF), Color(0xFFFFFFFF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final startX = size.width * 0.16;
    final startY = size.height * 0.58;
    final endX = size.width * 0.84;
    final endY = size.height * 0.58;

    // Curved dashed trajectory
    final path = Path();
    path.moveTo(startX + 14, startY - 2);
    path.cubicTo(
      size.width * 0.35,
      size.height * 0.26,
      size.width * 0.65,
      size.height * 0.28,
      endX - 14,
      endY - 2,
    );

    // Draw dashed trajectory
    final dashPaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.70)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = 0.0;
      const dashWidth = 5.0;
      const dashSpace = 4.0;
      while (distance < metric.length) {
        final extractLen = (distance + dashWidth < metric.length) ? dashWidth : (metric.length - distance);
        final segment = metric.extractPath(distance, distance + extractLen);
        canvas.drawPath(segment, dashPaint);
        distance += dashWidth + dashSpace;
      }
    }

    // 1. Green Pin on Left (Pickup)
    _drawGreenPin(canvas, Offset(startX, startY));

    // 2. Red Flag on Right (Drop)
    _drawRedFlag(canvas, Offset(endX, endY));

    // 3. Proper Sedan Car in middle of trajectory
    final carX = size.width * 0.50;
    final carY = size.height * 0.30;
    _drawSedanCar(canvas, Offset(carX, carY));
  }

  void _drawGreenPin(Canvas canvas, Offset center) {
    // Ground shadow / ring
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx, center.dy + 8), width: 22, height: 8),
      Paint()..color = const Color(0xFFDCFCE7),
    );

    // Green Pin shape
    final path = Path();
    path.moveTo(center.dx, center.dy + 6);
    path.cubicTo(center.dx - 11, center.dy - 6, center.dx - 11, center.dy - 18, center.dx, center.dy - 18);
    path.cubicTo(center.dx + 11, center.dy - 18, center.dx + 11, center.dy - 6, center.dx, center.dy + 6);
    path.close();

    canvas.drawPath(path, Paint()..color = const Color(0xFF10B981));

    // Center white dot
    canvas.drawCircle(
      Offset(center.dx, center.dy - 8),
      4.2,
      Paint()..color = Colors.white,
    );
  }

  void _drawRedFlag(Canvas canvas, Offset center) {
    // Ground shadow / ring
    canvas.drawOval(
      Rect.fromCenter(center: Offset(center.dx, center.dy + 8), width: 22, height: 8),
      Paint()..color = const Color(0xFFFEE2E2),
    );

    // Flagpole
    final polePaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx, center.dy + 6), Offset(center.dx, center.dy - 20), polePaint);

    // Flagpole top golden finial ball
    canvas.drawCircle(Offset(center.dx, center.dy - 21), 2.2, Paint()..color = const Color(0xFFF59E0B));

    // Red waving flag cloth
    final flagPath = Path();
    flagPath.moveTo(center.dx, center.dy - 20);
    flagPath.cubicTo(
      center.dx + 8, center.dy - 23,
      center.dx + 14, center.dy - 17,
      center.dx + 22, center.dy - 20,
    );
    flagPath.lineTo(center.dx + 22, center.dy - 9);
    flagPath.cubicTo(
      center.dx + 14, center.dy - 6,
      center.dx + 8, center.dy - 12,
      center.dx, center.dy - 9,
    );
    flagPath.close();

    canvas.drawPath(flagPath, Paint()..color = const Color(0xFFEF4444));
  }

  void _drawSedanCar(Canvas canvas, Offset pos) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(0.04); // subtle dynamic tilt

    // Scale sedan
    const s = 1.15;
    canvas.scale(s, s);

    // Car Body Paint
    final bodyPaint = Paint()..color = const Color(0xFF0F2B5C);

    // Lower Sedan Chassis
    final chassisPath = Path();
    chassisPath.moveTo(-20, 2);
    chassisPath.lineTo(-21, -2);
    chassisPath.lineTo(-18, -4);
    chassisPath.lineTo(-12, -4); // Hood
    chassisPath.lineTo(-6, -11); // Windshield
    chassisPath.lineTo(7, -11);  // Roof
    chassisPath.lineTo(13, -4);  // Rear window
    chassisPath.lineTo(20, -4);  // Trunk
    chassisPath.lineTo(22, -1);
    chassisPath.lineTo(21, 4);
    chassisPath.lineTo(-19, 4);
    chassisPath.close();
    canvas.drawPath(chassisPath, bodyPaint);

    // Sedan side character line
    canvas.drawLine(
      const Offset(-17, 0),
      const Offset(19, 0),
      Paint()..color = const Color(0xFF1E40AF)..strokeWidth = 1.0,
    );

    // Tinted Windows
    final windowPaint = Paint()..color = const Color(0xFFBAE6FD);
    // Front window
    final frontWin = Path();
    frontWin.moveTo(-5, -10);
    frontWin.lineTo(-1, -10);
    frontWin.lineTo(-1, -5);
    frontWin.lineTo(-9.5, -5);
    frontWin.close();
    canvas.drawPath(frontWin, windowPaint);

    // Rear window
    final rearWin = Path();
    rearWin.moveTo(1, -10);
    rearWin.lineTo(6, -10);
    rearWin.lineTo(11.5, -5);
    rearWin.lineTo(1, -5);
    rearWin.close();
    canvas.drawPath(rearWin, windowPaint);

    // B-Pillar divider
    canvas.drawLine(
      const Offset(0, -11),
      const Offset(0, -4.5),
      Paint()..color = const Color(0xFF0F172A)..strokeWidth = 1.8,
    );

    // Headlight (yellow/white glow)
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(19.5, -3, 2.5, 3), const Radius.circular(1)),
      Paint()..color = const Color(0xFFFEF08A),
    );

    // Taillight (red)
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-21.5, -3, 2.5, 3), const Radius.circular(1)),
      Paint()..color = const Color(0xFFEF4444),
    );

    // Front & Rear Wheels
    final tirePaint = Paint()..color = const Color(0xFF0F172A);
    final rimPaint = Paint()..color = const Color(0xFFE2E8F0);
    final centerCapPaint = Paint()..color = const Color(0xFF3B82F6);

    // Rear Wheel (-12, 5)
    canvas.drawCircle(const Offset(-12, 4.5), 4.5, tirePaint);
    canvas.drawCircle(const Offset(-12, 4.5), 2.4, rimPaint);
    canvas.drawCircle(const Offset(-12, 4.5), 1.0, centerCapPaint);

    // Front Wheel (13, 5)
    canvas.drawCircle(const Offset(13, 4.5), 4.5, tirePaint);
    canvas.drawCircle(const Offset(13, 4.5), 2.4, rimPaint);
    canvas.drawCircle(const Offset(13, 4.5), 1.0, centerCapPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A decorative yellow-and-black checkered strip matching Image 1 footer.
class _CheckeredTaxiPattern extends StatelessWidget {
  final double height;
  const _CheckeredTaxiPattern({this.height = 12});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CheckeredPainter(),
      ),
    );
  }
}

class _CheckeredPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const squareSize = 6.0;
    final yellow = Paint()..color = const Color(0xFFF59E0B);
    final black = Paint()..color = const Color(0xFF1E293B);

    final cols = (size.width / squareSize).ceil();
    final rows = (size.height / squareSize).ceil();

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final isYellow = (r + c) % 2 == 0;
        final rect = Rect.fromLTWH(
          c * squareSize,
          r * squareSize,
          squareSize,
          squareSize,
        );
        canvas.drawRect(rect, isYellow ? yellow : black);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
