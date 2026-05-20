import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/location_service.dart';
import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedCategory = 'all';
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final location = await LocationService.getCurrentLocation();
    if (!mounted) return;

    context.read<NotificationProvider>().fetchNotifications();
    context.read<WalletProvider>().fetchWallet();
    context.read<TaskProvider>().fetchBrowseTasks(
          category: _selectedCategory,
          lat: location?.latitude,
          lng: location?.longitude,
          radiusKm: 10,
          refresh: true,
        );
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      final tasks = context.read<TaskProvider>();
      if (!tasks.isLoadingBrowse && tasks.hasMore) {
        tasks.fetchBrowseTasks(category: _selectedCategory);
      }
    }
  }

  Future<void> _onRefresh() async {
    final location = await LocationService.getCurrentLocation();
    if (!mounted) return;
    await context.read<TaskProvider>().fetchBrowseTasks(
          category: _selectedCategory,
          lat: location?.latitude,
          lng: location?.longitude,
          radiusKm: 10,
          refresh: true,
        );
  }

  void _onCategorySelected(String cat) {
    setState(() => _selectedCategory = cat);
    context.read<TaskProvider>().fetchBrowseTasks(
          category: cat,
          refresh: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final notifications = context.watch<NotificationProvider>();
    final wallet = context.watch<WalletProvider>();

    return Scaffold(
      backgroundColor: AppColors.light,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // App Bar
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: AppColors.white,
            title: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: AppColors.gradient),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.handshake_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                const GradientText(
                  'Workmate4u',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            actions: [
              // Wallet balance chip
              GestureDetector(
                onTap: () => context.push('/wallet'),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.light,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        '₹${wallet.balance.balance.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark),
                      ),
                    ],
                  ),
                ),
              ),
              // Notifications
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => context.push('/notifications'),
                  ),
                  if (notifications.unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: AppColors.danger,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${notifications.unreadCount}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Welcome banner
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: GradientContainer(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hi, ${auth.user?.name.split(' ').first ?? 'there'}! 👋',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Find tasks near you or post your own',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => context.push('/post-task'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text('Post Task',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Category filter
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                children: [
                  _CategoryChip(
                    label: 'All',
                    selected: _selectedCategory == 'all',
                    onTap: () => _onCategorySelected('all'),
                  ),
                  ...TaskCategory.all.map((c) => _CategoryChip(
                        label: '${c.icon} ${c.label}',
                        selected: _selectedCategory == c.id,
                        onTap: () => _onCategorySelected(c.id),
                      )),
                ],
              ),
            ),
          ),

          // Section header
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Tasks Near You',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.dark)),
            ),
          ),

          // Task list
          Consumer<TaskProvider>(
            builder: (_, tasks, __) {
              if (tasks.isLoadingBrowse && tasks.browseTasks.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (tasks.browseTasks.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off,
                            size: 48, color: AppColors.grayLight),
                        const SizedBox(height: 8),
                        const Text('No tasks found',
                            style: TextStyle(color: AppColors.gray)),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: _onRefresh,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i == tasks.browseTasks.length) {
                      return tasks.isLoadingBrowse
                          ? const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          : const SizedBox(height: 80);
                    }
                    return TaskCard(
                      task: tasks.browseTasks[i],
                      onTap: () =>
                          context.push('/task/${tasks.browseTasks[i].id}'),
                    );
                  },
                  childCount: tasks.browseTasks.length + 1,
                ),
              );
            },
          ),
        ],
      ),

      // FAB – post task
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/post-task'),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Post Task',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.primary : AppColors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.gray,
            fontSize: 13,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
