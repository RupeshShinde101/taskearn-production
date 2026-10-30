import 'package:flutter/material.dart';

/// An elevated, modern price breakdown card for task creation and editing screens.
/// Features clean financial summary rows, escrow protection reassurance badge,
/// and clear "Due on Verification" messaging.
class TaskPriceBreakdownCard extends StatelessWidget {
  final double budget;
  final double serviceCharge;
  final double posterFee;
  final double totalCost;

  const TaskPriceBreakdownCard({
    super.key,
    required this.budget,
    this.serviceCharge = 0,
    required this.posterFee,
    required this.totalCost,
  });

  @override
  Widget build(BuildContext context) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 16,
                    color: Color(0xFF4F46E5),
                  ),
                  SizedBox(width: 7),
                  Text(
                    'Price Breakdown',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: Color(0xFF0F172A),
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
                    Text(
                      'Pay on Verification',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Itemized rows
          _PriceRow('Task Budget', '₹${budget.toStringAsFixed(0)}'),
          if (serviceCharge > 0) ...[
            const SizedBox(height: 8),
            _PriceRow('Distance / Service Charge', '₹${serviceCharge.toStringAsFixed(0)}'),
          ],
          if (posterFee > 0) ...[
            const SizedBox(height: 8),
            _PriceRow('Platform Fee & GST (20%)', '₹${posterFee.toStringAsFixed(0)}'),
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
              const Text(
                'Total (Pay after completion)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: Color(0xFF0F172A),
                ),
              ),
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
  const _PriceRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}
