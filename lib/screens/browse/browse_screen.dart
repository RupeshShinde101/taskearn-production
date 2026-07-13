import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_card.dart';
import '../../services/location_service.dart';

class BrowseScreen extends StatefulWidget {
  /// Set by the home screen before calling context.go('/browse') so that the
  /// browse screen can pre-select and filter by that category on arrival.
  static String? jumpToCategory;

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
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Fetch location first, then load tasks so radius filter applies immediately
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

  void _applyFilters() {
    context.read<TaskProvider>().fetchBrowseTasks(
          category: _selectedCategory,
          search: _searchCtrl.text.trim().isNotEmpty ? _searchCtrl.text.trim() : null,
          maxBudget: _maxBudget < 5000 ? _maxBudget : null,
          radiusKm: _userLat != null ? _radiusKm : null,
          lat: _userLat,
          lng: _userLng,
          refresh: true,
        );
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                  Navigator.pop(context);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search tasks…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilters();
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => _applyFilters(),
            ),
          ),

          // Task list
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
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppColors.grayLight.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              filtersActive
                                  ? Icons.search_off_rounded
                                  : Icons.inbox_outlined,
                              size: 32,
                              color: AppColors.gray,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            filtersActive
                                ? 'No tasks match your filters'
                                : 'No tasks available',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.dark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            filtersActive
                                ? 'Try adjusting or clearing your filters'
                                : 'Check back later for new tasks',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.gray,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (filtersActive)
                            OutlinedButton.icon(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: const Text('Clear Filters'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24)),
                              ),
                            )
                          else
                            TextButton(
                              onPressed: _applyFilters,
                              child: const Text('Refresh'),
                            ),
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => _applyFilters(),
                  child: ListView.builder(
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
