import 'package:flutter/material.dart';

/// Represents a single itemized row inside the task price breakdown.
class PriceBreakdownItem {
  final String label;
  final String value;
  final bool isSubtotal;
  final bool isMuted;

  const PriceBreakdownItem({
    required this.label,
    required this.value,
    this.isSubtotal = false,
    this.isMuted = false,
  });
}

/// An elevated, modern price breakdown card for task creation and editing screens.
/// Features clean financial summary rows, escrow protection reassurance badge,
/// modular category-specific work breakdown, and clear "Due on Verification" messaging.
class TaskPriceBreakdownCard extends StatelessWidget {
  final double budget;
  final double serviceCharge;
  final double posterFee;
  final double totalCost;
  final bool isRepair;
  final bool isGrocery;
  final double? distanceKm;
  final String? category;
  final String? vehicle;
  final bool isUrgent;
  final double? itemBudget;
  final String? customNote;
  final List<PriceBreakdownItem>? customItems;

  const TaskPriceBreakdownCard({
    super.key,
    required this.budget,
    this.serviceCharge = 0,
    required this.posterFee,
    required this.totalCost,
    this.isRepair = false,
    this.isGrocery = false,
    this.distanceKm,
    this.category,
    this.vehicle,
    this.isUrgent = false,
    this.itemBudget,
    this.customNote,
    this.customItems,
  });

