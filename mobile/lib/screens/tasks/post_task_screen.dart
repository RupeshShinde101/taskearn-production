import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class PostTaskScreen extends StatefulWidget {
  const PostTaskScreen({super.key});

  @override
  State<PostTaskScreen> createState() => _PostTaskScreenState();
}

class _PostTaskScreenState extends State<PostTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  String _selectedCategory = 'errands';
  LatLng? _location;
  bool _loading = false;
  bool _gettingLocation = false;

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _getLocation() async {
    setState(() => _gettingLocation = true);
    final loc = await LocationService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _location = loc;
        _gettingLocation = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please allow location access')),
      );
      return;
    }

    setState(() => _loading = true);

    final taskData = {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'category': _selectedCategory,
      'price': double.tryParse(_budgetCtrl.text) ?? 0,
      'budget': double.tryParse(_budgetCtrl.text) ?? 0,
      'latitude': _location!.latitude,
      'longitude': _location!.longitude,
      'address': _addressCtrl.text.isNotEmpty ? _addressCtrl.text.trim() : null,
    };

    final ok = await context.read<TaskProvider>().postTask(taskData);

    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task posted successfully!')),
      );
      context.go('/my-tasks');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                context.read<TaskProvider>().error ?? 'Failed to post task')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post a Task')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  hintText: 'e.g. Pick up parcel from Bandra',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 5) ? 'Min 5 characters' : null,
              ),
              const SizedBox(height: 14),

              // Category
              const Text('Category',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: AppColors.dark)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TaskCategory.all.map((c) {
                  final sel = _selectedCategory == c.id;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = c.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : AppColors.light,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? AppColors.primary : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '${c.icon} ${c.label}',
                        style: TextStyle(
                          color: sel ? Colors.white : AppColors.gray,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Description
              TextFormField(
                controller: _descCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Describe what needs to be done…',
                  prefixIcon: Icon(Icons.description_outlined),
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 10) ? 'Min 10 characters' : null,
              ),
              const SizedBox(height: 14),

              // Budget
              TextFormField(
                controller: _budgetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Budget (₹)',
                  hintText: 'Minimum ₹100',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n < 100) return 'Minimum budget is ₹100';
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Address
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address / Landmark (optional)',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 14),

              // Location status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _location != null
                      ? AppColors.success.withValues(alpha: 0.08)
                      : AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _location != null
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _location != null ? Icons.my_location : Icons.location_off,
                      color: _location != null
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _location != null
                            ? 'Location detected (${_location!.latitude.toStringAsFixed(4)}, ${_location!.longitude.toStringAsFixed(4)})'
                            : 'Location not detected',
                        style: TextStyle(
                          color: _location != null
                              ? AppColors.success
                              : AppColors.warning,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (_gettingLocation)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      TextButton(
                        onPressed: _getLocation,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              GradientButton(
                label: 'Post Task',
                loading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
