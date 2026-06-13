import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/common/kq_theme.dart';
import 'package:flutter_hbb/common/kq_oauth.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import './dialog.dart';

const kOpSvgList = [
  'github',
  'gitlab',
  'google',
  'apple',
  'okta',
  'facebook',
  'azure',
  'auth0',
  'microsoft'
];

bool _isKqOauthCancellation(Object err) =>
    err is KqOauthException && err.message == 'Authorization canceled.';

Future<void> _launchLoginUrl(Uri url) async {
  await launchUrl(
    url,
    mode: isMobile ? LaunchMode.inAppWebView : LaunchMode.externalApplication,
    webViewConfiguration: const WebViewConfiguration(
      enableJavaScript: true,
      enableDomStorage: true,
    ),
  );
}

Future<void> _closeLoginWebView() async {
  try {
    await closeInAppWebView();
  } catch (_) {
    // The login page may already be closed by the user or platform.
  }
}

Future<bool?> _loginWithKqOauthDirect() async {
  try {
    final resp = await KqOauth.login();
    await gFFI.userModel.applyLoginResponse(resp, storeLocalUserInfo: false);
    await UserModel.updateOtherModels();
    return true;
  } catch (err) {
    if (_isKqOauthCancellation(err)) {
      return false;
    }
    showToast(err.toString());
    return false;
  }
}

class _IconOP extends StatelessWidget {
  final String op;
  final String? icon;
  final EdgeInsets margin;
  const _IconOP(
      {Key? key,
      required this.op,
      required this.icon,
      this.margin = const EdgeInsets.symmetric(horizontal: 4.0)})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final svgFile =
        kOpSvgList.contains(op.toLowerCase()) ? op.toLowerCase() : 'default';
    return Container(
      margin: margin,
      child: icon == null
          ? SvgPicture.asset(
              'assets/auth-$svgFile.svg',
              width: 20,
            )
          : SvgPicture.string(
              icon!,
              width: 20,
            ),
    );
  }
}

class ButtonOP extends StatelessWidget {
  final String op;
  final RxString curOP;
  final String? icon;
  final Color primaryColor;
  final double height;
  final Function() onTap;

  const ButtonOP({
    Key? key,
    required this.op,
    required this.curOP,
    required this.icon,
    required this.primaryColor,
    required this.height,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final opLabel = {
          'github': 'GitHub',
          'gitlab': 'GitLab'
        }[op.toLowerCase()] ??
        toCapitalized(op);
    return Row(children: [
      Container(
        height: height,
        width: 200,
        child: Obx(() => ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: curOP.value.isEmpty || curOP.value == op
                  ? primaryColor
                  : Colors.grey,
            ).copyWith(elevation: ButtonStyleButton.allOrNull(0.0)),
            onPressed: curOP.value.isEmpty || curOP.value == op ? onTap : null,
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: _IconOP(
                    op: op,
                    icon: icon,
                    margin: EdgeInsets.only(right: 5),
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Center(
                        child: Text(translate("Continue with {$opLabel}"))),
                  ),
                ),
              ],
            ))),
      ),
    ]);
  }
}

class ConfigOP {
  final String op;
  final String? icon;
  ConfigOP({required this.op, required this.icon});
}

class WidgetOP extends StatefulWidget {
  final ConfigOP config;
  final RxString curOP;
  final Function(Map<String, dynamic>) cbLogin;
  const WidgetOP({
    Key? key,
    required this.config,
    required this.curOP,
    required this.cbLogin,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _WidgetOPState();
  }
}

class _WidgetOPState extends State<WidgetOP> {
  Timer? _updateTimer;
  String _stateMsg = '';
  String _failedMsg = '';
  String _url = '';

  @override
  void dispose() {
    super.dispose();
    _updateTimer?.cancel();
  }

