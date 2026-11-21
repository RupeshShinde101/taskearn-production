import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmate4u/models/task.dart';
import 'package:workmate4u/providers/auth_provider.dart';
import 'package:workmate4u/providers/notification_provider.dart';
import 'package:workmate4u/providers/task_provider.dart';
import 'package:workmate4u/providers/wallet_provider.dart';
import 'package:workmate4u/screens/home/home_screen.dart';
import 'package:workmate4u/screens/tasks/post_task_screen.dart';
import 'package:workmate4u/services/storage_service.dart';
import 'package:workmate4u/widgets/hero_map_background.dart';

void main() {
  test('heroAvatarAssetForGender resolves female vs male/default cleanly', () {
    expect(
      heroAvatarAssetForGender('female'),
      'assets/images/header_avatar_girl.png',
    );
    expect(
      heroAvatarAssetForGender('Female'),
      'assets/images/header_avatar_girl.png',
    );
    expect(
      heroAvatarAssetForGender('male'),
      'assets/images/header_avatar.png',
    );
    expect(
      heroAvatarAssetForGender(null),
      'assets/images/header_avatar.png',
    );
    expect(
      heroAvatarAssetForGender('other'),
      'assets/images/header_avatar.png',
    );
  });

  testWidgets(
      'PostTaskScreen shows girl avatar when user gender is female and boy avatar when male',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'profile_mode': 'poster',
      'user_gender': 'female',
    });
    await StorageService.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: const MaterialApp(home: PostTaskScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final girlImgFinder = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName ==
              'assets/images/header_avatar_girl.png',
    );
    expect(girlImgFinder, findsOneWidget);
    expect(tester.takeException(), isNull);

    // Switch stored gender to male
    await StorageService.saveGender('male');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: const MaterialApp(home: PostTaskScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final boyImgFinder = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName ==
              'assets/images/header_avatar.png',
    );
    expect(boyImgFinder, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'HomeScreen hero uses illustrated map background and gender-matched image without emoji circle or overflow',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'profile_mode': 'worker',
      'user_gender': 'female',
    });
    await StorageService.init();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => NotificationProvider()),
          ChangeNotifierProvider(create: (_) => WalletProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Girl image asset & HeroMapBackgroundPainter active; old emoji characters gone
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/images/header_avatar_girl.png',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is HeroMapBackgroundPainter,
      ),
      findsOneWidget,
    );
    expect(find.text('\u{1F467}'), findsNothing);
    expect(find.text('\u{1F466}'), findsNothing);
    expect(find.text('\u{1F9D1}'), findsNothing);
    expect(find.text('Post a Task'), findsOneWidget);
    expect(find.text('Find Tasks'), findsOneWidget);
    // Compact left-column button width (< 210dp on 360dp screen)
    expect(tester.getSize(find.widgetWithText(ElevatedButton, 'Post a Task')).width,
        lessThan(210));
    expect(tester.getSize(find.widgetWithText(OutlinedButton, 'Find Tasks')).width,
        lessThan(210));
    // Trusted local experts banner is informational only (no GestureDetector wrapper)
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
    await tester.pump(const Duration(milliseconds: 100));
    final trustedFinder = find.text('Trusted local experts');
    expect(trustedFinder, findsOneWidget);
    expect(
      find.ancestor(of: trustedFinder, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    // Switch gender to male
    await StorageService.saveGender('male');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => NotificationProvider()),
          ChangeNotifierProvider(create: (_) => WalletProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/images/header_avatar.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'HomeScreen shows Live Nearby Tasks Feed instead of What People Say and bottom CTA cards',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'profile_mode': 'helper',
      'user_gender': 'male',
    });
    await StorageService.init();

    final sampleTasks = [
      Task(
        id: 't1',
        title: 'Urgent grocery pickup',
        description: 'Pick up fresh veggies from Kothrud market',
        category: 'groceries',
        budget: 450,
        status: 'posted',
        posterId: 'u2',
        posterName: 'Priya M.',
        latitude: 18.5074,
        longitude: 73.8077,
        distanceKm: 1.2,
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
      Task(
        id: 't2',
        title: 'Deliver parcel to Baner',
        description: 'Small envelope delivery',
        category: 'delivery',
        budget: 180,
        status: 'posted',
        posterId: 'u3',
        posterName: 'Rohan S.',
        latitude: 18.5590,
        longitude: 73.7868,
        distanceKm: 2.5,
        createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => NotificationProvider()),
          ChangeNotifierProvider(create: (_) => WalletProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: MaterialApp(
          home: HomeScreen(initialNearbyTasks: sampleTasks),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Hero buttons stay intact at top; old bottom sections are gone
    expect(find.text('Post a Task'), findsOneWidget);
    expect(find.text('What People Say'), findsNothing);
    expect(find.text('Get help from skilled helpers nearby'), findsNothing);
    expect(find.text('Find tasks matching your skills & earn'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Live Nearby Tasks Feed'), findsOneWidget);
    expect(find.text('All (2)'), findsOneWidget);
    expect(find.text('Within 2 km'), findsOneWidget);
    expect(find.text('₹300+'), findsOneWidget);
    expect(find.text('Urgent grocery pickup'), findsOneWidget);
    expect(find.text('Deliver parcel to Baner'), findsOneWidget);
    expect(find.text('₹450'), findsOneWidget);
    expect(find.text('1.2 km'), findsOneWidget);
    expect(find.text('20 mins'), findsOneWidget);
    expect(find.text('Accept'), findsNWidgets(2));

    // Option 1 quick filters filter Live Nearby Tasks Feed interactively
    await tester.tap(find.text('Within 2 km'));
    await tester.pumpAndSettle();
    expect(find.text('Urgent grocery pickup'), findsOneWidget);
    expect(find.text('Deliver parcel to Baner'), findsNothing);
    expect(find.text('Accept'), findsOneWidget);

    await tester.ensureVisible(find.text('All (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Accept'), findsNWidgets(2));

    await tester.ensureVisible(find.text('₹300+'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('₹300+'));
    await tester.pumpAndSettle();
    expect(find.text('Urgent grocery pickup'), findsOneWidget);
    expect(find.text('Deliver parcel to Baner'), findsNothing);
    expect(find.text('Accept'), findsOneWidget);

    await tester.ensureVisible(find.text('All (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Accept'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'HomeScreen Live Nearby Tasks Feed loading skeleton and extreme text do not overflow at 320dp',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'profile_mode': 'helper',
      'user_gender': 'male',
    });
    await StorageService.init();

    // First verify skeleton loading state has zero overflow
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => NotificationProvider()),
          ChangeNotifierProvider(create: (_) => WalletProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pump();
    expect(find.text('Live Nearby Tasks Feed'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Then verify loaded card with long title/city and 1.3x text scale has zero overflow
    final stressTasks = [
      Task(
        id: 't_stress',
        title: 'Full 2BHK deep home cleaning and kitchen sanitization',
        description: 'Urgent deep clean',
        category: 'cleaning',
        budget: 14500,
        status: 'posted',
        posterId: 'u2',
        posterName: 'Priya M.',
        city: 'Pimpri-Chinchwad Municipal Area',
        latitude: 18.5074,
        longitude: 73.8077,
        distanceKm: 140.9,
        createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => NotificationProvider()),
          ChangeNotifierProvider(create: (_) => WalletProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            home: HomeScreen(initialNearbyTasks: stressTasks),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Accept'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'HomeScreen AI Suggested uses Concept A editorial cards with Accept button and zero overflow at 320dp 1.3x scale',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SharedPreferences.setMockInitialValues({
      'profile_mode': 'helper',
      'user_gender': 'male',
    });
    await StorageService.init();

    final suggested = [
      Task(
        id: 'ai_1',
        title: '2BHK Home Deep Cleaning & Kitchen Sanitizing',
        description: 'Deep clean kitchen and two bathrooms',
        category: 'cleaning',
        budget: 500,
        status: 'posted',
        posterId: 'u2',
        posterName: 'Vishal Uthale Longer Name',
        posterRating: 4.9,
        city: 'Kothrud Pune Maharashtra',
        latitude: 18.5074,
        longitude: 73.8077,
        distanceKm: 1.4,
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
      ),
      Task(
        id: 'ai_2',
        title: 'Express Document Drop',
        description: 'Deliver signed folder',
        category: 'delivery',
        budget: 180,
        status: 'posted',
        posterId: 'u3',
        posterName: 'Ananya K.',
        posterRating: 4.8,
        latitude: 18.51,
        longitude: 73.81,
        distanceKm: 2.1,
        createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => NotificationProvider()),
          ChangeNotifierProvider(create: (_) => WalletProvider()),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
        ],
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            home: HomeScreen(
              initialSuggestedTasks: suggested,
              initialTaskMatchPct: const {'ai_1': 92, 'ai_2': 86},
              initialNearbyTasks: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -650));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('AI Suggested for You'), findsOneWidget);
    expect(find.text('92% Match'), findsOneWidget);
    expect(find.text('86% Match'), findsOneWidget);
    expect(find.text('CLEANING'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/images/cat_home.jpg',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/images/cat_delivery.jpg',
      ),
      findsOneWidget,
    );
    expect(find.text('2BHK Home Deep Cleaning & Kitchen Sanitizing'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);
    expect(find.text('Apply →'), findsNothing);
    expect(find.text('Accept'), findsNWidgets(2));
    expect(tester.takeException(), isNull);

    // Tapping Accept on an AI Suggested card invokes the task-accept guard flow
    await tester.ensureVisible(find.text('Accept').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept').first);
    await tester.pumpAndSettle();
    expect(find.text('KYC Verification Required'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
