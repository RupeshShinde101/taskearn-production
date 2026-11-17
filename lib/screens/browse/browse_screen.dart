import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_card.dart';
import '../../services/location_service.dart';
import '../../widgets/task_screen_watermark.dart';
import '../../widgets/task_empty_state_illustration.dart';

class BrowseScreen extends StatefulWidget {
  /// Set by the home screen before calling context.go('/browse') so that the
  /// browse screen can pre-select and filter by that category on arrival.
  static String? jumpToCategory;
  /// Set before navigating to show tasks sorted by soonest-expiring first.
  static bool jumpToExpirySoon = false;
  /// Set by AI Suggested 'See all' to pre-populate the search field with a skill keyword.
  static String? jumpToSearch;

  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _searchCtrl = TextEditingController();
  String _selectedCategory = 'all';
  double _maxBudget = 5000;
  double _radiusKm = 10;
  Timer? _searchDebounce;
  bool _sortByExpiry = false;  // set when navigating from Expiring Soon
  bool _radiusFilterActive = false; // true only after user taps Apply Filters

  // User's current GPS location for radius filtering
  double? _userLat;
  double? _userLng;
  bool _locationDenied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Consume the category signal set by the home screen before navigating.
    final cat = BrowseScreen.jumpToCategory;
    if (cat != null) {
      BrowseScreen.jumpToCategory = null; // consume once
      setState(() => _selectedCategory = cat);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyFilters();
      });
    }
    // Consume the expiry-sort signal.
    if (BrowseScreen.jumpToExpirySoon) {
      BrowseScreen.jumpToExpirySoon = false;
      _sortByExpiry = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyFilters();
      });
    }
    // Consume skill search signal from AI Suggested 'See all'.
    final skillSearch = BrowseScreen.jumpToSearch;
    if (skillSearch != null) {
      BrowseScreen.jumpToSearch = null;
      _searchCtrl.text = skillSearch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyFilters();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Resolve GPS first so the 10 km radius filter is applied from the start.
      await _fetchLocation();
      if (!mounted) return;
      _applyFilters();
    });
  }

  Future<void> _fetchLocation() async {
    final pos = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        _userLat = pos.latitude;
        _userLng = pos.longitude;
        _locationDenied = false;
      });
    } else {
      setState(() => _locationDenied = true);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), _applyFilters);
  }

  void _applyFilters({bool sortByExpiry = false}) {
    final useExpiry = sortByExpiry || _sortByExpiry;
    context.read<TaskProvider>().fetchBrowseTasks(
          category: _selectedCategory,
          search: _searchCtrl.text.trim().isNotEmpty ? _searchCtrl.text.trim() : null,
          maxBudget: _maxBudget < 5000 ? _maxBudget : null,
          radiusKm: _radiusFilterActive && _userLat != null ? _radiusKm : null,
          lat: _userLat,
          lng: _userLng,
          excludePosterId: null,
          sort: useExpiry ? 'expiry' : null,
          expiringSoon: useExpiry,
          refresh: true,
        );
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filters',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              const Text('Category',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _SmallChip(
                      label: 'All',
                      selected: _selectedCategory == 'all',
                      onTap: () => setModal(() => _selectedCategory = 'all'),
                    ),
                    ...TaskCategory.all.map(
                      (c) => _SmallChip(
                        label: c.label,
                        selected: _selectedCategory == c.id,
                        onTap: () =>
                            setModal(() => _selectedCategory = c.id),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Max Budget',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('₹${_maxBudget.toInt()}',
                      style: const TextStyle(color: AppColors.primary)),
                ],
              ),
              Slider(
                value: _maxBudget,
                min: 100,
                max: 10000,
                divisions: 99,
                activeColor: AppColors.primary,
                onChanged: (v) => setModal(() => _maxBudget = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Radius',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('${_radiusKm.toInt()} km',
                      style: const TextStyle(color: AppColors.primary)),
                ],
              ),
              if (_locationDenied)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    '\u26a0\ufe0f Location permission denied — radius filter disabled',
                    style: TextStyle(color: AppColors.danger, fontSize: 12),
                  ),
                ),
              Slider(
                value: _radiusKm,
                min: 1,
                max: 50,
                divisions: 49,
                activeColor: _locationDenied ? AppColors.grayLight : AppColors.primary,
                onChanged: _locationDenied ? null : (v) => setModal(() => _radiusKm = v),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _radiusFilterActive = true);
                  _applyFilters();
                },
                child: const Text('Apply Filters'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _selectedCategory = 'all';
      _maxBudget = 5000;
      _radiusFilterActive = false;
      _searchCtrl.clear();
    });
    _applyFilters();
  }

  bool get _hasActiveFilters =>
      _selectedCategory != 'all' ||
      _maxBudget < 5000 ||
      _searchCtrl.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return TaskScreenWatermark(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: const Text(
            'Browse Tasks',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.tune_rounded, color: Color(0xFF0F172A), size: 24),
              onPressed: _showFilters,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            // Search bar matching Image 2
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCE7F5), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search tasks...',
                    hintStyle: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Color(0xFF2563EB),
                      size: 24,
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Color(0xFF94A3B8), size: 20),
                            onPressed: () {
                              _searchCtrl.clear();
                              _applyFilters();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  ),
                  onSubmitted: (_) => _applyFilters(),
                ),
              ),
            ),

            // Task list or empty state
            Expanded(
              child: Consumer<TaskProvider>(
                builder: (_, tasks, __) {
                  if (tasks.isLoadingBrowse && tasks.browseTasks.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (tasks.browseTasks.isEmpty) {
                    final filtersActive = _hasActiveFilters;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const EmptyTasksClipboardIllustration(
                              type: EmptyTasksClipboardType.browse,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              filtersActive
                                  ? 'No tasks match your filters'
                                  : 'No tasks available',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              filtersActive
                                  ? 'Try adjusting or clearing your filters'
                                  : 'Check back later for new tasks',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 24),
                            if (filtersActive)
                              OutlinedButton.icon(
                                onPressed: _clearFilters,
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: const Text('Clear Filters'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF2563EB),
                                  side: const BorderSide(
                                      color: Color(0xFF2563EB), width: 1.5),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 32, vertical: 13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24)),
                                  textStyle: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                              )
                            else
                              SizedBox(
                                width: 140,
                                height: 46,
                                child: ElevatedButton(
                                  onPressed: _applyFilters,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    shadowColor:
                                        const Color(0xFF2563EB).withValues(alpha: 0.35),
                                  ),
                                  child: const Text(
                                    'Refresh',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async => _applyFilters(),
                    child: ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        MediaQuery.of(context).viewPadding.bottom + 85,
                      ),
                      itemCount: tasks.browseTasks.length,
                      itemBuilder: (_, i) => TaskCard(
                        task: tasks.browseTasks[i],
                        onTap: () =>
                            context.push('/task/${tasks.browseTasks[i].id}'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SmallChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.light,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.gray,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