  _beginQueryState() {
    _updateTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _updateState();
    });
  }

  _updateState() {
    bind.mainAccountAuthResult().then((result) {
      if (result.isEmpty) {
        return;
      }
      final resultMap = jsonDecode(result);
      if (resultMap == null) {
        return;
      }
      final String stateMsg = resultMap['state_msg'];
      String failedMsg = resultMap['failed_msg'];
      final String? url = resultMap['url'];
      final bool urlLaunched = (resultMap['url_launched'] as bool?) ?? false;
      final authBody = resultMap['auth_body'];
      if (_stateMsg != stateMsg || _failedMsg != failedMsg) {
        if (_url.isEmpty && url != null && url.isNotEmpty) {
          if (!urlLaunched) {
            _launchLoginUrl(Uri.parse(url));
          }
          _url = url;
        }
        if (authBody != null) {
          _updateTimer?.cancel();
          if (isMobile) {
            unawaited(_closeLoginWebView());
          }
          widget.curOP.value = '';
          widget.cbLogin(authBody as Map<String, dynamic>);
        }

        setState(() {
          _stateMsg = stateMsg;
          _failedMsg = failedMsg;
          if (failedMsg.isNotEmpty) {
            widget.curOP.value = '';
            _updateTimer?.cancel();
          }
        });
      }
    });
  }

  _resetState() {
    _stateMsg = '';
    _failedMsg = '';
    _url = '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ButtonOP(
          op: widget.config.op,
          curOP: widget.curOP,
          icon: widget.config.icon,
          primaryColor: str2color(widget.config.op, 0x7f),
          height: 36,
          onTap: () async {
            _resetState();
            widget.curOP.value = widget.config.op;
            await bind.mainAccountAuth(op: widget.config.op, rememberMe: true);
            _beginQueryState();
          },
        ),
        Obx(() {
          if (widget.curOP.isNotEmpty &&
              widget.curOP.value != widget.config.op) {
            _failedMsg = '';
          }
          return Offstage(
            offstage:
                _failedMsg.isEmpty && widget.curOP.value != widget.config.op,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_stateMsg.isNotEmpty && _failedMsg.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: SelectableText(
                      translate(_stateMsg),
                      style: DefaultTextStyle.of(context)
                          .style
                          .copyWith(fontSize: 12),
                    ),
                  ),
                if (_failedMsg.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Builder(builder: (context) {
                      final errorColor = Theme.of(context).colorScheme.error;
                      final bgColor = Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withOpacity(0.3);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 6.0),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: errorColor, size: 16),
                            const SizedBox(width: 6),
                            Flexible(
                              child: SelectableText(
                                translate(_failedMsg),
                                style:
                                    DefaultTextStyle.of(context).style.copyWith(
                                          fontSize: 13,
                                          color: errorColor,
                                        ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
              ],
            ),
          );
        }),
        Obx(
          () => Offstage(
            offstage: widget.curOP.value != widget.config.op,
            child: const SizedBox(
              height: 5.0,
            ),
          ),
        ),
        Obx(
          () => Offstage(
            offstage: widget.curOP.value != widget.config.op,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 20),
              child: ElevatedButton(
                onPressed: () {
                  widget.curOP.value = '';
                  _updateTimer?.cancel();
                  _resetState();
                  bind.mainAccountAuthCancel();
                },
                child: Text(
                  translate('Cancel'),
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class LoginWidgetOP extends StatelessWidget {
  final List<ConfigOP> ops;
  final RxString curOP;
  final Function(Map<String, dynamic>) cbLogin;

  LoginWidgetOP({
    Key? key,
    required this.ops,
    required this.curOP,
    required this.cbLogin,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var children = ops
        .map((op) => [
              WidgetOP(
                config: op,
                curOP: curOP,
                cbLogin: cbLogin,
              ),
              const Divider(
                indent: 5,
                endIndent: 5,
              )
            ])
        .expand((i) => i)
        .toList();
    if (children.isNotEmpty) {
      children.removeLast();
    }
    return SingleChildScrollView(
        child: Container(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: children,
            )));
  }
}

class LoginWidgetUserPass extends StatelessWidget {
  final TextEditingController username;
  final TextEditingController pass;
  final String? usernameMsg;
  final String? passMsg;
  final bool isInProgress;
  final RxString curOP;
  final Function() onLogin;
  final FocusNode? userFocusNode;
  const LoginWidgetUserPass({
    Key? key,
    this.userFocusNode,
    required this.username,
    required this.pass,
    required this.usernameMsg,
    required this.passMsg,
    required this.isInProgress,
    required this.curOP,
    required this.onLogin,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EdgeInsets.all(0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8.0),
            DialogTextField(
                title: translate(DialogTextField.kUsernameTitle),
                controller: username,
                focusNode: userFocusNode,
                prefixIcon: DialogTextField.kUsernameIcon,
                errorText: usernameMsg),
            PasswordWidget(
              controller: pass,
              autoFocus: false,
              reRequestFocus: true,
              errorText: passMsg,
            ),
            // NOT use Offstage to wrap LinearProgressIndicator
            if (isInProgress) const LinearProgressIndicator(),
            const SizedBox(height: 12.0),
            FittedBox(
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                height: 38,
                width: 200,
                child: Obx(() => ElevatedButton(
                      child: Text(
                        translate('Login'),
                        style: TextStyle(fontSize: 16),
                      ),
                      onPressed: !isInProgress &&
                              (curOP.value.isEmpty || curOP.value == 'rustdesk')
                          ? () {
                              onLogin();
                            }
                          : null,
                    )),
              ),
            ])),
          ],
        ));
  }
}

