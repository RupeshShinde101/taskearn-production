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

class _MainShellState extends State<MainShell> {
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
    final isHome = idx == 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!isHome) {
          // Non-home tab → navigate to home instead of closing
          context.go('/home');
          return;
        }
        // Home tab → ask the user before exiting
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit App'),
            content: const Text('Do you want to close the application?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('No'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        );
        if (shouldExit == true && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: widget.child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                  selected: idx == 0,
                  onTap: () => _onTap(0),
                ),
                _NavItem(
                  icon: Icons.search_outlined,
                  activeIcon: Icons.search,
                  label: 'Browse',
                  selected: idx == 1,
                  onTap: () => _onTap(1),
                ),
                // Center "Post" button
                GestureDetector(
                  onTap: () => context.push('/post-task'),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      gradient:
                          LinearGradient(colors: AppColors.gradient),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x446366F1),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add,
                        color: Colors.white, size: 28),
                  ),
                ),
                _NavItem(
                  icon: Icons.assignment_outlined,
                  activeIcon: Icons.assignment,
                  label: 'My Tasks',
                  selected: idx == 2,
                  onTap: () => _onTap(2),
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Profile',
                  selected: idx == 3,
                  onTap: () => _onTap(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                selected ? activeIcon : icon,
                key: ValueKey(selected),
                color: selected ? AppColors.primary : AppColors.gray,
                size: 24,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? AppColors.primary : AppColors.gray,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
