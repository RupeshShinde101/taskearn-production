/// Shared date/time parsing utilities used by all model classes.
///
/// The Railway backend (PostgreSQL) often omits the trailing 'Z' from UTC
/// timestamps and sometimes uses a space separator instead of 'T'.
/// These helpers normalise both variants before parsing.
class AppDateUtils {
  AppDateUtils._();

  /// Parses [raw] as a UTC timestamp and converts it to local time.
  ///
  /// Accepts ISO-8601 and PostgreSQL-style ("2026-05-31 10:00:00") strings.
  /// Returns [fallback] (default: [DateTime.now]) when the value is null,
  /// empty, or unparseable.
  static DateTime parse(dynamic raw, {DateTime? fallback}) {
    final fb = fallback ?? DateTime.now();
    if (raw == null) return fb;
    var s = raw.toString().trim();
    if (s.isEmpty) return fb;
    // Normalise space separator → T  (e.g. "2026-05-31 10:00:00" → "2026-05-31T10:00:00")
    if (s.length > 10 && s[10] == ' ') s = '${s.substring(0, 10)}T${s.substring(11)}';
    // Treat no-timezone strings as UTC (Railway backend is UTC)
    if (!s.endsWith('Z') && !s.contains('+') && !RegExp(r'-\d{2}:\d{2}$').hasMatch(s)) {
      s = '${s}Z';
    }
    return DateTime.tryParse(s)?.toLocal() ?? fb;
  }

  /// Like [parse] but returns null instead of a fallback when the value is
  /// absent or unparseable.  Use for optional timestamps (e.g. completedAt).
  static DateTime? parseOrNull(dynamic raw) {
    if (raw == null) return null;
    var s = raw.toString().trim();
    if (s.isEmpty) return null;
    if (s.length > 10 && s[10] == ' ') s = '${s.substring(0, 10)}T${s.substring(11)}';
    if (!s.endsWith('Z') && !s.contains('+') && !RegExp(r'-\d{2}:\d{2}$').hasMatch(s)) {
      s = '${s}Z';
    }
    return DateTime.tryParse(s)?.toLocal();
  }
}
