import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../models/task.dart';
import 'delivery_price_breakdown_screen.dart';

/// Vehicle data specification for Delivery and Moving options.
/// Formatted according to user requirements: removed "NEW" tag, time, and size.
class DeliveryVehicleOption {
  final String id; // 'bike', 'rikshaw', 'tempo', 'truck'
  final String category; // 'delivery' or 'moving'
  final String name;
  final String subtitle;
  final String group;
  final String imageAsset;
  final String fallbackAsset;
  final String maxWeight;
  final String rateFormula;

  const DeliveryVehicleOption({
    required this.id,
    required this.category,
    required this.name,
    required this.subtitle,
    required this.group,
    required this.imageAsset,
    required this.fallbackAsset,
    required this.maxWeight,
    required this.rateFormula,
  });

  /// Calculates the price in INR based on distance.
  double calculatePrice(double distanceKm) {
    return Task.calculateDistancePrice(distanceKm, category, vehicle: id);
  }

  /// The 4 vehicles currently present in Delivery and Moving:
  static const List<DeliveryVehicleOption> all = [
    DeliveryVehicleOption(
      id: 'bike',
      category: 'delivery',
      name: '2 Wheeler',
      subtitle: 'Bike',
      group: 'RECOMMENDED',
      imageAsset: 'assets/images/vehicle_bike.png',
      fallbackAsset: 'assets/images/popup_delivery_scooter_3d.png',
      maxWeight: 'Max: 20 kg',
      rateFormula: '₹12/km (Min ₹24)',
    ),
    DeliveryVehicleOption(
      id: 'rikshaw',
      category: 'delivery',
      name: '3 Wheeler',
      subtitle: 'Auto / Rikshaw',
      group: 'RECOMMENDED',
      imageAsset: 'assets/images/vehicle_rikshaw.png',
      fallbackAsset: 'assets/images/popup_rikshaw_3d.png',
      maxWeight: 'Max: 85 kg',
      rateFormula: '₹18/km (Min ₹30)',
    ),
    DeliveryVehicleOption(
      id: 'tempo',
      category: 'moving',
      name: 'Tempo',
      subtitle: 'Mini Truck',
      group: 'TRUCKS',
      imageAsset: 'assets/images/vehicle_tempo.png',
      fallbackAsset: 'assets/images/popup_delivery_tempo_3d.png',
      maxWeight: 'Max: 400 kg',
      rateFormula: '₹400 base + ₹35/km',
    ),
    DeliveryVehicleOption(
      id: 'truck',
      category: 'moving',
      name: '14ft Truck',
      subtitle: 'Large Moving Truck',
      group: 'TRUCKS',
      imageAsset: 'assets/images/vehicle_truck.png',
      fallbackAsset: 'assets/images/popup_moving_truck_3d.png',
      maxWeight: 'Max: 4000 kg',
      rateFormula: '₹950 base + ₹55/km',
    ),
  ];
}

/// Screen 2: Select Vehicle Option.
///
/// Designed to match user's updated sketches in Image 3:
/// - Clean card layout showing Vehicle SVG, Vehicle Name, Max Weight Carry Capacity, and Price.
/// - NO "NEW" tag, NO time estimate, NO vehicle size tags.
/// - Interactive selection animation (Image 3 right sketch):
///   When a vehicle is tapped, the SVG animates/moves into position, the card expands,
///   and the capacity box & price adjust dynamically with smooth spring curves.
class VehicleSelectionScreen extends StatefulWidget {
  final String pickupAddress;
  final LatLng pickupLocation;
  final String dropAddress;
  final LatLng dropLocation;
  final double distanceKm;
  final String? initialTitle;

  const VehicleSelectionScreen({
    super.key,
    required this.pickupAddress,
    required this.pickupLocation,
    required this.dropAddress,
    required this.dropLocation,
    required this.distanceKm,
    this.initialTitle,
  });

