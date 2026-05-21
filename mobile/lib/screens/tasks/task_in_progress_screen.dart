import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class TaskInProgressScreen extends StatefulWidget {
  final String taskId;
  const TaskInProgressScreen({super.key, required this.taskId});

  @override
  State<TaskInProgressScreen> createState() => _TaskInProgressScreenState();
}

class _TaskInProgressScreenState extends State<TaskInProgressScreen> {
  Task? _task;
  bool _loading = true;
  bool _completing = false;
  bool _abandoning = false;
  String? _proofPath;

  @override
  void initState() {
    super.initState();
    _load();
    _startLocationUpdates();
  }

  Future<void> _load() async {
    final task = await context.read<TaskProvider>().getTaskDetail(widget.taskId);
    if (mounted) setState(() { _task = task; _loading = false; });
  }

  void _startLocationUpdates() {
    LocationService.getLocationStream().listen((position) async {
      if (!mounted) return;
      try {
        await ApiService.post('/tracking/update-location', body: {
          'task_id': widget.taskId,
          'latitude': position.latitude,
          'longitude': position.longitude,
        });
      } catch (_) {}
    });
  }

  Future<void> _openNavigation() async {
    if (_task == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${_task!.latitude},${_task!.longitude}'
        '&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps')),
      );
    }
  }

  Future<void> _callPoster() async {
    final phone = _task?.posterPhone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsappPoster() async {
    final raw = _task?.posterPhone?.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw == null || raw.isEmpty) return;
    final full = raw.startsWith('91') ? raw : '91$raw';
    final uri = Uri.parse('https://wa.me/$full');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _pickProof() async {
    final picker = ImagePicker();
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Add Completion Proof',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(ctx);
                final f = await picker.pickImage(
                    source: ImageSource.camera, imageQuality: 70);
                if (mounted && f != null) setState(() => _proofPath = f.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(ctx);
                final f = await picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 70);
                if (mounted && f != null) setState(() => _proofPath = f.path);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _markComplete() async {
    if (_proofPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a proof photo before submitting.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    setState(() => _completing = true);
    final ok = await context
        .read<TaskProvider>()
        .markCompleted(widget.taskId, proofPath: _proofPath);
    if (!mounted) return;
    setState(() => _completing = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Submitted! Poster will verify and release payment.'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/my-tasks');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<TaskProvider>().error ?? 'Failed to submit'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _releaseTask() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Task'),
        content: const Text(
            'Releasing a task without completing it may result in a penalty.\n\n'
            'More than 3 releases may trigger a 48-hour account suspension.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Release',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _abandoning = true);
    final ok = await context.read<TaskProvider>().abandonTask(widget.taskId);
    if (!mounted) return;
    setState(() => _abandoning = false);
    if (ok) {
      context.go('/my-tasks');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<TaskProvider>().error ?? 'Failed to release task'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task In Progress')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: AppColors.grayLight),
              const SizedBox(height: 12),
              const Text('Task not found',
                  style: TextStyle(color: AppColors.gray, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final task = _task!;
    final hasPhone =
        task.posterPhone != null && task.posterPhone!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task In Progress'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Active header ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.gradient),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.flash_on, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Task Active',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                          Text(
                            task.title,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${task.budget.toStringAsFixed(0)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Navigate to Location ─────────────────────────────────
              _SectionCard(
                title: 'Task Location',
                icon: Icons.location_on_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (task.address != null && task.address!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          task.address!,
                          style: const TextStyle(
                              color: AppColors.gray,
                              fontSize: 13,
                              height: 1.4),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _openNavigation,
                        icon: const Icon(Icons.navigation_rounded, size: 18),
                        label: const Text('Navigate to Task Location'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Poster Contact ───────────────────────────────────────
              _SectionCard(
                title: 'Task Poster',
                icon: Icons.person_outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          backgroundImage: task.posterAvatar != null
                              ? NetworkImage(task.posterAvatar!)
                              : null,
                          child: task.posterAvatar == null
                              ? Text(
                                  task.posterName.isNotEmpty
                                      ? task.posterName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.posterName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.dark),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (task.posterRating > 0)
                                Row(
                                  children: [
                                    const Icon(Icons.star,
                                        size: 13, color: AppColors.warning),
                                    const SizedBox(width: 2),
                                    Text(
                                      task.posterRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                          color: AppColors.gray, fontSize: 12),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (hasPhone)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _callPoster,
                              icon: const Icon(Icons.call, size: 16),
                              label: const Text('Call'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.success,
                                side: const BorderSide(
                                    color: AppColors.success),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _whatsappPoster,
                              icon: const Icon(Icons.message_outlined, size: 16),
                              label: const Text('WhatsApp'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF25D366),
                                side: const BorderSide(
                                    color: Color(0xFF25D366)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (!hasPhone)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Contact number not provided by poster.',
                          style: TextStyle(color: AppColors.gray, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Task Details ─────────────────────────────────────────
              _SectionCard(
                title: 'Task Details',
                icon: Icons.description_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailRow('Category', task.category),
                    const Divider(height: 14),
                    _DetailRow('Budget', '₹${task.budget.toStringAsFixed(0)}'),
                    const Divider(height: 14),
                    _DetailRow('Status', task.statusLabel),
                    const Divider(height: 14),
                    const Text('Description',
                        style: TextStyle(
                            color: AppColors.gray, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      task.description,
                      style: const TextStyle(
                          color: AppColors.dark, fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Completion Proof ─────────────────────────────────────
              const Text('Completion Proof',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.dark)),
              const SizedBox(height: 4),
              const Text(
                'The poster will see this photo to verify your work and release payment.',
                style: TextStyle(
                    color: AppColors.gray, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 10),
              if (_proofPath != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _proofPath!.startsWith('http')
                      ? Image.network(
                          _proofPath!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _proofError(),
                        )
                      : Image.file(
                          File(_proofPath!),
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _proofError(),
                        ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickProof,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(_proofPath == null
                      ? 'Add Proof Photo'
                      : 'Change Photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Actions ──────────────────────────────────────────────
              GradientButton(
                label: 'Mark as Completed',
                loading: _completing,
                onPressed:
                    (_completing || _abandoning) ? () {} : _markComplete,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      (_completing || _abandoning) ? null : _releaseTask,
                  icon: _abandoning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.danger),
                        )
                      : const Icon(Icons.exit_to_app_outlined, size: 18),
                  label: const Text('Release Task'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _proofError() => Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.light,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined,
              size: 48, color: AppColors.grayLight),
        ),
      );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard(
      {required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.dark),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: AppColors.gray, fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.dark,
                fontSize: 13),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
