import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../widgets/app_exit_dialog.dart';

/// Custom root back-button dispatcher that provides seamless back navigation
/// across all Android versions (including Android 13/14/15 Predictive Back):
/// 1. Tells the Android OS that Flutter actively handles back gestures.
/// 2. Closes the on-screen soft keyboard if open.
/// 3. Pops any pushed routes, dialogs, bottom sheets, or sub-pages (e.g. task detail, post-task).
/// 4. If on any non-home tab (/browse, /my-tasks, /profile), redirects the user to the Home tab.
/// 5. If on the Home tab, displays the styled Exit confirmation dialog ('Stay' or 'Exit').
class AppBackButtonDispatcher extends RootBackButtonDispatcher {
  final GoRouter router;
  bool _isExitDialogShowing = false;

  AppBackButtonDispatcher(this.router) {
    // Explicitly notify Android 13/14/15 OnBackInvokedDispatcher that Flutter handles back navigation
    SystemNavigator.setFrameworkHandlesBack(true);
  }

  @override
  Future<bool> didPopRoute() async {
    // Ensure Android 13/14/15 knows framework handles back
    SystemNavigator.setFrameworkHandlesBack(true);

    // 1. If on-screen keyboard is visible, dismiss it first and keep app open
    final bottom = WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;
    if (bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      return true;
    }

    // 2. If GoRouter has any pushed route / dialog on the stack, pop it
    if (router.canPop()) {
      router.pop();
      return true;
    }

    // 3. Inspect current route location
    final location = router.routerDelegate.currentConfiguration.uri.path;

    // If on any tab other than Home (/browse, /my-tasks, /profile) -> redirect to Home
    if (location.startsWith('/browse') ||
        location.startsWith('/my-tasks') ||
        location.startsWith('/profile')) {
      router.go('/home');
      return true;
    }

    // 4. If on Home tab -> show styled exit confirmation dialog ('Stay' or 'Exit')
    if (location == '/home' || location == '/') {
      if (_isExitDialogShowing) {
        return true;
      }
      final context = router.routerDelegate.navigatorKey.currentContext;
      if (context != null && context.mounted) {
        _isExitDialogShowing = true;
        showAppExitDialog(context).then((shouldExit) {
          _isExitDialogShowing = false;
          if (shouldExit == true) {
            SystemNavigator.pop();
          }
        }).catchError((_) {
          _isExitDialogShowing = false;
        });
      }
      return true;
    }

    // Default fallback
    return false;
  }
}
