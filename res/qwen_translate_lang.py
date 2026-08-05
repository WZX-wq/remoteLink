#!/usr/bin/env python3

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

import lang


API_URL = 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions'
MODEL = 'qwen3.8-max'
PLACEHOLDER_PATTERN = re.compile(r'\{\}|%min%|%max%')
LOCALE_NAMES = {
    'ar': 'Arabic',
    'bn': 'Bengali',
    'de': 'German',
    'en': 'English',
    'es': 'Spanish',
    'fa': 'Persian',
    'fr': 'French',
    'he': 'Hebrew',
    'hi': 'Hindi',
    'id': 'Indonesian',
    'it': 'Italian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'ms': 'Malay',
    'nl': 'Dutch',
    'pl': 'Polish',
    'pt': 'European Portuguese',
    'pt-br': 'Brazilian Portuguese',
    'ru': 'Russian',
    'sw': 'Swahili',
    'ta': 'Tamil',
    'th': 'Thai',
    'tl': 'Tagalog',
    'tr': 'Turkish',
    'uk': 'Ukrainian',
    'ur': 'Urdu',
    'vi': 'Vietnamese',
    'zh-cn': 'Simplified Chinese',
    'zh-tw': 'Traditional Chinese',
}
LOCALE_FILES = {
    'pt': 'pt_PT',
    'pt-br': 'ptbr',
    'zh-cn': 'cn',
    'zh-tw': 'tw',
}
# These values are locale-neutral product identifiers or technical tokens, not
# untranslated interface prose. URLs are also intentionally locale-neutral.
INVARIANT_VALUES = {
    'ID', 'OK', 'FPS', 'AV1', 'VP8', 'VP9', 'H264', 'H265', 'HD',
    'Kunqiong Remote Desktop', 'SD / 30 FPS', '1080p HD / 60 FPS',
    'WeChat QR', 'WeChat Pay', 'Alipay', 'Telegram bot', 'ScrollAuto',
    'ScrollEdge', 'upgrade_rustdesk_server_pro_{}_tip',
    'confirm-clear-shortcuts-inhibitor-permission-tip',
    'WOL', 'Token', 'System', 'Feedback', 'Updates', 'Links',
}


def placeholder_tokens(value):
    return PLACEHOLDER_PATTERN.findall(value)


def parse_translation_content(content):
    content = content.strip()
    if content.startswith('```'):
        lines = content.splitlines()
        if len(lines) < 3 or not lines[-1].strip().startswith('```'):
            raise ValueError('translation response has an incomplete code fence')
        content = '\n'.join(lines[1:-1]).strip()
    try:
        translations = json.loads(content)
    except json.JSONDecodeError as error:
        raise ValueError('translation response is not JSON') from error
    if not isinstance(translations, dict):
        raise ValueError('translation response must be a JSON object')
    return translations


def is_invariant_value(value):
    return value in INVARIANT_VALUES or value.startswith(('https://', 'http://'))


def validate_translations(source, translations, strict=False):
    if set(translations) != set(source):
        missing = sorted(set(source) - set(translations))
        unexpected = sorted(set(translations) - set(source))
        raise ValueError(
            'translation response keys do not match source '
            '(missing=%r, unexpected=%r)' % (missing[:3], unexpected[:3])
        )
    for key, source_value in source.items():
        translation = translations[key]
        if not isinstance(translation, str) or not translation.strip():
            raise ValueError('translation is empty for %r' % key)
        if placeholder_tokens(translation) != placeholder_tokens(source_value):
            raise ValueError('translation changes placeholders for %r' % key)
        if strict and translation == source_value and not is_invariant_value(source_value):
            raise ValueError('translation leaves unchanged English prose for %r' % key)


def locale_filename(locale):
    return './src/lang/%s.rs' % LOCALE_FILES.get(locale, locale)


def entries_needing_translation(locale, english, current):
    pending = {}
    for key, english_value in english.items():
        value = current.get(key, '')
        if not value or (value == english_value and not is_invariant_value(english_value)):
            pending[key] = english_value
    return pending


