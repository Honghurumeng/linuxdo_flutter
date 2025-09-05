import 'package:flutter/services.dart';

class NativeMedia {
  static const MethodChannel _channel = MethodChannel('app.media');

  static Future<bool> saveImage(Uint8List bytes, {required String name, String? mime}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('saveImage', {
        'bytes': bytes,
        'name': name,
        'mime': mime,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }
}

