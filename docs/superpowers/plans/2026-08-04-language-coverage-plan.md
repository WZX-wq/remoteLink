# Language Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every supported locale render all canonical product strings with reviewed translations where available and explicit English fallback everywhere else.

**Architecture:** Keep Rust as the single translation source used by Flutter through `platformFFI.translate`. Use `src/lang/en.rs` as the canonical key/value set, add a checked-in coverage test, and make missing locale entries explicit English values. Audit newer Flutter pages for user-visible strings that bypass Rust translation and route those strings through the existing `translate()` helper.

**Tech Stack:** Rust `HashMap` language tables, Rust unit tests, Flutter/Dart widgets, `rg`, Cargo, Flutter test.

---

### Task 1: Add translation-table coverage infrastructure

**Files:**
- Modify: `/Users/m4_txx/remoteLink/src/lang.rs`
- Test: `/Users/m4_txx/remoteLink/src/lang.rs` Rust test module

- [ ] **Step 1: Add a test-only registry for every supported table.**

  Add a `#[cfg(test)]` helper returning `LANGS` codes paired with each
  language map, including the `pt` -> `ptbr::T` mapping and both Chinese
  variants. Keep `template.rs` out of the supported registry because it is an
  empty authoring template.

- [ ] **Step 2: Write failing coverage tests before changing locale files.**

  Add tests that compare every table against `en::T` and fail with the locale
  code and key when a table has an empty value, a duplicate canonical key, or
  a missing English key. Add a placeholder parity assertion that compares `{}`
  and `%min%`/`%max%` tokens between the English value and the locale value.

  Run:

  ```bash
  cargo test -p rustdesk lang::test -- --nocapture
  ```

  Expected result before locale work: FAIL, reporting the first missing or
  empty locale entry instead of silently passing through the raw key.

- [ ] **Step 3: Keep the existing runtime fallback and make test diagnostics explicit.**

  Do not change `translate_with_lang` lookup order. The new test must explain
  that an explicit English value is acceptable for an unreviewed translation,
  while an empty value or missing canonical key is not.

### Task 2: Synchronize missing locale keys with explicit English fallback

**Files:**
- Modify: `/Users/m4_txx/remoteLink/res/lang.py`
- Modify: `/Users/m4_txx/remoteLink/src/lang/ar.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/be.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/bg.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/ca.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/cs.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/da.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/de.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/el.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/eo.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/es.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/et.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/eu.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/fa.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/fi.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/fr.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/ge.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/gu.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/he.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/hi.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/hr.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/hu.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/id.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/it.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/ja.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/ko.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/kz.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/lv.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/lt.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/ml.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/nb.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/nl.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/pl.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/ptbr.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/ro.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/ru.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/sc.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/sk.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/sl.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/sq.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/sr.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/sv.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/ta.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/th.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/tr.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/tw.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/uk.rs`
- Modify: `/Users/m4_txx/remoteLink/src/lang/vi.rs`

- [ ] **Step 1: Add a repeatable fallback synchronizer to `res/lang.py`.**

  Add a `fallback` command that reads the English entries with the existing
  `line_split()` parser, reads each supported `src/lang/*.rs` table, and
  inserts only absent keys immediately before `].iter().cloned().collect();`.
  Serialize Rust strings by escaping backslashes, quotes, carriage returns,
  newlines, and tabs. Never rewrite existing non-empty values, and skip
  `en.rs`, `template.rs`, and files not listed in `src/lang.rs`.

  Run the deterministic generator with:

  ```bash
  python3 res/lang.py fallback
  ```

  Running the command a second time must produce no diff. The generator must
  exit non-zero if the canonical English table cannot be parsed or a locale
  file has no closing table marker.

- [ ] **Step 2: Add reviewed translations for product-specific keys.**

  Before accepting English fallback, inspect keys added by the Kunqiong
  connection, membership, account deletion, screen-share, voice, privacy, and
  language-picker work. Add natural translations for the locales with existing
  maintained translations; leave long-tail locales at explicit English values.

- [ ] **Step 3: Run the coverage tests.**

  Run:

  ```bash
  cargo test -p rustdesk lang::test -- --nocapture
  ```

  Expected result: all locale tables pass key, empty-value, and placeholder
  checks.

### Task 3: Audit Flutter user-visible strings

**Files:**
- Inspect and modify only affected files under `/Users/m4_txx/remoteLink/flutter/lib/mobile/`
- Inspect and modify affected shared widgets under `/Users/m4_txx/remoteLink/flutter/lib/common/`
- Test: `/Users/m4_txx/remoteLink/flutter/test/kq_language_settings_test.dart`

- [ ] **Step 1: Produce the hardcoded-string audit.**

  Search `Text`, `label`, `hintText`, tooltip, toast, dialog, and error
  construction sites, then exclude logs, protocol strings, URLs, identifiers,
  product IDs, and values already passed through `translate()`.

  ```bash
  rg -n "Text\(|label:|hintText:|tooltip:|showToast\(|title:|message:" \
    flutter/lib/mobile flutter/lib/common
  ```

- [ ] **Step 2: Write a regression assertion for representative feature areas.**

  Extend the existing language test to require that connection, membership,
  account deletion, voice, screen-share, and privacy user-facing labels use
  `translate()` or an existing language helper rather than direct Chinese or
  English literals.

- [ ] **Step 3: Convert the audited literals.**

  Replace only user-visible literals with `translate('canonical English key')`
  or the existing page-local helper. Preserve dynamic interpolation and keep
  technical values unchanged. Add each new canonical key to `en.rs` before
  adding its locale values.

- [ ] **Step 4: Run Flutter language tests.**

  ```bash
  cd /Users/m4_txx/remoteLink/flutter
  /Users/m4_txx/.local/flutter/3.44.5/bin/flutter test test/kq_language_settings_test.dart
  ```

  Expected result: the existing language picker tests and the new hardcoded
  string assertions pass.

### Task 4: Verify runtime language behavior

**Files:**
- No production source changes expected.
- Verify: `/Users/m4_txx/remoteLink/flutter/build/ios_sim_arm64/Build/Products/Debug-iphonesimulator/Runner.app`

- [ ] **Step 1: Run the Rust and Flutter focused tests together.**

  ```bash
  cargo test -p rustdesk lang::test -- --nocapture
  cd /Users/m4_txx/remoteLink/flutter
  /Users/m4_txx/.local/flutter/3.44.5/bin/flutter test test/kq_language_settings_test.dart
  ```

- [ ] **Step 2: Build the arm64 simulator app with the existing simulator flow.**

  Use `flutter --config-only` with all five IAP defines, then Xcode with
  `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` and the booted simulator destination.
  Confirm the installed bundle version and launch the app.

- [ ] **Step 3: Perform the manual language smoke check.**

  Switch through supported locales and verify the connection page, recent
  connections, membership card, account deletion confirmation, voice controls,
  screen-share controls, privacy settings, and bottom navigation contain no
  blank labels, raw keys, or accidental Chinese fallback.

- [ ] **Step 4: Run final whitespace and scope checks.**

  ```bash
  git diff --check
  git status --short
  ```

  Confirm only translation resources, the translation coverage test, audited
  Flutter strings, and their focused tests are included in the feature change.
