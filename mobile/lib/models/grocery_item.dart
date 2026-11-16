import 'dart:convert';
import 'package:flutter/material.dart';

/// Predefined grocery item in the market catalog.
class GroceryCatalogItem {
  final String id;
  final String name;
  final String category;
  final String imageUrl;
  final String emoji;
  final Color bgColor;
  final List<String> popularBrands;

  const GroceryCatalogItem({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.emoji,
    required this.bgColor,
    this.popularBrands = const [],
  });
}

/// An item selected and customized by the task poster.
class SelectedGroceryItem {
  final String id;
  final String name;
  final String category;
  final String imageUrl;
  final String emoji;
  String qty;
  String kg;
  String gram;
  String litr;
  String rupee;
  String brand;

  SelectedGroceryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.emoji,
    this.qty = '',
    this.kg = '',
    this.gram = '',
    this.litr = '',
    this.rupee = '',
    this.brand = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'image_url': imageUrl,
    'emoji': emoji,
    if (qty.trim().isNotEmpty) 'qty': qty.trim(),
    if (kg.trim().isNotEmpty) 'kg': kg.trim(),
    if (gram.trim().isNotEmpty) 'gram': gram.trim(),
    if (litr.trim().isNotEmpty) 'litr': litr.trim(),
    if (rupee.trim().isNotEmpty) 'rupee': rupee.trim(),
    if (brand.trim().isNotEmpty) 'brand': brand.trim(),
  };

  factory SelectedGroceryItem.fromJson(Map<String, dynamic> json) {
    return SelectedGroceryItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Groceries',
      imageUrl: (json['image_url'] ?? json['imageUrl'])?.toString() ?? '',
      emoji: json['emoji']?.toString() ?? '🛒',
      qty: json['qty']?.toString() ?? '',
      kg: json['kg']?.toString() ?? '',
      gram: json['gram']?.toString() ?? '',
      litr: json['litr']?.toString() ?? '',
      rupee: json['rupee']?.toString() ?? '',
      brand: json['brand']?.toString() ?? '',
    );
  }

  SelectedGroceryItem copyWith({
    String? qty,
    String? kg,
    String? gram,
    String? litr,
    String? rupee,
    String? brand,
  }) {
    return SelectedGroceryItem(
      id: id,
      name: name,
      category: category,
      imageUrl: imageUrl,
      emoji: emoji,
      qty: qty ?? this.qty,
      kg: kg ?? this.kg,
      gram: gram ?? this.gram,
      litr: litr ?? this.litr,
      rupee: rupee ?? this.rupee,
      brand: brand ?? this.brand,
    );
  }

  /// Compact one-line summary for badges and card previews.
  String get requirementSummary {
    final parts = <String>[];
    if (qty.trim().isNotEmpty) parts.add('${qty.trim()} Qty');
    if (kg.trim().isNotEmpty) parts.add('${kg.trim()} kg');
    if (gram.trim().isNotEmpty) parts.add('${gram.trim()} g');
    if (litr.trim().isNotEmpty) parts.add('${litr.trim()} L');
    if (brand.trim().isNotEmpty) parts.add(brand.trim());
    if (rupee.trim().isNotEmpty) parts.add('₹${rupee.trim()}');
    if (parts.isEmpty) return 'Standard Pack';
    return parts.join(' · ');
  }

  /// Formatted string for task description bullet points.
  String get descriptionLine {
    final parts = <String>[];
    if (qty.trim().isNotEmpty) parts.add('Qty: ${qty.trim()}');
    if (kg.trim().isNotEmpty) parts.add('${kg.trim()} kg');
    if (gram.trim().isNotEmpty) parts.add('${gram.trim()} g');
    if (litr.trim().isNotEmpty) parts.add('${litr.trim()} L');
    if (brand.trim().isNotEmpty) parts.add('Brand: ${brand.trim()}');
    if (rupee.trim().isNotEmpty) parts.add('Est: ₹${rupee.trim()}');
    final details = parts.isNotEmpty ? ' (${parts.join(', ')})' : '';
    return '• $name$details';
  }

  String get formattedDescription => descriptionLine.replaceFirst('• ', '');
}

/// Comprehensive catalog of market grocery items organized by department.
class GroceryCatalog {
  static const List<String> categories = [
    'All',
    'Dairy & Breakfast',
    'Staples & Dals',
    'Vegetables & Fruits',
    'Oils & Masalas',
    'Snacks & Beverages',
    'Cleaning & Household',
  ];

