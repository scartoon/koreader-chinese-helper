local _ = require("gettext")
return {
    fullname = _("Chinese helper"),
    description = _([[Tap a Chinese character for every dictionary word it belongs to, from CC-CEDICT and fallback dictionaries in one popup. Optional pinyin above the characters, from only the rare ones up to every character (learner mode), with readings chosen from the surrounding words; mark a reading known to take its pinyin away, or remind-me to always show it. The book file is never modified.]]),
    version = "2.16.0",
}
