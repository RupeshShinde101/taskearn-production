import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onNativeBack);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
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

  Future<bool?> _showExitDialog() {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.5),
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
                  color: AppColors.primary.withOpacity(0.18),
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
                          color: Colors.white.withOpacity(0.2),
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
                                    color: AppColors.primary.withOpacity(0.35),
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
    final location = GoRouterState.of(context).matchedLocation;
    final idx = _indexForPath(location);
    _currentIdx = idx;

    // With extendBody:true, Flutter auto-adjusts MediaQuery.padding.bottom
    // for the body to equal navbarHeight + safeAreaBottom, so every screen
    // that reads MediaQuery.of(context).padding.bottom gets the right value.
    return Scaffold(
      extendBody: true,
      body: widget.child,
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
    (Icons.search_rounded,     'Search'),
    (Icons.assignment_rounded, 'Tasks'),
    (Icons.person_rounded,     'Profile'),
  ];

  // ── Geometry (dp) ──────────────────────────────────────────────────────────
  static const _barH   = 56.0;          // bar height
  static const _fabD   = 62.0;          // FAB diameter  (larger than bar!)
  static const _fabR   = _fabD / 2;     // 36
  static const _notchR = _fabR + 6.0;   // 42 — circular arc radius of notch
  static const _gapW   = _notchR * 2 + 10; // Row gap = ~94

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Notched pill bar ──────────────────────────────────────
            CustomPaint(
              painter: _NavBarPainter(notchRadius: _notchR),
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
                    const SizedBox(width: _gapW),
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
            // ── White halo behind FAB (bridges bar ↔ FAB seamlessly) ──
            Positioned(
              bottom: _barH - _notchR,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: _notchR * 2 - 2,
                  height: _notchR * 2 - 2,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            // ── FAB button ────────────────────────────────────────────
            Positioned(
              bottom: _barH - _notchR,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onPostTap,
                  child: Container(
                    width: _fabD,
                    height: _fabD,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.55),
                          blurRadius: 20,
                          spreadRadius: 1,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: const Color(0xFF93C5FD).withValues(alpha: 0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),
            // ── Dot indicator below FAB ───────────────────────────────
            Positioned(
              bottom: 5,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3B82F6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notched pill CustomPainter ────────────────────────────────────────────────

class _NavBarPainter extends CustomPainter {
  final double notchRadius;
  const _NavBarPainter({required this.notchRadius});

  static const _border  = Color(0xFFBDD5F6);
  static const _fill    = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildPath(size);

    // Blue outer glow
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4F46E5).withValues(alpha: 0.18)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 10),
    );

    // Fill
    canvas.drawPath(path,
        Paint()..color = _fill..style = PaintingStyle.fill);

    // Border
    canvas.drawPath(
      path,
      Paint()
        ..color = _border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _buildPath(Size size) {
    final w   = size.width;
    final h   = size.height;
    final cr  = h / 2;         // pill corner radius (fully rounded)
    final cx  = w / 2;
    final nr  = notchRadius;   // 42 — matches FAB halo radius
    final t   = 12.0;          // horizontal transition before arc starts

    final path = Path();

    // top-left pill corner
    path.moveTo(cr, 0);

    // top edge — left side
    path.lineTo(cx - nr - t, 0);

    // smooth cubic into the arc start (tangent match)
    path.cubicTo(
      cx - nr - t / 2, 0,   // ease out from flat
      cx - nr, 0,            // arrive at arc tangent point
      cx - nr, nr * 0.15,   // tiny drop before arc
    );

    // ── Circular arc for the notch ──────────────────────────────────
    // Arc from left side to right side of notch, curving downward.
    path.arcToPoint(
      Offset(cx + nr, nr * 0.15),
      radius: Radius.circular(nr),
      clockwise: true,
    );

    // smooth cubic out of arc (mirror of entry)
    path.cubicTo(
      cx + nr, 0,
      cx + nr + t / 2, 0,
      cx + nr + t, 0,
    );

    // top edge — right side
    path.lineTo(w - cr, 0);

    // right pill end
    path.arcToPoint(Offset(w, cr),
        radius: Radius.circular(cr), clockwise: true);
    path.lineTo(w, h - cr);
    path.arcToPoint(Offset(w - cr, h),
        radius: Radius.circular(cr), clockwise: true);

    // bottom edge
    path.lineTo(cr, h);

    // left pill end
    path.arcToPoint(Offset(0, h - cr),
        radius: Radius.circular(cr), clockwise: true);
    path.lineTo(0, cr);
    path.arcToPoint(Offset(cr, 0),
        radius: Radius.circular(cr), clockwise: true);

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _NavBarPainter old) =>
      old.notchRadius != notchRadius;
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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 230),
      value: widget.selected ? 1.0 : 0.0,
    );
    _color = ColorTween(
      begin: const Color(0xFF94A3B8),
      end: const Color(0xFF3B82F6),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_NavItem old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected) {
      widget.selected ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon with soft blue pill bg when active
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Color.lerp(
                        Colors.transparent,
                        const Color(0xFFDBEAFE),
                        t),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.icon, size: 20, color: _color.value),
                ),
                const SizedBox(height: 1),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        t > 0.5 ? FontWeight.w700 : FontWeight.w500,
                    color: _color.value,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 1),
                // Underline indicator
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 16 * t,
                  height: 2.0,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                        Colors.transparent,
                        const Color(0xFF3B82F6),
                        t),
                    borderRadius: BorderRadius.circular(2),
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