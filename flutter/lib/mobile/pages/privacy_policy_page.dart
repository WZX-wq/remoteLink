import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/kq_theme.dart';
import '../privacy/kq_privacy_policy.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  Future<void> _openPublicPolicy() async {
    final uri = Uri.tryParse(KqPrivacyPolicy.publicUrl);
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
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
              _PrivacyHeader(
                title: KqPrivacyPolicy.titleForCurrentLanguage(),
                onOpenPublicPolicy: _openPublicPolicy,
              ),
              Expanded(
                child: SelectionArea(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                    children: [
                      _PrivacyIntroCard(
                        title: KqPrivacyPolicy.titleForCurrentLanguage(),
                        summary: KqPrivacyPolicy.summaryForCurrentLanguage(),
                      ),
                      const SizedBox(height: 14),
                      for (final section in KqPrivacyPolicy.sections) ...[
                        _PrivacySectionCard(section: section),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyHeader extends StatelessWidget {
  const _PrivacyHeader({
    required this.title,
    required this.onOpenPublicPolicy,
  });

  final String title;
  final Future<void> Function() onOpenPublicPolicy;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: q.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            onPressed: () => onOpenPublicPolicy(),
            tooltip: 'Open public policy',
            icon: Icon(Icons.open_in_new_rounded, color: q.primary),
          ),
        ],
      ),
    );
  }
}

class _PrivacyIntroCard extends StatelessWidget {
  const _PrivacyIntroCard({required this.title, required this.summary});

  final String title;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: q.panelStrong.withValues(alpha: q.isDark ? 0.84 : 0.98),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: q.line.withValues(alpha: 0.64)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: q.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.privacy_tip_outlined, color: q.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: q.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  summary,
                  style: TextStyle(
                    color: q.muted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacySectionCard extends StatelessWidget {
  const _PrivacySectionCard({required this.section});

  final KqPrivacyPolicySection section;

  @override
  Widget build(BuildContext context) {
    final q = KqTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: q.panelStrong.withValues(alpha: q.isDark ? 0.8 : 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: q.line.withValues(alpha: 0.58)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.titleForCurrentLanguage(),
            style: TextStyle(
              color: q.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          for (final paragraph in section.paragraphsForCurrentLanguage())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                paragraph,
                style: TextStyle(
                  color: q.muted,
                  fontSize: 13,
                  height: 1.52,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
