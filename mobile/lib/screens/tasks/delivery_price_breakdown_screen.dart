import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/profile_mode_switch_dialog.dart';
import '../../widgets/task_price_breakdown_card.dart';
import '../../widgets/vehicle_task_posting_dialog.dart';
import 'vehicle_selection_screen.dart';

/// Screen 3: Price Breakdown and Final Task Confirmation.
///
/// Designed to match the sketch in Image 3:
/// - Route details (Pickup to Drop with distance and ETA).
/// - Selected vehicle card featuring Vehicle SVG, Vehicle Name, Weight carry capacity, and Rate.
/// - Task Title & Instructions/Notes inputs.
/// - Transparent itemized price breakdown (Distance fare, ₹0 service charge, Total).
/// - "Post Task" button triggering the cartoon vector [VehicleTaskPostingDialog].
class DeliveryPriceBreakdownScreen extends StatefulWidget {
  final String pickupAddress;
  final LatLng pickupLocation;
  final String dropAddress;
  final LatLng dropLocation;
  final double distanceKm;
  final DeliveryVehicleOption selectedVehicle;
  final String? initialTitle;

  const DeliveryPriceBreakdownScreen({
    super.key,
    required this.pickupAddress,
    required this.pickupLocation,
    required this.dropAddress,
    required this.dropLocation,
    required this.distanceKm,
    required this.selectedVehicle,
    this.initialTitle,
  });

  @override
  State<DeliveryPriceBreakdownScreen> createState() => _DeliveryPriceBreakdownScreenState();
}

