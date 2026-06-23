import 'package:image/image.dart' as img;
import 'package:flutter_hbb/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zxing2/qrcode.dart';

void main() {
  group('KqMemberOrder WeChat launch links', () {
    test('parses official WeChat App Pay request parameters', () {
      final order = KqMemberOrder.fromJson({
        'order_no': 'order-app',
        'pay_type': 1,
        'wechat_app_pay': {
          'appid': 'wx2421b1c4370ec43b',
          'mchid': '1900000109',
          'prepay_id': 'wx201410272009395522657a690389285100',
          'nonce_str': '593BEC0C930BF1AFEB40B4A08C8FB242',
          'timestamp': '1554208460',
          'sign': 'signed-value',
        },
      });

      expect(order.wechatAppPayRequest, isNotNull);
      expect(order.wechatAppPayRequest!.toMethodChannelArgs(), {
        'appId': 'wx2421b1c4370ec43b',
        'partnerId': '1900000109',
        'prepayId': 'wx201410272009395522657a690389285100',
        'packageValue': 'Sign=WXPay',
        'nonceStr': '593BEC0C930BF1AFEB40B4A08C8FB242',
        'timeStamp': '1554208460',
        'sign': 'signed-value',
      });
    });

    test('extracts nested encoded weixin payment links', () {
      final order = KqMemberOrder.fromJson({
        'order_no': 'order-1',
        'pay_type': 1,
        'payment': {
          'cashier':
              'https://cashier.example.test/pay?redirect=weixin%3A%2F%2Fwxpay%2Fbizpayurl%3Fpr%3Dabc123',
        },
      });

      expect(
        order.appLaunchUrlsForPayType(1),
        ['weixin://wxpay/bizpayurl?pr=abc123'],
      );
    });

    test('does not treat WeChat web cashier URLs as app links', () {
      final order = KqMemberOrder.fromJson({
        'order_no': 'order-2',
        'pay_type': 1,
        'wechat_app_url':
            'https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb',
        'code_url': 'https://wx.tenpay.com/qr/native/order-2',
      });

      expect(order.appLaunchUrlsForPayType(1), isEmpty);
    });

    test('decodes WeChat QR image payload before QR fallback', () {
      const payload = 'weixin://wxpay/bizpayurl?pr=qr123';

      expect(kqPaymentQrPayloadFromImageBytes(_qrPngBytes(payload)), payload);
    });
  });
}

List<int> _qrPngBytes(String text) {
  final qr = Encoder.encode(text, ErrorCorrectionLevel.l);
  final matrix = qr.matrix!;
  const quietZone = 4;
  const scale = 6;
  final width = (matrix.width + quietZone * 2) * scale;
  final height = (matrix.height + quietZone * 2) * scale;
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));

  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (matrix.get(x, y) != 1) continue;
      for (var dy = 0; dy < scale; dy++) {
        for (var dx = 0; dx < scale; dx++) {
          image.setPixelRgb(
            (x + quietZone) * scale + dx,
            (y + quietZone) * scale + dy,
            0,
            0,
            0,
          );
        }
      }
    }
  }

  return img.encodePng(image);
}
