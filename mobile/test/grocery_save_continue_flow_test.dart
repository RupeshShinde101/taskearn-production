import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:workmate4u/models/grocery_item.dart';
import 'package:workmate4u/providers/auth_provider.dart';
import 'package:workmate4u/providers/task_provider.dart';
import 'package:workmate4u/screens/tasks/grocery_item_picker_screen.dart';
import 'package:workmate4u/screens/tasks/post_task_screen.dart';
import 'package:workmate4u/services/storage_service.dart';
import 'package:workmate4u/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'profile_mode': 'poster'});
    await StorageService.init();
  });

  testWidgets('Test GroceryItemPicker with selected items -> Save & Continue -> PostTaskScreen flow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(() => tester.view.resetPhysicalSize());

    final initialItems = [
      SelectedGroceryItem(
        id: 'veg_methi',
        name: 'Fresh Methi (Fenugreek Leaves)',
        category: 'Vegetables & Fruits',
        imageUrl: 'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=300&q=80',
        emoji: '🌿',
        package: '2 Bunches (500g)',
        kg: '0.5',
      ),
      SelectedGroceryItem(
        id: 'veg_palak',
        name: 'Fresh Palak (Spinach)',
        category: 'Vegetables & Fruits',
        imageUrl: 'https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=300&q=80',
        emoji: '🥬',
        package: '1 Bunch (250g)',
        kg: '0.25',
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: PostTaskScreen(
            initialCategory: 'groceries',
            initialGroceryItems: initialItems,
          ),
        ),
      ),
    );

    // Initial pump & settle
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    // Verify PostTaskScreen loaded with the items & new clean grocery UI
    expect(find.text('Post a Task'), findsOneWidget);
    expect(find.text('Grocery Items Policy'), findsOneWidget); // Top ONLY
    expect(find.text('Grocery Items'), findsOneWidget);
    expect(find.text('2 Added'), findsOneWidget);
    expect(find.text('Fresh Methi (Fenugreek Leaves)'), findsOneWidget);
    expect(find.text('Fresh Palak (Spinach)'), findsOneWidget);
    expect(find.text('Delivery Address'), findsOneWidget);
    expect(find.text('Store Address'), findsOneWidget);
    expect(find.text('Price Breakdown'), findsOneWidget);
    expect(find.text('Handling & Shopping Charge'), findsOneWidget);
    expect(find.text('₹30'), findsOneWidget);
    expect(find.text('Platform Fee & GST (Fixed)'), findsOneWidget);
    expect(find.text('₹12'), findsOneWidget);
    // Suggested price and budget input box removed for groceries
    expect(find.text('Task Budget'), findsNothing);
    // Old combined header & hint text removed
    expect(find.text('Delivery Address & Store'), findsNothing);
    expect(find.textContaining('Auto-calculates'), findsNothing);

    // Verify encoded grocery JSON has NO Unsplash URLs or 10-digit photo IDs
    final encoded = GroceryCatalog.encodeGroceryItemsJson(initialItems);
    expect(encoded.contains('unsplash'), isFalse);
    expect(RegExp(r'(?:\+?91[\s\-]?)?[6-9]\d{9}').hasMatch(encoded), isFalse);
    // Verify parsing restores catalog imageUrl automatically
    final parsed = GroceryCatalog.parseGroceryItems(null, encoded);
    expect(parsed.length, 2);
    expect(parsed.first.imageUrl, isNotEmpty);
  });
}
