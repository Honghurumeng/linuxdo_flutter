import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../api/linuxdo_api.dart';

class SecureImage extends StatefulWidget {
  const SecureImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.error,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? error;

  @override
  State<SecureImage> createState() => _SecureImageState();
}

class _SecureImageState extends State<SecureImage> {
  final _api = LinuxDoApi();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchImageBytesWithType(widget.url);
  }

  @override
  void didUpdateWidget(covariant SecureImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = _api.fetchImageBytesWithType(widget.url);
    }
  }

  bool _isSvgContent(Uint8List data) {
    try {
      final header = String.fromCharCodes(data.take(100));
      return header.trim().startsWith('<svg') || header.contains('<svg');
    } catch (_) {
      return false;
    }
  }



  @override
  Widget build(BuildContext context) {
    final placeholder = widget.placeholder ?? _defaultPlaceholder();
    final error = widget.error ?? _defaultError();
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return placeholder;
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return error;
        }
        
        final result = snapshot.data!;
        final data = result['bytes'] as Uint8List;
        final isSvg = result['isSvg'] as bool;
        
        if (isSvg || _isSvgContent(data)) {
          return SvgPicture.memory(
            data,
            width: widget.width,
            height: widget.height,
            fit: widget.fit ?? BoxFit.contain,
            placeholderBuilder: (_) => placeholder,
            errorBuilder: (_, __, ___) => error,
          );
        }
        
        return Image.memory(
          data,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          gaplessPlayback: true,
        );
      },
    );
  }

  Widget _defaultPlaceholder() => SizedBox(
        width: widget.width,
        height: widget.height,
        child: const DecoratedBox(
          decoration: BoxDecoration(color: Color(0x11000000)),
        ),
      );

  Widget _defaultError() => SizedBox(
        width: widget.width,
        height: widget.height,
        child: const DecoratedBox(
          decoration: BoxDecoration(color: Color(0x11FF0000)),
        ),
      );
}

