import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/category_task_posting_dialog.dart';
import '../../widgets/profile_mode_switch_dialog.dart';

/// Price Breakdown screen matching the design reference for all parent categories:
/// - Repair
/// - Home
/// - Care Services
/// - Professional
/// - Other (and Shopping)
class CategoryPriceBreakdownScreen extends StatefulWidget {
  final TaskCategoryGroup parentGroup;
  final TaskCategory? subCategory;
  final String address;
  final LatLng? location;
  final String? landmark;
  final String? flat;
  final String? area;
  final String? initialTitle;

  const CategoryPriceBreakdownScreen({
    super.key,
    required this.parentGroup,
    this.subCategory,
    required this.address,
    this.location,
    this.landmark,
    this.flat,
    this.area,
    this.initialTitle,
  });

  @override
  State<CategoryPriceBreakdownScreen> createState() => _CategoryPriceBreakdownScreenState();
}

class _CategoryPriceBreakdownScreenState extends State<CategoryPriceBreakdownScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  final _instructionsCtrl = TextEditingController();
  late final TextEditingController _budgetCtrl;

  bool _submitting = false;

  String get _groupLabel => widget.parentGroup.label.toLowerCase();

  bool get _isRepair => _groupLabel.contains('repair');
  bool get _isHome => _groupLabel.contains('home');
  bool get _isCare => _groupLabel.contains('care');
  bool get _isProfessional => _groupLabel.contains('professional');
  bool get _isShopping => _groupLabel.contains('shopping') || _groupLabel.contains('grocery');

  Color get _primaryColor {
    if (_isRepair) return const Color(0xFF0284C7);
    if (_isHome) return const Color(0xFF059669);
    if (_isCare) return const Color(0xFFDB2777);
    if (_isProfessional) return const Color(0xFF1D4ED8);
    if (_isShopping) return const Color(0xFF7C3AED);
    return const Color(0xFF4338CA); // Other
  }

  List<Color> get _heroGradient {
    if (_isRepair) {
      return const [Color(0xFF0284C7), Color(0xFF2563EB)];
    } else if (_isHome) {
      return const [Color(0xFF059669), Color(0xFF10B981)];
    } else if (_isCare) {
      return const [Color(0xFFDB2777), Color(0xFFF43F5E)];
    } else if (_isProfessional) {
      return const [Color(0xFF1D4ED8), Color(0xFF4F46E5)];
    } else if (_isShopping) {
      return const [Color(0xFF6D28D9), Color(0xFF8B5CF6)];
    } else {
      // Other
      return const [Color(0xFF4338CA), Color(0xFF6366F1)];
    }
  }

  String get _heroIllustration {
    if (_isRepair) return 'assets/images/cat_3d_repair.png';
    if (_isHome) return 'assets/images/cat_3d_home.png';
    if (_isCare) return 'assets/images/cat_3d_care.png';
    if (_isProfessional) return 'assets/images/cat_3d_professional.png';
    if (_isShopping) return 'assets/images/cat_3d_shopping.png';
    return 'assets/images/cat_3d_other_skyline.png';
  }

  IconData get _breadcrumbIcon {
    if (_isRepair) return Icons.build_rounded;
    if (_isHome) return Icons.home_rounded;
    if (_isCare) return Icons.favorite_rounded;
    if (_isProfessional) return Icons.work_rounded;
    if (_isShopping) return Icons.shopping_bag_rounded;
    return Icons.assignment_rounded;
  }

  String get _heroTitle {
    if (widget.parentGroup.label == 'Other') {
      return 'Other Service Task';
    }
    return '${widget.parentGroup.label} Task';
  }

  String get _heroSubtitle {
    if (_isCare) {
      return 'Confirm your task details, set your budget and post it to get a caregiver.';
    } else if (widget.parentGroup.label == 'Other') {
      return 'Post a custom task or a service not listed in other categories.';
    } else if (_isShopping) {
      return 'Confirm your shopping details, set your budget and post it to get a helper.';
    }
    return 'Confirm your task details, set your budget and post it to get a helper.';
  }

  String get _titleHint {
    if (_isRepair) {
      return 'e.g., Fix leaking tap, Repair door lock';
    } else if (_isHome) {
      return 'e.g., House cleaning, Home painting, Furniture assembly';
    } else if (_isCare) {
      return 'e.g., Elder care, Child care, Patient support';
    } else if (_isProfessional) {
      return 'e.g., Deliver documents, Move 2 boxes';
    } else if (_isShopping) {
      return 'e.g., Buy groceries, Electronics pickup, Shopping';
    }
    return 'e.g., Deliver documents, Move 2 boxes';
  }

  String get _instructionsHint {
    if (_isRepair) {
      return 'Items to repair, issue details, preferred time, etc...';
    } else if (_isHome) {
      return 'Items to complete, area/room details, preferred time, etc...';
    } else if (_isCare) {
      return 'Care requirements, duration, special instructions...';
    } else if (_isShopping) {
      return 'Items to buy, preferred store, special instructions...';
    }
    return 'Items to carry, floor/flat no, receiver contact info...';
  }

  double get _minBaseBudget {
    final catId = widget.subCategory?.id ?? widget.parentGroup.categoryIds.first;
    final minB = Task.minBudgetForCategory(catId);
    return minB > 0 ? minB : 34.0;
  }

  double get _currentOffer {
    final raw = double.tryParse(_budgetCtrl.text.trim());
    return (raw != null && raw > 0) ? raw : _minBaseBudget;
  }

  double get _platformFee {
    return (_currentOffer * 0.20).roundToDouble();
  }

  double get _totalToPay {
    return _currentOffer + _platformFee;
  }

  @override
  void initState() {
    super.initState();

    _titleCtrl = TextEditingController(
      text: (widget.initialTitle != null && widget.initialTitle!.trim().isNotEmpty)
          ? widget.initialTitle!.trim()
          : '',
    );

    _budgetCtrl = TextEditingController(
      text: _minBaseBudget.toInt().toString(),
    );
    _budgetCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _instructionsCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _onPostTask() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isPosterMode) {
      final switched = await showProfileModeSwitchDialog(
        context,
        targetMode: 'poster',
        title: 'Switch to Poster Profile',
        message: 'Posting tasks requires a Poster profile. Would you like to switch to Poster mode to post this task?',
        actionLabel: 'Switch to Poster & Continue',
      );
      if (!switched || !mounted) return;
    }

    final catId = widget.subCategory?.id ?? widget.parentGroup.categoryIds.first;
    final budget = _currentOffer;
    final fee = _platformFee;
    final total = _totalToPay;
    final title = _titleCtrl.text.trim();
    final instructions = _instructionsCtrl.text.trim();

    final taskData = <String, dynamic>{
      'title': title,
      'description': instructions.isNotEmpty
          ? instructions
          : '${widget.subCategory?.label ?? widget.parentGroup.label} task',
      'category': catId,
      'price': budget,
      'budget': budget,
      'service_charge': fee,
      'serviceCharge': fee,
      'location': {
        'lat': widget.location?.latitude,
        'lng': widget.location?.longitude,
        'address': widget.address,
      },
      'pickup_address': widget.address,
      'pickupAddress': widget.address,
      'drop_address': widget.address,
      'dropAddress': widget.address,
      'delivery_address': widget.address,
      if (Task.isRepairCategory(catId)) ...{
        'separate_costs': 'Materials & spare parts required for service (paid separately by poster)',
      },
    };

    setState(() => _submitting = true);

    final postedOk = await CategoryTaskPostingDialog.show(
      context: context,
      parentGroup: widget.parentGroup,
      subCategory: widget.subCategory,
      category: catId,
      budget: total,
      address: widget.address,
      customTitle: title,
      onPostTask: () => context.read<TaskProvider>().postTask(taskData),
      onTrackInMyTasks: () {
        if (mounted) context.go('/my-tasks');
      },
      onBackToHome: () {
        if (mounted) context.go('/home');
      },
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (postedOk == true) {
      if (mounted) context.go('/my-tasks');
    } else {
      final err = context.read<TaskProvider>().error;
      if (err != null && err.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final offer = _currentOffer;
    final fee = _platformFee;
    final total = _totalToPay;
    final minBudget = _minBaseBudget;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Price Breakdown',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Hero Card with Gradient, 3D Graphic, Pill, and Title
                      _buildHeroCard(),
                      const SizedBox(height: 16),

                      // 2. Task Details Card
                      _buildTaskDetailsCard(),
                      const SizedBox(height: 16),

                      // 3. Task Budget Card
                      _buildTaskBudgetCard(offer, minBudget),
                      const SizedBox(height: 16),

                      // 4. Price Breakdown Card
                      _buildPriceBreakdownCard(offer, fee, total),
                      const SizedBox(height: 16),

                      // 5. Trust / Safety Strip
                      _buildTrustStrip(),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),

            // 6. Bottom Sticky Post Task Button
            _buildBottomBar(total),
          ],
        ),
      ),
    );
  }

  // ── 1. Hero Card ─────────────────────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _heroGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background decorative ambient circles
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left Column: Breadcrumb pill, Title, Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Breadcrumb Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_breadcrumbIcon, size: 14, color: Colors.white),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'Workmate4u › ${widget.parentGroup.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Title
                      Text(
                        _heroTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Subtitle
                      Text(
                        _heroSubtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Right Column: 3D Illustration
                SizedBox(
                  width: 95,
                  height: 95,
                  child: Image.asset(
                    _heroIllustration,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      _breadcrumbIcon,
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Task Details Card ─────────────────────────────────────
  Widget _buildTaskDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6.5),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.edit_note_rounded, size: 20, color: _primaryColor),
              ),
              const SizedBox(width: 9),
              const Text(
                'Task Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Field 1: Task Title *
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Task Title '),
                TextSpan(text: '*', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w800)),
              ],
            ),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _titleCtrl,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            decoration: InputDecoration(
              hintText: _titleHint,
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryColor, width: 1.5),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Please enter a task title';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Field 2: Package Details / Instructions (Optional)
          const Text(
            'Package Details / Instructions (Optional)',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _instructionsCtrl,
            minLines: 2,
            maxLines: 3,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
            decoration: InputDecoration(
              hintText: _instructionsHint,
              hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryColor, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. Task Budget Card ──────────────────────────────────────
  Widget _buildTaskBudgetCard(double offer, double minBudget) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6.5),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.payments_outlined, size: 20, color: _primaryColor),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Task Budget',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Badge Fare Est.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: _primaryColor.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Fare Est. ₹${minBudget.toInt()}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _primaryColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Label: Your Offer to Helper (₹) *
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Your Offer to Helper (₹) '),
                TextSpan(text: '*', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w800)),
              ],
            ),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),

          // Offer Input Field
          TextFormField(
            controller: _budgetCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Text(
                  '₹',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _primaryColor,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primaryColor, width: 1.5),
              ),
            ),
            validator: (v) {
              final parsed = double.tryParse(v?.trim() ?? '');
              if (parsed == null || parsed <= 0) {
                return 'Please enter a valid budget';
              }
              if (parsed < minBudget) {
                return 'Minimum offer for this category is ₹${minBudget.toInt()}';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),

          // Base fare caption
          Text(
            'Base fare for this service: ₹${minBudget.toInt()} (₹12/km (Min ₹${minBudget.toInt()}))',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  // ── 4. Price Breakdown Card ──────────────────────────────────
  Widget _buildPriceBreakdownCard(double offer, double fee, double total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6.5),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.receipt_long_rounded, size: 20, color: _primaryColor),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Price Breakdown',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Green Badge: Pay on Verification
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF15803D)),
                        SizedBox(width: 4),
                        Text(
                          'Pay on Verification',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Line 1: Task Budget
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Task Budget',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
              ),
              Text(
                '₹${offer.toInt()}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 9),

          // Line 2: Platform Fee & GST (20%)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Platform Fee & GST (20%)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
              ),
              Text(
                '₹${fee.toInt()}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Highlight Total Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Amount to Pay',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Pay only after work completion',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                Text(
                  '₹${total.toInt()}',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    color: _primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Security Notice Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9).withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF475569)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No payment needed upfront. Funds are released only after you verify the completed task.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 5. Trust / Safety Strip ──────────────────────────────────
  Widget _buildTrustStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _primaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primaryColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 18, color: _primaryColor),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Verified service partners • Transparent distance rates • No advance payment',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 6. Bottom Sticky Post Task Bar ───────────────────────────
  Widget _buildBottomBar(double total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
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
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _submitting ? null : _onPostTask,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.rocket_launch_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Post Task • ₹${total.toInt()}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
