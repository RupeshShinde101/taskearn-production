import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/message.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/chat_encryption_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  final String taskId;
  final Map<String, dynamic>? extra;

  const ChatScreen({super.key, required this.taskId, this.extra});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;

  // Task & participant info
  String _otherName = 'User';
  String _otherRole = 'Participant';
  String? _otherPhone;
  String _taskTitle = 'Task Discussion';
  String _taskCategory = '';
  double _taskBudget = 0.0;
  String _taskStatus = 'in_progress';

  @override
  void initState() {
    super.initState();
    NotificationService.activeChatTaskId = widget.taskId;
    _initParticipantData();
    _loadMessages();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollMessages());
  }

  @override
  void dispose() {
    if (NotificationService.activeChatTaskId == widget.taskId) {
      NotificationService.activeChatTaskId = null;
    }
    _pollTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _initParticipantData() {
    if (widget.extra != null) {
      final extra = widget.extra!;
      _otherName = extra['otherName'] ??
          extra['helper_name'] ??
          extra['poster_name'] ??
          'User';
      _otherRole = extra['otherRole'] ??
          (extra['isPoster'] == true ? 'Helper' : 'Task Poster');
      _otherPhone = extra['otherPhone'] ??
          extra['helper_phone'] ??
          extra['poster_phone'];
      _taskTitle = extra['taskTitle'] ?? extra['title'] ?? 'Task Discussion';
      _taskCategory = extra['category'] ?? '';
      _taskBudget = (extra['budget'] is num)
          ? (extra['budget'] as num).toDouble()
          : 0.0;
      _taskStatus = extra['status'] ?? 'in_progress';
    } else {
      _fetchTaskDetails();
    }
  }

  Future<void> _fetchTaskDetails() async {
    try {
      final res = await ApiService.get('/tasks/${widget.taskId}');
      final taskData = res['task'] ?? res;
      if (taskData != null && mounted) {
        final currentUserId = context.read<AuthProvider>().user?.id;
        final posterId = taskData['posted_by']?.toString();
        final isPoster = currentUserId == posterId;

        setState(() {
          _taskTitle = taskData['title'] ?? 'Task Discussion';
          _taskCategory = taskData['category'] ?? '';
          _taskBudget = (taskData['budget'] is num)
              ? (taskData['budget'] as num).toDouble()
              : 0.0;
          _taskStatus = taskData['status'] ?? 'in_progress';

          if (isPoster) {
            _otherName = taskData['helper_name'] ?? 'Helper';
            _otherRole = 'Helper';
            _otherPhone = taskData['helper_phone'];
          } else {
            _otherName = taskData['poster_name'] ?? 'Poster';
            _otherRole = 'Task Poster';
            _otherPhone = taskData['poster_phone'];
          }
        });
      }
    } catch (_) {}
  }

  String get _cacheKey => 'cached_chat_messages_${widget.taskId}';

  List<ChatMessage> _loadCachedMessages() {
    try {
      final raw = StorageService.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List? ?? [];
        return list
            .whereType<Map<String, dynamic>>()
            .map((j) => ChatMessage.fromJson(j, fallbackTaskId: widget.taskId))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  void _persistCachedMessages(List<ChatMessage> msgs) {
    try {
      final jsonList = msgs.map((m) => m.toJson()).toList();
      StorageService.setString(_cacheKey, jsonEncode(jsonList));
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    // 1. Show cached messages immediately for instant offline/resilient access
    final cached = _loadCachedMessages();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _messages = cached;
        _loading = false;
      });
      _scrollToBottom();
    }

    // 2. Fetch latest from server
    try {
      final data = await ApiService.get('/chat/${widget.taskId}/messages');
      final msgs = (data['messages'] as List? ?? [])
          .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>, fallbackTaskId: widget.taskId))
          .toList();

      if (mounted) {
        setState(() {
          _messages = msgs;
          _loading = false;
        });
        _persistCachedMessages(msgs);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('[ChatScreen] Load messages error: $e');
      if (mounted && _messages.isEmpty) setState(() => _loading = false);
    }
  }

  Future<void> _pollMessages() async {
    if (!mounted) return;
    try {
      final data = await ApiService.get('/chat/${widget.taskId}/messages');
      final msgs = (data['messages'] as List? ?? [])
          .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>, fallbackTaskId: widget.taskId))
          .toList();

      if (!mounted) return;
      // Preserve local pending messages that haven't confirmed yet
      final localPending = _messages.where((m) => m.id.startsWith('local_')).toList();
      final serverContents = msgs.map((m) => m.content).toSet();
      final remainingLocals = localPending.where((l) => !serverContents.contains(l.content)).toList();
      final merged = [...msgs, ...remainingLocals];

      if (merged.length != _messages.length ||
          (msgs.isNotEmpty && _messages.isNotEmpty && msgs.last.id != _messages.last.id)) {
        setState(() {
          _messages = merged;
        });
        _persistCachedMessages(merged);
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('[ChatScreen] Poll error: $e');
    }
  }

  Future<void> _send([String? customText]) async {
    final text = (customText ?? _msgCtrl.text).trim();
    if (text.isEmpty || _sending) return;

    if (customText == null) {
      _msgCtrl.clear();
    }
    setState(() => _sending = true);

    final currentUserId = context.read<AuthProvider>().user?.id ?? '';
    final currentUserName = context.read<AuthProvider>().user?.name ?? 'Me';

    // End-to-End Encrypt the message before sending to server
    final encryptedPayload = ChatEncryptionService.encrypt(text, widget.taskId);

    // Optimistically add decrypted message for instant UI responsiveness
    final optimisticMsg = ChatMessage(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      taskId: widget.taskId,
      senderId: currentUserId,
      senderName: currentUserName,
      content: text,
      sentAt: DateTime.now(),
    );

    setState(() {
      _messages.add(optimisticMsg);
    });
    _persistCachedMessages(_messages);
    _scrollToBottom();

    try {
      final res = await ApiService.post(
        '/chat/${widget.taskId}/send',
        body: {
          'message': encryptedPayload,
          'userName': currentUserName,
          'senderName': currentUserName,
        },
      );

      // Immediately upgrade local pending message to server-confirmed
      if (res is Map && mounted) {
        final serverMsg = res['message'];
        final serverId = serverMsg is Map ? serverMsg['id']?.toString() : null;
        if (serverId != null && serverId.isNotEmpty) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.id == optimisticMsg.id);
            if (idx != -1) {
              _messages[idx] = ChatMessage(
                id: serverId,
                taskId: optimisticMsg.taskId,
                senderId: optimisticMsg.senderId,
                senderName: optimisticMsg.senderName,
                content: optimisticMsg.content,
                sentAt: optimisticMsg.sentAt,
                isRead: true,
              );
            }
          });
          _persistCachedMessages(_messages);
        }
      }

      // Background poll will synchronize all messages
      _pollMessages();
    } catch (e) {
      debugPrint('[ChatScreen] Send message failed: $e');
      final errMsg = e is ApiException ? e.message : 'Failed to deliver message. Please check connection.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                setState(() {
                  _messages.removeWhere((m) => m.id == optimisticMsg.id);
                });
                _send(text);
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _callOtherParty() async {
    if (_otherPhone == null || _otherPhone!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Phone number not available for $_otherName.')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: _otherPhone!.trim());
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch dialer.')),
        );
      }
    }
  }

  List<String> get _quickReplies {
    final isHelper = _otherRole.toLowerCase().contains('poster');
    if (isHelper) {
      return [
        "I'm on my way",
        "I've arrived at the location",
        "Working on the task now",
        "Task completed! Please review.",
      ];
    } else {
      return [
        "Are you on your way?",
        "Please call me once you arrive",
        "Please let me know if you need anything",
        "Thank you! Everything looks great.",
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<AuthProvider>().user?.id ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.dark,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    _otherName.isNotEmpty ? _otherName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _otherName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _otherRole,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      const Icon(Icons.lock_rounded, size: 10, color: Color(0xFF059669)),
                      const SizedBox(width: 3),
                      const Text(
                        'End-to-End Encrypted',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_otherPhone != null && _otherPhone!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.phone_outlined, color: AppColors.primary, size: 21),
              tooltip: 'Call $_otherName',
              onPressed: _callOtherParty,
            ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: AppColors.gray, size: 21),
            tooltip: 'Task Details',
            onPressed: () => context.push('/task/${widget.taskId}'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Compact Task Header Banner ──
          GestureDetector(
            onTap: () => context.push('/task/${widget.taskId}'),
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Center(
                      child: Text(
                        _taskCategory.isNotEmpty
                            ? TaskCategory.iconFor(_taskCategory)
                            : '📋',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _taskTitle,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              'Budget: ₹${_taskBudget.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 3,
                              height: 3,
                              decoration: const BoxDecoration(
                                color: AppColors.grayLight,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _taskStatus.replaceAll('_', ' ').toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.grayLight, size: 20),
                ],
              ),
            ),
          ),

          // ── Encryption Assurance Strip ──
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined, size: 13, color: Color(0xFF047857)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Encrypted 1-on-1: Only you & $_otherName can read messages',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF047857),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // ── Message Stream ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: AppColors.primary,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Chat with $_otherName',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.dark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Discuss task details, timing, and directions in real-time. Messages are end-to-end encrypted.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.gray,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: _quickReplies.take(3).map((reply) {
                                  return ActionChip(
                                    label: Text(reply),
                                    backgroundColor: Colors.white,
                                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                                    labelStyle: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary,
                                    ),
                                    onPressed: () => _send(reply),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = _messages[i];
                          final isMe = msg.senderId == currentUserId ||
                              msg.id.startsWith('local_');
                          final showDateHeader = i == 0 ||
                              !_isSameDay(_messages[i - 1].sentAt, msg.sentAt);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showDateHeader)
                                _buildDateHeader(msg.sentAt),
                              _ChatBubble(
                                message: msg,
                                isMe: isMe,
                              ),
                            ],
                          );
                        },
                      ),
          ),

          // ── Quick Reply Chips Row (when messages exist) ──
          if (_messages.isNotEmpty)
            Container(
              height: 38,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: _quickReplies.length,
                itemBuilder: (_, i) {
                  return ActionChip(
                    label: Text(_quickReplies[i]),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFE2E8F0)),
                    labelStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
                    ),
                    onPressed: () => _send(_quickReplies[i]),
                  );
                },
              ),
            ),

          // ── Bottom Input Bar ──
          Container(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              MediaQuery.of(context).viewInsets.bottom > 0
                  ? 8
                  : MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: TextField(
                      controller: _msgCtrl,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 14, color: AppColors.dark),
                      decoration: const InputDecoration(
                        hintText: 'Type an encrypted message…',
                        hintStyle: TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          onPressed: () => _send(),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildDateHeader(DateTime date) {
    final now = DateTime.now();
    String label;
    if (_isSameDay(date, now)) {
      label = 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMM d, yyyy').format(date);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const _ChatBubble({
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('hh:mm a').format(message.sentAt);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3.5),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        decoration: BoxDecoration(
          gradient: isMe
              ? const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isMe ? null : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
          border: isMe ? null : Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && message.senderName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.senderName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
            Text(
              message.content,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: isMe ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.75)
                        : const Color(0xFF94A3B8),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.id.startsWith('local_')
                        ? Icons.access_time_rounded
                        : Icons.done_all_rounded,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
