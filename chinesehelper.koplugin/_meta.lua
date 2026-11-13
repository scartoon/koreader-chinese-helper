local _ = require("gettext")
return {
    fullname = _("Chinese helper"),
    description = _([[Tap a Chinese character for every dictionary word it belongs to, from CC-CEDICT and fallback dictionaries in one popup; optional pinyin above rare characters, with readings chosen from the surrounding words. The book file is never modified.]]),
    version = "1.8.0",
}
