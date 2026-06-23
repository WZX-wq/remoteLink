import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const kKqOauthProvider = 'kunqiong';
const kKqOauthProviderKey = 'external_auth_provider';

class KqOauthException implements Exception {
  final String message;

  KqOauthException(this.message);

  @override
  String toString() => message;
}

class KqOauth {
  static bool get isActive =>
      bind.mainGetLocalOption(key: kKqOauthProviderKey) == kKqOauthProvider;

  static void cancel() {}

  static Future<void> logout() async {}

  static Future<bool> checkLogin() async => false;

  static Future<LoginResponse> login() async {
    throw KqOauthException('Company OAuth login is only available on desktop.');
  }

  static Future<LoginResponse> loginWithPassword({
    required String username,
    required String password,
  }) async {
    throw KqOauthException('Company account login is only available in app.');
  }

  static Future<void> sendSmsCode({
    required String phone,
    String purpose = 'login',
  }) async {
    throw KqOauthException('Company SMS login is only available in app.');
  }

  static Future<LoginResponse> loginWithSms({
    required String phone,
    required String code,
  }) async {
    throw KqOauthException('Company SMS login is only available in app.');
  }

  static Future<LoginResponse> registerWithPhone({
    required String username,
    required String phone,
    required String code,
    required String password,
  }) async {
    throw KqOauthException(
        'Company account registration is only available in app.');
  }

  static Future<LoginResponse> resetPasswordWithPhone({
    required String phone,
    required String code,
    required String password,
  }) async {
    throw KqOauthException('Company password reset is only available in app.');
  }
}
