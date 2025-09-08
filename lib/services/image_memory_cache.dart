import 'package:flutter/foundation.dart';

class CachedImage {
  const CachedImage({required this.bytes, this.contentType});

  final Uint8List bytes;
  final String? contentType;
  int get length => bytes.lengthInBytes;
}

/// Lightweight in-memory LRU cache for this app session only.
/// Limits entries and total bytes to avoid unbounded growth.
class ImageMemoryCache {
  ImageMemoryCache._();
  static final ImageMemoryCache instance = ImageMemoryCache._();

  // Reasonable defaults; tweak if needed.
  int maxEntries = 500;
  int maxTotalBytes = 50 * 1024 * 1024; // 50MB

  final Map<String, CachedImage> _map = <String, CachedImage>{};
  int _totalBytes = 0;

  CachedImage? get(String key) {
    final v = _map.remove(key);
    if (v != null) {
      // Re-insert to mark as most recently used
      _map[key] = v;
      if (kDebugMode) {
        debugPrint('[ImageCache] hit $key (${v.length}B)');
      }
    }
    return v;
  }

  void set(String key, Uint8List bytes, {String? contentType}) {
    // Replace existing if present
    final old = _map.remove(key);
    if (old != null) {
      _totalBytes -= old.length;
    }
    final entry = CachedImage(bytes: bytes, contentType: contentType);
    _map[key] = entry;
    _totalBytes += entry.length;
    if (kDebugMode) {
      debugPrint('[ImageCache] put $key (${entry.length}B), total=${_totalBytes}B, entries=${_map.length}');
    }
    _evictIfNeeded();
  }

  void evict(String key) {
    final removed = _map.remove(key);
    if (removed != null) {
      _totalBytes -= removed.length;
    }
  }

  void clear() {
    _map.clear();
    _totalBytes = 0;
  }

  void _evictIfNeeded() {
    // Evict least-recently-used while over limits
    while (_map.length > maxEntries || _totalBytes > maxTotalBytes) {
      final oldestKey = _map.keys.first;
      final oldest = _map.remove(oldestKey);
      if (oldest != null) {
        _totalBytes -= oldest.length;
        if (kDebugMode) {
          debugPrint('[ImageCache] evict $oldestKey (${oldest.length}B)');
        }
      } else {
        break;
      }
    }
  }
}
