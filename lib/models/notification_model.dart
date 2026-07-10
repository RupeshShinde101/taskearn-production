class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? type;
  final String? taskId;
  final bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.type,
    this.taskId,
    this.isRead = false,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      body: json['body'] ?? json['message'] ?? '',
      type: json['type'],
      taskId: json['task_id']?.toString(),
      isRead: json['is_read'] ?? false,
      createdAt: _parseDateTime(json['created_at']),
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is int) {
      // Unix timestamp — seconds if plausibly seconds, else milliseconds
      final ms = value > 1e10 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }
}
