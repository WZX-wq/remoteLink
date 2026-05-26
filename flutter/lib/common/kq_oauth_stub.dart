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

  static Future<LoginResponse> login() async {
    throw KqOauthException('Company OAuth login is only available on desktop.');
  }
}
