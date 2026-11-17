import 'package:flutter/material.dart';
import '../../models/grocery_item.dart';

class GroceryItemPickerScreen extends StatefulWidget {
  final List<SelectedGroceryItem> initialSelected;

  const GroceryItemPickerScreen({
    super.key,
    this.initialSelected = const [],
  });

  @override
  State<GroceryItemPickerScreen> createState() => _GroceryItemPickerScreenState();
}

class _GroceryItemPickerScreenState extends State<GroceryItemPickerScreen> {
  late final Map<String, SelectedGroceryItem> _selectedMap;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedMap = {
      for (final item in widget.initialSelected) item.id: item.copyWith(),
    };
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<GroceryCatalogItem> get _filteredItems {
    return GroceryCatalog.allItems.where((item) {
      if (_selectedCategory != 'All' && item.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatch = item.name.toLowerCase().contains(q);
        final catMatch = item.category.toLowerCase().contains(q);
        final brandMatch = item.popularBrands.any((b) => b.toLowerCase().contains(q));
        return nameMatch || catMatch || brandMatch;
      }
      return true;
    }).toList();
  }

  void _showWeightLimitExceededDialog({
    required double currentWeight,
    required double attemptedWeight,
    required double itemWeight,
  }) {
    showDialog(
      context: context,
      builder: (alertCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 26),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Weight Limit Exceeded',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF102A56)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Two-wheeler (Bike / Scooty) delivery has a strict maximum capacity of 20 kg for road safety.',
              style: TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Max Allowed Weight:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                      Text('20.0 kg', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF102A56))),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Current Cart Weight:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                      Text('${currentWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF102A56))),
                    ],
                  ),
                  if (itemWeight > 0) ...[
                    const SizedBox(height: 5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Item Weight:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFDC2626))),
                        Text('+${itemWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                      ],
                    ),
                  ],
                  const Divider(height: 14, thickness: 1, color: Color(0xFFFECACA)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total If Added:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFFDC2626))),
                      Text('${attemptedWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFDC2626))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Please manage weight or reduce item quantities to keep total weight under 20 kg.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(alertCtx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Manage Weight & Items', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openItemRequirementDialog(GroceryCatalogItem item) {
    final existing = _selectedMap[item.id];

    // Initial prefilled package
    String selectedPackage = existing?.package ?? '';
    if (selectedPackage.isEmpty) {
      if (existing?.gram.isNotEmpty == true) {
        selectedPackage = '${existing!.gram}g';
      } else if (existing?.kg.isNotEmpty == true) {
        selectedPackage = '${existing!.kg}kg';
      } else if (existing?.litr.isNotEmpty == true) {
        selectedPackage = '${existing!.litr}L';
      } else if (existing?.qty.isNotEmpty == true) {
        selectedPackage = '${existing!.qty} Pack';
      } else if (item.effectivePackages.isNotEmpty) {
        selectedPackage = item.effectivePackages.first;
      }
    }

    int currentQty = int.tryParse(existing?.qty ?? '') ?? 1;
    if (currentQty < 1) currentQty = 1;
    final qtyCtrl = TextEditingController(text: currentQty.toString());

    String selectedBrand = existing?.brand ?? '';
    final brandCtrl = TextEditingController(text: selectedBrand);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 18,
                left: 18,
                right: 18,
                top: 14,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Header: Image + Name + Remove (if editing) + Close
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: item.bgColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: Image.network(
                              item.imageUrl,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(item.emoji, style: const TextStyle(fontSize: 24)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF102A56),
                                ),
                                maxLines: 2,
                                softWrap: true,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.category,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (existing != null) ...[
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedMap.remove(item.id);
                              });
                              Navigator.pop(modalCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Removed ${item.name} from your list'),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            ),
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFDC2626)),
                            label: const Text('Remove', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ],
                        IconButton(
                          onPressed: () => Navigator.pop(modalCtx),
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Unit Specific Package / Value Option ──
                    if (item.unitType == GroceryUnitType.weight) ...[
                      const Text(
                        'Select Package Weight',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF102A56)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: item.effectivePackages.map((pkg) {
                          final isSel = selectedPackage == pkg;
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                selectedPackage = pkg;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSel ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSel ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                                  width: 1.2,
                                ),
                              ),
                              child: Text(
                                pkg,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isSel ? Colors.white : const Color(0xFF334155),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ] else if (item.unitType == GroceryUnitType.liquid) ...[
                      const Text(
                        'Select Volume / Pack',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF102A56)),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: item.effectivePackages.map((pkg) {
                          final isSel = selectedPackage == pkg;
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                selectedPackage = pkg;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSel ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSel ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                                  width: 1.2,
                                ),
                              ),
                              child: Text(
                                pkg,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isSel ? Colors.white : const Color(0xFF334155),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ] else ...[
                      // Count item: Stepper with editable value
                      const Text(
                        'Select Quantity',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF102A56)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_rounded, color: Color(0xFF1E293B)),
                                  onPressed: () {
                                    if (currentQty > 1) {
                                      setModalState(() {
                                        currentQty--;
                                        qtyCtrl.text = currentQty.toString();
                                        selectedPackage = '$currentQty Pack${currentQty > 1 ? 's' : ''}';
                                      });
                                    }
                                  },
                                ),
                                Container(
                                  width: 44,
                                  alignment: Alignment.center,
                                  child: TextField(
                                    controller: qtyCtrl,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF102A56),
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onChanged: (val) {
                                      final parsed = int.tryParse(val.trim());
                                      if (parsed != null && parsed > 0 && parsed <= 50) {
                                        currentQty = parsed;
                                        selectedPackage = '$currentQty Pack${currentQty > 1 ? 's' : ''}';
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_rounded, color: Color(0xFF1E293B)),
                                  onPressed: () {
                                    if (currentQty < 50) {
                                      setModalState(() {
                                        currentQty++;
                                        qtyCtrl.text = currentQty.toString();
                                        selectedPackage = '$currentQty Pack${currentQty > 1 ? 's' : ''}';
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: item.effectivePackages.map((pkg) {
                                  final isSel = selectedPackage == pkg;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: GestureDetector(
                                      onTap: () {
                                        setModalState(() {
                                          selectedPackage = pkg;
                                          final m = RegExp(r'(\d+)').firstMatch(pkg);
                                          if (m != null) {
                                            currentQty = int.tryParse(m.group(1)!) ?? currentQty;
                                            qtyCtrl.text = currentQty.toString();
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: isSel ? const Color(0xFF2563EB) : const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isSel ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: Text(
                                          pkg,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: isSel ? Colors.white : const Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Popular Brands (if available)
                    if (item.popularBrands.isNotEmpty) ...[
                      const Text(
                        'Brand Preference (Optional)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF102A56)),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          GestureDetector(
                            onTap: () {
                              setModalState(() {
                                selectedBrand = '';
                                brandCtrl.clear();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: selectedBrand.isEmpty ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selectedBrand.isEmpty ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                'Any Brand',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: selectedBrand.isEmpty ? FontWeight.w800 : FontWeight.w500,
                                  color: selectedBrand.isEmpty ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                          ...item.popularBrands.map((b) {
                            final isSel = selectedBrand == b;
                            return GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  selectedBrand = b;
                                  brandCtrl.text = b;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isSel ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSel ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Text(
                                  b,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                                    color: isSel ? const Color(0xFF2563EB) : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 14),

                    // Direct Add / Update in List Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final finalPkg = selectedPackage.isNotEmpty
                              ? selectedPackage
                              : (item.unitType == GroceryUnitType.count ? '$currentQty Pack' : item.effectivePackages.first);

                          String q = '';
                          String k = '';
                          String g = '';
                          String l = '';

                          if (item.unitType == GroceryUnitType.count) {
                            q = currentQty.toString();
                          } else {
                            final gMatch = RegExp(r'(\d+)\s*g\b', caseSensitive: false).firstMatch(finalPkg);
                            if (gMatch != null) g = gMatch.group(1)!;

                            final kgMatch = RegExp(r'(\d+)\s*kg\b', caseSensitive: false).firstMatch(finalPkg);
                            if (kgMatch != null) k = kgMatch.group(1)!;

                            final mlMatch = RegExp(r'(\d+)\s*ml\b', caseSensitive: false).firstMatch(finalPkg);
                            if (mlMatch != null) g = mlMatch.group(1)!;

                            final lMatch = RegExp(r'(\d+)\s*L\b', caseSensitive: false).firstMatch(finalPkg);
                            if (lMatch != null) l = lMatch.group(1)!;
                          }

                          final selected = SelectedGroceryItem(
                            id: item.id,
                            name: item.name,
                            category: item.category,
                            imageUrl: item.imageUrl,
                            emoji: item.emoji,
                            package: finalPkg,
                            qty: q,
                            kg: k,
                            gram: g,
                            litr: l,
                            rupee: existing?.rupee ?? '',
                            brand: selectedBrand.isNotEmpty ? selectedBrand : brandCtrl.text.trim(),
                          );

                          // Check 20kg weight limit for two-wheeler delivery
                          final currentWeightExcludingThis = _selectedMap.values
                              .where((e) => e.id != item.id)
                              .fold<double>(0.0, (sum, e) => sum + e.estimatedWeightKg);
                          final itemWeight = selected.estimatedWeightKg;
                          final attemptedTotal = currentWeightExcludingThis + itemWeight;

                          if (itemWeight > GroceryCatalog.maxTwoWheelerWeightKg ||
                              attemptedTotal > GroceryCatalog.maxTwoWheelerWeightKg) {
                            _showWeightLimitExceededDialog(
                              currentWeight: currentWeightExcludingThis,
                              attemptedWeight: attemptedTotal,
                              itemWeight: itemWeight,
                            );
                            return;
                          }

                          setState(() {
                            _selectedMap[item.id] = selected;
                          });
                          Navigator.pop(modalCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Added ${item.name} ($finalPkg) to list'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: const Color(0xFF15803D),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: Icon(existing != null ? Icons.check_circle_rounded : Icons.add_shopping_cart_rounded, size: 18),
                        label: Text(
                          existing != null ? 'Update in List' : 'Add to List',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final totalAdded = _selectedMap.length;
    final totalWeight = GroceryCatalog.calculateTotalWeightKg(_selectedMap.values);
    final weightProgress = (totalWeight / GroceryCatalog.maxTwoWheelerWeightKg).clamp(0.0, 1.0);
    final isNearLimit = totalWeight >= 16.0;
    final isOverLimit = totalWeight > GroceryCatalog.maxTwoWheelerWeightKg;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        title: const Text(
          'Select Grocery Items',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF102A56),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF102A56)),
          onPressed: () => Navigator.of(context).pop(_selectedMap.values.toList()),
        ),
        actions: [
          if (totalAdded > 0)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOverLimit ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isOverLimit ? const Color(0xFFFCA5A5) : const Color(0xFF86EFAC)),
                ),
                child: Text(
                  '$totalAdded Items · ${totalWeight.toStringAsFixed(1)} kg',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isOverLimit ? const Color(0xFF991B1B) : const Color(0xFF166534),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Vehicle capacity & Weight limit indicator
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isOverLimit
                    ? const Color(0xFFFEF2F2)
                    : (isNearLimit ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOverLimit
                      ? const Color(0xFFFCA5A5)
                      : (isNearLimit ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              isOverLimit ? '⚠️' : '🛵',
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Bike / Scooty Capacity:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isOverLimit
                                      ? const Color(0xFF991B1B)
                                      : (isNearLimit ? const Color(0xFF92400E) : const Color(0xFF166534)),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${totalWeight.toStringAsFixed(1)} / 20.0 kg',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isOverLimit
                              ? const Color(0xFFDC2626)
                              : (isNearLimit ? const Color(0xFFD97706) : const Color(0xFF15803D)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: weightProgress,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isOverLimit
                            ? const Color(0xFFDC2626)
                            : (isNearLimit ? const Color(0xFFD97706) : const Color(0xFF16A34A)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Search & Filters Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search field
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Search items (e.g. Methi, Palak, Milk, Atta, Maggi...)',
                    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF2563EB)),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Category chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: GroceryCatalog.categories.map((cat) {
                      final isSel = cat == _selectedCategory;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedCategory = cat),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFF2563EB) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSel ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                color: isSel ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Items list — one item card in one row
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 10),
                        Text(
                          'No grocery items found for "$_searchQuery"',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final isSelected = _selectedMap.containsKey(item.id);
                      final selectedInfo = _selectedMap[item.id];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFE5EDF7),
                            width: isSelected ? 1.5 : 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isSelected
                                  ? const Color(0xFF2563EB).withValues(alpha: 0.08)
                                  : const Color(0xFF102A56).withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _openItemRequirementDialog(item),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Item Image with background
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: item.bgColor,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(13),
                                    child: Image.network(
                                      item.imageUrl,
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Text(item.emoji, style: const TextStyle(fontSize: 28)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Item details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                          color: Color(0xFF102A56),
                                          letterSpacing: -0.2,
                                        ),
                                        maxLines: 2,
                                        softWrap: true,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        item.category,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (isSelected && selectedInfo != null) ...[
                                        const SizedBox(height: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF0FDF4),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFBBF7D0)),
                                          ),
                                          child: Text(
                                            selectedInfo.requirementSummary,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF15803D),
                                            ),
                                            maxLines: 2,
                                            softWrap: true,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ] else if (item.popularBrands.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Brands: ${item.popularBrands.join(', ')}',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: Color(0xFF94A3B8),
                                          ),
                                          maxLines: 2,
                                          softWrap: true,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Right action button
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? const Color(0xFF86EFAC) : const Color(0xFFBFDBFE),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isSelected ? Icons.edit_rounded : Icons.add_rounded,
                                        size: 16,
                                        color: isSelected ? const Color(0xFF166534) : const Color(0xFF2563EB),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isSelected ? 'Edit' : 'Add',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: isSelected ? const Color(0xFF166534) : const Color(0xFF2563EB),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),

      // Bottom Bar with "Save & Continue" button
      bottomSheet: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  final totalW = GroceryCatalog.calculateTotalWeightKg(_selectedMap.values);
                  if (totalW > GroceryCatalog.maxTwoWheelerWeightKg) {
                    _showWeightLimitExceededDialog(
                      currentWeight: totalW,
                      attemptedWeight: totalW,
                      itemWeight: 0,
                    );
                    return;
                  }
                  Navigator.of(context).pop(_selectedMap.values.toList());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                label: Text(
                  totalAdded > 0 ? 'Save & Continue ($totalAdded Items · ${totalWeight.toStringAsFixed(1)} kg)' : 'Save & Continue',
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
