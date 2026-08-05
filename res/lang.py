#!/usr/bin/env python3

import os
import glob
import sys
import csv
import re


LANGS_TO_FILES = {
    "zh-cn": "cn",
    "zh-tw": "tw",
    "pt": "pt_PT",
    "pt-br": "ptbr",
}


def get_lang(lang):
    out = {}
    for ln in open('./src/lang/%s.rs' % lang, encoding='utf8'):
        ln = ln.strip()
        if ln.startswith('("'):
            k, v = line_split(ln)
            out[k] = v
    return out


def line_split(line):
    toks = line.split('", "')
    if len(toks) != 2:
        print(line)
        assert 0
    # Replace fixed position.
    # Because toks[1] may be v") or v"),
    k = toks[0][toks[0].find('"') + 1:]
    v = toks[1][:toks[1].rfind('"')]
    return k, v


def rust_string(value):
    return (
        value.replace('\\', '\\\\')
        .replace('"', '\\"')
        .replace('\r', '\\r')
        .replace('\n', '\\n')
        .replace('\t', '\\t')
    )


def decode_rust_string(value):
    out = []
    escaped = False
    for char in value:
        if not escaped:
            if char == '\\':
                escaped = True
            else:
                out.append(char)
            continue
        out.append({
            'n': '\n',
            'r': '\r',
            't': '\t',
            '"': '"',
            '\\': '\\',
        }.get(char, '\\' + char))
        escaped = False
    if escaped:
        raise ValueError('unterminated Rust string escape')
    return ''.join(out)


def parse_rust_entry(line):
    line = line.strip()
    if not line.startswith('("'):
        return None

    values = []
    index = 1
    while index < len(line) and len(values) < 2:
        if line[index] != '"':
            raise ValueError('translation entry must contain quoted strings: ' + line)
        index += 1
        chars = []
        escaped = False
        while index < len(line):
            char = line[index]
            index += 1
            if escaped:
                chars.append('\\' + char)
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                break
            else:
                chars.append(char)
        else:
            raise ValueError('unterminated translation entry: ' + line)
        values.append(decode_rust_string(''.join(chars)))
        while index < len(line) and line[index] in ' ,':
            index += 1
    if len(values) != 2:
        raise ValueError('translation entry must contain a key and value: ' + line)
    return values[0], values[1]


def get_rust_entries(filename, reject_duplicates=True):
    entries = []
    seen = set()
    with open(filename, encoding='utf8') as source:
        for line_number, line in enumerate(source, 1):
            entry = parse_rust_entry(line)
            if entry is None:
                continue
            key, value = entry
            if key in seen:
                if reject_duplicates:
                    raise ValueError('%s:%d duplicates key %r' % (filename, line_number, key))
                entries = [(old_key, old_value) for old_key, old_value in entries if old_key != key]
            seen.add(key)
            entries.append((key, value))
    return entries


def supported_language_files():
    with open('./src/lang.rs', encoding='utf8') as source_file:
        source = source_file.read()
    section = source[source.index('pub const LANGS'):source.index('];', source.index('pub const LANGS'))]
    language_codes = re.findall(r'\("([a-z-]+)",\s*"', section)
    files = []
    for code in language_codes:
        filename = LANGS_TO_FILES.get(code, code)
        path = './src/lang/%s.rs' % filename
        if not os.path.exists(path):
            raise FileNotFoundError('LANGS entry %s has no file %s' % (code, path))
        files.append((code, path))
    return files


def placeholder_tokens(value):
    return re.findall(r'\{\}|%min%|%max%', value)


def canonical_english_entries(language_files):
    english = get_rust_entries('./src/lang/en.rs', reject_duplicates=False)
    canonical = dict(english)
    for _, filename in language_files:
        for key, _ in get_rust_entries(filename, reject_duplicates=False):
            canonical.setdefault(key, key)
    return list(canonical.items())


