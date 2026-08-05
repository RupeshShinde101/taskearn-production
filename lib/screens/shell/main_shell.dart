import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _tabs = [
    '/home',
    '/browse',
    '/my-tasks',
    '/profile',
  ];

  static const _channel = MethodChannel('com.workmate4u/navigation');
  int _currentIdx = 0;
  bool _keyboardVisible = false;
  AuthProvider? _authListener;
  bool _popupScheduled = false;
  bool _popupActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onNativeBack);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _authListener = context.read<AuthProvider>()
        ..addListener(_onAuthStateChanged);
      _onAuthStateChanged();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    _authListener?.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  /// Fires whenever window metrics change (keyboard open/close, rotation, etc.).
  @override
  void didChangeMetrics() {
    final bottom = WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;
    final visible = bottom > 0;
    if (visible != _keyboardVisible) {
      _keyboardVisible = visible;
    }
  }

  /// Called from native Android when the back button / gesture is triggered.
  /// Returns true  → Flutter handled it (Android does nothing).
  /// Returns false → Android falls back to its default behaviour.
  Future<dynamic> _onNativeBack(MethodCall call) async {
    if (call.method != 'back_pressed' || !mounted) return false;

    // If the keyboard is currently visible, dismiss it and stop here.
    // The user's next back press will trigger navigation.
    if (_keyboardVisible) {
      FocusManager.instance.primaryFocus?.unfocus();
      return true;
    }

    // If there is a pushed route on the stack (e.g. task detail, notifications,
    // post-task, chat) — pop it normally and do NOT apply tab-level logic.
    if (GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
      return true;
    }

    if (_currentIdx != 0) {
      // Non-home tab → go to Home
      context.go('/home');
      return true;
    }
    // Home tab → ask before exiting
    final shouldExit = await _showExitDialog();
    if (shouldExit == true && mounted) SystemNavigator.pop();
    return true;
  }

  void _onAuthStateChanged() {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn && !auth.cityVerified && !auth.cityRestricted && !_popupScheduled && !_popupActive) {
      _popupScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _popupScheduled = false;
        if (!mounted) return;
        final a = context.read<AuthProvider>();
        if (a.isLoggedIn && !a.cityVerified && !a.cityRestricted && !_popupActive) _showCityGatePopup();
      });
    }
  }

  void _showCityGatePopup() {
    _popupActive = true;
    final auth = context.read<AuthProvider>();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: _CityGatePopup(
          onVerified: () {
            _popupActive = false;
            entry.remove();
            auth.setCityVerified();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('\u{1F4CD} You\'re in Pune! Welcome to Workmate4u.'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 4),
              ),
            );
          },
          onExit: (reason) {
            _popupActive = false;
            entry.remove();
            if (reason == 'blocked') { auth.setCityBlocked(); }
            else { auth.setCityMismatch(); }
          },
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  Future<bool?> _showExitDialog() {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with gradient
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppColors.gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.exit_to_app_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Exit App',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    children: [
                      const Text(
                        'Are you sure you want to close Workmate4u?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          // No button
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(
                                    color: AppColors.primary, width: 1.5),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Stay',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Yes button
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: AppColors.gradient,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Exit',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onTap(int index) {
    context.go(_tabs[index]);
  }

  int _indexForPath(String location) {
    if (location.startsWith('/browse')) return 1;
    if (location.startsWith('/my-tasks')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _indexForPath(location);
    _currentIdx = idx;

    Widget body = widget.child;
    if (auth.isLoggedIn && auth.cityRestricted) {
      body = Stack(
        children: [
          widget.child,
          _CityGateRestrictionView(
            reason: auth.cityGateReason,
            onRetry: () {
              setState(() => _popupScheduled = false);
              context.read<AuthProvider>().resetCityGateForRetry();
            },
          ),
        ],
      );
    }

    return Scaffold(
      extendBody: true,
      body: body,
      bottomNavigationBar: _FloatingNavBar(
        selectedIndex: idx,
        onTabTap: _onTap,
        onPostTap: () => context.push('/post-task'),
      ),
    );
  }
}

// ── Floating pill navigation bar ─────────────────────────────────────────────

class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabTap;
  final VoidCallback onPostTap;

  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onTabTap,
    required this.onPostTap,
  });

  static const _tabs = [
    (Icons.home_rounded,       'Home'),
    (Icons.explore_rounded,    'Search'),
    (Icons.checklist_rounded,  'Tasks'),
    (Icons.person_rounded,     'Profile'),
  ];

  // ── Geometry (dp) ──────────────────────────────────────────────────────────
  static const _barH   = 70.0;
  static const _fabD   = 44.0;          // inline center FAB diameter

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: CustomPaint(
            painter: const _NavBarPainter(),
            child: SizedBox(
              height: _barH,
              child: Row(
                children: [
                  for (int i = 0; i < 2; i++)
                    Expanded(
                      child: _NavItem(
                        icon: _tabs[i].$1,
                        label: _tabs[i].$2,
                        selected: selectedIndex == i,
                        onTap: () => onTabTap(i),
                      ),
                    ),
                  Expanded(
                    child: _CenterFab(onTap: onPostTap, fabD: _fabD),
                  ),
                  for (int i = 2; i < 4; i++)
                    Expanded(
                      child: _NavItem(
                        icon: _tabs[i].$1,
                        label: _tabs[i].$2,
                        selected: selectedIndex == i,
                        onTap: () => onTabTap(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Notched pill CustomPainter ────────────────────────────────────────────────

class _NavBarPainter extends CustomPainter {
  const _NavBarPainter();

  static const _border = Color(0xFF2563EB);
  static const _fill   = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);

    // Soft outer blue glow
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF2563EB).withValues(alpha: 0.14)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10),
    );

    // White fill
    canvas.drawPath(path, Paint()..color = _fill..style = PaintingStyle.fill);

    // Uniform thick blue border
    canvas.drawPath(
      path,
      Paint()
        ..color = _border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _buildPath(Size size) {
    return Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(size.height / 2),
      ));
  }

  @override
  bool shouldRepaint(covariant _NavBarPainter old) => false;
}
// ── Center inline FAB ───────────────────────────────────────────────────

class _CenterFab extends StatefulWidget {
  final VoidCallback onTap;
  final double fabD;
  const _CenterFab({required this.onTap, required this.fabD});
  @override
  State<_CenterFab> createState() => _CenterFabState();
}

class _CenterFabState extends State<_CenterFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: Center(
          child: Container(
            width: widget.fabD + 8,
            height: widget.fabD + 8,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFBFDBFE), width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.20),
                  blurRadius: 12,
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Container(
              width: widget.fabD,
              height: widget.fabD,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF1E40AF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
// ── Tab item ──────────────────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String   label;
  final bool     selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Color?>   _color;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 230),
      value: widget.selected ? 1.0 : 0.0,
    );
    _color = ColorTween(
      begin: const Color(0xFF111827),  // bold near-black inactive
      end:   const Color(0xFF2563EB),  // blue active
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_NavItem old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) {
      widget.selected ? _ctrl.forward() : _ctrl.reverse();
      if (_pressed) setState(() => _pressed = false);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon with tiny circle press highlight only
                AnimatedScale(
                  scale: _pressed ? 0.82 : 1.0,
                  duration: const Duration(milliseconds: 90),
                  curve: Curves.easeOut,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _pressed
                          ? const Color(0xFF2563EB).withValues(alpha: 0.10)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, size: 24,
                        color: _color.value),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _color.value,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 3),
                // Small active dot indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: t > 0.1 ? 5.0 : 0.0,
                  height: t > 0.1 ? 5.0 : 0.0,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                        Colors.transparent, const Color(0xFF2563EB), t),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// City gate — popup (new user) + restriction view (blocked / mismatch)
