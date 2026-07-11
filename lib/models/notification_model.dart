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
      type: json['notification_type'] ?? json['type'],
      taskId: json['task_id']?.toString(),
      isRead: json['status'] == 'read' || (json['is_read'] == true),
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
      // Normalize PostgreSQL "YYYY-MM-DD HH:MM:SS.ffffff" (space separator, no TZ)
      // to ISO 8601 so Dart can parse it.
      String s = value;
      if (s.contains(' ') && !s.contains('T')) {
        s = s.replaceFirst(' ', 'T');
      }
      // If there is no timezone info at all, the backend stored UTC — append Z.
      final hasZone = s.contains('+') || s.toUpperCase().contains('Z');
      if (!hasZone) s += 'Z';
      final parsed = DateTime.tryParse(s);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }
}
