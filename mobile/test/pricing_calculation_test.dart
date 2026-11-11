import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate4u/models/task.dart';
import 'package:workmate4u/providers/auth_provider.dart';
import 'package:workmate4u/providers/task_provider.dart';
import 'package:workmate4u/screens/tasks/post_task_screen.dart';
import 'package:workmate4u/services/storage_service.dart';
import 'package:workmate4u/widgets/task_price_breakdown_card.dart';

void main() {
  group('Task distance pricing & service charge', () {
    test('moving uses ₹400 base + ₹35/km for full distance (4.7 km -> ₹565)', () {
      expect(Task.calculateDistancePrice(4.7, 'moving'), 565.0);
      expect(Task.calculateDistancePrice(1.0, 'moving'), 435.0);
      expect(Task.calculateDistancePrice(0.0, 'moving'), 0.0);
    });

    test('moving itemized fare summary explains base + distance component', () {
      final summary = Task.distanceFareSummary(4.7, 'moving');
      expect(summary, contains('₹565'));
      expect(summary, contains('₹400 base'));
      expect(summary, contains('₹165'));
      expect(summary, contains('4.7 km @ ₹35/km'));
    });

    test('extra service charge is removed (₹0) across all categories', () {
      expect(Task.serviceChargeForCategory('moving'), 0);
      expect(Task.serviceChargeForCategory('delivery'), 0);
      expect(Task.serviceChargeForCategory('pickup'), 0);
      expect(Task.serviceChargeForCategory('transport'), 0);
      expect(Task.serviceChargeForCategory('cleaning'), 0);
    });

    test('moving budget suggestion aligns minBudget and suggestedBudget with 4.7 km fare', () {
      final std = Task.getBudgetSuggestion('moving', distanceKm: 4.7);
      expect(std.minBudget, 565.0);
      expect(std.suggestedBudget, 565.0);

      final kothrud = Task.getBudgetSuggestion(
        'moving',
        areaText: 'Kothrud',
        distanceKm: 4.7,
      );
      expect(kothrud.minBudget, 565.0);
      expect(kothrud.suggestedBudget, greaterThanOrEqualTo(565.0));
    });

    test('delivery pricing supports bike (₹12/km, min ₹24) and rikshaw (₹18/km, min ₹30)', () {
      expect(Task.minBudgetForCategory('delivery'), 24.0);
      expect(Task.minBudgetForCategory('delivery', vehicle: 'rikshaw'), 30.0);
      expect(Task.minBudgetForCategory('pickup'), 30.0);
      expect(Task.minBudgetForCategory('transport'), 50.0);

      expect(Task.calculateDistancePrice(4.7, 'delivery', vehicle: 'bike'), 56.0);
      expect(Task.calculateDistancePrice(4.7, 'delivery', vehicle: 'rikshaw'), 85.0);
      expect(Task.calculateDistancePrice(1.0, 'delivery', vehicle: 'bike'), 24.0);
      expect(Task.calculateDistancePrice(1.0, 'delivery', vehicle: 'rikshaw'), 30.0);

      expect(Task.distanceFareSummary(4.7, 'delivery', vehicle: 'bike'),
          'Min fare: ₹56 (4.7 km @ ₹12/km (Bike))');
      expect(Task.distanceFareSummary(1.0, 'delivery', vehicle: 'bike'),
          'Min fare: ₹24 (1.0 km @ ₹12/km — ₹24 min (Bike))');
      expect(Task.distanceFareSummary(4.7, 'delivery', vehicle: 'rikshaw'),
          'Min fare: ₹85 (4.7 km @ ₹18/km (Rikshaw))');
      expect(Task.distanceFareSummary(1.0, 'delivery', vehicle: 'rikshaw'),
          'Min fare: ₹30 (1.0 km @ ₹18/km — ₹30 min (Rikshaw))');

      final bikeNoDist = Task.getBudgetSuggestion('delivery', vehicle: 'bike');
      expect(bikeNoDist.minBudget, 24.0);
      expect(bikeNoDist.suggestedBudget, greaterThanOrEqualTo(24.0));

      final autoNoDist = Task.getBudgetSuggestion('delivery', vehicle: 'rikshaw');
      expect(autoNoDist.minBudget, 30.0);
      expect(autoNoDist.suggestedBudget, greaterThanOrEqualTo(30.0));

      final bike47 = Task.getBudgetSuggestion('delivery', distanceKm: 4.7, vehicle: 'bike');
      expect(bike47.minBudget, 56.0);
      expect(bike47.suggestedBudget, 56.0);

      final auto47 = Task.getBudgetSuggestion('delivery', distanceKm: 4.7, vehicle: 'rikshaw');
      expect(auto47.minBudget, 85.0);
      expect(auto47.suggestedBudget, 85.0);
    });
  });

  group('Pricing UI widgets', () {
    testWidgets('TaskPriceBreakdownCard renders 565 + 20% fee = 678 with zero service charge',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: TaskPriceBreakdownCard(
                budget: 565,
                serviceCharge: 0,
                posterFee: 113,
                totalCost: 678,
              ),
            ),
          ),
        ),
      );

      expect(find.text('₹565'), findsOneWidget);
      expect(find.text('₹113'), findsOneWidget);
      expect(find.text('₹678'), findsOneWidget);
      expect(find.text('Service Charge'), findsNothing);
      expect(find.text('Distance / Service Charge'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PostTaskScreen Delivery enforces ₹24 Bike / ₹30 Rikshaw minimum and zero extra service charge',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'profile_mode': 'poster'});
      await StorageService.init();

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => TaskProvider()),
          ],
          child: const MaterialApp(
            home: PostTaskScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default category is delivery -> Bike selected
      expect(find.text('Delivery Vehicle Option'), findsOneWidget);
      expect(find.text('₹12 / km (Bike)'), findsOneWidget);

      await tester.ensureVisible(find.text('Task Details Form'));
      await tester.tap(find.text('Task Details Form'));
      await tester.pumpAndSettle();

      // Enter ₹20 without coordinates -> below ₹24 Bike min
      final budgetField = find.widgetWithText(TextFormField, 'Budget (₹)');
      await tester.ensureVisible(budgetField);
      await tester.enterText(budgetField, '20');
      await tester.pumpAndSettle();
      expect(find.textContaining('Minimum budget for delivery is ₹24'), findsOneWidget);

      // Enter ₹25 -> valid for Bike (>= ₹24)
      await tester.enterText(budgetField, '25');
      await tester.pumpAndSettle();
      expect(find.textContaining('Minimum budget for'), findsNothing);

      // Switch to Rikshaw -> ₹25 is now below ₹30 Rikshaw min!
      await tester.ensureVisible(find.text('Rikshaw'));
      await tester.tap(find.text('Rikshaw'));
      await tester.pumpAndSettle();
      expect(find.text('₹18 / km (Rikshaw)'), findsOneWidget);
      expect(find.textContaining('Minimum budget for delivery is ₹30'), findsOneWidget);

      // Set Pickup & Drop localities -> computes distance fare and updates breakdown cleanly
      await tester.ensureVisible(find.text('Pickup Address *'));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Pickup Address *'), 'Baner');
      await tester.ensureVisible(find.text('Drop / Delivery Address *'));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Drop / Delivery Address *'),
          'Kothrud');
      await tester.pumpAndSettle();

      expect(find.textContaining('₹18/km (Rikshaw)'), findsWidgets);
      expect(find.text('Service Charge'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PostTaskScreen hides Bike/Rikshaw selector on Moving and shows ₹400 + ₹35/km banner',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'profile_mode': 'poster'});
      await StorageService.init();

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => TaskProvider()),
          ],
          child: const MaterialApp(
            home: PostTaskScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default category is delivery -> Bike / Rikshaw selector is visible
      expect(find.text('Delivery Vehicle Option'), findsOneWidget);

      // Delivery & Moving is already selected -> second tap opens sub-category sheet
      await tester.tap(find.text('Delivery & Moving'));
      await tester.pumpAndSettle();

      // Pick 'Moving'
      await tester.tap(find.text('Moving'));
      await tester.pumpAndSettle();

      expect(find.text('Delivery Vehicle Option'), findsNothing);
      expect(find.text('Moving & Packing Rate'), findsOneWidget);
      expect(find.text('₹400 base + ₹35 / km'), findsOneWidget);

      // Expand Task Details Form and verify zero layout overflow
      await tester.ensureVisible(find.text('Task Details Form'));
      await tester.tap(find.text('Task Details Form'));
      await tester.pumpAndSettle();

      expect(find.text('Budget'), findsOneWidget);
      expect(find.text('Price Breakdown'), findsOneWidget);

      // Fill Pickup & Drop with known localities -> triggers instant distance & auto-budget
      await tester.ensureVisible(find.text('Pickup Address *'));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Pickup Address *'), 'Baner');
      await tester.ensureVisible(find.text('Drop / Delivery Address *'));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Drop / Delivery Address *'),
          'Kothrud');
      await tester.pumpAndSettle();

      // Distance summary + Suggested card should now show ₹400 base + ₹35/km
      expect(find.textContaining('₹400 base'), findsWidgets);

      // Typing ₹400 for Moving (below distance min) shows inline warning immediately
      final budgetField = find.widgetWithText(TextFormField, 'Budget (₹)');
      await tester.ensureVisible(budgetField);
      await tester.enterText(budgetField, '400');
      await tester.pumpAndSettle();
      expect(find.textContaining('Minimum ₹'), findsOneWidget);

      // Tapping Apply sets suggested budget and clears the inline warning
      await tester.ensureVisible(find.text('Apply'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Minimum ₹'), findsNothing);
      expect(find.text('Service Charge'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
