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

/// Configuration for parent task category cards matching the design reference.
class BrowseCategoryConfig {
  final String label;
  final String subtitle;
  final List<String> categoryIds;
  final String? imageAsset;
  final List<Color> waveGradient;
  final bool isOther;

  const BrowseCategoryConfig({
    required this.label,
    required this.subtitle,
    required this.categoryIds,
    this.imageAsset,
    required this.waveGradient,
    this.isOther = false,
  });

  static const List<BrowseCategoryConfig> all = [
    BrowseCategoryConfig(
      label: 'Delivery and Transport',
      subtitle: 'Moving, delivery, transport',
      categoryIds: ['delivery', 'moving', 'transport', 'pickup'],
      imageAsset: 'assets/images/cat_3d_delivery.png',
      // Subtle, airy pastel sky blue
      waveGradient: [
        Color(0x30BAE6FD),
        Color(0x757DD3FC),
      ],
    ),
    BrowseCategoryConfig(
      label: 'Repair',
      subtitle: 'Plumbing, electrical, appliance',
      categoryIds: [
        'repair',
        'electrician',
        'plumbing',
        'carpentry',
        'vehicle',
        'tech_support',
      ],
      imageAsset: 'assets/images/cat_3d_repair.png',
      // Subtle, delicate warm peach/amber
      waveGradient: [
        Color(0x30FED7AA),
        Color(0x70FDBA74),
      ],
    ),
    BrowseCategoryConfig(
      label: 'Home & Lifestyle',
      subtitle: 'Painting, cleaning, home help',
      categoryIds: [
        'cleaning',
        'household',
        'cooking',
        'laundry',
        'gardening',
        'beauty',
      ],
      imageAsset: 'assets/images/cat_3d_home.png',
      // Subtle, soft mint green
      waveGradient: [
        Color(0x30BBF7D0),
        Color(0x7086EFAC),
      ],
    ),
    BrowseCategoryConfig(
      label: 'Shopping & Errands',
      subtitle: 'Purchase, pickup, daily errands',
      categoryIds: [
        'shopping',
        'groceries',
        'errands',
        'queue_standing',
        'event_help',
      ],
      imageAsset: 'assets/images/cat_3d_shopping.png',
      // Subtle, soft lavender purple
      waveGradient: [
        Color(0x30DDD6FE),
        Color(0x70C4B5FD),
      ],
    ),
    BrowseCategoryConfig(
      label: 'Professional',
      subtitle: 'IT, design, writing, accounting',
      categoryIds: [
        'freelancer',
        'data_entry',
        'photography',
        'tutoring',
        'painting',
      ],
      imageAsset: 'assets/images/cat_3d_professional.png',
      // Subtle, soft ice cyan
      waveGradient: [
        Color(0x30BAE6FD),
        Color(0x70A5F3FC),
      ],
    ),
    BrowseCategoryConfig(
      label: 'Care Services',
      subtitle: 'Nursing, elder care, pet care',
      categoryIds: ['child_care', 'elder_care', 'pet_care'],
      imageAsset: 'assets/images/cat_3d_care.png',
      // Subtle, delicate blush rose
      waveGradient: [
        Color(0x30FECDD3),
        Color(0x70FDA4AF),
      ],
    ),
    BrowseCategoryConfig(
      label: 'Other',
      subtitle: 'Miscellaneous services',
      categoryIds: ['other'],
      // Subtle, soft neutral slate
      waveGradient: [
        Color(0x35E2E8F0),
        Color(0x75CBD5E1),
      ],
      isOther: true,
    ),
  ];
}

class BrowseScreen extends StatefulWidget {
  /// Set by the home screen before calling context.go('/browse') so that the
  /// browse screen can pre-select and filter by that category on arrival.
  static String? jumpToCategory;

  /// Set before navigating to show tasks sorted by soonest-expiring first.
  static bool jumpToExpirySoon = false;

