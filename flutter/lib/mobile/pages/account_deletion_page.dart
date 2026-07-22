import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/kq_account_deletion.dart';
import '../../common/kq_theme.dart';
import '../../models/platform_model.dart';

class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage({super.key});

  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  final _confirmationController = TextEditingController();
  final _api = KqAccountDeletionApi.fromEnvironment();
  var _submitting = false;
  String? _error;

  bool get _confirmed => _confirmationController.text.trim() == 'DELETE';

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  String _text(String zh, String en) => kqUiPrefersChinese() ? zh : en;

  String _errorText(KqAccountDeletionException error) {
    switch (error.failure) {
      case KqAccountDeletionFailure.notLoggedIn:
        return _text(
            '请先登录后再注销账号。', 'Please log in before deleting the account.');
      case KqAccountDeletionFailure.confirmationRequired:
        return _text('请输入 DELETE 确认注销。', 'Enter DELETE to confirm deletion.');
      case KqAccountDeletionFailure.serviceUnavailable:
        return _text(
          '账号注销服务尚未配置，请稍后再试。',
          'Account deletion is not configured yet. Please try again later.',
        );
      case KqAccountDeletionFailure.requestFailed:
        return error.message;
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_confirmed) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _api.requestDeletion(
        token: bind.mainGetLocalOption(key: 'access_token'),
        confirmation: _confirmationController.text,
      );
      if (!mounted) return;
      await gFFI.userModel.logOut();
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(
        result.pending
            ? _text('已提交账号注销申请，请留意后续通知。',
                'Deletion request submitted. Please watch for updates.')
            : _text('账号已注销。', 'Your account has been deleted.'),
      );
    } on KqAccountDeletionException catch (error) {
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    final configured = _api.isConfigured;
    return Scaffold(
      backgroundColor: q.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: q.pageGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _AccountDeletionHeader(title: _text('注销账号', 'Delete account')),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                  children: [
                    _DeletionWarningCard(
                      title: _text('此操作不可撤销', 'This action cannot be undone'),
                      message: _text(
                        '提交后将删除账号及不再需要保留的相关数据。账号注销不会自动取消 Apple 自动续订，请先在 Apple 订阅管理中取消。',
                        'The request removes your account and related data that no longer needs to be retained. It does not cancel an Apple auto-renewing subscription; cancel that in Apple subscription management first.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (!configured) ...[
                      _DeletionInfoCard(
                        message: _text(
                          '此版本尚未连接账号注销服务，暂时不能提交注销申请。',
                          'This build is not connected to the account-deletion service yet.',
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      _text('请输入 DELETE 确认', 'Enter DELETE to confirm'),
                      style: TextStyle(
                        color: q.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _confirmationController,
                      enabled: configured && !_submitting,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'DELETE',
                        errorText: _error,
                        filled: true,
                        fillColor: q.field,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: q.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: q.line),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: configured && _confirmed && !_submitting
                            ? _submit
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: q.offline,
                          disabledBackgroundColor: q.offline.withOpacity(0.28),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.delete_forever_rounded),
                        label: Text(
                          _submitting
                              ? _text('正在提交...', 'Submitting...')
                              : _text('提交注销申请', 'Submit deletion request'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountDeletionHeader extends StatelessWidget {
  const _AccountDeletionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: q.ink),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: q.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeletionWarningCard extends StatelessWidget {
  const _DeletionWarningCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: q.offline.withOpacity(q.isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: q.offline.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: q.offline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  message,
                  style: TextStyle(color: q.muted, fontSize: 13, height: 1.48),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeletionInfoCard extends StatelessWidget {
  const _DeletionInfoCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: q.warning.withOpacity(q.isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: q.warning.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: q.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: q.muted, fontSize: 13, height: 1.42),
            ),
          ),
        ],
      ),
    );
  }
}
