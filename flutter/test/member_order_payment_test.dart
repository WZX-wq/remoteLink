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

  group('KqMemberOrder Alipay QR payload', () {
    test('builds a scannable gateway URL from Alipay submit HTML', () {
      final order = KqMemberOrder.fromJson({
        'order_no': 'order-alipay-html',
        'pay_type': 2,
        'alipaysubmit_html': '''
          <form method="post" action="https://openapi.alipay.com/gateway.do?charset=utf-8">
            <input type="hidden" name="app_id" value="2021000000000000">
            <input type="hidden" name="method" value="alipay.trade.page.pay">
            <input type="hidden" name="biz_content" value="{&quot;out_trade_no&quot;:&quot;A123&quot;}">
            <input type="submit" value="pay">
          </form>
        ''',
      });

      final payload = kqAlipayPaymentQrPayload(order);
      final uri = Uri.parse(payload!);

      expect(uri.host, 'openapi.alipay.com');
      expect(uri.queryParameters['charset'], 'utf-8');
      expect(uri.queryParameters['app_id'], '2021000000000000');
      expect(uri.queryParameters['method'], 'alipay.trade.page.pay');
      expect(uri.queryParameters['biz_content'], '{"out_trade_no":"A123"}');
    });

    test('extracts encoded Alipay app links before HTML fallback', () {
      final order = KqMemberOrder.fromJson({
        'order_no': 'order-alipay-link',
        'pay_type': 2,
        'alipay_app_url':
            'https://cashier.example.test/?url=alipays%3A%2F%2Fplatformapi%2Fstartapp%3FappId%3D20000067',
      });

      expect(
        kqAlipayPaymentQrPayload(order),
        'alipays://platformapi/startapp?appId=20000067',
      );
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
