import 'dart:typed_data';

import 'package:flutter/material.dart';

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
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.fetchImageBytes(widget.url);
  }

  @override
  void didUpdateWidget(covariant SecureImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _future = _api.fetchImageBytes(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = widget.placeholder ?? _defaultPlaceholder();
    final error = widget.error ?? _defaultError();
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return placeholder;
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return error;
        }
        return Image.memory(
          snapshot.data!,
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

