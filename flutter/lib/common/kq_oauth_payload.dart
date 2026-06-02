class KqOauthLoginPayload {
  final String accessToken;
  final Map<String, dynamic> user;

  const KqOauthLoginPayload({
    required this.accessToken,
    required this.user,
  });
}

Uri buildKqOauthAuthorizeUri({
  required String authorizeUrl,
  required String clientId,
  required String redirectUri,
  required String state,
}) {
  return Uri.parse(authorizeUrl).replace(queryParameters: {
    'response_type': 'code',
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'state': state,
  });
}

String parseKqOauthCallbackCode(Uri uri, String expectedState,
    {String callbackPath = '/oauth/callback'}) {
  final params = uri.queryParameters;
  if (uri.path != callbackPath) {
    throw const FormatException('Unexpected OAuth callback path.');
  }
  if (params['state'] != expectedState) {
    throw const FormatException('Invalid OAuth state.');
  }
  final error = params['error'];
  if (error != null && error.isNotEmpty) {
    throw FormatException(error);
  }
  final code = params['code'];
  if (code == null || code.isEmpty) {
    throw const FormatException('Authorization code is missing.');
  }
  return code;
}

String? parseKqOauthCallbackError(Uri uri, String expectedState,
    {String callbackPath = '/oauth/callback'}) {
  final params = uri.queryParameters;
  if (uri.path != callbackPath || params['state'] != expectedState) {
    return null;
  }
  final error = params['error'];
  if (error == null || error.isEmpty) {
    return null;
  }
  return error;
}

bool isKqOauthCallbackSuccess(Uri uri, String expectedState,
    {String callbackPath = '/oauth/callback'}) {
  try {
    parseKqOauthCallbackCode(uri, expectedState, callbackPath: callbackPath);
    return true;
  } on FormatException {
    return false;
  }
}

Map<String, dynamic> extractKqOauthTokenData(Map<String, dynamic> body) {
  if (!_isSuccessCode(body['code'])) {
    final message = body['message']?.toString();
    throw FormatException(message == null || message.isEmpty
        ? 'OAuth token exchange failed'
        : message);
  }
  final data = body['data'];
  if (data is! Map) {
    throw const FormatException('Token response data is missing.');
  }
  return Map<String, dynamic>.from(data);
}

KqOauthLoginPayload parseKqOauthLoginPayload(Map<String, dynamic> data) {
  final token = data['access_token']?.toString().trim();
  final user = normalizeKqOauthUser(data['user']);
  if (token == null || token.isEmpty || user == null) {
    throw const FormatException('Token response is missing token or user.');
  }
  return KqOauthLoginPayload(accessToken: token, user: user);
}

bool _isSuccessCode(dynamic value) {
  if (value is int) return value == 200;
  if (value is String) return int.tryParse(value) == 200;
  return false;
}

Map<String, dynamic>? normalizeKqOauthUser(dynamic value) {
  if (value is! Map) return null;
  final username = (value['username'] ?? value['name'] ?? value['id'] ?? '')
      .toString()
      .trim();
  if (username.isEmpty) return null;
  final displayName = (value['nickname'] ??
          value['display_name'] ??
          value['displayName'] ??
          username)
      .toString();
  return {
    'id': value['id']?.toString() ?? '',
    'name': username,
    'display_name': displayName,
    'avatar': value['avatar']?.toString() ?? '',
    'email': value['email']?.toString() ?? '',
    'status': 1,
    'is_admin': false,
  };
}
