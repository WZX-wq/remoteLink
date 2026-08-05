use hbb_common::regex::Regex;
use std::ops::Deref;

mod ar;
mod bn;
mod cn;
mod de;
mod en;
mod es;
mod fa;
mod fr;
mod he;
mod hi;
mod id;
mod it;
mod ja;
mod ko;
mod ms;
mod nl;
mod pl;
#[path = "lang/pt_PT.rs"]
mod pt;
mod ptbr;
mod ru;
mod sw;
mod ta;
mod th;
mod tl;
mod tr;
mod tw;
mod uk;
mod ur;
mod vi;

pub const LANGS: &[(&str, &str)] = &[
    ("ar", "العربية"),
    ("bn", "বাংলা"),
    ("de", "Deutsch"),
    ("en", "English"),
    ("es", "Español"),
    ("fa", "فارسی"),
    ("fr", "Français"),
    ("he", "עברית"),
    ("hi", "हिंदी"),
    ("id", "Bahasa Indonesia"),
    ("it", "Italiano"),
    ("ja", "日本語"),
    ("ko", "한국어"),
    ("ms", "Bahasa Melayu"),
    ("nl", "Nederlands"),
    ("pl", "Polski"),
    ("pt", "Português (Portugal)"),
    ("pt-br", "Português (Brasil)"),
    ("ru", "Русский"),
    ("sw", "Kiswahili"),
    ("ta", "தமிழ்"),
    ("th", "ไทย"),
    ("tl", "Filipino"),
    ("tr", "Türkçe"),
    ("uk", "Українська"),
    ("ur", "اردو"),
    ("vi", "Tiếng Việt"),
    ("zh-cn", "简体中文"),
    ("zh-tw", "繁體中文"),
];

#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn translate(name: String) -> String {
    let locale = sys_locale::get_locale().unwrap_or_default();
    translate_locale(name, &locale)
}

pub fn translate_locale(name: String, locale: &str) -> String {
    let locale = locale.to_lowercase();
    let mut lang = hbb_common::config::LocalConfig::get_option("lang").to_lowercase();
    if lang.is_empty() {
        lang = lang_from_locale(&locale);
    }
    translate_with_lang(name, &lang)
}

pub fn translate_explicit_locale(name: String, locale: &str) -> String {
    let locale = locale.to_lowercase();
    let mut lang = lang_from_locale(&locale);
    if lang.is_empty() {
        lang = hbb_common::config::LocalConfig::get_option("lang").to_lowercase();
    }
    translate_with_lang(name, &lang)
}

fn lang_from_locale(locale: &str) -> String {
    // zh_CN on Linux, zh-Hans-CN on mac, zh_CN_#Hans on Android
    if locale.starts_with("zh") {
        return (if locale.contains("tw")
            || locale.contains("hk")
            || locale.contains("mo")
            || locale.contains("hant")
        {
            "zh-tw"
        } else {
            "zh-cn"
        })
        .to_owned();
    }
    if locale.starts_with("pt") {
        let locale = locale.replace('_', "-");
        return if locale == "pt-br" { "pt-br" } else { "pt" }.to_owned();
    }
    locale
        .split("-")
        .next()
        .map(|x| x.split("_").next().unwrap_or_default())
        .unwrap_or_default()
        .to_owned()
}

fn translate_with_lang(name: String, lang: &str) -> String {
    let lang = lang.to_lowercase();
    let m = match lang.as_str() {
        "ar" => ar::T.deref(),
        "bn" => bn::T.deref(),
        "de" => de::T.deref(),
        "en" => en::T.deref(),
        "es" => es::T.deref(),
        "fa" => fa::T.deref(),
        "fr" => fr::T.deref(),
        "he" => he::T.deref(),
        "hi" => hi::T.deref(),
        "id" => id::T.deref(),
        "it" => it::T.deref(),
        "ja" => ja::T.deref(),
        "ko" => ko::T.deref(),
        "ms" => ms::T.deref(),
        "nl" => nl::T.deref(),
        "pl" => pl::T.deref(),
        "pt" | "pt-pt" | "pt_pt" => pt::T.deref(),
        "pt-br" | "pt_br" | "ptbr" | "br" => ptbr::T.deref(),
        "ru" => ru::T.deref(),
        "sw" => sw::T.deref(),
        "ta" => ta::T.deref(),
        "th" => th::T.deref(),
        "tl" => tl::T.deref(),
        "tr" => tr::T.deref(),
        "uk" => uk::T.deref(),
        "ur" => ur::T.deref(),
        "vi" => vi::T.deref(),
        "zh-cn" => cn::T.deref(),
        "zh-tw" => tw::T.deref(),
        _ => en::T.deref(),
    };
    let (name, placeholder_value) = extract_placeholder(&name);
    let replace = |s: &&str| {
        let mut s = s.to_string();
        if let Some(value) = placeholder_value.as_ref() {
            s = s.replace("{}", &value);
        }
        if !crate::is_rustdesk() {
            if s.contains("RustDesk") && !name.starts_with("upgrade_rustdesk_server_pro") {
                let app_name = crate::get_app_name();
                if !app_name.contains("RustDesk") {
                    s = s.replace("RustDesk", &app_name);
                } else {
                    // https://github.com/rustdesk/rustdesk-server-pro/issues/845
                    // If app_name contains "RustDesk" (e.g., "RustDesk-Admin"), we need to avoid
                    // replacing "RustDesk" within the already-substituted app_name, which would
                    // cause duplication like "RustDesk-Admin" -> "RustDesk-Admin-Admin".
                    //
                    // app_name only contains alphanumeric and hyphen.
                    const PLACEHOLDER: &str = "#A-P-P-N-A-M-E#";
                    if !s.contains(PLACEHOLDER) {
                        s = s.replace(&app_name, PLACEHOLDER);
                        s = s.replace("RustDesk", &app_name);
                        s = s.replace(PLACEHOLDER, &app_name);
                    } else {
                        // It's very unlikely to reach here.
                        // Skip replacement to avoid incorrect result.
                    }
                }
            }
        }
        s
    };
    if let Some(v) = m.get(&name as &str) {
        if !v.is_empty() {
            return replace(v);
        }
    }
    if lang != "en" {
        if let Some(v) = en::T.get(&name as &str) {
            if !v.is_empty() {
                return replace(v);
            }
        }
    }
    replace(&name.as_str())
}

