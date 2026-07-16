import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

typedef KqAccountDeletionPost = Future<http.Response> Function(
  Uri uri,
  Map<String, String> headers,
  String body,
);

enum KqAccountDeletionFailure {
  notLoggedIn,
  confirmationRequired,
  serviceUnavailable,
  requestFailed,
}

class KqAccountDeletionException implements Exception {
  const KqAccountDeletionException(this.failure, this.message);

  final KqAccountDeletionFailure failure;
  final String message;

  @override
  String toString() => message;
}

class KqAccountDeletionResult {
  const KqAccountDeletionResult({
    required this.pending,
    required this.message,
  });

  final bool pending;
  final String message;
}

/// Calls the account service only after the user has explicitly confirmed the
/// irreversible action. The endpoint is intentionally a build configuration:
/// the mobile client must never pretend to delete an account locally.
class KqAccountDeletionApi {
  KqAccountDeletionApi({
    Uri? endpoint,
    KqAccountDeletionPost? post,
  })  : _endpoint = endpoint,
        _post = post;

  static const endpointUrl = String.fromEnvironment('KQ_ACCOUNT_DELETE_URL');

  factory KqAccountDeletionApi.fromEnvironment() {
    final parsed = Uri.tryParse(endpointUrl.trim());
    return KqAccountDeletionApi(
      endpoint: parsed != null && parsed.scheme == 'https' ? parsed : null,
    );
  }

  final Uri? _endpoint;
  final KqAccountDeletionPost? _post;

  bool get isConfigured => _endpoint != null;

  Future<KqAccountDeletionResult> requestDeletion({
    required String token,
    required String confirmation,
  }) async {
    if (token.trim().isEmpty) {
      throw const KqAccountDeletionException(
        KqAccountDeletionFailure.notLoggedIn,
        'Please log in first.',
      );
    }
    if (confirmation.trim() != 'DELETE') {
      throw const KqAccountDeletionException(
        KqAccountDeletionFailure.confirmationRequired,
        'Enter DELETE to confirm account deletion.',
      );
    }
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw const KqAccountDeletionException(
        KqAccountDeletionFailure.serviceUnavailable,
        'Account deletion is not configured on the server.',
      );
    }

    final payload = jsonEncode(<String, String>{'confirmation': 'DELETE'});
    final headers = <String, String>{
      'Authorization': 'Bearer ${token.trim()}',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    late http.Response response;
    try {
      response = await (_post?.call(endpoint, headers, payload) ??
              http.post(endpoint, headers: headers, body: payload))
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const KqAccountDeletionException(
        KqAccountDeletionFailure.requestFailed,
        'The deletion request timed out. Please try again later.',
      );
    } catch (_) {
      throw const KqAccountDeletionException(
        KqAccountDeletionFailure.requestFailed,
        'Unable to submit the deletion request. Please try again later.',
      );
    }

    final body = _decodeBody(response.body);
    final message = _messageFromBody(body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KqAccountDeletionException(
        KqAccountDeletionFailure.requestFailed,
        message ?? 'The deletion request could not be completed.',
      );
    }
    if (body?['success'] == false) {
      throw KqAccountDeletionException(
        KqAccountDeletionFailure.requestFailed,
        message ?? 'The deletion request could not be completed.',
      );
    }
    final code = int.tryParse((body?['code'] ?? '').toString());
    if (code != null && code != 0 && code != 200 && code != 202) {
      throw KqAccountDeletionException(
        KqAccountDeletionFailure.requestFailed,
        message ?? 'The deletion request could not be completed.',
      );
    }
    final status = (body?['status'] ?? '').toString().trim().toLowerCase();
    return KqAccountDeletionResult(
      pending: status == 'pending' ||
          status == 'processing' ||
          response.statusCode == 202,
      message: message ?? 'Deletion request submitted.',
    );
  }

  Map<String, dynamic>? _decodeBody(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _messageFromBody(Map<String, dynamic>? body) {
    if (body == null) return null;
    for (final key in ['message', 'msg', 'error']) {
      final value = body[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