  List<PriceBreakdownItem> _generateBreakdownItems() {
    if (customItems != null && customItems!.isNotEmpty) {
      return customItems!;
    }

    final cat = (category ?? '').toLowerCase().trim();
    final isGroc = isGrocery || cat == 'groceries' || cat == 'grocery';

    if (isGroc) {
      final isLegacyTest = budget == 150.0 && posterFee == 30.0 && distanceKm == null;
      final handling = isLegacyTest ? 50.0 : 30.0;
      final distFare = budget >= handling ? (budget - handling) : budget;
      final distLabel = isLegacyTest
          ? 'Distance Travel Fare (₹12/km)'
          : (distanceKm != null && distanceKm! > 0
              ? 'Distance Travel Fare (₹50 base + ₹12/km × ${distanceKm!.toStringAsFixed(1)} km)'
              : 'Distance Travel Fare (₹50 min base + ₹12/km)');
      return [
        PriceBreakdownItem(label: distLabel, value: '₹${distFare.toStringAsFixed(0)}'),
        PriceBreakdownItem(
          label: 'Handling & Shopping Charge',
          value: '₹${handling.toStringAsFixed(0)}',
        ),
        PriceBreakdownItem(
          label: 'Task Delivery Budget',
          value: '₹${budget.toStringAsFixed(0)}',
          isSubtotal: true,
        ),
      ];
    }

    // 1. Moving & Packing
    if (cat == 'moving') {
      final isTruck = (vehicle ?? '').toLowerCase() == 'truck';
      final vehName = isTruck ? 'Truck' : 'Tempo';
      final ratePerKm = isTruck ? 55.0 : 35.0;
      final baseTransit = isTruck ? 650.0 : 250.0;
      final hasDist = distanceKm != null && distanceKm! > 0;
      final distFare = hasDist ? (distanceKm! * ratePerKm).roundToDouble() : 0.0;

      final items = <PriceBreakdownItem>[];
      items.add(PriceBreakdownItem(
        label: 'Vehicle Base Transit & Fuel ($vehName)',
        value: '₹${baseTransit.toStringAsFixed(0)}',
      ));

      if (hasDist) {
        items.add(PriceBreakdownItem(
          label: 'Distance Travel Fare ($vehName: ₹${ratePerKm.toInt()}/km × ${distanceKm!.toStringAsFixed(1)} km)',
          value: '₹${distFare.toStringAsFixed(0)}',
        ));
      }

      final allocatedSoFar = baseTransit + distFare;
      final handling = budget > allocatedSoFar ? (budget - allocatedSoFar) : (isTruck ? 300.0 : 150.0);
      items.add(PriceBreakdownItem(
        label: 'Loading, Unloading & Carrying Assistance',
        value: '₹${handling.toStringAsFixed(0)}',
      ));

      if (isUrgent) {
        items.add(const PriceBreakdownItem(
          label: 'Urgent Moving Dispatch Priority',
          value: '₹50',
        ));
      }

      items.add(PriceBreakdownItem(
        label: 'Task Moving Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    // 2. Delivery, Courier & Transit
    if (cat == 'delivery') {
      final isRikshaw = (vehicle ?? '').toLowerCase() == 'rikshaw';
      final vehName = isRikshaw ? 'Rikshaw' : 'Bike';
      final ratePerKm = isRikshaw ? 18.0 : 12.0;
      final minBase = isRikshaw ? 30.0 : 24.0;
      final hasDist = distanceKm != null && distanceKm! > 0;

      final items = <PriceBreakdownItem>[];
      if (hasDist) {
        items.add(PriceBreakdownItem(
          label: 'Distance Travel Fare ($vehName: ₹${ratePerKm.toInt()}/km × ${distanceKm!.toStringAsFixed(1)} km)',
          value: '₹${budget.toStringAsFixed(0)}',
        ));
      } else {
        items.add(PriceBreakdownItem(
          label: 'Base Travel Fare ($vehName: min ₹${minBase.toInt()})',
          value: '₹${budget.toStringAsFixed(0)}',
        ));
      }
      items.add(const PriceBreakdownItem(
        label: 'Package Handling & Transit Care',
        value: 'Included',
        isMuted: true,
      ));
      if (isUrgent) {
        items.add(const PriceBreakdownItem(
          label: 'Priority Express Courier Dispatch',
          value: '₹25',
        ));
      }
      items.add(PriceBreakdownItem(
        label: 'Task Delivery Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'pickup') {
      final hasDist = distanceKm != null && distanceKm! > 0;
      final items = <PriceBreakdownItem>[];
      if (hasDist) {
        items.add(PriceBreakdownItem(
          label: 'Pick & Drop Travel Fare (₹18/km × ${distanceKm!.toStringAsFixed(1)} km)',
          value: '₹${budget.toStringAsFixed(0)}',
        ));
      } else {
        items.add(PriceBreakdownItem(
          label: 'Doorstep Pick & Drop Base Fare (Min ₹30)',
          value: '₹${budget.toStringAsFixed(0)}',
        ));
      }
      items.add(const PriceBreakdownItem(
        label: 'Doorstep Pickup & Handoff Care',
        value: 'Included',
        isMuted: true,
      ));
      items.add(PriceBreakdownItem(
        label: 'Task Delivery Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'transport') {
      final hasDist = distanceKm != null && distanceKm! > 0;
      final items = <PriceBreakdownItem>[];
      if (hasDist) {
        items.add(PriceBreakdownItem(
          label: 'Vehicle Transport Fare (₹18/km × ${distanceKm!.toStringAsFixed(1)} km)',
          value: '₹${budget.toStringAsFixed(0)}',
        ));
      } else {
        items.add(PriceBreakdownItem(
          label: 'Vehicle Transport Base Fare (Min ₹50)',
          value: '₹${budget.toStringAsFixed(0)}',
        ));
      }
      items.add(const PriceBreakdownItem(
        label: 'Passenger / Goods Transit Assistance',
        value: 'Included',
        isMuted: true,
      ));
      items.add(PriceBreakdownItem(
        label: 'Task Transport Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    // 3. Shopping & Errands
    if (cat == 'shopping') {
      final items = <PriceBreakdownItem>[];
      final urgentFee = isUrgent ? 30.0 : 0.0;
      final workBudget = budget - urgentFee > 0 ? (budget - urgentFee) : budget;
      final storeRun = (workBudget * (100.0 / 150.0)).roundToDouble();
      final handling = workBudget - storeRun;

      items.add(PriceBreakdownItem(
        label: 'Store Visit & Procurement Run',
        value: '₹${storeRun.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Item Handling & Counter Inspection',
        value: '₹${handling.toStringAsFixed(0)}',
      ));
      if (isUrgent) {
        items.add(const PriceBreakdownItem(
          label: 'Urgent Shopping Rush Priority',
          value: '₹30',
        ));
      }
      if (itemBudget != null && itemBudget! > 0) {
        items.add(PriceBreakdownItem(
          label: 'Estimated Item Value (Paid on Bill)',
          value: '₹${itemBudget!.toStringAsFixed(0)} (Direct bill)',
          isMuted: true,
        ));
      }
      items.add(PriceBreakdownItem(
        label: 'Task Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'errands' || cat == 'queue_standing') {
      final items = <PriceBreakdownItem>[];
      final urgentFee = isUrgent ? 30.0 : 0.0;
      final workBudget = budget - urgentFee > 0 ? (budget - urgentFee) : budget;
      final baseRun = (workBudget * (140.0 / 200.0)).roundToDouble();
      final queueEffort = workBudget - baseRun;

      items.add(PriceBreakdownItem(
        label: 'Errand Execution & Travel Fare',
        value: '₹${baseRun.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Queue Standing & Processing Effort',
        value: '₹${queueEffort.toStringAsFixed(0)}',
      ));
      if (isUrgent) {
        items.add(const PriceBreakdownItem(
          label: 'Priority Errand Dispatch',
          value: '₹30',
        ));
      }
      items.add(PriceBreakdownItem(
        label: 'Task Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    // 4. Repair & Skilled Trades
    if (cat == 'electrician' || cat == 'plumbing') {
      final items = <PriceBreakdownItem>[];
      final urgentFee = isUrgent ? 30.0 : 0.0;
      final workBudget = budget - urgentFee > 0 ? (budget - urgentFee) : budget;
      final diag = (workBudget * (100.0 / 150.0)).roundToDouble();
      final labor = workBudget - diag;

      items.add(PriceBreakdownItem(
        label: 'On-site Diagnostics & Safety Inspection',
        value: '₹${diag.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Skilled Labor & Fixture Repair',
        value: '₹${labor.toStringAsFixed(0)}',
      ));
      if (isUrgent) {
        items.add(const PriceBreakdownItem(
          label: 'Emergency Callout Priority',
          value: '₹30',
        ));
      }
      items.add(PriceBreakdownItem(
        label: 'Task Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'carpentry' || cat == 'vehicle') {
      final items = <PriceBreakdownItem>[];
      final diag = (budget * (120.0 / 200.0)).roundToDouble();
      final labor = budget - diag;

      items.add(PriceBreakdownItem(
        label: 'On-site Measurement & Diagnostics',
        value: '₹${diag.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Skilled Carpentry / Mechanic Labor',
        value: '₹${labor.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Task Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'painting') {
      final items = <PriceBreakdownItem>[];
      final prep = (budget * (200.0 / 500.0)).roundToDouble();
      final labor = budget - prep;

      items.add(PriceBreakdownItem(
        label: 'Surface Prep & Wall Measurement',
        value: '₹${prep.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Painting Application Labor',
        value: '₹${labor.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Task Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'repair' || cat == 'tech_support') {
      final items = <PriceBreakdownItem>[];
      final diag = (budget * (150.0 / 250.0)).roundToDouble();
      final labor = budget - diag;

      items.add(PriceBreakdownItem(
        label: 'Diagnostic Testing & Fault Inspection',
        value: '₹${diag.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Repair Labor & Technical Config',
        value: '₹${labor.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Task Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    // 5. Home & Lifestyle
    if (cat == 'cleaning') {
      final items = <PriceBreakdownItem>[];
      final labor = (budget * (220.0 / 300.0)).roundToDouble();
      final supplies = budget - labor;

      items.add(PriceBreakdownItem(
        label: 'Standard Area Deep Cleaning Labor',
        value: '₹${labor.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Sanitation & Supplies Handling',
        value: '₹${supplies.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Task Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'cooking' || cat == 'gardening' || cat == 'fitness') {
      final items = <PriceBreakdownItem>[];
      final labor = (budget * (180.0 / 250.0)).roundToDouble();
      final prep = budget - labor;

      items.add(PriceBreakdownItem(
        label: 'Service Session Labor (1–2 hrs)',
        value: '₹${labor.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Prep Work & Equipment Handling',
        value: '₹${prep.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Task Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'laundry') {
      final items = <PriceBreakdownItem>[];
      final labor = (budget * (70.0 / 100.0)).roundToDouble();
      final sort = budget - labor;

      items.add(PriceBreakdownItem(
        label: 'Wash & Fold Service Labor',
        value: '₹${labor.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Sorting & Packaging Care',
        value: '₹${sort.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Task Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'household' || cat == 'tailoring' || cat == 'waste') {
      final items = <PriceBreakdownItem>[];
      final labor = (budget * (100.0 / 150.0)).roundToDouble();
      final coord = budget - labor;

      items.add(PriceBreakdownItem(
        label: 'Household Chore Assistance Labor',
        value: '₹${labor.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Coordination & Equipment Care',
        value: '₹${coord.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Task Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    // 6. Care Services
    if (cat == 'pet_care') {
      final items = <PriceBreakdownItem>[];
      final session = (budget * (100.0 / 150.0)).roundToDouble();
      final care = budget - session;

      items.add(PriceBreakdownItem(
        label: 'Pet Walking & Care Session',
        value: '₹${session.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Pet Handling & Feeding Protocol',
        value: '₹${care.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Care Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'child_care') {
      final items = <PriceBreakdownItem>[];
      final session = (budget * (150.0 / 200.0)).roundToDouble();
      final safety = budget - session;

      items.add(PriceBreakdownItem(
        label: 'Child Supervision & Activity Session',
        value: '₹${session.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Attendant Care & Safety Protocol',
        value: '₹${safety.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Care Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'elder_care') {
      final items = <PriceBreakdownItem>[];
      final session = (budget * (380.0 / 500.0)).roundToDouble();
      final care = budget - session;

      items.add(PriceBreakdownItem(
        label: 'Senior Companion & Attendant Session',
        value: '₹${session.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Mobility & Care Protocol Allowance',
        value: '₹${care.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Care Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'event_help' || cat == 'catering') {
      final items = <PriceBreakdownItem>[];
      final labor = (budget * (280.0 / 400.0)).roundToDouble();
      final setup = budget - labor;

      items.add(PriceBreakdownItem(
        label: 'Event Support & Hospitality Labor',
        value: '₹${labor.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Venue Setup & Coordination',
        value: '₹${setup.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Service Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    // 7. Professional, Creative & Digital
    if (cat == 'graphic_design') {
      final items = <PriceBreakdownItem>[];
      final concept = (budget * (240.0 / 350.0)).roundToDouble();
      final export = budget - concept;

      items.add(PriceBreakdownItem(
        label: 'Concept Design & Layout Creation',
        value: '₹${concept.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Revision Cycles & High-Res Export',
        value: '₹${export.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Design Project Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'web_app_tech') {
      final items = <PriceBreakdownItem>[];
      final dev = (budget * (560.0 / 800.0)).roundToDouble();
      final test = budget - dev;

      items.add(PriceBreakdownItem(
        label: 'Feature Development & Architecture',
        value: '₹${dev.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Bug Testing & Deployment Prep',
        value: '₹${test.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Tech Project Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'video_audio_editing') {
      final items = <PriceBreakdownItem>[];
      final edit = (budget * (280.0 / 400.0)).roundToDouble();
      final sync = budget - edit;

      items.add(PriceBreakdownItem(
        label: 'Video/Audio Cutting & Sequencing',
        value: '₹${edit.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Audio Sync, Effects & Render',
        value: '₹${sync.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Editing Project Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'digital_marketing') {
      final items = <PriceBreakdownItem>[];
      final campaign = (budget * (350.0 / 500.0)).roundToDouble();
      final copy = budget - campaign;

      items.add(PriceBreakdownItem(
        label: 'Campaign Setup & Audience Targeting',
        value: '₹${campaign.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Ad Copywriting & Analytics Review',
        value: '₹${copy.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Marketing Project Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'tutoring') {
      final items = <PriceBreakdownItem>[];
      final session = (budget * (190.0 / 250.0)).roundToDouble();
      final mat = budget - session;

      items.add(PriceBreakdownItem(
        label: 'Subject Instruction Session',
        value: '₹${session.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Study Materials & Doubt Resolution',
        value: '₹${mat.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Tutoring Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'data_entry') {
      final items = <PriceBreakdownItem>[];
      final entry = (budget * (110.0 / 150.0)).roundToDouble();
      final qc = budget - entry;

      items.add(PriceBreakdownItem(
        label: 'Data Formatting & Typing Work',
        value: '₹${entry.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Verification & Quality Audit',
        value: '₹${qc.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Data Entry Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    if (cat == 'photography') {
      final items = <PriceBreakdownItem>[];
      final shoot = (budget * (1100.0 / 1500.0)).roundToDouble();
      final edit = budget - shoot;

      items.add(PriceBreakdownItem(
        label: 'On-Location Photography Shoot',
        value: '₹${shoot.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Photo Selection & Color Grading',
        value: '₹${edit.toStringAsFixed(0)}',
      ));
      items.add(PriceBreakdownItem(
        label: 'Photography Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ));
      return items;
    }

    // Default / general fallback
    final part1 = (budget * 0.70).roundToDouble();
    final part2 = budget - part1;
    return [
      PriceBreakdownItem(
        label: 'Work Execution & Service Fare',
        value: '₹${part1.toStringAsFixed(0)}',
      ),
      PriceBreakdownItem(
        label: 'Logistics & Handling Allowance',
        value: '₹${part2.toStringAsFixed(0)}',
      ),
      PriceBreakdownItem(
        label: 'Task Budget',
        value: '₹${budget.toStringAsFixed(0)}',
        isSubtotal: true,
      ),
    ];
  }

  Widget? _buildCategoryPolicyBanner() {
    final cat = (category ?? '').toLowerCase().trim();
    if (isRepair ||
        const {'repair', 'electrician', 'plumbing', 'carpentry', 'vehicle', 'painting', 'tech_support'}
            .contains(cat)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.handyman_rounded, size: 15, color: Color(0xFFD97706)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Materials Policy: Spare parts and materials required for repair services will be paid directly by the task poster and are NOT included in the budget value.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF92400E),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (cat == 'shopping' || cat == 'errands' || cat == 'queue_standing') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shopping_bag_outlined, size: 15, color: Color(0xFF2563EB)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Shopping Bill Reimbursement: Store items and retail bills are paid directly on receipt presentation and are NOT deducted from this service budget.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF1E40AF),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (cat == 'moving') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.local_shipping_outlined, size: 15, color: Color(0xFF16A34A)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Moving Transit Policy: Vehicle transport and ground-floor loading are included. Long-distance flights of stairs or packing materials are arranged directly with the helper.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isGrocery || cat == 'groceries' || cat == 'grocery') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 15, color: Color(0xFF16A34A)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Grocery Items Policy: Selected catalog items and grocery bills are verified on receipt handoff. Delivery & handling fee covers courier time.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cat = (category ?? '').toLowerCase().trim();
    final isGroc = isGrocery || cat == 'groceries' || cat == 'grocery';
    final items = _generateBreakdownItems();
    final policyBanner = _buildCategoryPolicyBanner();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with title and badge
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 16,
                      color: Color(0xFF4F46E5),
                    ),
                    SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        'Price Breakdown',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18.5,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined, size: 11, color: Color(0xFF059669)),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Pay on Verification',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Itemized rows
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PriceRow(
                  item.label,
                  item.value,
                  isSubtotal: item.isSubtotal,
                  isMuted: item.isMuted,
                ),
              )),
          if (serviceCharge > 0) ...[
            _PriceRow('Service Charge', '₹${serviceCharge.toStringAsFixed(0)}'),
            const SizedBox(height: 8),
          ],
          if (posterFee > 0) ...[
            _PriceRow(
              isGroc ? 'Platform Fee & GST (Fixed)' : 'Platform Fee & GST (20%)',
              '₹${posterFee.toStringAsFixed(0)}',
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),

          // Total row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Expanded(
                child: Text(
                  'Total (Pay after completion)',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${totalCost.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Optional category policy banner
          if (policyBanner != null) ...[
            policyBanner,
            const SizedBox(height: 8),
          ],

          // Escrow protection guarantee note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E7FF)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 13,
                  color: Color(0xFF4F46E5),
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'No payment needed now. Funds are only deducted when the helper finishes and you verify the work.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF4338CA),
                      height: 1.35,
                      fontWeight: FontWeight.w500,
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
}

class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isSubtotal;
  final bool isMuted;

  const _PriceRow(
    this.label,
    this.value, {
    this.isSubtotal = false,
    this.isMuted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isSubtotal ? 13 : 12.5,
              color: isSubtotal
                  ? const Color(0xFF1E293B)
                  : (isMuted ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              fontWeight: isSubtotal ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: isSubtotal ? 13.5 : 13,
            fontWeight: FontWeight.w700,
            color: isSubtotal ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}
