import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../screens/browse/browse_screen.dart';
import '../widgets/app_exit_dialog.dart';

/// Centralized global back navigation handler for Workmate4u.
/// Handles back button presses from all sources:
/// 1. RootBackButtonDispatcher (Flutter system back)
/// 2. Root PopScope (predictive back gesture on modern Android)
/// 3. Native Android MethodChannel ('com.workmate4u/navigation')
class AppNavigationHandler {
  static GoRouter? _router;
  static bool _isExitDialogShowing = false;
  static const MethodChannel _channel = MethodChannel('com.workmate4u/navigation');
  static bool _initialized = false;

  static void initialize(GoRouter router) {
    _router = router;
    if (!_initialized) {
      _initialized = true;
      SystemNavigator.setFrameworkHandlesBack(true);
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'back_pressed') {
          return await handleBackPress();
        }
        return false;
      });
    }
  }

  /// Master back navigation router. Returns true if handled (app stays open),
  /// or false if system should perform default behavior.
  static Future<bool> handleBackPress() async {
    final router = _router;
    if (router == null) return false;

    // Explicitly notify Android OS that Flutter is handling back gestures
    SystemNavigator.setFrameworkHandlesBack(true);

    // 1. If on-screen soft keyboard is open, dismiss it first and stay on screen
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty && views.first.viewInsets.bottom > 0) {
        FocusManager.instance.primaryFocus?.unfocus();
        return true;
      }
    } catch (_) {}

    // 2. If BrowseScreen has an active search or category view open, return to main categories view
    try {
      if (BrowseScreen.onBackOverride?.call() == true) {
        return true;
      }
    } catch (_) {}

    // 3. If there is an open modal, dialog, or nested route on the Navigator stack, pop it
    final navContext = router.routerDelegate.navigatorKey.currentContext;
    if (navContext != null) {
      final navigator = Navigator.maybeOf(navContext);
      if (navigator != null && navigator.canPop()) {
        navigator.pop();
        return true;
      }
    }

    // 4. If GoRouter has any pushed route on the stack, pop it
    if (router.canPop()) {
      router.pop();
      return true;
    }

    // 5. Inspect current route path
    String location = '';
    try {
      location = router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {}

    // 6. If on the Application Home Screen ('/home' or '/'), show styled exit confirmation dialog
    if (location == '/home' || location == '/' || location.isEmpty) {
      if (_isExitDialogShowing) {
        return true;
      }
      final ctx = router.routerDelegate.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        _isExitDialogShowing = true;
        try {
          final shouldExit = await showAppExitDialog(ctx);
          if (shouldExit == true) {
            SystemNavigator.pop();
          }
        } catch (_) {
        } finally {
          _isExitDialogShowing = false;
        }
      }
      return true;
    }

    // 7. If on sub-auth routes (/register, /otp, /forgot-password), go back to /login
    if (location.startsWith('/register') ||
        location.startsWith('/otp') ||
        location.startsWith('/forgot-password')) {
      router.go('/login');
      return true;
    }

    // If on /login, show exit dialog
    if (location == '/login') {
      if (_isExitDialogShowing) return true;
      final ctx = router.routerDelegate.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        _isExitDialogShowing = true;
        try {
          final shouldExit = await showAppExitDialog(ctx);
          if (shouldExit == true) {
            SystemNavigator.pop();
          }
        } catch (_) {
        } finally {
          _isExitDialogShowing = false;
        }
      }
      return true;
    }

    // 8. If on ANY other screen in the entire application (e.g. /browse, /my-tasks,
    // /profile, /task/:id, /task-in-progress/:id, /poster-task-in-progress/:id,
    // /wallet, /notifications, /post-task, /chat/:taskId, /kyc, /referral, etc.):
    // NEVER exit to mobile home screen! Always redirect to the Application Home Screen (/home)!
    router.go('/home');
    return true;
  }
}

/// Root back button dispatcher registered with MaterialApp.router
class AppBackButtonDispatcher extends RootBackButtonDispatcher {
  final GoRouter router;

  AppBackButtonDispatcher(this.router) {
    AppNavigationHandler.initialize(router);
  }

  @override
  Future<bool> didPopRoute() async {
    return await AppNavigationHandler.handleBackPress();
  }
}