  /// Set by AI Suggested 'See all' to pre-populate the search field with a skill keyword.
  static String? jumpToSearch;

  /// Callback registered with MainShell to handle native Android back gesture.
  static bool Function()? onBackOverride;

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
  bool _sortByExpiry = false;
  bool _radiusFilterActive = false;

  // Selected category when user taps on a category card to enter it
  BrowseCategoryConfig? _selectedCategoryConfig;

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
      final catLower = cat.toLowerCase();
      BrowseCategoryConfig? targetConfig;
      for (final config in BrowseCategoryConfig.all) {
        if (config.categoryIds.any((id) => id.toLowerCase() == catLower) ||
            config.label.toLowerCase() == catLower) {
          targetConfig = config;
          break;
        }
      }
      setState(() {
        _selectedCategory = cat;
        if (targetConfig != null) {
          _selectedCategoryConfig = targetConfig;
        }
      });
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
    BrowseScreen.onBackOverride = _handleBackPress;
    _searchCtrl.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _fetchLocation();
      if (!mounted) return;
      _applyFilters();
    });
  }

  bool _handleBackPress() {
    if (_selectedCategoryConfig != null) {
      setState(() => _selectedCategoryConfig = null);
      return true;
    }
    return false;
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
    if (BrowseScreen.onBackOverride == _handleBackPress) {
      BrowseScreen.onBackOverride = null;
    }
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
          search: _searchCtrl.text.trim().isNotEmpty
              ? _searchCtrl.text.trim()
              : null,
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
              const Text(
                'Filters',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Category',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                ),
              ),
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
                        onTap: () => setModal(() => _selectedCategory = c.id),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Max Budget',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                    ),
                  ),
                  Text(
                    '₹${_maxBudget.toInt()}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                    ),
                  ),
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
                  const Text(
                    'Radius',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                    ),
                  ),
                  Text(
                    '${_radiusKm.toInt()} km',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                    ),
                  ),
                ],
              ),
              if (_locationDenied)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    '⚠️ Location permission denied — radius filter disabled',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                      fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                    ),
                  ),
                ),
              Slider(
                value: _radiusKm,
                min: 1,
                max: 50,
                divisions: 49,
                activeColor:
                    _locationDenied ? AppColors.grayLight : AppColors.primary,
                onChanged: _locationDenied
                    ? null
                    : (v) => setModal(() => _radiusKm = v),
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
      _selectedCategoryConfig = null;
      _searchCtrl.clear();
    });
    _applyFilters();
  }

  bool get _hasActiveFilters =>
      _selectedCategory != 'all' ||
      _maxBudget < 5000 ||
      _searchCtrl.text.isNotEmpty;

  /// Matches a task against a parent category configuration.
  static BrowseCategoryConfig _findCategoryForTask(Task task) {
    final taskCat = task.category.trim().toLowerCase();
    for (final config in BrowseCategoryConfig.all) {
      if (config.isOther) continue;
      for (final id in config.categoryIds) {
        final idLower = id.toLowerCase();
        if (taskCat == idLower ||
            taskCat.contains(idLower) ||
            idLower.contains(taskCat)) {
          return config;
        }
      }
      if (taskCat == config.label.toLowerCase() ||
          config.label.toLowerCase().contains(taskCat) ||
          taskCat.contains(config.label.toLowerCase())) {
        return config;
      }
    }
    return BrowseCategoryConfig.all.firstWhere((c) => c.isOther);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedCategoryConfig == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedCategoryConfig != null) {
          setState(() => _selectedCategoryConfig = null);
        }
      },
      child: TaskScreenWatermark(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: Consumer<TaskProvider>(
              builder: (_, tasks, __) {
                // Group tasks by category config
                final Map<BrowseCategoryConfig, List<Task>> categoryTasksMap =
                    {};
                for (final config in BrowseCategoryConfig.all) {
                  categoryTasksMap[config] = [];
                }
                for (final task in tasks.browseTasks) {
                  final config = _findCategoryForTask(task);
                  categoryTasksMap[config]!.add(task);
                }

                // If user is inside a specific category view
                if (_selectedCategoryConfig != null) {
                  final catTasks =
                      categoryTasksMap[_selectedCategoryConfig!] ?? [];
                  return _buildCategoryDetailView(
                      _selectedCategoryConfig!, catTasks);
                }

                // Main Browse Category Cards View
                return _buildMainCategoriesView(tasks, categoryTasksMap);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Main Browse Tasks Screen showing Category Cards matching reference design.
  Widget _buildMainCategoriesView(TaskProvider tasks,
      Map<BrowseCategoryConfig, List<Task>> categoryTasksMap) {
    final query = _searchCtrl.text.trim().toLowerCase();

    // Show ALL categories by default as shown in reference design!
    final List<BrowseCategoryConfig> visibleCategories = [];
    for (final config in BrowseCategoryConfig.all) {
      if (query.isNotEmpty) {
        final catTasks = categoryTasksMap[config] ?? [];
        final matchesLabel = config.label.toLowerCase().contains(query);
        final matchesSub = config.subtitle.toLowerCase().contains(query);
        final matchesTasks = catTasks.any((t) =>
            t.title.toLowerCase().contains(query) ||
            t.description.toLowerCase().contains(query));
        if (!matchesLabel && !matchesSub && !matchesTasks) {
          continue;
        }
      }
      visibleCategories.add(config);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Header matching Image Reference
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Browse Tasks',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Find tasks posted by people near you.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                      ),
                    ),
                  ],
                ),
              ),
              // Filter Action Button matching Image
              GestureDetector(
                onTap: _showFilters,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFDCE7F5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFF2563EB).withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.tune_rounded,
                      color: Color(0xFF2563EB),
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Search bar with exact placeholder 'Search tasks, categories...'
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFDCE7F5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.05),
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
                fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
              ),
              decoration: InputDecoration(
                hintText: 'Search tasks, categories...',
                hintStyle: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                  fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              onSubmitted: (_) => _applyFilters(),
            ),
          ),
        ),

        // Category Cards List OR Empty State
        Expanded(
          child: Builder(
            builder: (_) {
              // When search query matches no categories or tasks
              if (visibleCategories.isEmpty) {
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
                        const Text(
                          'No categories or tasks found',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.2,
                            fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Try searching with another keyword or clear search',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF64748B),
                            fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                          ),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: () {
                            _searchCtrl.clear();
                            _applyFilters();
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('Clear Search'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2563EB),
                            side: const BorderSide(
                                color: Color(0xFF2563EB), width: 1.5),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Display Category Cards matching reference design
              return RefreshIndicator(
                onRefresh: () async => _applyFilters(),
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    2,
                    16,
                    MediaQuery.of(context).viewPadding.bottom + 85,
                  ),
                  itemCount: visibleCategories.length,
                  itemBuilder: (_, i) {
                    final config = visibleCategories[i];
                    final catTasks = categoryTasksMap[config] ?? [];
                    return _buildCategoryCard(config, catTasks);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Category Card matching design reference:
  /// - Exact proportional height: 90px
  /// - Soft, subtle translucent background wave cradling the 3D illustration
  /// - Perfectly centered vertical alignment for title, illustration, and chevron
  /// - Expanded title with 20px left margin
  /// - Prominent 72x72 3D illustration with 14px gap to chevron
  /// - 18px right padding with 22px chevron
  Widget _buildCategoryCard(
      BrowseCategoryConfig config, List<Task> catTasks) {
    return Container(
      height: 90,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFF1F5F9),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            setState(() => _selectedCategoryConfig = config);
          },
          child: Stack(
            children: [
              // Soft organic curved wave on the right matching category theme
              Positioned.fill(
                child: CustomPaint(
                  painter: _CategoryCardWavePainter(config.waveGradient),
                ),
              ),

              // Content Row: Only Title, Illustration, and Chevron
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Only Title inside card data as requested
                    Expanded(
                      child: Text(
                        config.label,
                        style: const TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.3,
                          fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // SVG / 3D Illustration (enlarged to 72x72 for better proportions)
                    _buildIllustration(config),

                    const SizedBox(width: 14),

                    // Chevron right navigation indicator
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF334155),
                      size: 22,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds category illustration: 3D asset or 3 glossy blue dots for Other.
  Widget _buildIllustration(BrowseCategoryConfig config) {
    if (config.isOther || config.imageAsset == null) {
      return const _ThreeDots3DIllustration();
    }
    return SizedBox(
      width: 72,
      height: 72,
      child: Center(
        child: Image.asset(
          config.imageAsset!,
          width: 72,
          height: 72,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => const _ThreeDots3DIllustration(),
        ),
      ),
    );
  }

  /// Detailed category view shown when user taps and enters into a category.
  /// Shows category title, subtitle, task count badge, and full task list.
  Widget _buildCategoryDetailView(
      BrowseCategoryConfig config, List<Task> catTasks) {
    return Column(
      children: [
        // Navigation Bar with Back Button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedCategoryConfig = null),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFDCE7F5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFF2563EB).withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Color(0xFF0F172A),
                      size: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  config.label,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                    fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: _showFilters,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFDCE7F5),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFF2563EB).withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.tune_rounded,
                      color: Color(0xFF2563EB),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Category Header Card (Title, Subtitle details, and Task count badge)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.035),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CategoryCardWavePainter(config.waveGradient),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          config.label,
                          style: const TextStyle(
                            fontSize: 18.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.2,
                            fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          config.subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w400,
                            fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Badge showing count of available tasks
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFBFDBFE),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.layers_rounded,
                                color: Color(0xFF2563EB),
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${catTasks.length} ${catTasks.length == 1 ? 'task' : 'tasks'} available',
                                style: const TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildIllustration(config),
                ],
              ),
            ],
          ),
        ),

        // List of Tasks in this category
        Expanded(
          child: catTasks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const EmptyTasksClipboardIllustration(
                          type: EmptyTasksClipboardType.browse,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No tasks in this category',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                            fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'New tasks posted by clients for ${config.label.toLowerCase()} will appear here.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Color(0xFF64748B),
                            fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async => _applyFilters(),
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      4,
                      16,
                      MediaQuery.of(context).viewPadding.bottom + 85,
                    ),
                    itemCount: catTasks.length,
                    itemBuilder: (_, i) => TaskCard(
                      task: catTasks[i],
                      onTap: () =>
                          context.push('/task/${catTasks[i].id}'),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Organic bezier wave painter drawing a delicate, soft translucent pastel curve on the right.
class _CategoryCardWavePainter extends CustomPainter {
  final List<Color> colors;

  const _CategoryCardWavePainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;

    final paint = Paint()
      ..shader = LinearGradient(
        colors: colors.length > 1 ? colors : [colors.first, colors.first],
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
      ).createShader(
        Rect.fromLTWH(size.width * 0.48, 0, size.width * 0.52, size.height),
      )
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width, size.height);
    path.lineTo(size.width * 0.56, size.height);
    path.cubicTo(
      size.width * 0.66,
      size.height * 0.95,
      size.width * 0.70,
      size.height * 0.22,
      size.width,
      size.height * 0.08,
    );
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CategoryCardWavePainter oldDelegate) =>
      oldDelegate.colors != colors;
}

/// 3D Glossy Blue Dots illustration for the 'Other' category matching reference.
class _ThreeDots3DIllustration extends StatelessWidget {
  const _ThreeDots3DIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.35, -0.35),
                  radius: 0.85,
                  colors: [
                    Color(0xFF60A5FA),
                    Color(0xFF2563EB),
                    Color(0xFF1D4ED8),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SmallChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
            fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
          ),
        ),
      ),
    );
  }
}
