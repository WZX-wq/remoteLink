# Language Coverage Design

## Goal

Ensure every supported locale can render all translation keys used by the
application without showing an empty string, raw internal key, or unrelated
Chinese text. Existing reviewed translations remain authoritative. Missing or
unreviewed translations use English as the explicit fallback.

## Current Architecture

- Rust owns the translation tables in `src/lang/*.rs`.
- `src/lang/en.rs` is the canonical key and English-value table.
- Flutter calls `platformFFI.translate(name, locale)` through `translate()` in
  `flutter/lib/common.dart`.
- The Rust lookup already falls back to the English table, then to the input
  key when no value exists.
- Some newer mobile pages also contain local language maps or direct display
  text; these are part of the audit because they can bypass Rust translation.

## Design

### 1. Canonical key coverage

Use the English table as the canonical set. Add a repository test that parses
the Rust translation tables and reports:

- keys missing from a locale;
- keys whose value is empty;
- duplicate keys in a locale;
- locale modules declared in `LANGS` but missing from the source tree.

The test must cover every locale listed in `src/lang.rs`, including the
Chinese variants and regional Portuguese mapping.

### 2. Translation policy

- Preserve existing non-empty translations.
- Add translations for high-use product-specific text and recently added
  connection, membership, account, voice, screen-share, and privacy flows.
- For a key without a reviewed translation, add the English value explicitly
  in the locale table. This makes the fallback intentional and detectable,
  rather than leaving a raw key or empty value.
- Do not translate product names, URLs, identifiers, product IDs, or technical
  tokens that must remain unchanged.
- Preserve `{}` placeholders, `%min%`/`%max%` tokens, and capitalization rules.

### 3. Flutter hardcoded text audit

Search mobile and shared Flutter code for user-visible `Text`, `label`,
`hintText`, tooltip, toast, dialog, and error strings that bypass `translate()`.
Convert only user-facing static strings to the existing translation API. Keep
logs, protocol values, URLs, code identifiers, and accessibility semantics
outside the translation table unless they are displayed to users.

### 4. Runtime fallback behavior

Keep the current lookup order:

1. selected locale value;
2. English value;
3. original key as a last-resort diagnostic.

The coverage test should make step 3 unreachable for all canonical keys. The
last-resort behavior remains for server errors or dynamically supplied text.

## Verification

- Rust translation coverage test passes for every supported locale.
- Placeholder parity test confirms each locale preserves the placeholders in
  the English source.
- Flutter language tests cover the mobile language picker and representative
  connection, membership, account deletion, voice, screen-share, and error
  strings.
- Static audit confirms no newly converted user-facing string bypasses the
  translation API.
- Build one simulator debug app and manually switch through the supported
  language picker, checking that no visible label is blank, Chinese-only, or a
  raw key when English fallback is expected.

## Scope Boundaries

This change does not alter language selection behavior, locale identifiers,
server APIs, membership logic, or remote connection protocol behavior. It also
does not claim professional human review for languages that use the explicit
English fallback.
