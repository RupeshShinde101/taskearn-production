import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

// Caches the last decoded MemoryImage so that rapid notifyListeners() calls
// (e.g. loading state toggling) don't re-decode base64 and cause flicker.
int? _cachedDataUriHash;
MemoryImage? _cachedMemoryImage;

/// Returns the appropriate [ImageProvider] for an avatar/photo URL.
///
/// Handles three cases:
///   1. `data:image/...;base64,...`  — decoded once and cached by content hash
///      to prevent flicker on widget rebuilds.
///   2. `https://` / `http://`       — [CachedNetworkImageProvider] which keeps
///      the image in memory/disk cache across rebuilds.
///   3. null / empty / other          — returns null (caller shows placeholder).
ImageProvider? avatarImage(String? url) {
  if (url == null || url.isEmpty) return null;

  if (url.startsWith('data:')) {
    final hash = url.hashCode;
    if (hash == _cachedDataUriHash && _cachedMemoryImage != null) {
      return _cachedMemoryImage;
    }
    try {
      final comma = url.indexOf(',');
      if (comma != -1) {
        final image = MemoryImage(base64Decode(url.substring(comma + 1)));
        _cachedDataUriHash = hash;
        _cachedMemoryImage = image;
        return image;
      }
    } catch (_) {}
    return null;
  }

  if (url.startsWith('http://') || url.startsWith('https://')) {
    return CachedNetworkImageProvider(url);
  }

  return null;
}