class LoginWidgetKqOauth extends StatelessWidget {
  final RxString curOP;
  final bool isInProgress;
  final String? errorText;
  final Function() onLogin;

  const LoginWidgetKqOauth({
    Key? key,
    required this.curOP,
    required this.isInProgress,
    required this.errorText,
    required this.onLogin,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 38,
          width: 200,
          child: Obx(() => ElevatedButton.icon(
                icon: const Icon(Icons.business_center_outlined, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(translate('Log in to your Kunqiong account')),
                ),
                onPressed: !isInProgress &&
                        (curOP.value.isEmpty || curOP.value == kKqOauthProvider)
                    ? onLogin
                    : null,
              )),
        ),
        if (isInProgress) const LinearProgressIndicator().marginOnly(top: 8),
        if (errorText != null)
          SelectableText(
            errorText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ).paddingOnly(top: 8, left: 12, right: 12),
      ],
    );
  }
}

class _KqNativeMobileLoginPage extends StatefulWidget {
  const _KqNativeMobileLoginPage();

  @override
  State<_KqNativeMobileLoginPage> createState() =>
      _KqNativeMobileLoginPageState();
}

class _KqNativeMobileLoginPageState extends State<_KqNativeMobileLoginPage> {
  final _accountController =
      TextEditingController(text: UserModel.getLocalUserInfo()?['name'] ?? '');
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  final _accountFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _smsCodeFocusNode = FocusNode();

