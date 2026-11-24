import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/profile_mode_switch_dialog.dart';
import '../../navigation/app_back_button_dispatcher.dart';

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {
  static const _tabs = [
    '/home',
    '/browse',
    '/my-tasks',
    '/profile',
  ];

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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        await AppNavigationHandler.handleBackPress();
      },
      child: Scaffold(
        extendBody: true,
        body: widget.child,
        bottomNavigationBar: _FloatingNavBar(
          selectedIndex: idx,
          onTabTap: _onTap,
          onPostTap: () async {
            final auth = context.read<AuthProvider>();
            if (!auth.isPosterMode) {
              final switched = await showProfileModeSwitchDialog(
                context,
                targetMode: 'poster',
                title: 'Switch to Poster Profile',
                message:
                    'Posting tasks requires a Poster profile. Would you like to switch to Poster mode to post this task?',
                actionLabel: 'Switch to Poster & Continue',
              );
              if (switched != true) return;
            }
            if (context.mounted) {
              context.push('/post-task');
            }
          },
        ),
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