  @override
  State<VehicleSelectionScreen> createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends State<VehicleSelectionScreen> {
  late DeliveryVehicleOption _selectedVehicle;

  @override
  void initState() {
    super.initState();
    _selectedVehicle = DeliveryVehicleOption.all.first;
  }

  void _onContinue() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeliveryPriceBreakdownScreen(
          pickupAddress: widget.pickupAddress,
          pickupLocation: widget.pickupLocation,
          dropAddress: widget.dropAddress,
          dropLocation: widget.dropLocation,
          distanceKm: widget.distanceKm,
          selectedVehicle: _selectedVehicle,
          initialTitle: widget.initialTitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recommendedVehicles = DeliveryVehicleOption.all.where((v) => v.group == 'RECOMMENDED').toList();
    final truckVehicles = DeliveryVehicleOption.all.where((v) => v.group == 'TRUCKS').toList();

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
          'Select Vehicle',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Route and distance summary chip bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.route_rounded, size: 16, color: Color(0xFF2563EB)),
                      const SizedBox(width: 5),
                      Text(
                        '${widget.distanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.pickupAddress} → ${widget.dropAddress}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable list of vehicles
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // RECOMMENDED Section
                  _buildSectionHeader('RECOMMENDED'),
                  const SizedBox(height: 8),
                  ...recommendedVehicles.map(_buildAnimatedVehicleCard),

                  const SizedBox(height: 18),

                  // TRUCKS Section
                  _buildSectionHeader('TRUCKS'),
                  const SizedBox(height: 8),
                  ...truckVehicles.map(_buildAnimatedVehicleCard),
                ],
              ),
            ),
          ),

          // Fixed bottom button bar
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
                onPressed: _onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B63F6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue with ${_selectedVehicle.name}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xFF64748B),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  /// Vehicle card with animation of SVG movement and details adjustment
  /// exactly matching the before & after sketches in Image 3.
  Widget _buildAnimatedVehicleCard(DeliveryVehicleOption vehicle) {
    final isSelected = _selectedVehicle.id == vehicle.id;
    final price = vehicle.calculatePrice(widget.distanceKm);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_selectedVehicle.id != vehicle.id) {
              setState(() => _selectedVehicle = vehicle);
            }
          },
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: isSelected ? 16 : 12,
            ),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFF0F6FF) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isSelected ? const Color(0xFF0B63F6) : const Color(0xFFE2E8F0),
                width: isSelected ? 2.2 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? const Color(0xFF0B63F6).withValues(alpha: 0.14)
                      : const Color(0xFF0F172A).withValues(alpha: 0.03),
                  blurRadius: isSelected ? 12 : 6,
                  offset: isSelected ? const Offset(0, 4) : const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Animated Vehicle SVG / Image container ("Moving of SVG" from Image 3 right sketch)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: isSelected ? 82 : 68,
                  height: isSelected ? 70 : 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    scale: isSelected ? 1.15 : 1.0,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      offset: isSelected ? const Offset(0.04, 0) : Offset.zero,
                      child: Image.asset(
                        vehicle.imageAsset,
                        width: isSelected ? 66 : 54,
                        height: isSelected ? 58 : 46,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Image.asset(
                          vehicle.fallbackAsset,
                          width: isSelected ? 66 : 54,
                          height: isSelected ? 58 : 46,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            vehicle.category == 'moving' ? Icons.local_shipping_rounded : Icons.two_wheeler_rounded,
                            size: isSelected ? 40 : 34,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                // Vehicle Details: Name & Max Weight Carry Capacity
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Name of vehicle
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 240),
                        style: TextStyle(
                          fontSize: isSelected ? 17 : 15.5,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? const Color(0xFF0B63F6) : const Color(0xFF0F172A),
                          letterSpacing: -0.2,
                          fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
                        ),
                        child: Text(vehicle.name),
                      ),

                      const SizedBox(height: 6),

                      // Max weight carry capacity (Box/pill from sketch)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.scale_rounded,
                              size: 13,
                              color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              vehicle.maxWeight,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Price display on right (Amount from sketch)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 240),
                      style: TextStyle(
                        fontSize: isSelected ? 21 : 18,
                        fontWeight: FontWeight.w900,
                        color: isSelected ? const Color(0xFF0B63F6) : const Color(0xFF0F172A),
                        letterSpacing: -0.3,
                        fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
                      ),
                      child: Text('₹${price.toInt()}'),
                    ),
                    const SizedBox(height: 3),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B63F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 10, color: Colors.white),
                            SizedBox(width: 3),
                            Text(
                              'Selected',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        vehicle.category == 'moving' ? 'Base + dist' : 'Fare',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF94A3B8),
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
  }
}
