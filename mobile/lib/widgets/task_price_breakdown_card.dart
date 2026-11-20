import 'package:flutter/material.dart';

/// An elevated, modern price breakdown card for task creation and editing screens.
/// Features clean financial summary rows, escrow protection reassurance badge,
/// and clear "Due on Verification" messaging.
class TaskPriceBreakdownCard extends StatelessWidget {
  final double budget;
  final double serviceCharge;
  final double posterFee;
  final double totalCost;
  final bool isRepair;
  final bool isGrocery;
  final double? distanceKm;
  final String? customNote;

  const TaskPriceBreakdownCard({
    super.key,
    required this.budget,
    this.serviceCharge = 0,
    required this.posterFee,
    required this.totalCost,
    this.isRepair = false,
    this.isGrocery = false,
    this.distanceKm,
    this.customNote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A56).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with title and verified badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      size: 18,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Price Breakdown',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16.5,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_rounded, size: 12, color: Color(0xFF059669)),
                    SizedBox(width: 4),
                    Text(
                      'Pay on Verification',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF065F46),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Itemized rows
          if (isGrocery) ...[
            _PriceRow(
              distanceKm != null && distanceKm! > 0
                  ? 'Distance Fare (₹50 base + ₹12/km × ${distanceKm!.toStringAsFixed(1)} km)'
                  : 'Distance Fare (₹50 min base + ₹12/km)',
              '₹${(budget >= 30.0 ? (budget - 30.0) : budget).toStringAsFixed(0)}',
            ),
            const SizedBox(height: 10),
            const _PriceRow('Handling & Shopping Charge', '₹30'),
            const SizedBox(height: 10),
            _PriceRow('Delivery Budget', '₹${budget.toStringAsFixed(0)}'),
            const SizedBox(height: 10),
            const _PriceRowWithBadge(
              label: 'Platform Fee & GST',
              badgeText: 'Flat ₹12',
              value: '₹12',
            ),
          ] else if (isRepair) ...[
            _PriceRow('Technician Visiting Fee', '₹${budget.toStringAsFixed(0)}'),
            const SizedBox(height: 10),
            const _PriceRowWithBadge(
              label: 'Platform Fee & GST',
              badgeText: 'Flat ₹20',
              value: '₹20',
            ),
          ] else ...[
            _PriceRow('Task Budget', '₹${budget.toStringAsFixed(0)}'),
            if (serviceCharge > 0) ...[
              const SizedBox(height: 10),
              _PriceRow('Service Charge', '₹${serviceCharge.toStringAsFixed(0)}'),
            ],
            if (posterFee > 0) ...[
              const SizedBox(height: 10),
              _PriceRow('Platform Fee & GST (20%)', '₹${posterFee.toStringAsFixed(0)}'),
            ],
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),

          // Total row with elevated styling
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Amount to Pay',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Pay only after work completion',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${totalCost.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: Color(0xFF4338CA),
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          if (isRepair) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A), width: 1.1),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: Color(0xFFD97706),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Spare parts & extra materials (if required) are quoted on-site and paid directly to the technician.',
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
            ),
            const SizedBox(height: 8),
          ],

          // Escrow protection guarantee note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE0E7FF)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: Color(0xFF4F46E5),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No payment needed upfront. Funds are released only after you verify the completed task.',
                    style: TextStyle(
                      fontSize: 11.5,
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
  const _PriceRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

class _PriceRowWithBadge extends StatelessWidget {
  final String label;
  final String badgeText;
  final String value;

  const _PriceRowWithBadge({
    required this.label,
    required this.badgeText,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Text(
                badgeText,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4338CA),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}
