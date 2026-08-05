#!/usr/bin/env python3

import pathlib
import re
import subprocess
import sys
import unittest


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import lang
from qwen_translate_lang import LOCALE_NAMES, entries_needing_translation


ROOT = pathlib.Path(__file__).resolve().parent.parent


def mobile_localization_keys():
    patterns = (
        re.compile(r'''translate\(\s*(['"])((?:\\.|(?!\1).)*)\1\s*\)''', re.S),
        re.compile(
            r'''kqLocaleText\((?:(?!\)).)*?\ben\s*:\s*(['"])((?:\\.|(?!\1).)*)\1''',
            re.S,
        ),
        re.compile(
            r'''_iosShareText\((?:(?!\)).)*?\ben\s*:\s*(['"])((?:\\.|(?!\1).)*)\1''',
            re.S,
        ),
        re.compile(
            r'''(?:_text|text)\(\s*(?:['"])(?:\\.|[^'"])*(?:['"])\s*,\s*(['"])((?:\\.|(?!\1).)*)\1''',
            re.S,
        ),
    )
    keys = set()
    for directory in (ROOT / 'flutter/lib/mobile', ROOT / 'flutter/lib/common'):
        for filename in directory.rglob('*.dart'):
            source = filename.read_text(encoding='utf-8')
            for pattern in patterns:
                for match in pattern.finditer(source):
                    value = match.group(2)
                    value = value.replace(r'\n', '\n')
                    value = value.replace(r'\"', '"').replace(r"\'", "'")
                    value = re.sub(r'\{\$\{.*?\}\}', '{}', value)
                    value = re.sub(r'\{\$[A-Za-z_][A-Za-z0-9_]*\}', '{}', value)
                    keys.add(value)
    return keys


class TranslationCoverageTest(unittest.TestCase):
    def test_mobile_localization_calls_are_registered(self):
        english = dict(lang.get_rust_entries(str(ROOT / 'src/lang/en.rs')))
        missing = sorted(mobile_localization_keys() - english.keys())
        self.assertFalse(
            missing,
            'Mobile localization calls must be registered in the English baseline: %s'
            % missing,
        )

    def test_account_route_labels_are_registered_for_every_locale(self):
        required_keys = {
            'Privacy policy',
            'Delete account',
            'Remove your account and data',
            'Unlimited',
            'Kunqiong account',
            'Signed in',
            'Alipay is not installed. Please install Alipay and try again.',
            'Payment cancelled',
            'Payment was not completed',
            'Basic uses SD / 30 FPS. Membership unlocks 1080p HD / 60 FPS.',
            'This action cannot be undone',
            'Deleting the account clears all Kunqiong account data. Proceed carefully. It does not cancel an Apple auto-renewing subscription; cancel that in Apple subscription management first.',
            'This build is not connected to the account-deletion service yet.',
            'Enter DELETE to confirm',
            'Submit deletion request',
            'Submitting...',
            'Please log in before deleting the account.',
            'Enter DELETE to confirm deletion.',
            'Account deletion is not configured yet. Please try again later.',
            'Deletion request submitted. Please watch for updates.',
            'Your account has been deleted.',
            'Data we collect',
            'To create and protect an account, we process your username, phone number, sign-in credentials, and account profile.',
            'To provide remote assistance, we process device and connection identifiers, remote display frames, input actions, and the application audio, voice data, files, and clipboard content you choose to transmit.',
            'How we use data',
            'We use this data only to authenticate you, establish remote sessions, transfer content you initiate, protect service security, process membership entitlements, and provide support.',
            'We do not use personal data for cross-app tracking or sell personal data.',
            'Data sharing and security',
            'Remote display frames, application audio, voice content, control instructions, files, and clipboard data are sent only to the other side of the remote session you start.',
            'We process data with bound service providers only when necessary to provide the service, protect security, verify payment, or comply with law.',
            'Retention, deletion, and your choices',
            'We retain account and service data only for the period needed to provide the service and meet legal obligations. You can manage microphone, photos, and file permissions in system settings and can sign out at any time.',
            'You can initiate account deletion from Personal center. Deletion removes the account and related data that we do not need to retain; data required by law is removed after the applicable retention period.',
            'Membership and payments',
            'Membership purchase and purchase restoration in the App Store build are handled by Apple In-App Purchase. We process only the transaction information needed to verify membership entitlements.',
            'Deleting an account does not automatically cancel an Apple subscription. Cancel any auto-renewing subscription in Apple subscription management first.',
            'Contact us',
            'For privacy, data-access, correction, or deletion requests, use the Contact us channel in the app.',
            'We update this policy when there are material changes to features or data handling.',
            'Learn how we handle data for accounts, remote assistance, and membership services.',
        }
        english = dict(lang.get_rust_entries(str(ROOT / 'src/lang/en.rs')))

        self.assertTrue(
            required_keys.issubset(english),
            'Account-route labels must be registered in the English baseline.',
        )
        for locale, filename in lang.supported_language_files():
            entries = dict(lang.get_rust_entries(filename))
            self.assertTrue(
                required_keys.issubset(entries),
                '%s is missing an account-route label' % locale,
            )

    def test_mobile_navigation_and_broadcast_labels_are_registered_for_every_locale(self):
        required_keys = {
            'Recent connections',
            'Mobile devices',
            'Desktop devices',
            'Loading',
            'No recent connection records',
            'Connected devices will appear here for quick access',
            'Records will be shown here after available devices are added',
            'Online',
            'Offline',
            'Checking',
            'Start live',
        }
        english = dict(lang.get_rust_entries(str(ROOT / 'src/lang/en.rs')))

        self.assertTrue(
            required_keys.issubset(english),
            'Mobile UI labels must be registered in the English baseline.',
        )
        for locale, filename in lang.supported_language_files():
            entries = dict(lang.get_rust_entries(filename))
            self.assertTrue(
                required_keys.issubset(entries),
                '%s is missing a mobile navigation or broadcast label' % locale,
            )

    def test_supported_language_list_matches_the_product_language_policy(self):
        expected = [
            'ar', 'bn', 'de', 'en', 'es', 'fa', 'fr', 'he', 'hi', 'id',
            'it', 'ja', 'ko', 'ms', 'nl', 'pl', 'pt', 'pt-br', 'ru', 'sw',
            'ta', 'th', 'tl', 'tr', 'uk', 'ur', 'vi', 'zh-cn', 'zh-tw',
        ]

        self.assertEqual(
            [locale for locale, _ in lang.supported_language_files()], expected)
        self.assertEqual(list(LOCALE_NAMES), expected)

    def test_all_supported_locale_tables_are_complete(self):
        result = subprocess.run(
            [sys.executable, "res/lang.py", "check"],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

    def test_selected_locales_have_no_untranslated_english_values(self):
        english = dict(lang.get_rust_entries(str(ROOT / 'src/lang/en.rs')))
        for locale, filename in lang.supported_language_files():
            if locale == 'en':
                continue
            current = dict(lang.get_rust_entries(filename))
            pending = entries_needing_translation(locale, english, current)
            self.assertFalse(
                pending,
                '%s still has untranslated English values: %s' %
                (locale, sorted(pending)[:5]),
            )


if __name__ == "__main__":
    unittest.main()
