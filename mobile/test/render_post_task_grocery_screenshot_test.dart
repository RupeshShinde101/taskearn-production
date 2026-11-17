import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate4u/models/grocery_item.dart';
import 'package:workmate4u/providers/auth_provider.dart';
import 'package:workmate4u/providers/task_provider.dart';
import 'package:workmate4u/screens/tasks/post_task_screen.dart';
import 'package:workmate4u/services/storage_service.dart';

void main() {
  testWidgets('Render PostTaskScreen grocery view and save screenshot', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'profile_mode': 'poster'});
    await StorageService.init();

    final repaintBoundaryKey = GlobalKey();

    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RepaintBoundary(
            key: repaintBoundaryKey,
            child: const PostTaskScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Select Shopping & Errands
    final shoppingFinder = find.text('Shopping & Errands');
    expect(shoppingFinder, findsOneWidget);
    await tester.tap(shoppingFinder);
    await tester.pumpAndSettle();

    // 2. Select Groceries in the dialog
    final groceryFinder = find.text('Groceries');
    expect(groceryFinder, findsOneWidget);
    await tester.tap(groceryFinder);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // 3. Catalog screen is open: tap Add on first item
    final addFinder = find.text('Add').first;
    expect(addFinder, findsOneWidget);
    await tester.tap(addFinder);
    await tester.pumpAndSettle();

    // 4. Modal bottom sheet opens: tap 'Add to List'
    final addToListFinder = find.text('Add to List');
    expect(addToListFinder, findsOneWidget);
    await tester.tap(addToListFinder);
    await tester.pumpAndSettle();

    // Wait for the floating snackbar to dismiss so it doesn't block the bottom button
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // 5. Tap 'Save & Continue' on the catalog screen
    final saveContinueFinder = find.textContaining('Save & Continue');
    expect(saveContinueFinder, findsOneWidget);
    await tester.tap(saveContinueFinder, warnIfMissed: false);
    await tester.pumpAndSettle();

    // 6. Verify we returned to PostTaskScreen cleanly without freezing
    expect(find.text('Delivery Address & Store'), findsOneWidget);
    expect(find.text('Store / Supermarket (10 km Radius)'), findsOneWidget);
    expect(find.text('Grocery Items'), findsOneWidget);
    expect(find.text('Price Breakdown'), findsOneWidget);
    expect(find.text('Distance Travel Fare (₹12/km)'), findsOneWidget);
    expect(find.text('Handling & Shopping Charge'), findsOneWidget);

    // 7. Capture rendered image
    final boundary = repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    expect(boundary, isNotNull);

    await tester.runAsync(() async {
      final image = await boundary!.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final file = File(r'C:\Users\therh\.gemini\antigravity\brain\9fd4d3b7-665d-4018-b3aa-85d24b67f566\post_task_grocery_screen.png');
      await file.writeAsBytes(pngBytes);
    });
  });
}