def synchronize_table(locale, filename, english):
    english_by_key = dict(english)
    with open(filename, encoding='utf8') as source:
        lines = source.readlines()
    existing = dict(get_rust_entries(filename, reject_duplicates=False))
    last_entry_line = {}
    for line_number, line in enumerate(lines):
        entry = parse_rust_entry(line)
        if entry is not None:
            last_entry_line[entry[0]] = line_number
    changed = []
    output = []
    inserted = False
    for line_number, line in enumerate(lines):
        entry = parse_rust_entry(line)
        if entry is not None and entry[0] in english_by_key and entry[1] == '':
            indent = line[:len(line) - len(line.lstrip())]
            key = entry[0]
            line = '%s("%s", "%s"),\n' % (
                indent,
                rust_string(key),
                rust_string(english_by_key[key]),
            )
            changed.append(key)
        if entry is not None and last_entry_line[entry[0]] != line_number:
            changed.append(entry[0])
            continue
        if '].iter().cloned().collect();' in line:
            missing = [key for key, _ in english if key not in existing]
            if missing:
                output.extend(
                    '        ("%s", "%s"),\n' %
                    (rust_string(key), rust_string(english_by_key[key]))
                    for key in missing
                )
                changed.extend(missing)
            inserted = True
        output.append(line)
    if not inserted:
        raise ValueError('%s has no translation table closing marker' % filename)
    if changed:
        with open(filename, 'w', encoding='utf8') as target:
            target.writelines(output)
        print('%s: synchronized %d entries' % (locale, len(changed)))


def fallback():
    language_files = supported_language_files()
    english = canonical_english_entries(language_files)
    for locale, filename in language_files:
        synchronize_table(locale, filename, english)


def check():
    language_files = supported_language_files()
    english = get_rust_entries('./src/lang/en.rs')
    english_by_key = dict(english)
    errors = []
    for locale, filename in language_files:
        try:
            entries = get_rust_entries(filename)
        except ValueError as error:
            errors.append(str(error))
            continue
        translations = dict(entries)
        for key, english_value in english:
            value = translations.get(key)
            if value is None:
                errors.append('%s is missing canonical key %r' % (locale, key))
            elif not value:
                errors.append('%s has empty value for %r' % (locale, key))
            elif placeholder_tokens(value) != placeholder_tokens(english_value):
                errors.append('%s changes placeholders for %r' % (locale, key))
        for key in translations:
            if key not in english_by_key:
                errors.append('%s has key outside English baseline %r' % (locale, key))
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print('All supported language tables are complete.')
    return 0


def main():
    if len(sys.argv) == 1:
        expand()
    elif sys.argv[1] == '1':
        to_csv()
    elif sys.argv[1] == 'fallback':
        fallback()
    elif sys.argv[1] == 'check':
        return check()
    else:
        to_rs(sys.argv[1])
    return 0


def expand():
    for fn in glob.glob('./src/lang/*.rs'):
        lang = os.path.basename(fn)[:-3]
        if lang in ['en', 'template']: continue
        print(lang)
        dict = get_lang(lang)
        fw = open("./src/lang/%s.rs" % lang, "wt", encoding='utf8')
        for line in open('./src/lang/template.rs', encoding='utf8'):
            line_strip = line.strip()
            if line_strip.startswith('("'):
                k, v = line_split(line_strip)
                if k in dict:
                    # embraced with " to avoid empty v
                    line = line.replace('"%s"' % v, '"%s"' % dict[k])
                else:
                    line = line.replace(v, "")
                fw.write(line)
            else:
                fw.write(line)
        fw.close()


def to_csv():
    for fn in glob.glob('./src/lang/*.rs'):
        lang = os.path.basename(fn)[:-3]
        csvfile = open('./src/lang/%s.csv' % lang, "wt", encoding='utf8')
        csvwriter = csv.writer(csvfile)
        for line in open(fn, encoding='utf8'):
            line_strip = line.strip()
            if line_strip.startswith('("'):
                k, v = line_split(line_strip)
                csvwriter.writerow([k, v])
        csvfile.close()


def to_rs(lang):
    csvfile = open('%s.csv' % lang, "rt", encoding='utf8')
    fw = open("./src/lang/%s.rs" % lang, "wt", encoding='utf8')
    fw.write('''lazy_static::lazy_static! {
pub static ref T: std::collections::HashMap<&'static str, &'static str> =
    [
''')
    for row in csv.reader(csvfile):
        fw.write('        ("%s", "%s"),\n' % (row[0].replace('"', '\"'), row[1].replace('"', '\"')))
    fw.write('''    ].iter().cloned().collect();
}
''')
    fw.close()


if __name__ == '__main__':
    sys.exit(main())