def load_checkpoint(filename, source=None):
    if not filename.exists():
        return {}
    with filename.open(encoding='utf8') as checkpoint_file:
        data = json.load(checkpoint_file)
    if not isinstance(data, dict) or not all(
            isinstance(key, str) and isinstance(value, str)
            for key, value in data.items()):
        raise ValueError('translation checkpoint must be a JSON string map')
    if source is not None:
        validate_checkpoint_source(filename, source)
    return data


def checkpoint_metadata_filename(filename):
    return filename.with_suffix('.meta.json')


def source_digest(source):
    canonical = json.dumps(source, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(canonical.encode('utf8')).hexdigest()


def save_checkpoint(filename, translations, source=None):
    filename.parent.mkdir(parents=True, exist_ok=True)
    temporary = filename.with_suffix(filename.suffix + '.tmp')
    with temporary.open('w', encoding='utf8') as target:
        json.dump(translations, target, ensure_ascii=False, indent=2, sort_keys=True)
        target.write('\n')
    temporary.replace(filename)
    if source is not None:
        metadata_filename = checkpoint_metadata_filename(filename)
        metadata_temporary = metadata_filename.with_suffix(metadata_filename.suffix + '.tmp')
        with metadata_temporary.open('w', encoding='utf8') as target:
            json.dump({'source_sha256': source_digest(source)}, target)
            target.write('\n')
        metadata_temporary.replace(metadata_filename)


def validate_checkpoint_source(filename, source):
    metadata_filename = checkpoint_metadata_filename(filename)
    if not metadata_filename.exists():
        return
    with metadata_filename.open(encoding='utf8') as metadata_file:
        metadata = json.load(metadata_file)
    if metadata.get('source_sha256') != source_digest(source):
        raise ValueError(
            'translation checkpoint source changed; review or remove %s and resume' % filename
        )


def validate_checkpoint(english, checkpoint):
    unexpected = set(checkpoint) - set(english)
    if unexpected:
        raise ValueError('translation checkpoint has unknown keys: %r' % sorted(unexpected)[:3])
    for key, value in checkpoint.items():
        validate_translations({key: english[key]}, {key: value})


def build_translation_prompt(locale, source):
    language = LOCALE_NAMES[locale]
    must_change = sorted(
        value for value in set(source.values()) if not is_invariant_value(value))
    forbidden = json.dumps(must_change, ensure_ascii=False)
    return (
        'Translate every JSON value from English into %s for a desktop and mobile '
        'remote-control application. Return exactly one JSON object with the same '
        'keys and translated string values. Preserve {}, %%min%%, %%max%%, and technical '
        'acronyms such as ID, FPS, AV1, VP8, VP9, H264, and H265 exactly. Preserve '
        'the product name Kunqiong Remote Desktop and URLs. Translate every other '
        'ordinary interface label into idiomatic native wording. Do not retain English '
        'loanwords for ordinary labels: use a native synonym instead. Every value in '
        'the forbidden list must differ byte-for-byte from its source value. Do not '
        'include markdown, analysis, or commentary. The following source values '
        'must not be returned unchanged: %s. Unchanged values forbidden: %s\n\n%s'
    ) % (language, forbidden, forbidden, json.dumps(source, ensure_ascii=False))


def translate_batch(locale, source, api_key, model):
    prompt = build_translation_prompt(locale, source)
    body = json.dumps({
        'model': model,
        'temperature': 0.3,
        'enable_thinking': False,
        'messages': [
            {'role': 'system', 'content': 'You are a precise software localization translator.'},
            {'role': 'user', 'content': prompt},
        ],
    }, ensure_ascii=False).encode('utf8')
    request = urllib.request.Request(
        API_URL,
        data=body,
        headers={
            'Authorization': 'Bearer ' + api_key,
            'Content-Type': 'application/json',
        },
        method='POST',
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode('utf8', errors='replace')[:1000]
        raise RuntimeError('DashScope request failed with HTTP %d: %s' % (error.code, detail)) from error
    except (TimeoutError, urllib.error.URLError, OSError) as error:
        raise RuntimeError(
            'DashScope is temporarily unavailable; completed batches are saved: %s' % error
        ) from error
    content = payload.get('choices', [{}])[0].get('message', {}).get('content')
    if not isinstance(content, str):
        raise RuntimeError('DashScope response does not contain translated content')
    translations = parse_translation_content(content)
    validate_translations(source, translations, strict=True)
    return translations


def write_locale_table(filename, entries):
    with open(filename, 'w', encoding='utf8') as target:
        target.write('''lazy_static::lazy_static! {
pub static ref T: std::collections::HashMap<&'static str, &'static str> =
    [
''')
        for key, value in entries:
            target.write('        ("%s", "%s"),\n' %
                         (lang.rust_string(key), lang.rust_string(value)))
        target.write('''    ].iter().cloned().collect();
}
''')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--locale',
        choices=sorted(locale for locale in LOCALE_NAMES if locale != 'en'),
        required=True,
    )
    parser.add_argument('--batch-size', type=int, default=20)
    parser.add_argument('--limit', type=int)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--model', default=os.environ.get('KQ_DASHSCOPE_MODEL', MODEL))
    parser.add_argument('--checkpoint-dir', default='.kq-translation-checkpoints')
    args = parser.parse_args()
    if args.batch_size < 1:
        parser.error('--batch-size must be positive')

    english_entries = lang.get_rust_entries('./src/lang/en.rs')
    english = dict(english_entries)
    filename = locale_filename(args.locale)
    current = dict(lang.get_rust_entries(filename)) if os.path.exists(filename) else {}
    checkpoint_filename = pathlib.Path(args.checkpoint_dir) / (args.locale + '.json')
    checkpoint = load_checkpoint(checkpoint_filename)
    validate_checkpoint_source(checkpoint_filename, english)
    validate_checkpoint(english, checkpoint)
    current.update(checkpoint)
    pending = entries_needing_translation(args.locale, english, current)
    items = list(pending.items())
    if args.limit is not None:
        items = items[:args.limit]
    if not items:
        if args.apply:
            incomplete = [key for key, _ in english_entries if key not in current]
            if incomplete:
                print('%s: %d entries remain before %s can be written' %
                      (args.locale, len(incomplete), filename))
                return 0
            write_locale_table(filename, [(key, current[key]) for key, _ in english_entries])
            print('%s: no API work needed; wrote %s' % (args.locale, filename))
        else:
            print('%s: no API work needed; checkpoint/current table is complete' % args.locale)
        return 0
    api_key = os.environ.get('KQ_DASHSCOPE_API_KEY', '').strip()
    if not api_key:
        parser.error('KQ_DASHSCOPE_API_KEY is required for translation work')
    try:
        for start in range(0, len(items), args.batch_size):
            batch = dict(items[start:start + args.batch_size])
            translations = translate_batch(args.locale, batch, api_key, args.model)
            checkpoint.update(translations)
            save_checkpoint(checkpoint_filename, checkpoint, english)
            current.update(translations)
            print('%s: translated %d/%d entries using %s' %
                  (args.locale, min(start + len(batch), len(items)), len(items), args.model))
            if start + len(batch) < len(items):
                time.sleep(0.2)
    except (RuntimeError, ValueError, urllib.error.URLError) as error:
        print('%s: paused after saving completed batches: %s' %
              (args.locale, error), file=sys.stderr)
        return 1
    if args.apply:
        incomplete = [key for key, _ in english_entries if key not in current]
        if incomplete:
            print('%s: checkpoint saved; %d entries remain before %s can be written' %
                  (args.locale, len(incomplete), filename))
            return 0
        write_locale_table(filename, [(key, current[key]) for key, _ in english_entries])
        print('%s: wrote %s' % (args.locale, filename))
    elif items:
        print('%s: dry run complete; rerun with --apply to write translations' % args.locale)


if __name__ == '__main__':
    sys.exit(main() or 0)
