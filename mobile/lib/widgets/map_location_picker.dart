import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

// ── Nominatim result model ────────────────────────────────────────────────────
class _NominatimResult {
  final String displayName;
  final double lat;
  final double lon;
  const _NominatimResult(
      {required this.displayName, required this.lat, required this.lon});
}

/// Full-screen map picker.
/// Supports: tap-on-map · GPS · **search by name** (Nominatim/OSM).
/// Returns `{'location': LatLng, 'address': String?}` via [Navigator.pop].
class MapLocationPicker extends StatefulWidget {
  final LatLng? initialLocation;
  const MapLocationPicker({super.key, this.initialLocation});

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  LatLng? _picked;
  String? _address;
  bool _geocoding = false;
  bool _gettingGps = false;
  bool _mapReady = false; // shows loading overlay until first tile renders

  // Search
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<_NominatimResult> _searchResults = [];
  bool _searching = false;
  bool _showResults = false;

  late final MapController _mapController;

  // Default centre: Mumbai
  static const _defaultCenter = LatLng(19.0760, 72.8777);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    if (widget.initialLocation != null) {
      _picked = widget.initialLocation;
      _reverseGeocode(widget.initialLocation!);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Reverse geocode (tap / GPS) ───────────────────────────────────────────
  Future<void> _reverseGeocode(LatLng loc) async {
    setState(() => _geocoding = true);
    try {
      final places = await placemarkFromCoordinates(loc.latitude, loc.longitude)
          .timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (places.isNotEmpty) {
        final p = places.first;
        final parts = [p.name, p.subLocality, p.locality, p.administrativeArea]
            .where((s) => s != null && s!.isNotEmpty)
            .map((s) => s!)
            .toList();
        setState(() {
          _address = parts.isEmpty ? null : parts.join(', ');
          _geocoding = false;
        });
      } else {
        setState(() => _geocoding = false);
      }
    } catch (_) {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  // ── Forward search via Nominatim ──────────────────────────────────────────
  Future<void> _searchLocation(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _searchResults = [];
        _showResults = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _showResults = true;
    });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'json',
        'limit': '6',
        'addressdetails': '1',
      });
      final resp = await http.get(uri, headers: {
        'User-Agent': 'Workmate4u/1.0 (com.workmate4u.workmate4u)',
        'Accept-Language': 'en',
      }).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as List<dynamic>;
        _searchResults = data.map((e) {
          final map = e as Map<String, dynamic>;
          return _NominatimResult(
            displayName: map['display_name'] as String,
            lat: double.parse(map['lat'] as String),
            lon: double.parse(map['lon'] as String),
          );
        }).toList();
      }
    } catch (_) {
      // silently ignore network errors
    }
    if (mounted) setState(() => _searching = false);
  }

  void _selectResult(_NominatimResult result) {
    final point = LatLng(result.lat, result.lon);
    // Take first 3 comma-separated parts for a cleaner display address
    final shortAddr =
        result.displayName.split(',').take(3).join(',').trim();
    _mapController.move(point, 15);
    setState(() {
      _picked = point;
      _address = shortAddr;
      _searchResults = [];
      _showResults = false;
    });
    _searchCtrl.text = shortAddr;
    _searchFocus.unfocus();
  }

  void _dismissSearch() {
    setState(() {
      _showResults = false;
      _searchResults = [];
    });
    _searchFocus.unfocus();
  }

  // ── GPS ───────────────────────────────────────────────────────────────────
  Future<void> _useGps() async {
    _dismissSearch();
    setState(() => _gettingGps = true);
    final loc = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() => _gettingGps = false);
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not detect GPS location')),
      );
      return;
    }
    _mapController.move(loc, 15);
    _searchCtrl.clear();
    setState(() {
      _picked = loc;
      _address = null;
    });
    await _reverseGeocode(loc);
  }

  // ── Map tap ───────────────────────────────────────────────────────────────
  void _onTap(TapPosition _, LatLng point) {
    _dismissSearch();
    _searchCtrl.clear();
    setState(() {
      _picked = point;
      _address = null;
    });
    _reverseGeocode(point);
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final center = _picked ?? _defaultCenter;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Location on Map'),
        actions: [
          if (_gettingGps)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.my_location),
              tooltip: 'Use my GPS location',
              onPressed: _useGps,
            ),
        ],
      ),
      body: GestureDetector(
        // Dismiss search results when tapping outside the search field
        onTap: _dismissSearch,
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            // ── Map ──────────────────────────────────────────────────────
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: _picked != null ? 15 : 12,
                onTap: _onTap,
                onMapReady: () => setState(() => _mapReady = true),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.workmate4u.workmate4u',
                  maxZoom: 19,
                ),
                if (_picked != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _picked!,
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.location_pin,
                          color: AppColors.danger,
                          size: 48,
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            // Map loading overlay — shown until onMapReady fires
            if (!_mapReady)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFFE8EDF0),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Loading map…',
                            style: TextStyle(
                                color: Color(0xFF666666), fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),

            // Search bar + results dropdown ─────────────────────────────
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search text field
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search location…',
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.primary),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    color: AppColors.gray),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _searchResults = [];
                                    _showResults = false;
                                  });
                                },
                              )
                            : _searching
                                ? const Padding(
                                    padding:
                                        EdgeInsets.all(12),
                                    child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child:
                                            CircularProgressIndicator(
                                                strokeWidth: 2)),
                                  )
                                : null,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) {
                        setState(() {}); // update clear icon
                        if (v.trim().isEmpty) {
                          setState(() {
                            _searchResults = [];
                            _showResults = false;
                          });
                        }
                      },
                      onSubmitted: _searchLocation,
                    ),
                  ),

                  // Results dropdown
                  if (_showResults && _searchResults.isNotEmpty)
                    Material(
                      elevation: 6,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxHeight: 270),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final r = _searchResults[i];
                              // Split display_name into primary / secondary
                              final parts = r.displayName.split(',');
                              final primary = parts.first.trim();
                              final secondary = parts.length > 1
                                  ? parts
                                      .skip(1)
                                      .take(3)
                                      .map((s) => s.trim())
                                      .join(', ')
                                  : '';
                              return InkWell(
                                onTap: () => _selectResult(r),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.place_outlined,
                                          color: AppColors.primary,
                                          size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              primary,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  fontSize: 13),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                            if (secondary.isNotEmpty)
                                              Text(
                                                secondary,
                                                style: const TextStyle(
                                                    color: AppColors.gray,
                                                    fontSize: 12),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                  // "No results" hint
                  if (_showResults &&
                      !_searching &&
                      _searchResults.isEmpty)
                    Material(
                      elevation: 4,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: const [
                            Icon(Icons.search_off,
                                color: AppColors.gray, size: 18),
                            SizedBox(width: 8),
                            Text('No results found',
                                style: TextStyle(
                                    color: AppColors.gray, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Tap-hint label (only when no results dropdown visible) ────
            if (!_showResults)
              Positioned(
                bottom: 130,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Or tap anywhere on the map',
                        style:
                            TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Bottom confirm bar ────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 8)
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_picked != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: AppColors.primary, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _geocoding
                                  ? const Text('Getting address…',
                                      style: TextStyle(
                                          color: AppColors.gray,
                                          fontSize: 13))
                                  : Text(
                                      _address ??
                                          '${_picked!.latitude.toStringAsFixed(5)}, '
                                              '${_picked!.longitude.toStringAsFixed(5)}',
                                      style: const TextStyle(
                                          color: AppColors.dark,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      ElevatedButton.icon(
                        onPressed: _picked == null
                            ? null
                            : () => Navigator.of(context).pop({
                                  'location': _picked,
                                  'address': _address,
                                }),
                        icon: const Icon(Icons.check),
                        label: const Text('Use This Location'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.grayLight,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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
    );
  }
}
