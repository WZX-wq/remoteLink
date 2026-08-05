#!/usr/bin/env python3

import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch


sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from qwen_translate_lang import (
    build_translation_prompt,
    entries_needing_translation,
    is_invariant_value,
    load_checkpoint,
    parse_translation_content,
    save_checkpoint,
    source_digest,
    translate_batch,
    validate_translations,
)


class QwenTranslationTest(unittest.TestCase):
    def test_parses_a_fenced_json_response_and_preserves_placeholders(self):
        content = '''```json
{
  "Connect": "اتصل",
  "Downloading {}": "تنزيل {}",
  "length %min% to %max%": "الطول من %min% إلى %max%"
}
```'''
        source = {
            "Connect": "Connect",
            "Downloading {}": "Downloading {}",
            "length %min% to %max%": "length %min% to %max%",
        }

        translations = parse_translation_content(content)

        validate_translations(source, translations)
        self.assertEqual(translations["Connect"], "اتصل")

    def test_rejects_a_missing_or_changed_placeholder(self):
        source = {"Downloading {}": "Downloading {}"}

        with self.assertRaisesRegex(ValueError, "placeholders"):
            validate_translations(source, {"Downloading {}": "تنزيل"})

    def test_checkpoint_persists_completed_batches_for_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = pathlib.Path(directory) / 'bn.json'
            completed = {
                'Connect': 'সংযোগ করুন',
                'Downloading {}': '{} ডাউনলোড হচ্ছে',
            }
            source = {
                'Connect': 'Connect',
                'Downloading {}': 'Downloading {}',
            }

            save_checkpoint(checkpoint, completed, source)

            self.assertEqual(load_checkpoint(checkpoint, source), completed)

    def test_checkpoint_rejects_changed_english_source(self):
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = pathlib.Path(directory) / 'bn.json'
            completed = {'Connect': 'সংযোগ করুন'}
            source = {'Connect': 'Connect'}

            save_checkpoint(checkpoint, completed, source)

            with self.assertRaisesRegex(ValueError, 'source changed'):
                load_checkpoint(checkpoint, {'Connect': 'Connect to device'})

    def test_source_digest_is_order_independent(self):
        self.assertEqual(
            source_digest({'a': 'A', 'b': 'B'}),
            source_digest({'b': 'B', 'a': 'A'}),
        )

    def test_strict_scan_allows_only_true_invariant_english_values(self):
        english = {
            'Kunqiong Remote Desktop': 'Kunqiong Remote Desktop',
            'doc': 'https://example.com/docs',
            'HD': 'HD',
            'Folder': 'Folder',
        }
        current = english.copy()

        self.assertEqual(
            entries_needing_translation('de', english, current),
            {'Folder': 'Folder'},
        )

    def test_wol_is_treated_as_a_technical_invariant(self):
        self.assertTrue(is_invariant_value('WOL'))

    def test_token_is_treated_as_a_technical_invariant(self):
        self.assertTrue(is_invariant_value('Token'))

    def test_strict_response_rejects_untranslated_interface_text(self):
        with self.assertRaisesRegex(ValueError, 'unchanged English'):
            validate_translations(
                {'Folder': 'Folder'},
                {'Folder': 'Folder'},
                strict=True,
            )

    def test_prompt_marks_regular_english_labels_as_forbidden_unchanged_values(self):
        prompt = build_translation_prompt(
            'de',
            {
                'Folder': 'Folder',
                'Kunqiong Remote Desktop': 'Kunqiong Remote Desktop',
            },
        )

        self.assertIn('must not be returned unchanged', prompt)
        self.assertIn('Unchanged values forbidden: ["Folder"]', prompt)

    @patch('qwen_translate_lang.urllib.request.urlopen')
    def test_translation_timeout_is_reported_as_recoverable(self, urlopen):
        urlopen.side_effect = TimeoutError('timed out')

        with self.assertRaisesRegex(RuntimeError, 'temporarily unavailable'):
            translate_batch('ar', {'Loading': 'Loading'}, 'test-key', 'test-model')

    def test_translation_requests_disable_deep_reasoning_for_short_ui_copy(self):
        source = pathlib.Path(__file__).with_name('qwen_translate_lang.py').read_text()

        self.assertIn("'enable_thinking': False", source)


if __name__ == "__main__":
    unittest.main()