  bool _useSms = false;
  bool _passwordVisible = false;
  bool _isSubmitting = false;
  bool _isSendingSms = false;
  int _smsCountdown = 0;
  String? _errorText;
  Timer? _smsTimer;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      (_useSms ? _phoneFocusNode : _accountFocusNode).requestFocus();
    });
  }

  @override
  void dispose() {
    _smsTimer?.cancel();
    _accountController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    _accountFocusNode.dispose();
    _passwordFocusNode.dispose();
    _phoneFocusNode.dispose();
    _smsCodeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _errorText = null);

    final account = _accountController.text.trim();
    final password = _passwordController.text;
    final phone = _phoneController.text.trim();
    final code = _smsCodeController.text.trim();

    if (_useSms) {
      if (!_isValidPhone(phone)) {
        setState(
            () => _errorText = translate('Please enter a valid phone number'));
        return;
      }
      if (code.isEmpty) {
        setState(() => _errorText = translate('Please enter the SMS code'));
        return;
      }
    } else {
      if (account.isEmpty) {
        setState(() => _errorText = translate('Username missed'));
        return;
      }
      if (password.isEmpty) {
        setState(() => _errorText = translate('Password missed'));
        return;
      }
    }

    setState(() => _isSubmitting = true);
    try {
      final resp = _useSms
          ? await KqOauth.loginWithSms(phone: phone, code: code)
          : await KqOauth.loginWithPassword(
              username: _normalizeAccountInput(account),
              password: password,
            );
      await gFFI.userModel.applyLoginResponse(resp, storeLocalUserInfo: false);
      await UserModel.updateOtherModels();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      setState(() => _errorText = _formatKqLoginError(err));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _sendSmsCode() async {
    if (_isSendingSms || _smsCountdown > 0) return;
    final phone = _phoneController.text.trim();
    if (!_isValidPhone(phone)) {
      setState(
          () => _errorText = translate('Please enter a valid phone number'));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _errorText = null;
      _isSendingSms = true;
    });
    try {
      await KqOauth.sendSmsCode(phone: phone);
      if (!mounted) return;
      showToast(translate('SMS code sent'));
      _startSmsCountdown();
    } catch (err) {
      if (!mounted) return;
      setState(() => _errorText = _formatKqLoginError(err));
    } finally {
      if (mounted) {
        setState(() => _isSendingSms = false);
      }
    }
  }

  void _startSmsCountdown() {
    _smsTimer?.cancel();
    setState(() => _smsCountdown = 60);
    _smsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_smsCountdown <= 1) {
        timer.cancel();
        setState(() => _smsCountdown = 0);
      } else {
        setState(() => _smsCountdown--);
      }
    });
  }

  String _normalizeAccountInput(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('+86')) {
      final phone = trimmed.substring(3).replaceAll(RegExp(r'\s+'), '');
      if (_isValidPhone(phone)) return phone;
    }
    return trimmed;
  }

  bool _isValidPhone(String value) => RegExp(r'^1[3-9]\d{9}$').hasMatch(value);

  String _formatKqLoginError(Object err) {
    var text = err.toString();
    if (err is KqOauthException) {
      text = err.message;
    }
    text = text.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    return text.isEmpty ? translate('Kunqiong login failed') : translate(text);
  }

  void _switchMode(bool sms) {
    if (_isSubmitting || _isSendingSms || sms == _useSms) return;
    setState(() {
      _useSms = sms;
      _errorText = null;
    });
    Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      (_useSms ? _phoneFocusNode : _accountFocusNode).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: q.pageGradient,
          ),
        ),
        child: SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: bottomInset > 0 ? 8 : 0),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                _KqNativeLoginTopBar(q: q),
                const SizedBox(height: 26),
                _KqNativeLoginHero(q: q),
                const SizedBox(height: 22),
                _KqNativeLoginPanel(
                  q: q,
                  useSms: _useSms,
                  passwordVisible: _passwordVisible,
                  isSubmitting: _isSubmitting,
                  isSendingSms: _isSendingSms,
                  smsCountdown: _smsCountdown,
                  errorText: _errorText,
                  accountController: _accountController,
                  passwordController: _passwordController,
                  phoneController: _phoneController,
                  smsCodeController: _smsCodeController,
                  accountFocusNode: _accountFocusNode,
                  passwordFocusNode: _passwordFocusNode,
                  phoneFocusNode: _phoneFocusNode,
                  smsCodeFocusNode: _smsCodeFocusNode,
                  onSwitchMode: _switchMode,
                  onSubmit: _submit,
                  onSendSms: _sendSmsCode,
                  onTogglePassword: () =>
                      setState(() => _passwordVisible = !_passwordVisible),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KqNativeLoginTopBar extends StatelessWidget {
  final KqTheme q;

  const _KqNativeLoginTopBar({required this.q});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: translate('Back'),
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.arrow_back_rounded),
          color: q.ink,
          style: IconButton.styleFrom(
            backgroundColor: q.panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: q.line),
            ),
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => launchUrl(Uri.parse('https://kunqiongai.com/')),
          style: TextButton.styleFrom(foregroundColor: q.primary),
          child: Text(translate('Company website')),
        ),
      ],
    );
  }
}

class _KqNativeLoginHero extends StatelessWidget {
  final KqTheme q;

