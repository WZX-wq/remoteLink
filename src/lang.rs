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
    if let Some(value) = kq_timeout_translation(&name, &lang) {
        let mut value = value.to_owned();
        if let Some(placeholder) = placeholder_value.as_ref() {
            value = value.replace("{}", placeholder);
        }
        return value;
    }
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

fn kq_timeout_translation(name: &str, lang: &str) -> Option<&'static str> {
    let value = match name {
        "Automatic disconnect range: 10-65535 minutes" => match lang {
            "ar" => "نطاق قطع الاتصال التلقائي: 10-65535 دقيقة",
            "bn" => "স্বয়ংক্রিয় সংযোগ বিচ্ছিন্নতার পরিসর: 10-65535 মিনিট",
            "de" => "Bereich für automatische Trennung: 10-65535 Minuten",
            "en" => "Automatic disconnect range: 10-65535 minutes",
            "es" => "Rango de desconexión automática: 10-65535 minutos",
            "fa" => "محدوده قطع خودکار اتصال: ۱۰ تا ۶۵۵۳۵ دقیقه",
            "fr" => "Plage de déconnexion automatique : 10-65535 minutes",
            "he" => "טווח ניתוק אוטומטי: 10-65535 דקות",
            "hi" => "स्वचालित डिस्कनेक्ट सीमा: 10-65535 मिनट",
            "id" => "Rentang pemutusan otomatis: 10-65535 menit",
            "it" => "Intervallo di disconnessione automatica: 10-65535 minuti",
            "ja" => "自動切断の範囲: 10-65535 分",
            "ko" => "자동 연결 해제 범위: 10-65535분",
            "ms" => "Julat pemutusan automatik: 10-65535 minit",
            "nl" => "Bereik voor automatische verbreking: 10-65535 minuten",
            "pl" => "Zakres automatycznego rozłączania: 10-65535 minut",
            "pt" => "Intervalo de desligamento automático: 10-65535 minutos",
            "pt-br" => "Faixa de desconexão automática: 10-65535 minutos",
            "ru" => "Диапазон автоматического отключения: 10-65535 минут",
            "sw" => "Masafa ya kukata muunganisho kiotomatiki: dakika 10-65535",
            "ta" => "தானியங்கி துண்டிப்பு வரம்பு: 10-65535 நிமிடங்கள்",
            "th" => "ช่วงเวลาตัดการเชื่อมต่ออัตโนมัติ: 10-65535 นาที",
            "tl" => "Saklaw ng awtomatikong pagdiskonekta: 10-65535 minuto",
            "tr" => "Otomatik bağlantı kesme aralığı: 10-65535 dakika",
            "uk" => "Діапазон автоматичного відключення: 10-65535 хвилин",
            "ur" => "خودکار ڈس کنکشن کی حد: 10-65535 منٹ",
            "vi" => "Phạm vi tự động ngắt kết nối: 10-65535 phút",
            "zh-cn" => "自动断开范围：10-65535 分钟",
            "zh-tw" => "自動中斷範圍：10-65535 分鐘",
            _ => "Automatic disconnect range: 10-65535 minutes",
        },
        "Enter a value from 10 to 65535 minutes" => match lang {
            "ar" => "أدخل قيمة من 10 إلى 65535 دقيقة",
            "bn" => "10 থেকে 65535 মিনিটের মধ্যে একটি মান লিখুন",
            "de" => "Geben Sie einen Wert zwischen 10 und 65535 Minuten ein",
            "en" => "Enter a value from 10 to 65535 minutes",
            "es" => "Introduce un valor entre 10 y 65535 minutos",
            "fa" => "مقداری بین ۱۰ تا ۶۵۵۳۵ دقیقه وارد کنید",
            "fr" => "Saisissez une valeur entre 10 et 65535 minutes",
            "he" => "הזן ערך בין 10 ל-65535 דקות",
            "hi" => "10 से 65535 मिनट के बीच मान दर्ज करें",
            "id" => "Masukkan nilai dari 10 hingga 65535 menit",
            "it" => "Inserisci un valore da 10 a 65535 minuti",
            "ja" => "10～65535 分の値を入力してください",
            "ko" => "10~65535분 사이의 값을 입력하세요",
            "ms" => "Masukkan nilai antara 10 hingga 65535 minit",
            "nl" => "Voer een waarde van 10 tot 65535 minuten in",
            "pl" => "Wprowadź wartość od 10 do 65535 minut",
            "pt" => "Introduza um valor entre 10 e 65535 minutos",
            "pt-br" => "Digite um valor entre 10 e 65535 minutos",
            "ru" => "Введите значение от 10 до 65535 минут",
            "sw" => "Weka thamani kutoka dakika 10 hadi 65535",
            "ta" => "10 முதல் 65535 நிமிடங்களுக்குள் மதிப்பை உள்ளிடவும்",
            "th" => "กรอกค่าระหว่าง 10-65535 นาที",
            "tl" => "Maglagay ng halagang 10 hanggang 65535 minuto",
            "tr" => "10 ile 65535 dakika arasında bir değer girin",
            "uk" => "Введіть значення від 10 до 65535 хвилин",
            "ur" => "10 سے 65535 منٹ کے درمیان قدر درج کریں",
            "vi" => "Nhập giá trị từ 10 đến 65535 phút",
            "zh-cn" => "请输入 10 到 65535 分钟",
            "zh-tw" => "請輸入 10 到 65535 分鐘",
            _ => "Enter a value from 10 to 65535 minutes",
        },
        "Auto disconnect: {} minutes (range 10-65535)" => match lang {
            "ar" => "{} دقيقة (10-65535)",
            "bn" => "{} মিনিট (10-65535)",
            "de" => "{} Min. (10-65535)",
            "en" => "{} min (10-65535)",
            "es" => "{} min (10-65535)",
            "fa" => "{} دقیقه (۱۰-۶۵۵۳۵)",
            "fr" => "{} min (10-65535)",
            "he" => "{} דק׳ (10-65535)",
            "hi" => "{} मिनट (10-65535)",
            "id" => "{} menit (10-65535)",
            "it" => "{} min (10-65535)",
            "ja" => "{} 分 (10-65535)",
            "ko" => "{}분 (10-65535)",
            "ms" => "{} minit (10-65535)",
            "nl" => "{} min (10-65535)",
            "pl" => "{} min (10-65535)",
            "pt" => "{} min (10-65535)",
            "pt-br" => "{} min (10-65535)",
            "ru" => "{} мин. (10-65535)",
            "sw" => "Dakika {} (10-65535)",
            "ta" => "{} நிமிடங்கள் (10-65535)",
            "th" => "{} นาที (10-65535)",
            "tl" => "{} minuto (10-65535)",
            "tr" => "{} dk. (10-65535)",
            "uk" => "{} хв. (10-65535)",
            "ur" => "{} منٹ (10-65535)",
            "vi" => "{} phút (10-65535)",
            "zh-cn" => "{} 分钟（10-65535）",
            "zh-tw" => "{} 分鐘（10-65535）",
            _ => "{} min (10-65535)",
        },
        _ => return None,
    };
    Some(value)
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
    use super::{
        ar, bn, cn, de, en, es, fa, fr, he, hi, id, it, ja, ko, ms, nl, pl, pt, ptbr, ru, sw, ta,
        th, tl, tr, tw, uk, ur, vi,
    };
    use hbb_common::config::LocalConfig;
    use std::collections::HashMap;
    use std::ops::Deref;

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
                let value = table
                    .get(key)
                    .unwrap_or_else(|| panic!("locale {locale} is missing canonical key {key:?}"));
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

    #[test]
    fn auto_disconnect_strings_cover_every_supported_locale() {
        let keys = [
            "Automatic disconnect range: 10-65535 minutes",
            "Enter a value from 10 to 65535 minutes",
            "Auto disconnect: {} minutes (range 10-65535)",
        ];

        for (locale, _) in supported_tables() {
            for key in keys {
                assert!(
                    super::kq_timeout_translation(key, locale).is_some(),
                    "locale {locale} is missing {key:?}",
                );
            }

            let summary = super::translate_with_lang(
                "Auto disconnect: {10} minutes (range 10-65535)".to_owned(),
                locale,
            );
            assert!(
                !summary.contains("{}"),
                "locale {locale} did not substitute the timeout value",
            );
        }
    }
}
