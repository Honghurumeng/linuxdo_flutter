import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import '../services/native_media.dart';

import '../api/linuxdo_api.dart';

class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({super.key, required this.url});

  final String url;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  final _api = LinuxDoApi();
  late Future<Uint8List> _future;
  int _turns = 0; // 0..3 四个方向
  int _pvSeed = 0; // 变更以强制 PhotoView 重新计算适屏比例

  @override
  void initState() {
    super.initState();
    _future = _api.fetchImageBytes(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('查看图片'),
        actions: [
          IconButton(
            tooltip: '重置缩放/旋转',
            icon: const Icon(Icons.restart_alt),
            onPressed: _reset,
          ),
          IconButton(
            tooltip: '左旋转90°',
            icon: const Icon(Icons.rotate_left),
            onPressed: () => setState(() {
              _turns = (_turns + 3) % 4; // -90°
              _pvSeed++;
            }),
          ),
          IconButton(
            tooltip: '右旋转90°',
            icon: const Icon(Icons.rotate_right),
            onPressed: () => setState(() {
              _turns = (_turns + 1) % 4; // +90°
              _pvSeed++;
            }),
          ),
          IconButton(
            tooltip: '保存到相册',
            icon: const Icon(Icons.download),
            onPressed: _save,
          ),
        ],
      ),
      body: Center(
        child: FutureBuilder<Uint8List>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator(color: Colors.white);
            }
            if (snap.hasError || !snap.hasData) {
              return Text('加载失败: ${snap.error}', style: const TextStyle(color: Colors.white));
            }
            final bytes = snap.data!;
            return RotatedBox(
              quarterTurns: _turns,
              child: PhotoView(
                key: ValueKey('pv-$_pvSeed-$_turns'),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 6.0,
                initialScale: PhotoViewComputedScale.contained,
                basePosition: Alignment.center,
                tightMode: true,
                imageProvider: MemoryImage(bytes),
              ),
            );
          },
        ),
      ),
    );
  }

  void _reset() {
    setState(() {
      _turns = 0;
      _pvSeed++;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重置至默认视图')),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final bytes = await _future;
      final name = 'linuxdo_${DateTime.now().millisecondsSinceEpoch}${_inferExt(widget.url)}';
      final ok = await NativeMedia.saveImage(bytes, name: name, mime: _inferMime(widget.url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '已保存到相册' : '保存失败')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  String _inferExt(String url) {
    final u = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (u.endsWith('.png')) return '.png';
    if (u.endsWith('.jpg') || u.endsWith('.jpeg')) return '.jpg';
    if (u.endsWith('.gif')) return '.gif';
    if (u.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  String _inferMime(String url) {
    final u = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (u.endsWith('.png')) return 'image/png';
    if (u.endsWith('.jpg') || u.endsWith('.jpeg')) return 'image/jpeg';
    if (u.endsWith('.gif')) return 'image/gif';
    if (u.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
