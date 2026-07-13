import 'dart:typed_data';

class TextureRgbaRenderer {
  Future<int> createTexture(int key) {
    throw UnimplementedError();
  }

  Future<bool> closeTexture(int key) {
    return Future(() => true);
  }

  Future<bool> markFrameAvailable(int key) {
    return Future(() => false);
  }

  Future<bool> onRgba(
      int key, Uint8List data, int height, int width, int strideAlign) {
    throw UnimplementedError();
  }

  Future<int> getTexturePtr(int key) {
    throw UnimplementedError();
  }
}
