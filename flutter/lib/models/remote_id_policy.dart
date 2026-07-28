String kqNormalizeRemoteIdentifier(String input) {
  return input.replaceAll(RegExp(r'\s+'), '').trim();
}

String _withoutRelaySuffix(String input) {
  if (input.endsWith('/r') || input.endsWith(r'\r')) {
    return input.substring(0, input.length - 2);
  }
  return input;
}

bool _isValidLookupId(String input) {
  if (RegExp(r'^\d{6,16}$').hasMatch(input)) {
    return true;
  }
  return RegExp(r'^[A-Za-z][A-Za-z0-9_-]{5,15}$').hasMatch(input);
}

bool isValidKqRemoteIdentifierFormat(String input) {
  final normalized = _withoutRelaySuffix(kqNormalizeRemoteIdentifier(input));
  if (normalized.isEmpty || normalized.length > 320) {
    return false;
  }

  final at = normalized.indexOf('@');
  if (at >= 0) {
    if (at == 0 ||
        at != normalized.lastIndexOf('@') ||
        at == normalized.length - 1) {
      return false;
    }
    return _isValidLookupId(normalized.substring(0, at)) &&
        RegExp(r'^[A-Za-z0-9._:\-\[\]?=&+/]+$')
            .hasMatch(normalized.substring(at + 1));
  }

  if (_isValidLookupId(normalized)) {
    return true;
  }

  // Direct IP/domain endpoints are supported by the native connection layer.
  return (normalized.contains('.') || normalized.contains(':')) &&
      RegExp(r'^[A-Za-z0-9._:\-\[\]]+$').hasMatch(normalized);
}

bool kqRemoteIdentifierSupportsOnlineLookup(String input) {
  final normalized = _withoutRelaySuffix(kqNormalizeRemoteIdentifier(input));
  return _isValidLookupId(normalized);
}
