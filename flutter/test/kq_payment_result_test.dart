import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/kq_payment_result.dart';

void main() {
  test('uses Alipay memo when SDK provides one', () {
    final detail = kqAlipayPaymentFailureDetail({
      'memo': '用户取消',
      'result': '{"ignored":true}',
    });

    expect(detail, '用户取消');
  });

  test('extracts Alipay API sub message from SDK result JSON', () {
    final detail = kqAlipayPaymentFailureDetail({
      'resultStatus': '4000',
      'memo': '',
      'result':
          '{"alipay_trade_app_pay_response":{"code":"40006","msg":"Insufficient Permissions","sub_code":"isv.insufficient-isv-permissions","sub_msg":"ISV权限不足"}}',
    });

    expect(detail, 'ISV权限不足 (isv.insufficient-isv-permissions)');
  });

  test('returns empty detail when Alipay result has no diagnostic fields', () {
    expect(kqAlipayPaymentFailureDetail({'result': '{bad json'}), '');
  });
}
