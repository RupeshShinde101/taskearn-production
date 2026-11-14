import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:workmate4u/navigation/app_back_button_dispatcher.dart';
import 'package:workmate4u/providers/auth_provider.dart';
import 'package:workmate4u/screens/shell/main_shell.dart';

class MockAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  bool get isPosterMode => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Full Back navigation flow: tabs redirect to /home, and /home shows Exit dialog', (tester) async {
    final router = GoRouter(
      initialLocation: '/browse',
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, __) => const Scaffold(body: Text('Home Screen Content')),
            ),
            GoRoute(
              path: '/browse',
              builder: (_, __) => const Scaffold(body: Text('Browse Screen Content')),
            ),
            GoRoute(
              path: '/my-tasks',
              builder: (_, __) => const Scaffold(body: Text('My Tasks Content')),
            ),
            GoRoute(
              path: '/profile',
              builder: (_, __) => const Scaffold(body: Text('Profile Content')),
            ),
          ],
        ),
      ],
    );

    final dispatcher = AppBackButtonDispatcher(router);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: MockAuthProvider(),
        child: MaterialApp.router(
          routeInformationProvider: router.routeInformationProvider,
          routeInformationParser: router.routeInformationParser,
          routerDelegate: router.routerDelegate,
          backButtonDispatcher: dispatcher,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Initial screen is Browse
    expect(find.text('Browse Screen Content'), findsOneWidget);

    // 2. System Back on Browse -> redirects to Home
    final res1 = await dispatcher.didPopRoute();
    await tester.pumpAndSettle();
    expect(res1, isTrue);
    expect(find.text('Home Screen Content'), findsOneWidget);

    // 3. Switch to My Tasks tab
    router.go('/my-tasks');
    await tester.pumpAndSettle();
    expect(find.text('My Tasks Content'), findsOneWidget);

    // 4. System Back on My Tasks -> redirects to Home
    final res2 = await dispatcher.didPopRoute();
    await tester.pumpAndSettle();
    expect(res2, isTrue);
    expect(find.text('Home Screen Content'), findsOneWidget);

    // 5. Switch to Profile tab
    router.go('/profile');
    await tester.pumpAndSettle();
    expect(find.text('Profile Content'), findsOneWidget);

    // 6. System Back on Profile -> redirects to Home
    final res3 = await dispatcher.didPopRoute();
    await tester.pumpAndSettle();
    expect(res3, isTrue);
    expect(find.text('Home Screen Content'), findsOneWidget);

    // 7. System Back on Home -> displays Exit App popup with 'Stay' and 'Exit'
    final res4 = await dispatcher.didPopRoute();
    await tester.pumpAndSettle();
    expect(res4, isTrue);
    expect(find.text('Exit App'), findsOneWidget);
    expect(find.text('Are you sure you want to close Workmate4u?'), findsOneWidget);
    expect(find.text('Stay'), findsOneWidget);
    expect(find.text('Exit'), findsOneWidget);

    // 8. Tapping 'Stay' dismisses dialog and keeps user on Home screen
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text('Exit App'), findsNothing);
    expect(find.text('Home Screen Content'), findsOneWidget);
  });
}