  const _KqNativeLoginHero({required this.q});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 72,
          height: 72,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: q.panelStrong,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: q.line),
            boxShadow: [
              BoxShadow(
                color: q.shadow,
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: loadIcon(50),
        ),
        const SizedBox(height: 18),
        Text(
          translate('Log in to Kunqiong Remote Desktop'),
          style: TextStyle(
            color: q.ink,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          translate(
              'Use your Kunqiong account to sync devices, favorites, and membership benefits.'),
          style: TextStyle(
            color: q.muted,
            fontSize: 14,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}

class _KqNativeLoginPanel extends StatelessWidget {
  final KqTheme q;
  final bool useSms;
  final bool passwordVisible;
  final bool isSubmitting;
  final bool isSendingSms;
  final int smsCountdown;
  final String? errorText;
  final TextEditingController accountController;
  final TextEditingController passwordController;
  final TextEditingController phoneController;
  final TextEditingController smsCodeController;
  final FocusNode accountFocusNode;
  final FocusNode passwordFocusNode;
  final FocusNode phoneFocusNode;
  final FocusNode smsCodeFocusNode;
  final void Function(bool) onSwitchMode;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onSendSms;
  final VoidCallback onTogglePassword;

  const _KqNativeLoginPanel({
    required this.q,
    required this.useSms,
    required this.passwordVisible,
    required this.isSubmitting,
    required this.isSendingSms,
    required this.smsCountdown,
    required this.errorText,
    required this.accountController,
    required this.passwordController,
    required this.phoneController,
    required this.smsCodeController,
    required this.accountFocusNode,
    required this.passwordFocusNode,
    required this.phoneFocusNode,
    required this.smsCodeFocusNode,
    required this.onSwitchMode,
    required this.onSubmit,
    required this.onSendSms,
    required this.onTogglePassword,
  });

  @override
  Widget build(BuildContext context) {
    final isBusy = isSubmitting || isSendingSms;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: q.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: q.line),
        boxShadow: [
          BoxShadow(
            color: q.shadow,
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KqLoginModeSwitch(
            q: q,
            useSms: useSms,
            onSwitchMode: onSwitchMode,
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: useSms
                ? Column(
                    key: const ValueKey('sms-login'),
                    children: [
                      _KqNativeTextField(
                        q: q,
                        controller: phoneController,
                        focusNode: phoneFocusNode,
                        label: translate('Phone number'),
                        hint: translate('Enter phone number'),
                        icon: Icons.phone_android_rounded,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => smsCodeFocusNode.requestFocus(),
                      ),
                      const SizedBox(height: 12),
                      _KqNativeTextField(
                        q: q,
                        controller: smsCodeController,
                        focusNode: smsCodeFocusNode,
                        label: translate('SMS code'),
                        hint: translate('Enter SMS code'),
                        icon: Icons.sms_outlined,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => onSubmit(),
                        suffix: TextButton(
                          onPressed:
                              isBusy || smsCountdown > 0 ? null : onSendSms,
                          child: isSendingSms
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: q.primary,
                                  ),
                                )
                              : Text(
                                  smsCountdown > 0
                                      ? '${smsCountdown}s'
                                      : translate('Get code'),
                                ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('password-login'),
                    children: [
                      _KqNativeTextField(
                        q: q,
                        controller: accountController,
                        focusNode: accountFocusNode,
                        label: translate('Account'),
                        hint: translate('Username / phone / email'),
                        icon: Icons.person_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => passwordFocusNode.requestFocus(),
                      ),
                      const SizedBox(height: 12),
                      _KqNativeTextField(
                        q: q,
                        controller: passwordController,
                        focusNode: passwordFocusNode,
                        label: translate('Password'),
                        hint: translate('Enter your password'),
                        icon: Icons.lock_outline_rounded,
                        obscureText: !passwordVisible,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => onSubmit(),
                        suffix: IconButton(
                          tooltip: translate(passwordVisible ? 'Hide' : 'Show'),
                          onPressed: onTogglePassword,
                          icon: Icon(
                            passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          color: q.muted,
                        ),
                      ),
                    ],
                  ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: errorText == null || errorText!.isEmpty
                ? const SizedBox(height: 14)
                : Container(
                    key: ValueKey(errorText),
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: q.offline.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: q.offline.withOpacity(0.24)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: q.offline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorText!,
                            style: TextStyle(
                              color: q.offline,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: isSubmitting ? null : onSubmit,
            style: FilledButton.styleFrom(
              backgroundColor: q.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: q.primary.withOpacity(0.42),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    translate('Login'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            translate('Login is completed securely inside the app.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: q.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _KqLoginModeSwitch extends StatelessWidget {
  final KqTheme q;
  final bool useSms;
  final void Function(bool) onSwitchMode;

  const _KqLoginModeSwitch({
    required this.q,
    required this.useSms,
    required this.onSwitchMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: q.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line),
      ),
      child: Row(
        children: [
          _KqLoginModeButton(
            q: q,
            selected: !useSms,
            label: translate('Password login'),
            onTap: () => onSwitchMode(false),
          ),
          _KqLoginModeButton(
            q: q,
            selected: useSms,
            label: translate('SMS login'),
            onTap: () => onSwitchMode(true),
          ),
        ],
      ),
    );
  }
}

class _KqLoginModeButton extends StatelessWidget {
  final KqTheme q;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _KqLoginModeButton({
    required this.q,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? q.panelStrong : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: q.shadow,
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? q.primary : q.muted,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _KqNativeTextField extends StatelessWidget {
  final KqTheme q;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  const _KqNativeTextField({
    required this.q,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.suffix,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: TextStyle(color: q.ink, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: q.primary),
        suffixIcon: suffix,
        filled: true,
        fillColor: q.field,
        labelStyle: TextStyle(color: q.muted),
        hintStyle: TextStyle(color: q.muted.withOpacity(0.7)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: q.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: q.primary, width: 1.4),
        ),
      ),
    );
  }
}

const kAuthReqTypeOidc = 'oidc/';

// call this directly
Future<bool?> loginDialog() async {
  if (isDesktop) {
    return _loginWithKqOauthDirect();
  }
  if (isMobile) {
    final context = globalKey.currentContext ?? Get.context;
    if (context == null) {
      return false;
    }
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _KqNativeMobileLoginPage()),
    );
  }

  var username =
      TextEditingController(text: UserModel.getLocalUserInfo()?['name'] ?? '');
  var password = TextEditingController();
  final userFocusNode = FocusNode()..requestFocus();
  Timer(Duration(milliseconds: 100), () => userFocusNode..requestFocus());

  String? usernameMsg;
  String? passwordMsg;
  String? kqOauthMsg;
  var isInProgress = false;
  var isKqOauthInProgress = false;
  final RxString curOP = ''.obs;
  // Track hover state for the close icon
  bool isCloseHovered = false;
  bool isDialogClosed = false;

  final loginOptions = [].obs;
  Future.delayed(Duration.zero, () async {
    loginOptions.value = await UserModel.queryOidcLoginOptions();
  });

  final res = await gFFI.dialogManager.show<bool>((setState, close, context) {
    username.addListener(() {
      if (usernameMsg != null) {
        setState(() => usernameMsg = null);
      }
    });

    password.addListener(() {
      if (passwordMsg != null) {
        setState(() => passwordMsg = null);
      }
    });

    onDialogCancel() {
      isDialogClosed = true;
      KqOauth.cancel();
      isInProgress = false;
      close(false);
    }

    handleLoginResponse(LoginResponse resp, bool storeIfAccessToken,
        void Function([dynamic])? close) async {
      switch (resp.type) {
        case HttpType.kAuthResTypeToken:
          if (resp.access_token != null) {
            if (storeIfAccessToken) {
              await bind.mainSetLocalOption(
                  key: 'access_token', value: resp.access_token!);
              await bind.mainSetLocalOption(
                  key: 'user_info', value: jsonEncode(resp.user ?? {}));
              await bind.mainSetLocalOption(
                  key: kKqOauthProviderKey, value: '');
            }
            await gFFI.userModel.applyLoginResponse(
              resp,
              storeLocalUserInfo: true,
            );
            if (close != null) {
              close(true);
            }
            return;
          }
          break;
        case HttpType.kAuthResTypeEmailCheck:
          bool? isEmailVerification;
          if (resp.tfa_type == null ||
              resp.tfa_type == HttpType.kAuthResTypeEmailCheck) {
            isEmailVerification = true;
          } else if (resp.tfa_type == HttpType.kAuthResTypeTfaCheck) {
            isEmailVerification = false;
          } else {
            passwordMsg = "Failed, bad tfa type from server";
          }
          if (isEmailVerification != null) {
            if (isMobile) {
              if (close != null) close(null);
              verificationCodeDialog(
                  resp.user, resp.secret, isEmailVerification);
            } else {
              setState(() => isInProgress = false);
              // Workaround for web, close the dialog first, then show the verification code dialog.
              // Otherwise, the text field will keep selecting the text and we can't input the code.
              // Not sure why this happens.
              if (isWeb && close != null) close(null);
              final res = await verificationCodeDialog(
                  resp.user, resp.secret, isEmailVerification);
              if (res == true) {
                if (!isWeb && close != null) close(false);
                return;
              }
            }
          }
          break;
        default:
          passwordMsg = "Failed, bad response from server";
          break;
      }
    }

    onKqOauthLogin() async {
      curOP.value = kKqOauthProvider;
      setState(() {
        kqOauthMsg = null;
        isKqOauthInProgress = true;
      });
      try {
        final resp = await KqOauth.login();
        if (isDialogClosed) return;
        await gFFI.userModel.applyLoginResponse(
          resp,
          storeLocalUserInfo: false,
        );
        close(true);
        return;
      } catch (err) {
        if (isDialogClosed) return;
        if (!_isKqOauthCancellation(err)) {
          kqOauthMsg = err.toString();
        }
      }
      curOP.value = '';
      setState(() => isKqOauthInProgress = false);
    }

    onLogin() async {
      if (isInProgress) return;
      // validate
      if (username.text.isEmpty) {
        setState(() => usernameMsg = translate('Username missed'));
        return;
      }
      if (password.text.isEmpty) {
        setState(() => passwordMsg = translate('Password missed'));
        return;
      }
      curOP.value = 'rustdesk';
      setState(() => isInProgress = true);
      try {
        final resp = await gFFI.userModel.login(LoginRequest(
            username: username.text,
            password: password.text,
            id: await bind.mainGetMyId(),
            uuid: await bind.mainGetUuid(),
            autoLogin: true,
            type: HttpType.kAuthReqTypeAccount));
        await handleLoginResponse(resp, true, close);
      } on RequestException catch (err) {
        passwordMsg = translate(err.cause);
      } catch (err) {
        passwordMsg = "Unknown Error: $err";
      }
      curOP.value = '';
      setState(() => isInProgress = false);
    }

    thirdAuthWidget() => Obx(() {
          return Offstage(
            offstage: loginOptions.isEmpty,
            child: Column(
              children: [
                const SizedBox(
                  height: 8.0,
                ),
                Center(
                    child: Text(
                  translate('or'),
                  style: TextStyle(fontSize: 16),
                )),
                const SizedBox(
                  height: 8.0,
                ),
                LoginWidgetOP(
                  ops: loginOptions
                      .map((e) => ConfigOP(op: e['name'], icon: e['icon']))
                      .toList(),
                  curOP: curOP,
                  cbLogin: (Map<String, dynamic> authBody) async {
                    LoginResponse? resp;
                    try {
                      // access_token is already stored in the rust side.
                      resp =
                          gFFI.userModel.getLoginResponseFromAuthBody(authBody);
                    } catch (e) {
                      debugPrint(
                          'Failed to parse oidc login body: "$authBody"');
                    }
                    close(true);

                    if (resp != null) {
                      await handleLoginResponse(resp, false, null);
                    }
                  },
                ),
              ],
            ),
          );
        });

    companyAuthWidget() => Column(
          children: [
            const SizedBox(height: 8.0),
            Center(
                child: Text(
              translate('or'),
              style: TextStyle(fontSize: 16),
            )),
            const SizedBox(height: 8.0),
            LoginWidgetKqOauth(
              curOP: curOP,
              isInProgress: isKqOauthInProgress,
              errorText: kqOauthMsg,
              onLogin: onKqOauthLogin,
            ),
          ],
        );

    final title = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translate('Login'),
        ).marginOnly(top: MyTheme.dialogPadding),
        MouseRegion(
          onEnter: (_) => setState(() => isCloseHovered = true),
          onExit: (_) => setState(() => isCloseHovered = false),
          child: InkWell(
            child: Icon(
              Icons.close,
              size: 25,
              // No need to handle the branch of null.
              // Because we can ensure the color is not null when debug.
              color: isCloseHovered
                  ? Colors.white
                  : Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.color
                      ?.withOpacity(0.55),
            ),
            onTap: onDialogCancel,
            hoverColor: Colors.red,
            borderRadius: BorderRadius.circular(5),
          ),
        ).marginOnly(top: 10, right: 15),
      ],
    );
    final titlePadding = EdgeInsets.fromLTRB(MyTheme.dialogPadding, 0, 0, 0);

    return CustomAlertDialog(
      title: title,
      titlePadding: titlePadding,
      contentBoxConstraints: BoxConstraints(minWidth: 400),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            height: 8.0,
          ),
          LoginWidgetUserPass(
            username: username,
            pass: password,
            usernameMsg: usernameMsg,
            passMsg: passwordMsg,
            isInProgress: isInProgress,
            curOP: curOP,
            onLogin: onLogin,
            userFocusNode: userFocusNode,
          ),
          thirdAuthWidget(),
          if (isDesktop) companyAuthWidget(),
        ],
      ),
      onCancel: onDialogCancel,
      onSubmit: onLogin,
    );
  });

  if (res != null) {
    await UserModel.updateOtherModels();
  }

  return res;
}

Future<bool?> verificationCodeDialog(
    UserPayload? user, String? secret, bool isEmailVerification) async {
  var autoLogin = true;
  var isInProgress = false;
  String? errorText;

  final code = TextEditingController();

  final res = await gFFI.dialogManager.show<bool>((setState, close, context) {
    void onVerify() async {
      setState(() => isInProgress = true);

      try {
        final resp = await gFFI.userModel.login(LoginRequest(
            verificationCode: code.text,
            tfaCode: isEmailVerification ? null : code.text,
            secret: secret,
            username: user?.name,
            id: await bind.mainGetMyId(),
            uuid: await bind.mainGetUuid(),
            autoLogin: autoLogin,
            type: HttpType.kAuthReqTypeEmailCode));

        switch (resp.type) {
          case HttpType.kAuthResTypeToken:
            if (resp.access_token != null) {
              await bind.mainSetLocalOption(
                  key: 'access_token', value: resp.access_token!);
              await gFFI.userModel.applyLoginResponse(resp);
              close(true);
              return;
            }
            break;
          default:
            errorText = "Failed, bad response from server";
            break;
        }
      } on RequestException catch (err) {
        errorText = translate(err.cause);
      } catch (err) {
        errorText = "Unknown Error: $err";
      }

      setState(() => isInProgress = false);
    }

    final codeField = isEmailVerification
        ? DialogEmailCodeField(
            controller: code,
            errorText: errorText,
            readyCallback: onVerify,
            onChanged: () => errorText = null,
          )
        : Dialog2FaField(
            controller: code,
            errorText: errorText,
            readyCallback: onVerify,
            onChanged: () => errorText = null,
          );

    getOnSubmit() => codeField.isReady ? onVerify : null;

    return CustomAlertDialog(
        title: Text(translate("Verification code")),
        contentBoxConstraints: BoxConstraints(maxWidth: 300),
        content: Column(
          children: [
            Offstage(
                offstage: !isEmailVerification || user?.email == null,
                child: TextField(
                  decoration: InputDecoration(
                      labelText: "Email", prefixIcon: Icon(Icons.email)),
                  readOnly: true,
                  controller: TextEditingController(text: user?.email),
                ).workaroundFreezeLinuxMint()),
            isEmailVerification ? const SizedBox(height: 8) : const Offstage(),
            codeField,
            /*
            CheckboxListTile(
              contentPadding: const EdgeInsets.all(0),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Row(children: [
                Expanded(child: Text(translate("Trust this device")))
              ]),
              value: trustThisDevice,
              onChanged: (v) {
                if (v == null) return;
                setState(() => trustThisDevice = !trustThisDevice);
              },
            ),
            */
            // NOT use Offstage to wrap LinearProgressIndicator
            if (isInProgress) const LinearProgressIndicator(),
          ],
        ),
        onCancel: close,
        onSubmit: getOnSubmit(),
        actions: [
          dialogButton("Cancel", onPressed: close, isOutline: true),
          dialogButton("Verify", onPressed: getOnSubmit()),
        ]);
  });
  // For verification code, desktop update other models in login dialog, mobile need to close login dialog first,
  // otherwise the soft keyboard will jump out on each key press, so mobile update in verification code dialog.
  if (isMobile && res == true) {
    await UserModel.updateOtherModels();
  }

  return res;
}

void logOutConfirmDialog() {
  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      close();
      gFFI.userModel.logOut();
    }

    return CustomAlertDialog(
      content: Text(translate("logout_tip")),
      actions: [
        dialogButton(translate("Cancel"), onPressed: close, isOutline: true),
        dialogButton(translate("OK"), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}
