import 'dart:convert';

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
    // Primary: task_id DB column. Fallback: parse from the 'data' JSON field
    // (which stores {"type":"skill_matched","taskId":"5",...}) so navigation
    // still works even if the DB column is unexpectedly null.
    String? taskId = json['task_id']?.toString();
    if (taskId == null || taskId.isEmpty) {
      try {
        final raw = json['data'];
        if (raw != null) {
          final Map<String, dynamic> dataMap =
              raw is String ? (jsonDecode(raw) as Map<String, dynamic>) : Map<String, dynamic>.from(raw as Map);
          taskId = dataMap['task_id']?.toString() ?? dataMap['taskId']?.toString();
        }
      } catch (_) {}
    }
    return AppNotification(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      body: json['body'] ?? json['message'] ?? '',
      type: json['notification_type'] ?? json['type'],
      taskId: taskId,
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
      // 1. Try RFC 7231 HTTP-date: "Thu, 11 Jul 2024 10:35:42 GMT"
      //    Flask 3.0 DefaultJSONProvider emits this for datetime objects.
      final httpParsed = _tryParseHttpDate(value);
      if (httpParsed != null) return httpParsed;

      // 2. Normalize PostgreSQL "YYYY-MM-DD HH:MM:SS" (space, no timezone).
      String s = value;
      if (s.contains(' ') && !s.contains('T')) {
        s = s.replaceFirst(' ', 'T');
      }
      // No timezone info → backend stores UTC, append Z.
      final hasZone = s.contains('+') || s.toUpperCase().contains('Z');
      if (!hasZone) s += 'Z';
      final parsed = DateTime.tryParse(s);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }

  // Parses RFC 7231 / RFC 2616 HTTP-date: "Thu, 11 Jul 2024 10:35:42 GMT"
  static const _monthMap = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4,  'may': 5,  'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static DateTime? _tryParseHttpDate(String s) {
    try {
      final clean = s.replaceAll(',', '').trim();
      final parts = clean.split(RegExp(r'\s+'));
      // ["Thu", "11", "Jul", "2024", "10:35:42", "GMT"]
      if (parts.length < 5) return null;
      final day   = int.tryParse(parts[1]);
      final month = _monthMap[parts[2].toLowerCase()];
      final year  = int.tryParse(parts[3]);
      final time  = parts[4].split(':');
      if (day == null || month == null || year == null || time.length != 3) return null;
      final hour = int.tryParse(time[0]);
      final min  = int.tryParse(time[1]);
      final sec  = int.tryParse(time[2]);
      if (hour == null || min == null || sec == null) return null;
      return DateTime.utc(year, month, day, hour, min, sec).toLocal();
    } catch (_) {
      return null;
    }
  }
}
