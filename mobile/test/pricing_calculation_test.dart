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

      // Task Details Form, Budget, and Location fields are directly visible (no dropdown collapse)
      expect(find.text('Task Details Form'), findsOneWidget);
      expect(find.text('Budget'), findsOneWidget);

      // Verify Task Title field disables inherited inner OutlineInputBorder
      final titleField = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Task Title'),
          matching: find.byType(TextField),
        ),
      );
      expect(titleField.decoration?.border, InputBorder.none);
      expect(titleField.decoration?.enabledBorder, InputBorder.none);
      expect(titleField.decoration?.focusedBorder, InputBorder.none);
      expect(titleField.decoration?.filled, isFalse);

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

      // Default category is delivery -> Bike / Rikshaw selector & hero map badge are visible
      expect(find.text('Near you'), findsNothing);
      expect(find.text('Delivery Vehicle Option'), findsOneWidget);

      // Tapping an unselected parent category opens its child category sheet on the FIRST tap
      await tester.tap(find.text('Repair'));
      await tester.pumpAndSettle();
      expect(find.text('Select a specific category'), findsOneWidget);
      expect(find.text('Electrician'), findsOneWidget);
      expect(find.text('Carpentry'), findsOneWidget);
      expect(TaskCategory.iconFor('carpentry'), isNot('\u{1FA9A}'));
      expect(find.text(TaskCategory.iconFor('carpentry')), findsOneWidget);
      expect(find.text('Tech Support'), findsNothing);
      expect(
        TaskCategoryGroup.all
            .firstWhere((g) => g.label == 'Professional')
            .categoryIds,
        contains('tech_support'),
      );
      await tester.tap(find.text('Electrician'));
      await tester.pumpAndSettle();
      expect(find.text('Select a specific category'), findsNothing);
      expect(find.text('Delivery Vehicle Option'), findsNothing);

      // Tapping Delivery & Moving opens its child category sheet on the FIRST tap even when unselected
      await tester.tap(find.text('Delivery & Moving'));
      await tester.pumpAndSettle();

      // Pick 'Moving'
      await tester.tap(find.text('Moving'));
      await tester.pumpAndSettle();

      expect(find.text('Delivery Vehicle Option'), findsNothing);
      expect(find.text('Moving & Packing Rate'), findsOneWidget);
      expect(find.text('₹400 base + ₹35 / km'), findsOneWidget);

      // Task Details Form, Budget, and Price Breakdown remain directly visible without dropdown
      expect(find.text('Task Details Form'), findsOneWidget);

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

    test('freelancer child categories enforce real-world market pricing', () {
      expect(TaskCategoryGroup.freelancerChildIds, hasLength(5));
      expect(Task.minBudgetForCategory('business_admin'), 300.0);
      expect(Task.minBudgetForCategory('graphic_design'), 350.0);
      expect(Task.minBudgetForCategory('video_audio_editing'), 400.0);
      expect(Task.minBudgetForCategory('digital_marketing'), 500.0);
      expect(Task.minBudgetForCategory('web_app_tech'), 800.0);

      final gfx = Task.getBudgetSuggestion('graphic_design');
      expect(gfx.minBudget, 350.0);
      expect(gfx.suggestedBudget, 600.0);
      expect(gfx.maxBudget, 1500.0);

      final web = Task.getBudgetSuggestion('web_app_tech');
      expect(web.minBudget, 800.0);
      expect(web.suggestedBudget, 1500.0);
      expect(web.maxBudget, 4000.0);

      final webPremium = Task.getBudgetSuggestion('web_app_tech', areaText: 'Hinjewadi');
      expect(webPremium.suggestedBudget, 1875.0);
      expect(webPremium.maxBudget, 5000.0);

      final vid = Task.getBudgetSuggestion('video_audio_editing');
      expect(vid.minBudget, 400.0);
      expect(vid.suggestedBudget, 750.0);
      expect(vid.maxBudget, 2000.0);

      final mkt = Task.getBudgetSuggestion('digital_marketing');
      expect(mkt.minBudget, 500.0);
      expect(mkt.suggestedBudget, 1000.0);
      expect(mkt.maxBudget, 2500.0);

      final biz = Task.getBudgetSuggestion('business_admin');
      expect(biz.minBudget, 300.0);
      expect(biz.suggestedBudget, 500.0);
      expect(biz.maxBudget, 1000.0);
    });

    test('freelancer dual pricing calculates package/unit & hourly quotes across all categories', () {
      // Web Website (/page): ₹800 min / ₹1500 sug per page + Domain & Hosting separate
      final web1 = Task.calculateFreelancerQuote('web_app_tech', mode: 'package', tierId: 'website_pages', units: 1);
      expect(web1.minBudget, 800.0);
      expect(web1.suggestedBudget, 1500.0);
      expect(web1.separateCostsTitle, 'Domain & Hosting Separate');

      final web5 = Task.calculateFreelancerQuote('web_app_tech', mode: 'package', tierId: 'website_pages', units: 5);
      expect(web5.minBudget, 4000.0);
      expect(web5.suggestedBudget, 7500.0);
      expect(web5.scopeSummary, 'Website (/page) (5 pages)');

      final webLanding = Task.calculateFreelancerQuote('web_app_tech', mode: 'package', tierId: 'landing_page');
      expect(webLanding.minBudget, 2000.0);
      expect(webLanding.suggestedBudget, 3000.0);

      // Web Hourly: min ₹400/hr, custom rate * hours
      final webHourly = Task.calculateFreelancerQuote('web_app_tech', mode: 'hourly', hourlyRate: 700, hours: 4);
      expect(webHourly.minBudget, 1600.0);
      expect(webHourly.suggestedBudget, 2800.0);
      expect(webHourly.scopeSummary, 'Hourly (₹700/hr × 4 hrs)');

      // Video Long Video (/min): base + per min
      final vid5 = Task.calculateFreelancerQuote('video_audio_editing', mode: 'package', tierId: 'long_video_mins', units: 5);
      expect(vid5.minBudget, 2600.0);
      expect(vid5.suggestedBudget, 4000.0);

      // Pitch Deck (/slide) & Ads Campaign
      final deck10 = Task.calculateFreelancerQuote('business_admin', mode: 'package', tierId: 'slides', units: 10);
      expect(deck10.minBudget, 1500.0);
      expect(deck10.suggestedBudget, 2500.0);

      final mktHourly = Task.calculateFreelancerQuote('digital_marketing', mode: 'hourly', hourlyRate: 900, hours: 2);
      expect(mktHourly.minBudget, 1000.0);
      expect(mktHourly.suggestedBudget, 1800.0);
      expect(mktHourly.separateCostsTitle, 'Ad Wallet Spend Separate');
    });

    testWidgets('Professional -> Freelancer -> Dual Pricing (Per Project pages & Hourly) sets market pricing',
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

      // Step 1: Tap Professional -> opens Professional subcategory popup
      await tester.ensureVisible(find.text('Professional'));
      await tester.tap(find.text('Professional'));
      await tester.pumpAndSettle();
      expect(find.text('Select a specific category'), findsOneWidget);
      expect(find.text('Freelancer'), findsOneWidget);

      // Step 2: Tap Freelancer -> opens nested Freelancer child category popup
      await tester.tap(find.text('Freelancer'));
      await tester.pumpAndSettle();
      expect(find.text('Select a freelancer category'), findsOneWidget);
      expect(find.text('Graphic Design & Branding'), findsOneWidget);
      expect(find.text('Web, App & Tech Projects'), findsOneWidget);
      expect(find.text('Video & Audio Editing'), findsOneWidget);
      expect(find.text('Digital Marketing'), findsOneWidget);
      expect(find.text('Business, Office & Admin'), findsOneWidget);
      expect(find.text('From ₹350 · /design or /hr'), findsOneWidget);
      expect(find.text('From ₹800 · /page or /hr'), findsOneWidget);

      // Verify back arrow returns cleanly to Professional popup, then re-open Freelancer
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Select a specific category'), findsOneWidget);
      await tester.tap(find.text('Freelancer'));
      await tester.pumpAndSettle();

      // Step 3: Select 'Web, App & Tech Projects'
      await tester.tap(find.text('Web, App & Tech Projects'));
      await tester.pumpAndSettle();

      // Dual Pricing card & Domain/Hosting Separate disclosure appear immediately
      expect(find.text('Freelancer Pricing Model'), findsOneWidget);
      expect(find.text('Per Project'), findsOneWidget);
      expect(find.text('Hourly Rate'), findsOneWidget);
      expect(find.text('Website (/page)'), findsOneWidget);
      expect(find.text('Domain & Hosting Separate'), findsOneWidget);

      // Step 4: Increase website pages from 1 -> 3 via '+' stepper -> min ₹2400, auto-budget ₹4500
      final unitInc = find.byKey(const Key('freelancer_unit_inc'));
      await tester.ensureVisible(unitInc);
      await tester.tap(unitInc);
      await tester.pumpAndSettle();
      await tester.tap(unitInc);
      await tester.pumpAndSettle();

      final budgetField = find.widgetWithText(TextFormField, 'Budget (₹)');
      final budgetWidget = tester.widget<TextFormField>(budgetField);
      expect(budgetWidget.controller?.text, '4500');
      expect(find.text('Min ₹2400'), findsOneWidget);

      // Enter ₹2000 -> inline validation warns minimum ₹2400 for 3 pages
      await tester.ensureVisible(budgetField);
      await tester.enterText(budgetField, '2000');
      await tester.pumpAndSettle();
      expect(find.textContaining('Minimum budget for web app tech (Website (/page) (3 pages)) is ₹2400'),
          findsOneWidget);

      // Step 5: Switch to Hourly Rate mode -> defaults ₹600/hr × 3 hrs = ₹1800, then +₹50 & +1h = 650 × 4 = ₹2600
      final hourlyTab = find.byKey(const Key('freelancer_mode_hourly'));
      await tester.ensureVisible(hourlyTab);
      await tester.tap(hourlyTab);
      await tester.pumpAndSettle();

      expect(find.text('₹600'), findsOneWidget);
      expect(find.text('3 hrs'), findsOneWidget);
      await tester.tap(find.byKey(const Key('freelancer_rate_inc')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('freelancer_hours_inc')));
      await tester.pumpAndSettle();

      final updatedBudget = tester.widget<TextFormField>(budgetField);
      expect(updatedBudget.controller?.text, '2600');
      expect(find.text('Minimum budget for'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}