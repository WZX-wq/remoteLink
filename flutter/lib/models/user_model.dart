import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/common/kq_oauth.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../utils/http_service.dart' as http;
import 'model.dart';
import 'platform_model.dart';

bool refreshingUser = false;

class UserModel {
  static const memberActiveKey = 'kq_member_active';
  static const memberUserIdKey = 'kq_member_user_id';
  static const memberExpireAtKey = 'kq_member_expire_at';
  static const memberSubsiteKey = 'kq_member_subsite_name';
  static const memberLastErrorKey = 'kq_member_last_error';
  static const memberSubsiteName = 'https://remote.kunqiongai.com/';
  static const memberApiBaseUrl = 'https://api-web.kunqiongai.com';
  static const kqTestUnlimitedMemberUserId = '13';
  static const remoteQualityKey = 'custom_image_quality';
  static const remoteFpsKey = 'custom-fps';
  static const remoteCodecKey = 'codec-preference';
  static const remoteResolutionTierKey = 'kq_remote_resolution_tier';
  static const remoteFpsTierKey = 'kq_remote_fps_tier';
  static const remoteResolution720p = '720p';
  static const remoteResolution1080p = '1080p';
  static const freeMaxFps = 30;
  static const memberDefaultFps = 60;
  static const memberMaxFps = 60;
  static const freeRemoteQuality = '50';
  static const memberRemoteQuality = '50';

  final RxString userName = ''.obs;
  final RxString displayName = ''.obs;
  final RxString avatar = ''.obs;
  final RxBool isAdmin = false.obs;
  final RxString networkError = ''.obs;
  final RxBool isMember = false.obs;
  final RxBool isRefreshingMembership = false.obs;
  final RxString memberExpireAt = ''.obs;
  final RxString memberSubsite = memberSubsiteName.obs;
  final RxString memberLastError = ''.obs;
  final RxList<KqMemberPackage> memberPackages = <KqMemberPackage>[].obs;
  int _membershipRefreshSerial = 0;
  bool get isLogin => userName.isNotEmpty;
  bool get canUseMemberRemoteQuality => isMember.value;
  String get remoteResolutionSelection {
    final saved = bind.mainGetLocalOption(key: remoteResolutionTierKey).trim();
    if (saved == remoteResolution1080p && canUseMemberRemoteQuality) {
      return remoteResolution1080p;
    }
    return remoteResolution720p;
  }

  int get remoteFpsSelection {
    final saved = int.tryParse(bind.mainGetLocalOption(key: remoteFpsTierKey));
    final fallback =
        int.tryParse(bind.mainGetUserDefaultOption(key: remoteFpsKey));
    final fps = saved ??
        fallback ??
        (canUseMemberRemoteQuality ? memberDefaultFps : freeMaxFps);
    if (canUseMemberRemoteQuality) {
      if (fps >= memberMaxFps) return memberMaxFps;
      if (fps >= memberDefaultFps) return memberDefaultFps;
      return freeMaxFps;
    }
    return freeMaxFps;
  }

  int get remoteMaxLongEdge =>
      remoteResolutionSelection == remoteResolution1080p ? 1920 : 1280;
  int get remoteMaxShortEdge =>
      remoteResolutionSelection == remoteResolution1080p ? 1080 : 720;
  int get remoteEntitlementMaxFps =>
      canUseMemberRemoteQuality ? memberMaxFps : freeMaxFps;
  int get remoteMaxFps => remoteEntitlementMaxFps;
  String get remoteResolutionLabel => remoteResolutionSelection;
  String get remoteQualityLabel =>
      '$remoteResolutionLabel / $remoteFpsSelection FPS';
  String get membershipName =>
      translate(isMember.value ? 'Member plan' : 'Basic plan');
  String get remoteEntitlementHint => isMember.value
      ? translate('Members can switch between 720p / 1080p and 30 / 60 FPS.')
      : translate(
          'Basic plan supports up to 720p / 30 FPS. Members can use 1080p / 60 FPS.');
  String get displayNameOrUserName =>
      displayName.value.trim().isEmpty ? userName.value : displayName.value;
  String get accountLabelWithHandle {
    final username = userName.value.trim();
    if (username.isEmpty) {
      return '';
    }
    final preferred = displayName.value.trim();
    if (preferred.isEmpty || preferred == username) {
      return username;
    }
    return '$preferred (@$username)';
  }