class _DeliveryPriceBreakdownScreenState extends State<DeliveryPriceBreakdownScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  final _descCtrl = TextEditingController();
  late final TextEditingController _budgetCtrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Task Title left blank for poster to fill
    _titleCtrl = TextEditingController(
      text: (widget.initialTitle != null && widget.initialTitle!.trim().isNotEmpty)
          ? widget.initialTitle!.trim()
          : '',
    );

    // Initial budget set to calculated distance price of selected vehicle
    final estimatedFare = widget.selectedVehicle.calculatePrice(widget.distanceKm).toInt();
    _budgetCtrl = TextEditingController(
      text: estimatedFare > 0 ? estimatedFare.toString() : '50',
    );
    _budgetCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
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
        message: 'Posting tasks requires a Poster profile. Would you like to switch to Poster mode to post this delivery task?',
        actionLabel: 'Switch to Poster & Continue',
      );
      if (!switched || !mounted) return;
    }

    final totalBudget = double.tryParse(_budgetCtrl.text.trim()) ??
        widget.selectedVehicle.calculatePrice(widget.distanceKm);
    final title = _titleCtrl.text.trim();
    final description = _descCtrl.text.trim();

    final taskData = <String, dynamic>{
      'title': title,
      'description': description.isNotEmpty ? description : 'Delivery task with ${widget.selectedVehicle.name}',
      'category': widget.selectedVehicle.category,
      'price': totalBudget,
      'budget': totalBudget,
      'service_charge': 0,
      'serviceCharge': 0,
      'location': {
        'lat': widget.pickupLocation.latitude,
        'lng': widget.pickupLocation.longitude,
        'address': widget.pickupAddress,
      },
      'vehicle': widget.selectedVehicle.id,
      'pickup_address': widget.pickupAddress,
      'pickupAddress': widget.pickupAddress,
      'delivery_address': widget.dropAddress,
      'drop_location_address': widget.dropAddress,
      'drop_address': widget.dropAddress,
      'dropAddress': widget.dropAddress,
      'drop_location': {
        'lat': widget.dropLocation.latitude,
        'lng': widget.dropLocation.longitude,
        'address': widget.dropAddress,
      },
      'dropLocation': {
        'lat': widget.dropLocation.latitude,
        'lng': widget.dropLocation.longitude,
        'address': widget.dropAddress,
      },
    };

    setState(() => _submitting = true);

    final postedOk = await VehicleTaskPostingDialog.show(
      context: context,
      category: widget.selectedVehicle.category,
      vehicleType: widget.selectedVehicle.id,
      budget: totalBudget,
      distanceKm: widget.distanceKm,
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
      if (mounted) {
        context.go('/my-tasks');
      }
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
    final vehicle = widget.selectedVehicle;
    final estimatedFare = vehicle.calculatePrice(widget.distanceKm);
    final enteredBudget = double.tryParse(_budgetCtrl.text.trim());
    final currentBudget = (enteredBudget != null && enteredBudget > 0)
        ? enteredBudget
        : estimatedFare;
    final posterFee = (currentBudget * 0.20).roundToDouble();
    final totalCost = currentBudget + posterFee;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Price Breakdown',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: false,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Route summary card
                    _buildRouteCard(),

                    const SizedBox(height: 16),

                    // 2. Selected Vehicle Card (Layout from Sketch Image 3)
                    _buildVehicleSummaryCard(vehicle, estimatedFare),

                    const SizedBox(height: 16),

                    // 3. Task Title and Package Details Input Card
                    _buildTaskDetailsCard(),

                    const SizedBox(height: 16),

                    // 4. Task Budget Input Card (Between Task Details and Price Breakdown)
                    _buildTaskBudgetCard(vehicle, estimatedFare),

                    const SizedBox(height: 16),

                    // 5. Itemized Price Breakdown Card (Matching Reference Image 2)
                    TaskPriceBreakdownCard(
                      budget: currentBudget,
                      posterFee: posterFee,
                      totalCost: totalCost,
                      serviceCharge: 0,
                    ),

                    const SizedBox(height: 16),

                    // 6. Trust Guarantee Banner
                    _buildTrustBanner(),
                  ],
                ),
              ),
            ),

            // Fixed bottom bar with "Post Task" button
            Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _onPostTask,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B63F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    disabledBackgroundColor: const Color(0xFF94A3B8),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.rocket_launch_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Post Task • ₹${totalCost.toInt()}',
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header: Distance and Time Pills
          Row(
            children: [
              const Icon(Icons.navigation_rounded, size: 16, color: Color(0xFF2563EB)),
              const SizedBox(width: 6),
              const Text(
                'Trip Overview',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${widget.distanceKm.toStringAsFixed(1)} km',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Pickup Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 26,
                    color: const Color(0xFFCBD5E1),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pickup',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    Text(
                      widget.pickupAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Drop Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Drop',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    Text(
                      widget.dropAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Vehicle summary card laid out exactly matching the sketch in Image 3:
  /// Left: Vehicle SVG/image
  /// Middle: Vehicle Name & Weight carry capacity
  /// Right: Rate
  Widget _buildVehicleSummaryCard(DeliveryVehicleOption vehicle, double totalFare) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0B63F6), width: 1.6),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B63F6).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left: Vehicle SVG / Image
          Container(
            width: 64,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.asset(
              vehicle.imageAsset,
              width: 52,
              height: 46,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Image.asset(
                vehicle.fallbackAsset,
                width: 52,
                height: 46,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.local_shipping_rounded,
                  size: 32,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Middle: Vehicle Name & Weight carry capacity
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  vehicle.maxWeight,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
          ),

          // Right: Rate
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${totalFare.toInt()}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0B63F6),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                vehicle.rateFormula,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text(
                'Task Details',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Task Title Input
          const Text(
            'Task Title *',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _titleCtrl,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'e.g., Deliver documents, Move 2 boxes',
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
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
                borderSide: const BorderSide(color: Color(0xFF0B63F6), width: 1.5),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Task title is required';
              if (v.trim().length < 3) return 'Title must be at least 3 characters';
              return null;
            },
          ),

          const SizedBox(height: 12),

          // Notes / Package Description Input
          const Text(
            'Package Details / Instructions (Optional)',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _descCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Items to carry, floor/flat no, receiver contact info...',
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                borderSide: const BorderSide(color: Color(0xFF0B63F6), width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskBudgetCard(DeliveryVehicleOption vehicle, double estimatedFare) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 18, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              const Text(
                'Task Budget',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Text(
                  'Fare Est. ₹${estimatedFare.toInt()}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Your Offer to Helper (₹) *',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _budgetCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              hintText: 'Enter budget amount',
              hintStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Color(0xFF94A3B8)),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 14, right: 8),
                child: Text(
                  '₹',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B63F6),
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
                borderSide: const BorderSide(color: Color(0xFF0B63F6), width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Task budget is required';
              }
              final parsed = double.tryParse(v.trim());
              if (parsed == null || parsed <= 0) {
                return 'Please enter a valid budget';
              }
              return null;
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Base fare for this vehicle: ₹${estimatedFare.toInt()} (${vehicle.rateFormula})',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        children: [
          Icon(Icons.security_rounded, size: 18, color: Color(0xFF2563EB)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Verified delivery partners • Transparent distance rates • No advance payment',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1D4ED8),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