// Matching pattern is {}
// Write {value} in the UI and {} in the translation file
//
// Example:
// Write in the UI: translate("There are {24} hours in a day")
// Write in the translation file: ("There are {} hours in a day", "{} hours make up a day")
fn extract_placeholder(input: &str) -> (String, Option<String>) {
    if let Ok(re) = Regex::new(r#"\{(.*?)\}"#) {
        if let Some(captures) = re.captures(input) {
            if let Some(inner_match) = captures.get(1) {
                let name = re.replace(input, "{}").to_string();
                let value = inner_match.as_str().to_string();
                return (name, Some(value));
            }
        }
    }
    (input.to_string(), None)
}

#[cfg(test)]
mod test {
    use std::collections::HashMap;
    use hbb_common::config::LocalConfig;

    fn supported_tables() -> Vec<(&'static str, &'static HashMap<&'static str, &'static str>)> {
        vec![
            ("ar", ar::T.deref()),
            ("bn", bn::T.deref()),
            ("de", de::T.deref()),
            ("en", en::T.deref()),
            ("es", es::T.deref()),
            ("fa", fa::T.deref()),
            ("fr", fr::T.deref()),
            ("he", he::T.deref()),
            ("hi", hi::T.deref()),
            ("id", id::T.deref()),
            ("it", it::T.deref()),
            ("ja", ja::T.deref()),
            ("ko", ko::T.deref()),
            ("ms", ms::T.deref()),
            ("nl", nl::T.deref()),
            ("pl", pl::T.deref()),
            ("pt", pt::T.deref()),
            ("pt-br", ptbr::T.deref()),
            ("ru", ru::T.deref()),
            ("sw", sw::T.deref()),
            ("ta", ta::T.deref()),
            ("th", th::T.deref()),
            ("tl", tl::T.deref()),
            ("tr", tr::T.deref()),
            ("uk", uk::T.deref()),
            ("ur", ur::T.deref()),
            ("vi", vi::T.deref()),
            ("zh-cn", cn::T.deref()),
            ("zh-tw", tw::T.deref()),
        ]
    }

    fn placeholders(value: &str) -> Vec<&str> {
        ["{}", "%min%", "%max%"]
            .into_iter()
            .filter(|placeholder| value.contains(placeholder))
            .collect()
    }

    #[test]
    fn every_supported_locale_covers_the_english_key_set() {
        let tables = supported_tables();
        let english = tables
            .iter()
            .find(|(locale, _)| *locale == "en")
            .expect("English translation table must exist")
            .1;

        for (locale, table) in tables {
            for key in table.keys() {
                assert!(
                    english.contains_key(key),
                    "locale {locale} has key outside the English baseline {key:?}",
                );
            }
            for (key, english_value) in english {
                let value = table.get(key).unwrap_or_else(|| {
                    panic!("locale {locale} is missing canonical key {key:?}")
                });
                assert!(!value.is_empty(), "locale {locale} has empty key {key:?}");
                assert_eq!(
                    placeholders(english_value),
                    placeholders(value),
                    "locale {locale} changed placeholders for {key:?}",
                );
            }
        }
    }

    #[test]
    fn test_extract_placeholders() {
        use super::extract_placeholder as f;

        assert_eq!(f(""), ("".to_string(), None));
        assert_eq!(
            f("{3} sessions"),
            ("{} sessions".to_string(), Some("3".to_string()))
        );
        assert_eq!(f(" } { "), (" } { ".to_string(), None));
        // Allow empty value
        assert_eq!(
            f("{} sessions"),
            ("{} sessions".to_string(), Some("".to_string()))
        );
        // Match only the first one
        assert_eq!(
            f("{2} times {4} makes {8}"),
            ("{} times {4} makes {8}".to_string(), Some("2".to_string()))
        );
    }

    #[test]
    fn test_translate_locale_prefers_explicit_locale_for_flutter() {
        let prev_lang = LocalConfig::get_option("lang");
        LocalConfig::set_option("lang".to_owned(), "en".to_owned());

        let translated =
            super::translate_explicit_locale("Current connections".to_owned(), "zh-tw");

        LocalConfig::set_option("lang".to_owned(), prev_lang);
        assert_eq!(translated, "目前連線");
    }

    #[test]
    fn test_portuguese_locale_selects_the_correct_region_table() {
        assert_eq!(super::lang_from_locale("pt"), "pt");
        assert_eq!(super::lang_from_locale("pt-PT"), "pt");
        assert_eq!(super::lang_from_locale("pt_BR"), "pt-br");
    }
}
