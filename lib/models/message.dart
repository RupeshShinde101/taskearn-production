class ChatMessage {
  final String id;
  final String taskId;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String content;
  final String? imageUrl;
  final bool isRead;
  final DateTime sentAt;

  ChatMessage({
    required this.id,
    required this.taskId,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.content,
    this.imageUrl,
    this.isRead = false,
    required this.sentAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      taskId: json['task_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender_name'] ?? '',
      senderAvatar: json['sender_avatar'],
      content: json['content'] ?? json['message'] ?? '',
      imageUrl: json['image_url'],
      isRead: json['is_read'] ?? false,
      sentAt: json['sent_at'] != null
          ? DateTime.tryParse(json['sent_at']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