// ═══════════════════════════════════════════════════════════════════════════

// ── Restriction view: covers tab content, navbar stays visible ──────────────
class _CityGateRestrictionView extends StatelessWidget {
  final String reason;
  final VoidCallback onRetry;
  const _CityGateRestrictionView({required this.reason, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom + 88;
    return Container(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 40, 24, bottomPad),
        child: Center(
          child: reason == 'blocked'
              ? const _CgBlockedCard()
              : _CgMismatchCard(onRetry: onRetry),
        ),
      ),
    );
  }
}

// ── Full-screen popup overlay (non-dismissible) ─────────────────────────────
class _CityGatePopup extends StatefulWidget {
  final VoidCallback onVerified;
  final void Function(String reason) onExit;
  const _CityGatePopup({required this.onVerified, required this.onExit});

  @override
  State<_CityGatePopup> createState() => _CityGatePopupState();
}

class _CityGatePopupState extends State<_CityGatePopup>
    with WidgetsBindingObserver {
  final _cityCtrl = TextEditingController();
  bool _loading = false;
  String? _errorMsg;
  bool _blocked = false;
  bool _gpsMismatch = false;
  bool _verified = false;
  bool _locationConflict = false;
  String _enteredCity = '';

  static const double _puneLat = 18.5204;
  static const double _puneLng = 73.8567;
  static const double _puneRadiusM = 50000.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Future<bool> didPopRoute() async {
    if (!_verified) {
      if (!_blocked && !_locationConflict) {
        setState(() => _errorMsg = 'Please enter your city first.');
      }
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) {
      setState(() => _errorMsg = 'Please enter your city name.');
      return;
    }
    final cityIsPune = city.toLowerCase() == 'pune';
    setState(() {
      _loading = true; _errorMsg = null;
      _blocked = false; _gpsMismatch = false; _locationConflict = false;
    });

    if (!cityIsPune) {
      // Non-Pune city: silently check GPS only if permission already granted —
      // never pop a permission dialog just because the user typed a non-Pune city.
      final perm = await Geolocator.checkPermission();
      final hasPermission = perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever;
      if (hasPermission) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
          final distM = Geolocator.distanceBetween(
              pos.latitude, pos.longitude, _puneLat, _puneLng);
          if (!mounted) return;
          if (distM <= _puneRadiusM) {
            setState(() { _loading = false; _locationConflict = true; _enteredCity = city; });
            return;
          }
        } catch (_) {} // GPS failed silently — fall through to block
      }
      if (!mounted) return;
      setState(() { _loading = false; _blocked = true; });
      return;
    }

    // City is Pune — full GPS check, request permission if needed
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorMsg = 'Location permission required.\nPlease enable it in Settings and try again.';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 15),
      );
      final distM = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, _puneLat, _puneLng);
      if (!mounted) return;
      if (distM <= _puneRadiusM) {
        setState(() { _loading = false; _verified = true; });
        Future.delayed(const Duration(seconds: 2), () { if (mounted) widget.onVerified(); });
      } else {
        setState(() { _loading = false; _gpsMismatch = true; });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMsg = 'Could not get your location. Make sure GPS is enabled and try again.';
      });
    }
  }

  void _onScrimTap() {
    if (!_blocked && !_verified && !_locationConflict) {
      setState(() => _errorMsg = 'Please enter your city first.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final topPad = MediaQuery.of(context).padding.top;

    final card = AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(24, 40, 24, 40 + bottomInset),
      child: Center(
        child: _locationConflict
            ? _CgLocationConflictCard(
                enteredCity: _enteredCity,
                onUsePune: () {
                  setState(() { _locationConflict = false; _verified = true; });
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) widget.onVerified();
                  });
                },
                onKeepCity: () => setState(() {
                  _locationConflict = false;
                  _blocked = true;
                }),
              )
            : _blocked
            ? _CgBlockedCard(
                onAcknowledge: () => widget.onExit('blocked'),
              )
            : _gpsMismatch
                ? _CgMismatchCard(
                    onRetry: () => setState(() {
                      _gpsMismatch = false;
                      _errorMsg = null;
                      _cityCtrl.clear();
                    }),
                    onContinue: () => widget.onExit('mismatch'),
                  )
                : _verified
                    ? const _CgVerifiedCard()
                    : _CgInputCard(
                        ctrl: _cityCtrl,
                        loading: _loading,
                        onVerify: () {
                          if (_errorMsg != null) setState(() => _errorMsg = null);
                          _verify();
                        },
                      ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onScrimTap,
            child: Container(color: Colors.black.withValues(alpha: 0.65)),
          ),
        ),
        card,
        if (_errorMsg != null)
          Positioned(
            top: topPad + 16, left: 24, right: 24,
            child: IgnorePointer(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMsg!,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Input card ───────────────────────────────────────────────────────────────
class _CgInputCard extends StatelessWidget {
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onVerify;
  const _CgInputCard({required this.ctrl, required this.loading, required this.onVerify});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76, height: 76,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: AppColors.gradient),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_city_rounded, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 22),
            const Text('Where are you located?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.dark),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text("Enter your city to verify you're in our service area.",
                style: TextStyle(color: AppColors.gray, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 26),
            TextField(
              controller: ctrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'City', hintText: 'e.g. Pune',
                prefixIcon: const Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => onVerify(),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: loading ? null : onVerify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Text('Verify Location',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── GPS mismatch card ────────────────────────────────────────────────────────
class _CgMismatchCard extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback? onContinue; // null in restriction view
  const _CgMismatchCard({required this.onRetry, this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84, height: 84,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: const Icon(Icons.wrong_location_rounded, color: AppColors.danger, size: 42),
            ),
            const SizedBox(height: 22),
            const Text('Location Mismatch',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.dark),
                textAlign: TextAlign.center),
            const SizedBox(height: 14),
            const Text(
              "You entered Pune, but your GPS shows you're outside Pune.\n\nMake sure you're physically in Pune and try again.",
              style: TextStyle(fontSize: 14, color: AppColors.gray, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Try Again', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (onContinue != null) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: onContinue,
                child: const Text('Continue with restrictions',
                    style: TextStyle(color: AppColors.gray, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Blocked card (city ≠ Pune) ───────────────────────────────────────────────
class _CgBlockedCard extends StatelessWidget {
  final VoidCallback? onAcknowledge; // null in restriction view (permanent block)
  const _CgBlockedCard({this.onAcknowledge});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84, height: 84,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.location_off_rounded, color: AppColors.warning, size: 42),
            ),
            const SizedBox(height: 22),
            const Text('Not Available Yet',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.dark),
                textAlign: TextAlign.center),
            const SizedBox(height: 14),
            const Text(
              "We're not available in your city yet.\nWe'll be there soon! \u{1F680}",
              style: TextStyle(fontSize: 15, color: AppColors.gray, height: 1.65),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.light, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text('\u{1F4CD}  Currently serving: Pune only',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary, fontSize: 13),
                  textAlign: TextAlign.center),
            ),
            if (onAcknowledge != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 46,
                child: OutlinedButton(
                  onPressed: onAcknowledge,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Understood',
                      style: TextStyle(color: AppColors.gray, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Verified / welcome card ──────────────────────────────────────────────────
class _CgVerifiedCard extends StatelessWidget {
  const _CgVerifiedCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84, height: 84,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 50),
            ),
            const SizedBox(height: 22),
            const Text('Welcome to Workmate4u! \u{1F389}',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.dark),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text("Great news \u2014 you're in Pune!\nTaking you to the app\u2026",
                style: TextStyle(fontSize: 15, color: AppColors.gray, height: 1.6),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// ── Location conflict card (non-Pune city typed but GPS shows Pune) ──────────
class _CgLocationConflictCard extends StatelessWidget {
  final String enteredCity;
  final VoidCallback onUsePune;
  final VoidCallback onKeepCity;
  const _CgLocationConflictCard({
    required this.enteredCity,
    required this.onUsePune,
    required this.onKeepCity,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84, height: 84,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_searching_rounded,
                  color: AppColors.warning, size: 42),
            ),
            const SizedBox(height: 22),
            const Text('Location Conflict',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800,
                    color: AppColors.dark),
                textAlign: TextAlign.center),
            const SizedBox(height: 14),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(fontSize: 14, color: AppColors.gray,
                    height: 1.6),
                children: [
                  const TextSpan(
                      text: 'Your GPS shows you are currently in '),
                  const TextSpan(
                      text: 'Pune',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                  const TextSpan(text: ', but you entered '),
                  TextSpan(
                      text: enteredCity,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark)),
                  const TextSpan(
                      text: '.\n\nWhich city would you like to use?'),
                ],
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                onPressed: onUsePune,
                icon: const Icon(Icons.my_location_rounded, size: 20),
                label: const Text('Use Current Location (Pune)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity, height: 46,
              child: OutlinedButton(
                onPressed: onKeepCity,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Continue with $enteredCity',
                    style: const TextStyle(color: AppColors.gray,
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}