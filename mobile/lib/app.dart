import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/browse/browse_screen.dart';
import 'screens/browse/task_detail_screen.dart';
import 'screens/tasks/post_task_screen.dart';
import 'screens/tasks/my_tasks_screen.dart';
import 'screens/tasks/task_in_progress_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/wallet/wallet_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/referral/referral_screen.dart';
import 'screens/shell/main_shell.dart';

class Workmate4uApp extends StatefulWidget {
  const Workmate4uApp({super.key});

  @override
  State<Workmate4uApp> createState() => _Workmate4uAppState();
}

class _Workmate4uAppState extends State<Workmate4uApp> {
  late final GoRouter _router;
  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/splash',
      redirect: (context, state) {
        final auth = context.read<AuthProvider>();
        final status = auth.status;
        final loc = state.matchedLocation;

        // While checking auth, stay on splash screen
        if (status == AuthStatus.unknown) {
          return loc == '/splash' ? null : '/splash';
        }

        final isAuthRoute = loc.startsWith('/login') ||
            loc.startsWith('/register') ||
            loc.startsWith('/otp');

        if (status == AuthStatus.unauthenticated && !isAuthRoute) return '/login';
        if (status == AuthStatus.authenticated && (isAuthRoute || loc == '/splash')) return '/home';
        return null;
      },
      routes: [
        // Splash
        GoRoute(
          path: '/splash',
          builder: (_, __) => const SplashScreen(),
        ),

        // Auth routes (no shell)
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (_, __) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/otp',
          builder: (_, state) =>
              OtpScreen(extra: state.extra as Map<String, dynamic>?),
        ),

        // Main shell with bottom nav
        ShellRoute(
          builder: (_, __, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, __) => const HomeScreen(),
            ),
            GoRoute(
              path: '/browse',
              builder: (_, __) => const BrowseScreen(),
            ),
            GoRoute(
              path: '/my-tasks',
              builder: (_, __) => const MyTasksScreen(),
            ),
            GoRoute(
              path: '/profile',
              builder: (_, __) => const ProfileScreen(),
            ),
          ],
        ),

        // Full-screen routes
        GoRoute(
          path: '/task/:id',
          builder: (_, state) =>
              TaskDetailScreen(taskId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/post-task',
          builder: (_, __) => const PostTaskScreen(),
        ),
        GoRoute(
          path: '/task-in-progress/:id',
          builder: (_, state) =>
              TaskInProgressScreen(taskId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/chat/:taskId',
          builder: (_, state) => ChatScreen(
            taskId: state.pathParameters['taskId']!,
            extra: state.extra as Map<String, dynamic>?,
          ),
        ),
        GoRoute(
          path: '/wallet',
          builder: (_, __) => const WalletScreen(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/referral',
          builder: (_, __) => const ReferralScreen(),
        ),
      ],
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthProvider>();
    if (_authProvider != auth) {
      _authProvider?.removeListener(_onAuthChanged);
      _authProvider = auth;
      _authProvider!.addListener(_onAuthChanged);
    }
  }

  void _onAuthChanged() {
    _router.refresh();
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Workmate4u',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      routerConfig: _router,
    );
  }
}
