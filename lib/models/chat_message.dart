import '../services/chat_encryption_service.dart';

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

  factory ChatMessage.fromJson(Map<String, dynamic> json, {String? fallbackTaskId}) {
    final tId = json['task_id']?.toString() ??
        json['taskId']?.toString() ??
        fallbackTaskId ??
        '';
    final rawContent = (json['content'] ?? json['message'] ?? '').toString();
    final decryptedContent = tId.isNotEmpty
        ? ChatEncryptionService.decrypt(rawContent, tId)
        : rawContent;

    return ChatMessage(
      id: json['id']?.toString() ?? '',
      taskId: tId,
      senderId: (json['sender_id'] ?? json['user_id'] ?? json['userId'])?.toString() ?? '',
      senderName: json['sender_name'] ?? json['user_name'] ?? json['userName'] ?? 'User',
      senderAvatar: json['sender_avatar'],
      content: decryptedContent,
      imageUrl: json['image_url'],
      isRead: json['is_read'] ?? false,
      sentAt: json['sent_at'] != null
          ? DateTime.tryParse(json['sent_at'].toString()) ?? DateTime.now()
          : (json['timestamp'] != null
              ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
              : DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'sender_id': senderId,
      'sender_name': senderName,
      'sender_avatar': senderAvatar,
      'content': content,
      'image_url': imageUrl,
      'is_read': isRead,
      'sent_at': sentAt.toIso8601String(),
    };
  }
}
