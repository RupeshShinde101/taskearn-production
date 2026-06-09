import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'services/notification_service.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/otp_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/browse/browse_screen.dart';
import 'screens/browse/task_detail_screen.dart';
import 'screens/tasks/post_task_screen.dart';
import 'screens/tasks/my_tasks_screen.dart';
import 'screens/tasks/task_in_progress_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/wallet/wallet_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/kyc_screen.dart';
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
  StreamSubscription<Map<String, dynamic>>? _notifSub;
  StreamSubscription<Map<String, dynamic>>? _taskCompletedSub;
  /// Navigation path deferred until the user is authenticated.
  /// Set when a notification tap arrives before auth is established.
  String? _pendingNavPath;

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
            loc.startsWith('/otp') ||
            loc.startsWith('/forgot-password');

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
        GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen(),
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
        GoRoute(
          path: '/kyc',
          builder: (_, __) => const KycScreen(),
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
    // Listen to notification taps and route to the correct screen.
    _notifSub ??= NotificationService.onNotificationTap.stream
        .listen(_handleNotifTap);

    // Consume any notification that launched the app from a terminated state.
    // Must be done AFTER subscribing so we can immediately process it.
    final pendingTap = NotificationService.consumePendingInitialTap();
    if (pendingTap != null) {
      _handleNotifTap(pendingTap);
    }

    // Show in-app popup when a task_completed event arrives while the poster
    // is actively using the app.
    _taskCompletedSub ??= NotificationService.onTaskCompleted.stream.listen((data) {
      final taskId = data['task_id']?.toString() ?? '';
      if (taskId.isEmpty) return;
      final navKey = _router.routerDelegate.navigatorKey;
      final ctx = navKey.currentContext;
      if (ctx == null) return;
      showDialog<void>(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50)),
              SizedBox(width: 8),
              Text('Task Completed!'),
            ],
          ),
          content: const Text(
            'Your task has been completed by the helper.\n'
            'Please verify the work and complete payment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Later'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                _router.push('/task/$taskId');
              },
              child: const Text('Verify & Pay Now'),
            ),
          ],
        ),
      );
    });
  }

  void _handleNotifTap(Map<String, dynamic> data) {
    // Resolve task ID — check all common key names the backend may send.
    final taskId = data['task_id']?.toString()
        ?? data['taskId']?.toString()
        ?? data['id']?.toString();
    final type = data['type']?.toString() ?? '';

    // Determine where to navigate.
    // inProgressTypes — these screens should open the in-progress view.
    const inProgressTypes = {
      'task_assigned',       // helper just accepted
      'task_accepted',       // poster confirmation
      'task_started',
      'task_completed_helper',
      'task_verify_sent',
      'payment_released',
      'payment_received',
    };
    // Notification types that map to the browse / detail view.
    const matchedTypes = {'task_matched', 'matched_task', 'skill_matched', 'nearby_task'};
    // Wallet-specific notification types that should open the wallet screen.
    const walletTypes = {
      'wallet_topup', 'wallet_credited',
      'withdrawal_requested', 'withdrawal_approved', 'withdrawal_rejected',
      'penalty_deducted', 'release_penalty', 'task_abandoned_penalty',
    };
    // Admin notification types — navigate to the notifications screen.
    const adminTypes = {
      'account_suspended', 'admin_suspended',
      'account_banned', 'admin_banned',
      'account_restored',
      'admin_warning', 'admin_message',
      'admin_balance_adjusted',
    };

    String destination;
    if (taskId != null && taskId.isNotEmpty) {
      destination = inProgressTypes.contains(type)
          ? '/task-in-progress/$taskId'
          : '/task/$taskId';
    } else {
      // No task ID in the FCM payload — pick the most appropriate screen.
      if (adminTypes.contains(type)) {
        destination = '/notifications';
      } else if (matchedTypes.contains(type)) {
        destination = '/browse'; // Matched-task alerts → browse for the task
      } else if (walletTypes.contains(type) || type.contains('payment')) {
        destination = '/wallet';
      } else if (type.isNotEmpty) {
        destination = '/my-tasks';
      } else {
        destination = '/notifications';
      }
    }

    // If the user is already authenticated, navigate immediately.
    // Otherwise, store the path and navigate once auth resolves.
    if (_authProvider?.status == AuthStatus.authenticated) {
      _router.push(destination);
    } else {
      _pendingNavPath = destination;
    }
  }

  void _onAuthChanged() {
    _router.refresh();
    // Navigate to a deferred notification destination now that auth is ready.
    if (_authProvider?.status == AuthStatus.authenticated &&
        _pendingNavPath != null) {
      final path = _pendingNavPath!;
      _pendingNavPath = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _router.push(path);
      });
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    _notifSub?.cancel();
    _taskCompletedSub?.cancel();
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
