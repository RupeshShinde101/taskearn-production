import 'dart:convert';
import 'package:flutter/widgets.dart';

/// Returns the appropriate [ImageProvider] for an avatar/photo URL.
///
/// Handles three cases:
///   1. `data:image/...;base64,...`  — Google Sign-In sometimes returns these;
///      decoded with [base64Decode] and served as [MemoryImage].
///   2. `https://` / `http://`       — regular remote URL → [NetworkImage].
///   3. null / empty / other          — returns null (caller shows placeholder).
ImageProvider? avatarImage(String? url) {
  if (url == null || url.isEmpty) return null;

  if (url.startsWith('data:')) {
    try {
      final comma = url.indexOf(',');
      if (comma != -1) {
        return MemoryImage(base64Decode(url.substring(comma + 1)));
      }
    } catch (_) {}
    return null;
  }

  if (url.startsWith('http://') || url.startsWith('https://')) {
    return NetworkImage(url);
  }

  return null;
}