  static const List<GroceryCatalogItem> allItems = [
    // ── Dairy & Breakfast ──────────────────────────────────────────────────
    GroceryCatalogItem(
      id: 'milk',
      name: 'Fresh Milk',
      category: 'Dairy & Breakfast',
      emoji: '🥛',
      bgColor: Color(0xFFEFF6FF),
      imageUrl: 'https://images.unsplash.com/photo-1550583724-b2692b85b150?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Amul', 'Mother Dairy', 'Nandini', 'Govind'],
    ),
    GroceryCatalogItem(
      id: 'curd',
      name: 'Curd / Dahi',
      category: 'Dairy & Breakfast',
      emoji: '🥣',
      bgColor: Color(0xFFF0FDF4),
      imageUrl: 'https://images.unsplash.com/photo-1571212515416-fef01fc43637?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Amul', 'Mother Dairy', 'Gowardhan'],
    ),
    GroceryCatalogItem(
      id: 'paneer',
      name: 'Fresh Paneer',
      category: 'Dairy & Breakfast',
      emoji: '🧀',
      bgColor: Color(0xFFFFFBEB),
      imageUrl: 'https://images.unsplash.com/photo-1631452180519-c014fe946bc7?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Amul', 'Mother Dairy', 'Local Dairy'],
    ),
    GroceryCatalogItem(
      id: 'butter',
      name: 'Butter',
      category: 'Dairy & Breakfast',
      emoji: '🧈',
      bgColor: Color(0xFFFEF3C7),
      imageUrl: 'https://images.unsplash.com/photo-1589985270826-4b7bb135bc9d?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Amul', 'Nutralite', 'Mother Dairy'],
    ),
    GroceryCatalogItem(
      id: 'cheese',
      name: 'Cheese Slices / Block',
      category: 'Dairy & Breakfast',
      emoji: '🧀',
      bgColor: Color(0xFFFFF7ED),
      imageUrl: 'https://images.unsplash.com/photo-1486297678162-eb2a19b0a32d?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Amul', 'Britannia', 'Go Cheese'],
    ),
    GroceryCatalogItem(
      id: 'bread',
      name: 'Fresh Bread',
      category: 'Dairy & Breakfast',
      emoji: '🍞',
      bgColor: Color(0xFFFDF4FF),
      imageUrl: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Britannia', 'Modern', 'Harvest Gold'],
    ),
    GroceryCatalogItem(
      id: 'eggs',
      name: 'Eggs (Tray / Pack)',
      category: 'Dairy & Breakfast',
      emoji: '🥚',
      bgColor: Color(0xFFFFFBEB),
      imageUrl: 'https://images.unsplash.com/photo-1506976785307-8732e854ad03?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Fresh Farm', 'Eggoz', 'Suguna'],
    ),

    // ── Staples & Dals ─────────────────────────────────────────────────────
    GroceryCatalogItem(
      id: 'atta',
      name: 'Atta / Wheat Flour',
      category: 'Staples & Dals',
      emoji: '🌾',
      bgColor: Color(0xFFFEF2F2),
      imageUrl: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Aashirvaad', 'Fortune', 'Patanjali', 'Chakki Fresh'],
    ),
    GroceryCatalogItem(
      id: 'rice',
      name: 'Rice (Basmati / Kolam)',
      category: 'Staples & Dals',
      emoji: '🍚',
      bgColor: Color(0xFFF8FAFC),
      imageUrl: 'https://images.unsplash.com/photo-1586201375761-83865001e31c?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['India Gate', 'Daawat', 'Fortune', 'Wada Kolam'],
    ),
    GroceryCatalogItem(
      id: 'toor_dal',
      name: 'Toor / Arhar Dal',
      category: 'Staples & Dals',
      emoji: '🥣',
      bgColor: Color(0xFFFEF9C3),
      imageUrl: 'https://images.unsplash.com/photo-1546833999-b9f581a1996d?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Tata Sampann', 'Fortune', 'Catch'],
    ),
    GroceryCatalogItem(
      id: 'moong_dal',
      name: 'Moong Dal (Yellow / Green)',
      category: 'Staples & Dals',
      emoji: '🥣',
      bgColor: Color(0xFFECFDF5),
      imageUrl: 'https://images.unsplash.com/photo-1546833999-b9f581a1996d?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Tata Sampann', 'Fortune', 'Organic Tattva'],
    ),
    GroceryCatalogItem(
      id: 'chana_dal',
      name: 'Chana Dal / Besan',
      category: 'Staples & Dals',
      emoji: '🧆',
      bgColor: Color(0xFFFFFBEB),
      imageUrl: 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Tata Sampann', 'Rajdhani', 'Fortune'],
    ),
    GroceryCatalogItem(
      id: 'poha',
      name: 'Poha / Flattened Rice',
      category: 'Staples & Dals',
      emoji: '🌾',
      bgColor: Color(0xFFF1F5F9),
      imageUrl: 'https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Tata Sampann', 'MTR', 'Loose Best'],
    ),
    GroceryCatalogItem(
      id: 'sooji',
      name: 'Sooji / Rava',
      category: 'Staples & Dals',
      emoji: '🌾',
      bgColor: Color(0xFFFFF7ED),
      imageUrl: 'https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Tata Sampann', 'Rajdhani', 'Fortune'],
    ),
    GroceryCatalogItem(
      id: 'sugar',
      name: 'Sugar / Cheeni',
      category: 'Staples & Dals',
      emoji: '🍬',
      bgColor: Color(0xFFF8FAFC),
      imageUrl: 'https://images.unsplash.com/photo-1622484216805-4c07ea86d70d?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Madhur', 'Trust', 'Mawana'],
    ),
    GroceryCatalogItem(
      id: 'salt',
      name: 'Iodized Salt',
      category: 'Staples & Dals',
      emoji: '🧂',
      bgColor: Color(0xFFEFF6FF),
      imageUrl: 'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Tata Salt', 'Aashirvaad', 'Patanjali'],
    ),

    // ── Oils & Masalas ─────────────────────────────────────────────────────
    GroceryCatalogItem(
      id: 'cooking_oil',
      name: 'Cooking / Sunflower Oil',
      category: 'Oils & Masalas',
      emoji: '🌻',
      bgColor: Color(0xFFFEF3C7),
      imageUrl: 'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Fortune', 'Gemini', 'Saffola', 'Dhara'],
    ),
    GroceryCatalogItem(
      id: 'mustard_oil',
      name: 'Mustard Oil (Sarson)',
      category: 'Oils & Masalas',
      emoji: '🛢️',
      bgColor: Color(0xFFFEF08A),
      imageUrl: 'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Fortune Kachi Ghani', 'Engine', 'Emami'],
    ),
    GroceryCatalogItem(
      id: 'ghee',
      name: 'Pure Desi Ghee',
      category: 'Oils & Masalas',
      emoji: '🧈',
      bgColor: Color(0xFFFFFBEB),
      imageUrl: 'https://images.unsplash.com/photo-1589985270826-4b7bb135bc9d?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Amul', 'Gowardhan', 'Patanjali', 'Mother Dairy'],
    ),
    GroceryCatalogItem(
      id: 'haldi_powder',
      name: 'Turmeric / Haldi Powder',
      category: 'Oils & Masalas',
      emoji: '🟡',
      bgColor: Color(0xFFFEF9C3),
      imageUrl: 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Everest', 'MDH', 'Catch', 'Tata Sampann'],
    ),
    GroceryCatalogItem(
      id: 'chilli_powder',
      name: 'Red Chilli / Mirch Powder',
      category: 'Oils & Masalas',
      emoji: '🌶️',
      bgColor: Color(0xFFFEE2E2),
      imageUrl: 'https://images.unsplash.com/photo-1627662236973-4fd8358fa206?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Everest', 'MDH', 'Catch', 'Tata Sampann'],
    ),
    GroceryCatalogItem(
      id: 'garam_masala',
      name: 'Garam Masala',
      category: 'Oils & Masalas',
      emoji: '🥣',
      bgColor: Color(0xFFFFF7ED),
      imageUrl: 'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Everest', 'MDH', 'Catch'],
    ),

    // ── Fresh Vegetables & Fruits ──────────────────────────────────────────
    GroceryCatalogItem(
      id: 'potato',
      name: 'Potato (Aloo)',
      category: 'Vegetables & Fruits',
      emoji: '🥔',
      bgColor: Color(0xFFFEF3C7),
      imageUrl: 'https://images.unsplash.com/photo-1518977676601-b53f82aba655?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Fresh Local'],
    ),
    GroceryCatalogItem(
      id: 'onion',
      name: 'Onion (Pyaz)',
      category: 'Vegetables & Fruits',
      emoji: '🧅',
      bgColor: Color(0xFFFCE7F3),
      imageUrl: 'https://images.unsplash.com/photo-1618512496248-a07fe83aa8cb?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Fresh Nashik', 'Fresh Local'],
    ),
    GroceryCatalogItem(
      id: 'tomato',
      name: 'Tomato (Tamatar)',
      category: 'Vegetables & Fruits',
      emoji: '🍅',
      bgColor: Color(0xFFFEE2E2),
      imageUrl: 'https://images.unsplash.com/photo-1592924357228-91a4daadcfea?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Fresh Local', 'Hybrid / Country'],
    ),
    GroceryCatalogItem(
      id: 'ginger_garlic',
      name: 'Ginger & Garlic (Adrak Lehsun)',
      category: 'Vegetables & Fruits',
      emoji: '🧄',
      bgColor: Color(0xFFF8FAFC),
      imageUrl: 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Fresh Local'],
    ),
    GroceryCatalogItem(
      id: 'green_chillies',
      name: 'Green Chillies & Lemon',
      category: 'Vegetables & Fruits',
      emoji: '🌶️',
      bgColor: Color(0xFFECFDF5),
      imageUrl: 'https://images.unsplash.com/photo-1525607551316-4a8e16d1f9ba?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Fresh Local'],
    ),
    GroceryCatalogItem(
      id: 'apple',
      name: 'Fresh Apples',
      category: 'Vegetables & Fruits',
      emoji: '🍎',
      bgColor: Color(0xFFFEE2E2),
      imageUrl: 'https://images.unsplash.com/photo-1560806887-1e4cd0b6cbd6?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Shimla', 'Kinnaur', 'Washington'],
    ),
    GroceryCatalogItem(
      id: 'banana',
      name: 'Bananas (Kela)',
      category: 'Vegetables & Fruits',
      emoji: '🍌',
      bgColor: Color(0xFFFEF9C3),
      imageUrl: 'https://images.unsplash.com/photo-1571771894821-ce9b6c11b08e?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Robusta', 'Yellaki'],
    ),

    // ── Snacks & Beverages ─────────────────────────────────────────────────
    GroceryCatalogItem(
      id: 'tea',
      name: 'Tea / Chai Patti',
      category: 'Snacks & Beverages',
      emoji: '☕',
      bgColor: Color(0xFFFEF3C7),
      imageUrl: 'https://images.unsplash.com/photo-1594631252845-29fc4cc8cde9?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Tata Tea Gold', 'Red Label', 'Wagh Bakri', 'Society'],
    ),
    GroceryCatalogItem(
      id: 'coffee',
      name: 'Instant Coffee Powder',
      category: 'Snacks & Beverages',
      emoji: '☕',
      bgColor: Color(0xFFFFF7ED),
      imageUrl: 'https://images.unsplash.com/photo-1587734195503-904fca47e0e9?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Nescafe Classic', 'BRU', 'Continental'],
    ),
    GroceryCatalogItem(
      id: 'maggi',
      name: 'Maggi 2-Min Noodles',
      category: 'Snacks & Beverages',
      emoji: '🍜',
      bgColor: Color(0xFFFEF9C3),
      imageUrl: 'https://images.unsplash.com/photo-1612927601601-6638404737ce?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Nestle Maggi', 'Yippee', 'Knorr'],
    ),
    GroceryCatalogItem(
      id: 'biscuits',
      name: 'Biscuits / Cookies',
      category: 'Snacks & Beverages',
      emoji: '🍪',
      bgColor: Color(0xFFFFFBEB),
      imageUrl: 'https://images.unsplash.com/photo-1558961363-fa8fdf82db35?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Parle-G', 'Britannia Good Day', 'Marie Gold', 'Oreo'],
    ),
    GroceryCatalogItem(
      id: 'chips',
      name: 'Potato Chips & Snacks',
      category: 'Snacks & Beverages',
      emoji: '🥔',
      bgColor: Color(0xFFFEF08A),
      imageUrl: 'https://images.unsplash.com/photo-1566478989037-eec170784d0b?auto=format&fit=crop&w=300&q=80',
      popularBrands: ["Lay's", 'Kurkure', 'Bingo', "Haldiram's"],
    ),

    // ── Cleaning & Household ───────────────────────────────────────────────
    GroceryCatalogItem(
      id: 'soap',
      name: 'Bathing Soap',
      category: 'Cleaning & Household',
      emoji: '🧼',
      bgColor: Color(0xFFEFF6FF),
      imageUrl: 'https://images.unsplash.com/photo-1607006314646-63304c51950e?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Dettol', 'Dove', 'Lifebuoy', 'Pears', 'Cinthol'],
    ),
    GroceryCatalogItem(
      id: 'detergent',
      name: 'Detergent Powder / Liquid',
      category: 'Cleaning & Household',
      emoji: '🫧',
      bgColor: Color(0xFFE0F2FE),
      imageUrl: 'https://images.unsplash.com/photo-1583947215259-38e31be8751f?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Surf Excel', 'Ariel', 'Tide', 'Rin'],
    ),
    GroceryCatalogItem(
      id: 'dishwash',
      name: 'Dishwash Bar / Gel',
      category: 'Cleaning & Household',
      emoji: '🍽️',
      bgColor: Color(0xFFDCFCE7),
      imageUrl: 'https://images.unsplash.com/photo-1585421514738-01798e348b17?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Vim', 'Pril', 'Exo'],
    ),
    GroceryCatalogItem(
      id: 'toothpaste',
      name: 'Toothpaste',
      category: 'Cleaning & Household',
      emoji: '🪥',
      bgColor: Color(0xFFEFF6FF),
      imageUrl: 'https://images.unsplash.com/photo-1559599101-f09722fb4948?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Colgate', 'Closeup', 'Dabur Red', 'Sensodyne'],
    ),
    GroceryCatalogItem(
      id: 'shampoo',
      name: 'Hair Shampoo',
      category: 'Cleaning & Household',
      emoji: '🧴',
      bgColor: Color(0xFFF3E8FF),
      imageUrl: 'https://images.unsplash.com/photo-1535585209827-a15fcdbc4c2d?auto=format&fit=crop&w=300&q=80',
      popularBrands: ['Clinic Plus', 'Head & Shoulders', 'Dove', 'Pantene'],
    ),
  ];

  /// Serializes grocery items into a safe JSON tag for description storage.
  static String encodeGroceryItemsJson(List<SelectedGroceryItem> items) {
    return '[GROCERY_ITEMS]${jsonEncode(items.map((e) => e.toJson()).toList())}[/GROCERY_ITEMS]';
  }

  /// Parses grocery items from JSON or task description fallback.
  static List<SelectedGroceryItem> parseGroceryItems(dynamic raw, [String? description]) {
    final list = <SelectedGroceryItem>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(SelectedGroceryItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      if (list.isNotEmpty) return list;
    }

    // Try parsing encoded JSON block inside description: [GROCERY_ITEMS]...[/GROCERY_ITEMS]
    if (description != null && description.isNotEmpty) {
      final match = RegExp(r'\[GROCERY_ITEMS\](.*?)\[/GROCERY_ITEMS\]', dotAll: true).firstMatch(description);
      if (match != null) {
        try {
          final decoded = jsonDecode(match.group(1)!);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                list.add(SelectedGroceryItem.fromJson(Map<String, dynamic>.from(item)));
              }
            }
            if (list.isNotEmpty) return list;
          }
        } catch (_) {}
      }

      // Fallback: parse bullet points under "Grocery Items:"
      final bulletMatches = RegExp(r'•\s*([^\n\(\)]+?)(?:\s*\((.*?)\))?(?:\n|$)', caseSensitive: false).allMatches(description);
      for (final m in bulletMatches) {
        final rawName = m.group(1)?.trim() ?? '';
        if (rawName.isEmpty ||
            rawName.toLowerCase().startsWith('vehicle') ||
            rawName.toLowerCase().startsWith('grocery item') ||
            rawName.toLowerCase().startsWith('materials') ||
            rawName.toLowerCase().startsWith('pricing')) {
          continue;
        }
        final details = m.group(2) ?? '';
        String qty = '';
        String kg = '';
        String gram = '';
        String litr = '';
        String rupee = '';
        String brand = '';

        final qtyMatch = RegExp(r'Qty:\s*([0-9]+)', caseSensitive: false).firstMatch(details);
        if (qtyMatch != null) qty = qtyMatch.group(1) ?? '';

        final kgMatch = RegExp(r'([0-9.]+)\s*kg', caseSensitive: false).firstMatch(details);
        if (kgMatch != null) kg = kgMatch.group(1) ?? '';

        final gMatch = RegExp(r'([0-9.]+)\s*g\b', caseSensitive: false).firstMatch(details);
        if (gMatch != null) gram = gMatch.group(1) ?? '';

        final lMatch = RegExp(r'([0-9.]+)\s*L', caseSensitive: false).firstMatch(details);
        if (lMatch != null) litr = lMatch.group(1) ?? '';

        final rupeeMatch = RegExp(r'₹\s*([0-9.]+)', caseSensitive: false).firstMatch(details);
        if (rupeeMatch != null) rupee = rupeeMatch.group(1) ?? '';

        final brandMatch = RegExp(r'Brand:\s*([^,)]+)', caseSensitive: false).firstMatch(details);
        if (brandMatch != null) brand = brandMatch.group(1)?.trim() ?? '';

        list.add(SelectedGroceryItem(
          id: rawName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_'),
          name: rawName,
          category: 'Groceries',
          imageUrl: '',
          emoji: '🛒',
          qty: qty,
          kg: kg,
          gram: gram,
          litr: litr,
          rupee: rupee,
          brand: brand,
        ));
      }
    }
    return list;
  }
}
