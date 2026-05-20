import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_card.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _searchCtrl = TextEditingController();
  String _selectedCategory = 'all';
  double _maxBudget = 5000;
  double _radiusKm = 10;

  @override
  void initState() {
    super.initState();
    context.read<TaskProvider>().fetchBrowseTasks(
          category: _selectedCategory,
          radiusKm: _radiusKm,
          refresh: true,
        );
  }

  void _applyFilters() {
    context.read<TaskProvider>().fetchBrowseTasks(
          category: _selectedCategory,
          maxBudget: _maxBudget,
          radiusKm: _radiusKm,
          refresh: true,
        );
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filters',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              const Text('Category',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _SmallChip(
                      label: 'All',
                      selected: _selectedCategory == 'all',
                      onTap: () => setModal(() => _selectedCategory = 'all'),
                    ),
                    ...TaskCategory.all.map(
                      (c) => _SmallChip(
                        label: c.label,
                        selected: _selectedCategory == c.id,
                        onTap: () =>
                            setModal(() => _selectedCategory = c.id),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Max Budget',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('₹${_maxBudget.toInt()}',
                      style: const TextStyle(color: AppColors.primary)),
                ],
              ),
              Slider(
                value: _maxBudget,
                min: 100,
                max: 10000,
                divisions: 99,
                activeColor: AppColors.primary,
                onChanged: (v) => setModal(() => _maxBudget = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Radius',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('${_radiusKm.toInt()} km',
                      style: const TextStyle(color: AppColors.primary)),
                ],
              ),
              Slider(
                value: _radiusKm,
                min: 1,
                max: 50,
                divisions: 49,
                activeColor: AppColors.primary,
                onChanged: (v) => setModal(() => _radiusKm = v),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _applyFilters();
                },
                child: const Text('Apply Filters'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search tasks…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilters();
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => _applyFilters(),
            ),
          ),

          // Task list
          Expanded(
            child: Consumer<TaskProvider>(
              builder: (_, tasks, __) {
                if (tasks.isLoadingBrowse && tasks.browseTasks.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (tasks.browseTasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inbox_outlined,
                            size: 64, color: AppColors.grayLight),
                        const SizedBox(height: 12),
                        const Text('No tasks available'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _applyFilters,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => _applyFilters(),
                  child: ListView.builder(
                    itemCount: tasks.browseTasks.length,
                    itemBuilder: (_, i) => TaskCard(
                      task: tasks.browseTasks[i],
                      onTap: () =>
                          context.push('/task/${tasks.browseTasks[i].id}'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SmallChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.light,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.gray,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
