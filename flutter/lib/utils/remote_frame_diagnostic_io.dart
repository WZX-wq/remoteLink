import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

Future<String?> saveRemoteRgbaDiagnostic({
  required Uint8List rgba,
  required int width,
  required int height,
  required String sessionId,
}) async {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return null;
  }
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    order: img.ChannelOrder.rgba,
  );
  final safeSessionId = sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '_');
  final path = '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'kq-first-rgba-$safeSessionId.png';
  await File(path).writeAsBytes(img.encodePng(image), flush: true);
  return path;
}
