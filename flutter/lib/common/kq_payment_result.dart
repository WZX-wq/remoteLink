import 'dart:convert';

String kqAlipayPaymentFailureDetail(Object? result) {
  if (result is! Map) return '';
  final memo = _kqNonEmptyString(result['memo']);
  if (memo.isNotEmpty) return memo;

  final rawResult = _kqNonEmptyString(result['result']);
  if (rawResult.isEmpty) return '';

  Object? decoded;
  try {
    decoded = jsonDecode(rawResult);
  } catch (_) {
    return '';
  }
  if (decoded is! Map) return '';

  final response = decoded['alipay_trade_app_pay_response'];
  if (response is! Map) return '';

  final subMsg = _kqNonEmptyString(response['sub_msg']);
  final subCode = _kqNonEmptyString(response['sub_code']);
  if (subMsg.isNotEmpty) {
    return subCode.isEmpty ? subMsg : '$subMsg ($subCode)';
  }

  final msg = _kqNonEmptyString(response['msg']);
  final code = _kqNonEmptyString(response['code']);
  if (msg.isNotEmpty) {
    return code.isEmpty ? msg : '$msg ($code)';
  }
  return code;
}

String _kqNonEmptyString(Object? value) => (value ?? '').toString().trim();
