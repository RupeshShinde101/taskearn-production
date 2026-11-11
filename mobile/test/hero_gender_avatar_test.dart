import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}