  WeakReference<FFI> parent;

  UserModel(this.parent) {
    _loadLocalMembership();
    userName.listen((p0) {
      // When user name becomes empty, show login button
      // When user name becomes non-empty:
      //  For _updateLocalUserInfo, network error will be set later
      //  For login success, should clear network error
      networkError.value = '';
    });
  }

  void refreshCurrentUser() async {
    if (bind.isDisableAccount()) return;
    networkError.value = '';
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token == '') {
      await _setMemberStatus(false, expireAt: '', error: '');
      await updateOtherModels();
      return;
    }
    _updateLocalUserInfo();
    if (KqOauth.isActive) {
      await refreshMembership();
      await updateOtherModels();
      return;
    }
    final url = await bind.mainGetApiServer();
    final body = {
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid()
    };
    if (refreshingUser) return;
    try {
      refreshingUser = true;
      final http.Response response;
      try {
        response = await http.post(Uri.parse('$url/api/currentUser'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            },
            body: json.encode(body));
      } catch (e) {
        networkError.value = e.toString();
        rethrow;
      }
      refreshingUser = false;
      final status = response.statusCode;
      if (status == 401 || status == 400) {
        reset(resetOther: status == 401);
        return;
      }
      final data = json.decode(decode_http_response(response));
      final error = data['error'];
      if (error != null) {
        throw error;
      }

      final user = UserPayload.fromJson(data);
      await _parseAndUpdateUser(user);
    } catch (e) {
      debugPrint('Failed to refreshCurrentUser: $e');
    } finally {
      refreshingUser = false;
      await refreshMembership();
      await updateOtherModels();
    }
  }

  static Map<String, dynamic>? getLocalUserInfo() {
    final userInfo = bind.mainGetLocalOption(key: 'user_info');
    if (userInfo == '') {
      return null;
    }
    try {
      return json.decode(userInfo);
    } catch (e) {
      debugPrint('Failed to get local user info "$userInfo": $e');
    }
    return null;
  }

  static String _localUserPrimaryId() {
    final userInfo = getLocalUserInfo();
    if (userInfo == null) {
      return '';
    }
    final direct = (userInfo['id'] ?? '').toString().trim();
    if (direct.isNotEmpty) {
      return direct;
    }
    final raw = userInfo['external_auth_raw'];
    if (raw is Map) {
      final user = raw['user'];
      if (user is Map) {
        return (user['id'] ?? '').toString().trim();
      }
    }
    return '';
  }

  static bool get isKqTestUnlimitedMember =>
      _localUserPrimaryId() == kqTestUnlimitedMemberUserId;

  static bool get isLocalMemberActiveForCurrentUser {
    final userId = _localUserPrimaryId();
    if (userId == kqTestUnlimitedMemberUserId) {
      return true;
    }
    if (userId.isEmpty) {
      return false;
    }
    return bind.mainGetLocalOption(key: memberActiveKey) == 'Y' &&
        bind.mainGetLocalOption(key: memberUserIdKey).trim() == userId;
  }

  _updateLocalUserInfo() {
    final userInfo = getLocalUserInfo();
    if (userInfo != null) {
      userName.value = (userInfo['name'] ?? '').toString();
      displayName.value = (userInfo['display_name'] ?? '').toString();
      avatar.value = (userInfo['avatar'] ?? '').toString();
    }
    _loadLocalMembership();
  }

  Future<void> reset({bool resetOther = false}) async {
    _membershipRefreshSerial++;
    isRefreshingMembership.value = false;
    await bind.mainSetLocalOption(key: 'access_token', value: '');
    await bind.mainSetLocalOption(key: 'user_info', value: '');
    await bind.mainSetLocalOption(key: kKqOauthProviderKey, value: '');
    await _setMemberStatus(false, expireAt: '', error: '');
    if (resetOther) {
      await gFFI.abModel.reset();
      await gFFI.groupModel.reset();
    }
    userName.value = '';
    displayName.value = '';
    avatar.value = '';
  }

  Future<void> _parseAndUpdateUser(UserPayload user) async {
    userName.value = user.name;
    displayName.value = user.displayName;
    avatar.value = user.avatar;
    isAdmin.value = user.isAdmin;
    await bind.mainSetLocalOption(key: kKqOauthProviderKey, value: '');
    await bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(user));
    if (isWeb) {
      // ugly here, tmp solution
      await bind.mainSetLocalOption(
          key: 'verifier', value: user.verifier ?? '');
    }
  }

  void _loadLocalMembership() {
    isMember.value = isLocalMemberActiveForCurrentUser;
    memberExpireAt.value = bind.mainGetLocalOption(key: memberExpireAtKey);
    final subsite = bind.mainGetLocalOption(key: memberSubsiteKey);
    memberSubsite.value = subsite.isEmpty ? memberSubsiteName : subsite;
    memberLastError.value = bind.mainGetLocalOption(key: memberLastErrorKey);
    unawaited(_syncRemoteQualityDefaults(isMember.value));
  }

  Future<void> _syncRemoteQualityDefaults(
    bool active, {
    bool preferMemberDefaults = false,
  }) async {
    final savedResolution =
        bind.mainGetLocalOption(key: remoteResolutionTierKey).trim();
    final savedFps =
        int.tryParse(bind.mainGetLocalOption(key: remoteFpsTierKey).trim());
    final fallbackFps =
        int.tryParse(bind.mainGetUserDefaultOption(key: remoteFpsKey));
    final useMemberDefaults =
        active && (preferMemberDefaults || savedResolution.isEmpty);
    await setRemotePerformanceProfile(
      resolutionTier: useMemberDefaults
          ? remoteResolution1080p
          : (savedResolution.isEmpty ? remoteResolution720p : savedResolution),
      fps: useMemberDefaults
          ? memberDefaultFps
          : (savedFps ?? fallbackFps ?? freeMaxFps),
    );
  }

  Future<void> setRemotePerformanceProfile({
    required String resolutionTier,
    required int fps,
  }) async {
    final normalizedResolution =
        resolutionTier == remoteResolution1080p && canUseMemberRemoteQuality
            ? remoteResolution1080p
            : remoteResolution720p;
    final normalizedFps = canUseMemberRemoteQuality
        ? (fps >= memberMaxFps
            ? memberMaxFps
            : (fps >= memberDefaultFps ? memberDefaultFps : freeMaxFps))
        : freeMaxFps;
    final quality = normalizedResolution == remoteResolution1080p
        ? memberRemoteQuality
        : freeRemoteQuality;
    await bind.mainSetLocalOption(
        key: remoteResolutionTierKey, value: normalizedResolution);
    await bind.mainSetLocalOption(
        key: remoteFpsTierKey, value: normalizedFps.toString());
    await bind.mainSetUserDefaultOption(
        key: kOptionImageQuality, value: kRemoteImageQualityCustom);
    await bind.mainSetUserDefaultOption(key: remoteQualityKey, value: quality);
    await bind.mainSetUserDefaultOption(
        key: remoteFpsKey, value: normalizedFps.toString());
    await bind.mainSetUserDefaultOption(key: remoteCodecKey, value: 'auto');
    await bind.mainSetUserDefaultOption(key: kOptionEnableHwcodec, value: 'Y');
  }

  Future<void> _setMemberStatus(
    bool active, {
    required String expireAt,
    required String error,
    String? subsite,
    bool Function()? shouldApply,
  }) async {
    bool canApply() => shouldApply == null || shouldApply();
    if (!canApply()) return;
    final wasMember = isLocalMemberActiveForCurrentUser;
    final userId = _localUserPrimaryId();
    if (!canApply()) return;
    isMember.value = active;
    memberExpireAt.value = expireAt;
    memberSubsite.value =
        subsite == null || subsite.isEmpty ? memberSubsiteName : subsite;
    memberLastError.value = error;
    if (!canApply()) return;
    await bind.mainSetLocalOption(
        key: memberActiveKey, value: active ? 'Y' : 'N');
    if (!canApply()) return;
    await bind.mainSetLocalOption(
        key: memberUserIdKey, value: active && userId.isNotEmpty ? userId : '');
    if (!canApply()) return;
    await bind.mainSetLocalOption(key: memberExpireAtKey, value: expireAt);
    if (!canApply()) return;
    await bind.mainSetLocalOption(
        key: memberSubsiteKey, value: memberSubsite.value);
    if (!canApply()) return;
    await bind.mainSetLocalOption(key: memberLastErrorKey, value: error);
    if (!canApply()) return;
    await _syncRemoteQualityDefaults(active,
        preferMemberDefaults: active && !wasMember);
  }

  bool _memberBool(dynamic value) {
    if (value == true || value == 1) return true;
    final s = value?.toString().trim().toLowerCase() ?? '';
    return ['1', 'true', 'yes', 'y', 'on'].contains(s);
  }

  bool isRemoteResolutionAllowed(int width, int height) {
    if (width <= 0 || height <= 0) return true;
    final longEdge = math.max(width, height);
    final shortEdge = math.min(width, height);
    return longEdge <= remoteMaxLongEdge && shortEdge <= remoteMaxShortEdge;
  }

  ({int width, int height}) clampRemoteResolution(int width, int height) {
    if (isRemoteResolutionAllowed(width, height)) {
      return (width: width, height: height);
    }
    final longEdge = math.max(width, height).toDouble();
    final shortEdge = math.min(width, height).toDouble();
    if (longEdge <= 0 || shortEdge <= 0) {
      return (width: width, height: height);
    }
    final scale = math.min(
      remoteMaxLongEdge / longEdge,
      remoteMaxShortEdge / shortEdge,
    );
    return (
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  }

  int clampRemoteFps(num fps) {
    final value = fps.round();
    return math.max(5, math.min(remoteEntitlementMaxFps, value));
  }

  Iterable<String> _memberTokenCandidates() sync* {
    final values = <String>[];
    void add(dynamic value) {
      values.add((value ?? '').toString());
    }

    add(bind.mainGetLocalOption(key: 'access_token'));
    add(bind.mainGetLocalOption(key: 'kq_api_web_token'));
    add(bind.mainGetLocalOption(key: 'api_web_token'));
    add(bind.mainGetLocalOption(key: 'kq_token'));
    add(bind.mainGetLocalOption(key: 'user_token'));
    final userInfo = getLocalUserInfo();
    if (userInfo != null) {
      for (final key in [
        'api_web_token',
        'apiWebToken',
        'kq_token',
        'token',
        'user_token'
      ]) {
        add(userInfo[key]);
      }
      final raw = userInfo['external_auth_raw'];
      if (raw is Map) {
        for (final key in [
          'api_web_token',
          'apiWebToken',
          'kq_token',
          'token',
          'user_token',
          'access_token'
        ]) {
          add(raw[key]);
        }
      }
    }
    final orderedTokens = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = value
          .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
          .trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (seen.add(normalized)) {
        orderedTokens.add(normalized);
      }
    }
    yield* orderedTokens;
  }

  Future<void> refreshMembership({bool showError = false}) async {
    final refreshSerial = ++_membershipRefreshSerial;
    bool isCurrentRefresh() => refreshSerial == _membershipRefreshSerial;
    Future<void> setCurrentMemberStatus(
      bool active, {
      required String expireAt,
      required String error,
      String? subsite,
    }) async {
      if (!isCurrentRefresh()) return;
      await _setMemberStatus(active,
          expireAt: expireAt,
          error: error,
          subsite: subsite,
          shouldApply: isCurrentRefresh);
    }

    isRefreshingMembership.value = true;
    try {
      if (!isLogin) {
        await setCurrentMemberStatus(false, expireAt: '', error: '');
        return;
      }
      if (isKqTestUnlimitedMember) {
        await setCurrentMemberStatus(true,
            expireAt: 'unlimited', error: '', subsite: memberSubsiteName);
        if (isCurrentRefresh()) {
          memberPackages.clear();
        }
        return;
      }

      final candidates = _memberTokenCandidates().toList();
      if (candidates.isEmpty) {
        await setCurrentMemberStatus(false,
            expireAt: '',
            error: translate('Missing membership login credential'));
        return;
      }

      Object? lastError;
      for (final token in candidates) {
        try {
          final projectMemberInfo = await _getProjectMemberInfo(token);
          if (projectMemberInfo != null) {
            await _applyMemberInfo(
              projectMemberInfo,
              shouldApply: isCurrentRefresh,
            );
            return;
          }

          final response = await _postMemberApi(
            'get_web_member_package_info',
            token: token,
            body: {'subsite_name': memberSubsiteName},
          );

          final body = _decodeMemberBody(response);
          if (body is! Map) {
            throw translate('Membership API returned an invalid format');
          }
          final code = int.tryParse((body['code'] ?? '').toString());
          if (response.statusCode == 401 || code == 401) {
            lastError = body['msg'] ??
                body['message'] ??
                translate('Membership login credential expired');
            continue;
          }
          if (response.statusCode < 200 ||
              response.statusCode >= 300 ||
              code != 1) {
            throw body['msg'] ??
                body['message'] ??
                translate('Membership API request failed');
          }
          final data = body['data'];
          if (data is! Map) {
            throw translate('Membership API data is empty');
          }
          await _applyMemberInfo(data, shouldApply: isCurrentRefresh);
          return;
        } catch (e) {
          lastError = e;
        }
      }

      final message = lastError?.toString() ??
          translate('Failed to refresh membership status');
      await setCurrentMemberStatus(false, expireAt: '', error: message);
      if (showError && isCurrentRefresh()) {
        showToast(message);
      }
    } finally {
      if (isCurrentRefresh()) {
        isRefreshingMembership.value = false;
      }
    }
  }

  Future<http.Response> _postMemberApi(
    String action, {
    required String token,
    required Map<String, String> body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    final form = <String, String>{
      ...body,
      'token': token,
    };
    return http
        .post(
          Uri.parse('$memberApiBaseUrl/user/$action'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
            'Accept': 'application/json',
            'token': token,
            'Authorization': 'Bearer $token',
          },
          body: Uri(queryParameters: form).query,
        )
        .timeout(timeout);
  }

  dynamic _decodeMemberBody(http.Response response) {
    return jsonDecode(decode_http_response(response));
  }

  Future<void> _applyMemberInfo(
    Map data, {
    bool Function()? shouldApply,
  }) async {
    if (shouldApply != null && !shouldApply()) return;
    final packages = data['packages'];
    if (packages is List) {
      final nextPackages = packages
          .whereType<Map>()
          .map((item) => KqMemberPackage.fromJson(item))
          .where((item) => item.id > 0)
          .toList();
      if (shouldApply != null && !shouldApply()) return;
      memberPackages.assignAll(nextPackages);
    }
    if (shouldApply != null && !shouldApply()) return;
    await _setMemberStatus(
      _memberBool(data['web_member_active']),
      expireAt: (data['web_member_expire_at'] ?? '').toString(),
      subsite: (data['subsite_name'] ?? memberSubsiteName).toString(),
      error: '',
      shouldApply: shouldApply,
    );
  }

  String get _projectApiBaseUrl {
    final local = bind.mainGetLocalOption(key: 'kq_project_api_server').trim();
    final buildin =
        bind.mainGetBuildinOption(key: 'kq-project-api-server').trim();
    final value = local.isNotEmpty ? local : buildin;
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  Map<String, String> _projectApiHeaders(String token) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'token': token,
        'Authorization': 'Bearer $token',
      };

  Future<Map?> _getProjectMemberInfo(String token) async {
    final api = _projectApiBaseUrl;
    if (api.isEmpty) return null;
    try {
      final response = await http
          .get(
            Uri.parse('$api/member/packages'),
            headers: _projectApiHeaders(token),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = jsonDecode(decode_http_response(response));
      if (body is Map && body['ok'] == true && body['member'] is Map) {
        return body['member'] as Map;
      }
    } catch (e) {
      debugPrint('KQ project API member refresh fallback: $e');
    }
    return null;
  }

  Future<KqMemberOrder?> _createProjectMemberOrder({
    required String token,
    required int packageId,
    required int payType,
  }) async {
    final api = _projectApiBaseUrl;
    if (api.isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$api/member/orders'),
            headers: _projectApiHeaders(token),
            body: jsonEncode({
              'package_id': packageId,
              'pay_type': payType,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = jsonDecode(decode_http_response(response));
      if (body is Map && body['ok'] == true && body['order'] is Map) {
        return KqMemberOrder.fromJson(body['order'] as Map);
      }
    } catch (e) {
      debugPrint('KQ project API create order fallback: $e');
    }
    return null;
  }

  Future<KqMemberOrderStatus?> _checkProjectMemberOrder({
    required String token,
    required String orderNo,
  }) async {
    final api = _projectApiBaseUrl;
    if (api.isEmpty) return null;
    try {
      final response = await http
          .get(
            Uri.parse('$api/member/orders/${Uri.encodeComponent(orderNo)}'),
            headers: _projectApiHeaders(token),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = jsonDecode(decode_http_response(response));
      if (body is Map && body['ok'] == true && body['status'] is Map) {
        return KqMemberOrderStatus.fromJson(body['status'] as Map);
      }
    } catch (e) {
      debugPrint('KQ project API check order fallback: $e');
    }
    return null;
  }

  Future<KqMemberOrder> createMemberOrder({
    required int packageId,
    required int payType,
  }) async {
    if (!isLogin) {
      throw translate('Please log in first');
    }
    Object? lastError;
    for (final token in _memberTokenCandidates()) {
      try {
        final projectOrder = await _createProjectMemberOrder(
          token: token,
          packageId: packageId,
          payType: payType,
        );
        if (projectOrder != null) {
          return projectOrder;
        }

        final response = await _postMemberApi(
          'create_web_member_order',
          token: token,
          body: {
            'package_id': packageId.toString(),
            'pay_type': payType.toString(),
            'subsite_name': memberSubsiteName,
          },
        );
        final body = _decodeMemberBody(response);
        if (body is! Map) {
          throw translate('Membership order API returned an invalid format');
        }
        final code = int.tryParse((body['code'] ?? '').toString());
        if (response.statusCode == 401 || code == 401) {
          lastError = body['msg'] ??
              body['message'] ??
              translate('Please log in first');
          continue;
        }
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            code != 1) {
          throw body['msg'] ??
              body['message'] ??
              translate('Failed to create membership order');
        }
        final data = body['data'];
        if (data is! Map) {
          throw translate('Membership order data is empty');
        }
        return KqMemberOrder.fromJson(data);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? translate('Failed to create membership order');
  }

  Future<KqMemberOrderStatus> checkMemberOrder(String orderNo) async {
    if (orderNo.trim().isEmpty) {
      throw translate('Order number is empty');
    }
    Object? lastError;
    for (final token in _memberTokenCandidates()) {
      try {
        final projectStatus = await _checkProjectMemberOrder(
          token: token,
          orderNo: orderNo,
        );
        if (projectStatus != null) {
          return projectStatus;
        }

        final response = await _postMemberApi(
          'check_web_member_order_paystatus',
          token: token,
          body: {'order_no': orderNo},
          timeout: const Duration(seconds: 8),
        );
        final body = _decodeMemberBody(response);
        if (body is! Map) {
          throw translate('Order status API returned an invalid format');
        }
        final code = int.tryParse((body['code'] ?? '').toString());
        if (response.statusCode == 401 || code == 401) {
          lastError = body['msg'] ??
              body['message'] ??
              translate('Please log in first');
          continue;
        }
        if (response.statusCode < 200 ||
            response.statusCode >= 300 ||
            code != 1) {
          throw body['msg'] ??
              body['message'] ??
              translate('Failed to check order status');
        }
        final data = body['data'];
        if (data is! Map) {
          throw translate('Order status data is empty');
        }
        return KqMemberOrderStatus.fromJson(data);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? translate('Failed to check order status');
  }

  // update ab and group status
  static Future<void> updateOtherModels() async {
    await Future.wait([
      gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: false),
      gFFI.groupModel.pull()
    ]);
  }

  Future<void> logOut({String? apiServer}) async {
    if (KqOauth.isActive) {
      await reset(resetOther: true);
      return;
    }
    final tag = gFFI.dialogManager.showLoading(translate('Waiting'));
    try {
      final url = apiServer ?? await bind.mainGetApiServer();
      final authHeaders = getHttpHeaders();
      authHeaders['Content-Type'] = "application/json";
      await http
          .post(Uri.parse('$url/api/logout'),
              body: jsonEncode({
                'id': await bind.mainGetMyId(),
                'uuid': await bind.mainGetUuid(),
              }),
              headers: authHeaders)
          .timeout(Duration(seconds: 2));
    } catch (e) {
      debugPrint("request /api/logout failed: err=$e");
    } finally {
      await reset(resetOther: true);
      gFFI.dialogManager.dismissByTag(tag);
    }
  }

  /// throw [RequestException]
  Future<LoginResponse> login(LoginRequest loginRequest) async {
    final url = await bind.mainGetApiServer();
    final resp = await http.post(Uri.parse('$url/api/login'),
        body: jsonEncode(loginRequest.toJson()));

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(decode_http_response(resp));
    } catch (e) {
      debugPrint("login: jsonDecode resp body failed: ${e.toString()}");
      if (resp.statusCode != 200) {
        BotToast.showText(
            contentColor: Colors.red, text: 'HTTP ${resp.statusCode}');
      }
      rethrow;
    }
    if (resp.statusCode != 200) {
      throw RequestException(resp.statusCode, body['error'] ?? '');
    }
    if (body['error'] != null) {
      throw RequestException(0, body['error']);
    }

    return getLoginResponseFromAuthBody(body);
  }

  LoginResponse getLoginResponseFromAuthBody(Map<String, dynamic> body) {
    final LoginResponse loginResponse;
    try {
      loginResponse = LoginResponse.fromJson(body);
    } catch (e) {
      debugPrint("login: jsonDecode LoginResponse failed: ${e.toString()}");
      rethrow;
    }

    return loginResponse;
  }

  Future<void> applyLoginResponse(LoginResponse loginResponse,
      {bool storeLocalUserInfo = true}) async {
    if (loginResponse.type == HttpType.kAuthResTypeToken &&
        loginResponse.user != null) {
      if (storeLocalUserInfo) {
        await _parseAndUpdateUser(loginResponse.user!);
      } else {
        userName.value = loginResponse.user!.name;
        displayName.value = loginResponse.user!.displayName;
        avatar.value = loginResponse.user!.avatar;
        isAdmin.value = loginResponse.user!.isAdmin;
      }
      isMember.value = isLocalMemberActiveForCurrentUser;
      memberExpireAt.value = bind.mainGetLocalOption(key: memberExpireAtKey);
      memberLastError.value = bind.mainGetLocalOption(key: memberLastErrorKey);
      return refreshMembership();
    }
    return Future.value();
  }

  static Future<List<dynamic>> queryOidcLoginOptions() async {
    try {
      final url = await bind.mainGetApiServer();
      if (url.trim().isEmpty) return [];
      final resp = await http.get(Uri.parse('$url/api/login-options'));
      final List<String> ops = [];
      for (final item in jsonDecode(resp.body)) {
        ops.add(item as String);
      }
      for (final item in ops) {
        if (item.startsWith('common-oidc/')) {
          return jsonDecode(item.substring('common-oidc/'.length));
        }
      }
      return ops
          .where((item) => item.startsWith('oidc/'))
          .map((item) => {'name': item.substring('oidc/'.length)})
          .toList();
    } catch (e) {
      debugPrint(
          "queryOidcLoginOptions: jsonDecode resp body failed: ${e.toString()}");
      return [];
    }
  }
}

class KqMemberPackage {
  final int id;
  final String name;
  final String description;
  final int days;
  final double priceYuan;
  final String benefitText;
  final String coverUrl;

  const KqMemberPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.days,
    required this.priceYuan,
    required this.benefitText,
    required this.coverUrl,
  });

  factory KqMemberPackage.fromJson(Map json) {
    return KqMemberPackage(
      id: int.tryParse((json['id'] ?? '').toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      days: int.tryParse((json['days'] ?? '').toString()) ?? 0,
      priceYuan: double.tryParse((json['price_yuan'] ?? '').toString()) ?? 0,
      benefitText: (json['benefit_text'] ?? '').toString(),
      coverUrl: (json['cover_url'] ?? '').toString(),
    );
  }

  String get displayName => _kqLocalizedMembershipPackageName(
        rawName: name,
        days: days,
      );

  String get displayBenefitText => _kqLocalizedMembershipBenefit(benefitText);

  String get priceLabel {
    if (priceYuan == priceYuan.roundToDouble()) {
      return '¥${priceYuan.toStringAsFixed(0)}';
    }
    return '¥${priceYuan.toStringAsFixed(2)}';
  }

  String get durationLabel {
    if (days >= 999999) return translate('Membership lifetime');
    if (days >= 365 && days % 365 == 0) {
      final years = days ~/ 365;
      return years == 1
          ? translate('1 membership year')
          : '$years ${translate('membership years')}';
    }
    if (days >= 30 && days % 30 == 0) {
      final months = days ~/ 30;
      return months == 1
          ? translate('1 membership month')
          : '$months ${translate('membership months')}';
    }
    return days == 1
        ? translate('1 membership day')
        : '$days ${translate('membership days')}';
  }
}

final _kqHanTextPattern = RegExp('[\u4e00-\u9fff]');

bool _kqUiPrefersChinese() {
  final selectedLang =
      bind.mainGetLocalOption(key: kCommConfKeyLang).trim().toLowerCase();
  if (selectedLang == 'zh-cn' || selectedLang == 'zh-tw') {
    return true;
  }
  if (selectedLang.isNotEmpty && selectedLang != defaultOptionLang) {
    return false;
  }
  return localeName.toString().toLowerCase().startsWith('zh');
}

bool _kqShouldReplaceBackendText(String value) {
  final text = value.trim();
  return text.isEmpty ||
      (!_kqUiPrefersChinese() && _kqHanTextPattern.hasMatch(text));
}

String _kqMembershipPackageNameByDays(int days) {
  if (days >= 999999) return translate('Lifetime membership');
  if (days >= 365 && days % 365 == 0) {
    final years = days ~/ 365;
    return years == 1
        ? translate('Annual membership')
        : '$years ${translate('year membership')}';
  }
  if (days >= 30 && days % 30 == 0) {
    final months = days ~/ 30;
    if (months == 1) return translate('Monthly membership');
    if (months == 3) return translate('Quarterly membership');
    return '$months ${translate('month membership')}';
  }
  return days > 0
      ? '$days ${translate('day membership')}'
      : translate('Membership package');
}

String _kqLocalizedMembershipPackageName({
  required String rawName,
  required int days,
}) {
  final text = rawName.trim();
  if (_kqShouldReplaceBackendText(text)) {
    return _kqMembershipPackageNameByDays(days);
  }
  return text;
}

String _kqLocalizedMembershipBenefit(String rawBenefit) {
  final text = rawBenefit.trim();
  if (_kqShouldReplaceBackendText(text)) {
    return translate('1080p / 60 FPS remote control');
  }
  return text;
}

class KqMemberOrder {
  final String orderNo;
  final int packageId;
  final String packageName;
  final int packageDays;
  final double payAmount;
  final int payType;
  final String subsiteName;
  final String qrcodeImgUrl;
  final String codeUrl;
  final String alipaySubmitHtml;

  const KqMemberOrder({
    required this.orderNo,
    required this.packageId,
    required this.packageName,
    required this.packageDays,
    required this.payAmount,
    required this.payType,
    required this.subsiteName,
    required this.qrcodeImgUrl,
    required this.codeUrl,
    required this.alipaySubmitHtml,
  });

  factory KqMemberOrder.fromJson(Map json) {
    return KqMemberOrder(
      orderNo: (json['order_no'] ?? '').toString(),
      packageId: int.tryParse((json['package_id'] ?? '').toString()) ?? 0,
      packageName: (json['package_name'] ?? '').toString(),
      packageDays: int.tryParse((json['package_days'] ?? '').toString()) ?? 0,
      payAmount: double.tryParse((json['pay_amount'] ?? '').toString()) ?? 0,
      payType: int.tryParse((json['pay_type'] ?? '').toString()) ?? 0,
      subsiteName: (json['subsite_name'] ?? '').toString(),
      qrcodeImgUrl: (json['qrcode_img_url'] ?? '').toString(),
      codeUrl: (json['code_url'] ?? '').toString(),
      alipaySubmitHtml: (json['alipaysubmit_html'] ?? '').toString(),
    );
  }

  String get displayPackageName => _kqLocalizedMembershipPackageName(
        rawName: packageName,
        days: packageDays,
      );
}

class KqMemberOrderStatus {
  final String orderNo;
  final int payStatus;
  final String expireAt;

  const KqMemberOrderStatus({
    required this.orderNo,
    required this.payStatus,
    required this.expireAt,
  });

  factory KqMemberOrderStatus.fromJson(Map json) {
    return KqMemberOrderStatus(
      orderNo: (json['order_no'] ?? '').toString(),
      payStatus: int.tryParse((json['pay_status'] ?? '').toString()) ?? 0,
      expireAt: (json['expire_at'] ?? '').toString(),
    );
  }

  bool get isPaid => payStatus == 1;
}
