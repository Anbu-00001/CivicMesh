"""Deterministic multilingual front end — language ID + need routing, no LLM.

Two layers, both sub-millisecond:

  1. Script identification. Most of the languages spoken in U.S. homes are
     written in a script that names them outright (Tamil, Telugu, Bengali,
     Gujarati, Gurmukhi, Hangul, Kana, Thai, Khmer, Ethiopic, Armenian,
     Georgian, Greek, Hebrew, ...). Shared scripts are split by
     letters only one language uses: Urdu ٹ ڈ ڑ ں ے vs Persian پ چ ژ گ vs
     Arabic; Ukrainian і ї є ґ vs Russian; Kana → Japanese, Han-only → Chinese.
  2. Latin-script languages are scored by distinctive function words plus
     diacritics (Vietnamese ơ ư đ + tone marks, Polish ł ą ę, Turkish ı ğ ş,
     Portuguese ã õ ç, ...).

Routing keywords (food / housing / healthcare / legal, plus crisis, domestic
violence, urgency, homelessness and children) cover the most-spoken U.S.
home languages after English (Census ACS table S1601). Anything outside the
lexicon still gets an answer: the language is identified or left as "auto",
the one narration call writes back in the user's own language, and a
time-boxed LLM read is used only when no need could be routed at all.

Stems match at a word start for Latin scripts ("despej" → despejo,
despejada) and as substrings for scripts written without spaces or with
heavy agglutination (Chinese, Japanese, Thai, Tamil, Telugu, ...).
"""

import re;
import unicodedata;
import bisect;
import from engine.messages { has_messages, catalog_review }

# (first code point, last code point, script)
glob SCRIPT_RANGES: list = [
    [0x0370, 0x03FF, "greek"], [0x0400, 0x04FF, "cyrillic"], [0x0530, 0x058F, "armenian"],
    [0x0590, 0x05FF, "hebrew"], [0x0600, 0x06FF, "arabic"], [0x0750, 0x077F, "arabic"],
    [0x0900, 0x097F, "devanagari"], [0x0980, 0x09FF, "bn"], [0x0A00, 0x0A7F, "pa"],
    [0x0A80, 0x0AFF, "gu"], [0x0B00, 0x0B7F, "or"], [0x0B80, 0x0BFF, "ta"],
    [0x0C00, 0x0C7F, "te"], [0x0C80, 0x0CFF, "kn"], [0x0D00, 0x0D7F, "ml"],
    [0x0D80, 0x0DFF, "si"], [0x0E00, 0x0E7F, "th"], [0x0E80, 0x0EFF, "lo"],
    [0x0F00, 0x0FFF, "bo"], [0x1000, 0x109F, "my"], [0x10A0, 0x10FF, "ka"],
    [0x1100, 0x11FF, "hangul"], [0x1200, 0x137F, "am"], [0x13A0, 0x13FF, "chr"],
    [0x1780, 0x17FF, "km"], [0x1800, 0x18AF, "mn"], [0x3040, 0x30FF, "kana"],
    [0x3130, 0x318F, "hangul"], [0x3400, 0x4DBF, "han"], [0x4E00, 0x9FFF, "han"],
    [0xAC00, 0xD7AF, "hangul"], [0xF900, 0xFAFF, "han"], [0xFB50, 0xFDFF, "arabic"],
    [0xFE70, 0xFEFF, "arabic"]
];
glob RANGE_STARTS: list = [r[0] for r in SCRIPT_RANGES];

# ISO code → [English name, endonym]
glob LANG_NAMES: dict = {
    "yue": ["Cantonese", "粵語"], "ps": ["Pashto", "پښتو"], "ckb": ["Kurdish (Sorani)", "کوردیی ناوەندی"],
    "kmr": ["Kurdish (Kurmanji)", "Kurmancî"], "ti": ["Tigrinya", "ትግርኛ"], "ro": ["Romanian", "Română"],
    "sq": ["Albanian", "Shqip"], "sh": ["Bosnian / Croatian / Serbian", "Bosanski / Hrvatski / Српски"],
    "bg": ["Bulgarian", "Български"], "mk": ["Macedonian", "Македонски"], "be": ["Belarusian", "Беларуская"],
    "cs": ["Czech", "Čeština"], "sk": ["Slovak", "Slovenčina"], "hu": ["Hungarian", "Magyar"], "nl": ["Dutch", "Nederlands"],
    "kk": ["Kazakh", "Қазақша"], "uz": ["Uzbek", "Oʻzbekcha"], "yo": ["Yoruba", "Yorùbá"], "ig": ["Igbo", "Asụsụ Igbo"],
    "ha": ["Hausa", "Hausa"], "wo": ["Wolof", "Wolof"], "rw": ["Kinyarwanda / Kirundi", "Ikinyarwanda / Ikirundi"],
    "om": ["Oromo", "Afaan Oromoo"], "ceb": ["Cebuano (Bisaya)", "Sinugbuanong Binisaya"], "ilo": ["Ilocano", "Ilokano"],
    "sm": ["Samoan", "Gagana Sāmoa"], "to": ["Tongan", "Lea faka-Tonga"], "mh": ["Marshallese", "Kajin M̧ajeļ"],
    "kea": ["Cape Verdean Creole", "Kriolu"], "jam": ["Jamaican Patois", "Patwa"], "yi": ["Yiddish", "ייִדיש"],
    "ff": ["Fula (Pulaar)", "Pulaar"], "ln": ["Lingala", "Lingála"], "ak": ["Twi (Akan)", "Twi"], "qu": ["Quechua", "Runa Simi"],
    "ksw": ["Karen (S'gaw)", "ကညီကျိာ်"], "myn": ["Mayan language", "Maya"],
    "hi-Latn": ["Hindi (romanized)", "Hinglish"], "ta-Latn": ["Tamil (romanized)", "Tanglish"],
    "en": ["English", "English"], "es": ["Spanish", "Español"], "zh": ["Chinese", "中文"],
    "tl": ["Tagalog", "Tagalog"], "vi": ["Vietnamese", "Tiếng Việt"], "ar": ["Arabic", "العربية"],
    "fr": ["French", "Français"], "ko": ["Korean", "한국어"], "ru": ["Russian", "Русский"],
    "ht": ["Haitian Creole", "Kreyòl ayisyen"], "de": ["German", "Deutsch"], "hi": ["Hindi", "हिन्दी"],
    "pt": ["Portuguese", "Português"], "it": ["Italian", "Italiano"], "pl": ["Polish", "Polski"],
    "ur": ["Urdu", "اردو"], "fa": ["Persian", "فارسی"], "ja": ["Japanese", "日本語"],
    "gu": ["Gujarati", "ગુજરાતી"], "te": ["Telugu", "తెలుగు"], "bn": ["Bengali", "বাংলা"],
    "ta": ["Tamil", "தமிழ்"], "pa": ["Punjabi", "ਪੰਜਾਬੀ"], "uk": ["Ukrainian", "Українська"],
    "el": ["Greek", "Ελληνικά"], "hy": ["Armenian", "Հայերեն"], "he": ["Hebrew", "עברית"],
    "am": ["Amharic", "አማርኛ"], "so": ["Somali", "Soomaali"], "ne": ["Nepali", "नेपाली"],
    "th": ["Thai", "ไทย"], "km": ["Khmer", "ខ្មែរ"], "hmn": ["Hmong", "Hmoob"],
    "my": ["Burmese", "မြန်မာ"], "sw": ["Swahili", "Kiswahili"], "ml": ["Malayalam", "മലയാളം"],
    "kn": ["Kannada", "ಕನ್ನಡ"], "mr": ["Marathi", "मराठी"], "tr": ["Turkish", "Türkçe"],
    "id": ["Indonesian", "Bahasa Indonesia"], "lo": ["Lao", "ລາວ"], "ka": ["Georgian", "ქართული"],
    "si": ["Sinhala", "සිංහල"], "or": ["Odia", "ଓଡ଼ିଆ"], "bo": ["Tibetan", "བོད་ཡིག"],
    "chr": ["Cherokee", "ᏣᎳᎩ"], "mn": ["Mongolian", "Монгол"]
};

# Distinctive function words for Latin-script languages (never English or
# Spanish words, which detect_language already counts).
glob LATIN_MARKERS: dict = {
    "pt": ["eu", "não", "nao", "você", "voce", "nós", "estou", "preciso", "minha", "meu", "meus", "minhas", "também", "está", "são", "tenho", "temos", "uma", "com", "sem", "hoje", "emprego", "obrigado", "obrigada", "filhos",
           "em", "moro", "moramos", "ganho", "ganhamos", "mês", "ajuda", "fome", "aluguel", "precisamos", "família", "dinheiro", "quero", "onde", "posso", "pra", "muito", "trabalho", "agora", "então"],
    "fr": ["je", "j'ai", "nous", "pour", "avec", "les", "des", "est", "pas", "mon", "ma", "mes", "besoin", "aide", "suis", "sommes", "avons", "enfants", "travail", "dans", "ne", "une", "aujourd'hui", "merci", "loyer"],
    "it": ["io", "non", "sono", "ho", "bisogno", "aiuto", "mio", "mia", "siamo", "abbiamo", "figli", "perché", "della", "sto", "anche", "lavoro", "oggi", "grazie", "affitto",
           "gli", "di", "che", "per", "è", "più", "sua", "suo", "lei", "qualcuno", "stanotte", "c'è", "dove", "posso", "mangiare", "soldi", "cibo", "mese", "anni", "figlio"],
    # Lithuanian / Latvian: identified so the answer and narration come back
    # in the language (no routing lexicon yet; words shared with Spanish or
    # English — "es", "un", "su", "man" — left out).
    "lt": ["aš", "mano", "reikia", "pagalbos", "maisto", "kad", "yra", "neturiu", "turiu", "šiandien", "vaikai", "vaikų", "būstas", "darbo", "kaip", "jūs", "jūsų", "kiek", "labai", "ačiū", "namų", "dėl", "nėra", "arba", "kokios", "gyvena"],
    "lv": ["mans", "mana", "vajag", "vajadzīga", "palīdzība", "palīdzību", "pārtika", "vai", "nav", "šodien", "bērni", "bērns", "darbs", "kā", "jūs", "jūsu", "cik", "paldies", "mājās", "ēdiens", "dzīvoju", "esmu", "kāda", "kur"],
    "de": ["ich", "und", "nicht", "wir", "mein", "meine", "brauche", "hilfe", "habe", "keine", "kein", "bin", "sind", "haben", "für", "kinder", "arbeit", "heute", "mir", "mich", "bitte"],
    "tl": ["ako", "ang", "mga", "ng", "sa", "po", "namin", "kami", "wala", "kailangan", "tulong", "hindi", "akin", "ko", "naman", "lang", "pero", "dahil", "kasi", "ngayon", "trabaho"],
    "ht": ["mwen", "nou", "gen", "pou", "ak", "bezwen", "èd", "ki", "li", "pitit", "travay", "lajan", "kounye", "jodi", "pa gen", "m pa"],
    "pl": ["nie", "jestem", "mam", "potrzebuję", "potrzebuje", "pomocy", "się", "moja", "mój", "dzieci", "pracy", "że", "jest", "mamy", "dla", "dzisiaj", "proszę"],
    "tr": ["ben", "ve", "bir", "bu", "için", "yardım", "ihtiyacım", "yok", "var", "benim", "beni", "bana", "istiyor", "istiyorum", "lazım", "gerek", "çocuk", "çocuklarım", "değil", "çok", "ama", "bugün", "lütfen"],
    "id": ["saya", "dan", "tidak", "kami", "untuk", "dengan", "butuh", "perlu", "bantuan", "ada", "anak", "yang", "ini", "itu", "tolong", "bisa", "sudah", "belum", "hari ini"],
    "sw": ["mimi", "sina", "nina", "kwa", "msaada", "nahitaji", "watoto", "kazi", "hakuna", "sisi", "tafadhali", "leo"],
    "so": ["waxaan", "iyo", "waa", "anigu", "waxaa", "baahan", "caawimaad", "carruur", "shaqo", "maanta",
           "baahanahay", "baahnahay", "qoyskayga", "qoyska", "ayaan", "hadda", "rabaa", "haysto", "lacag", "cunto", "gurigayga", "carruurta", "iga", "igu"],
    "hmn": ["kuv", "koj", "peb", "yog", "tsis", "muaj", "xav", "pab", "thov", "tsev", "noj", "mov"],
    "vi": ["tôi", "chúng", "không", "cần", "giúp", "của", "và", "có", "được", "với", "hôm nay"],
    "ro": ["și", "nu", "eu", "sunt", "avem", "nevoie", "ajutor", "pentru", "copii", "este", "acasă", "vă", "rog", "mulțumesc", "mâncare", "să", "mă", "pot", "vrea", "meu", "mea"],
    "sq": ["unë", "kam", "nevojë", "ndihmë", "nuk", "jam", "fëmijët", "është", "dhe", "për", "lutem", "faleminderit", "shtëpi", "ushqim"],
    "sh": ["sam", "nemam", "trebam", "treba", "pomoć", "pomoc", "djeca", "deca", "hvala", "molim", "nije", "imam", "smo", "stan"],
    "cs": ["potřebuji", "potrebuji", "pomoc", "jsem", "nemám", "máme", "děti", "prosím", "děkuji", "není", "jídlo"],
    "sk": ["potrebujem", "pomoc", "som", "nemám", "máme", "deti", "prosím", "ďakujem", "nie", "jedlo"],
    "hu": ["segítség", "segítséget", "nincs", "vagyok", "kell", "gyerekek", "kérem", "köszönöm", "és", "nekem", "nem"],
    "nl": ["ik", "heb", "hulp", "nodig", "een", "het", "niet", "wij", "kinderen", "alstublieft", "dank", "eten", "huur"],
    "kmr": ["ez", "min", "ji", "hewce", "alîkarî", "dixwazim", "heye", "tune", "zarok", "em", "ne"],
    "uz": ["men", "menga", "kerak", "yordam", "bor", "yo'q", "yoʻq", "va", "uchun", "bolalar", "iltimos", "rahmat"],
    "yo": ["mo", "ní", "fún", "àwọn", "awọn", "ọmọ", "nílò", "nilo", "ìrànlọ́wọ́", "iranlọwọ", "kò", "jẹ", "ẹ", "wà"],
    "ig": ["achọrọ", "achoro", "enyemaka", "anyị", "nke", "bụ", "nwere", "enweghị", "ụmụ", "biko", "daalụ", "achọ"],
    "ha": ["ina", "bukatar", "taimako", "muna", "yara", "don", "ban", "abinci", "gida", "yunwa", "sannu"],
    "wo": ["dama", "soxla", "ndimbal", "amul", "xale", "ndax", "jërëjëf", "waaw", "déedéet", "lekk"],
    "rw": ["ndashaka", "nkeneye", "ubufasha", "mfite", "ntabwo", "turi", "abana", "murakoze", "ndagusaba", "ibiryo"],
    "om": ["ani", "nan", "barbaada", "gargaarsa", "qaba", "hin", "keessa", "ijoollee", "galatoomi", "maaloo", "nyaata"],
    "ceb": ["nako", "kinahanglan", "tabang", "naa", "og", "unsa", "dili", "kaayo", "akong", "among", "palihug"],
    "ilo": ["siak", "kasapulak", "awan", "adda", "dagiti", "ken", "pangngaasim", "agyamanak", "diak", "taraon"],
    "sm": ["manaomia", "fesoasoani", "matou", "fanau", "faamolemole", "faafetai", "ou te", "meaai"],
    "to": ["ʻoku", "oku ou", "fiemaʻu", "fiema'u", "tokoni", "kātaki", "ʻikai", "fānau", "mālō", "meʻakai"],
    "mh": ["aikuj", "jipañ", "kom̧m̧ool", "ij", "eo", "ilo", "kōjparok", "mona"],
    "kea": ["kre", "nha", "mininus", "fidjus", "obrigadu", "sta", "ka ten", "N ka", "kumida"],
    "jam": ["nuh", "yuh", "unnu", "pickney", "cyaan", "deh", "nyam", "yaad", "wah", "fi"],
    "ff": ["miɗo", "yiɗi", "wallitaade", "ɓiɓɓe", "jaaraama", "ñaamdu", "suudu"],
    "ln": ["nazali", "nalingi", "lisungi", "bana", "mpe", "malamu", "matondi", "bolimbisi", "nakoki", "bilei"],
    "ak": ["hia", "mmoa", "yɛ", "wɔ", "mma", "medaase", "mepa", "kyɛw", "aduane", "ɛkɔm"],
    "qu": ["ñuqa", "noqa", "ñoqa", "yanapay", "kani", "kanchu", "wawakuna", "munani", "sulpayki", "allinllachu", "mikhuna"],
    "hi-Latn": ["mujhe", "mera", "meri", "mere", "hai", "hain", "nahi", "nahin", "chahiye", "kya", "hum", "humein", "hamare", "aap", "kuch", "bahut", "paisa", "paise", "mein", "ghar", "bacche", "karo"],
    "ta-Latn": ["enakku", "naan", "naanga", "illa", "illai", "venum", "vendum", "romba", "konjam", "enna", "epdi", "engaluku", "kaasu", "panam", "irukku", "vaanga", "pannunga"]
};
# Vietnamese: breve / horn / đ / hook / tilde letters are distinctive; the
# dot-below vowels alone are shared with Yoruba and Igbo, and â ê ô with
# French and Portuguese.
glob VI_STRONG: str = "đơưấầẩẫậắằẳẵặếềểễệốồổỗộớờởỡợứừửữựảẻẽỉỏủỷỹĩũ";
glob VI_WEAK: str = "ạẹịọụỵ";
# Letters (almost) exclusive to one language; ç is shared by pt/fr/tr, so it
# is not a hint for any of them.
glob LATIN_CHAR_HINTS: dict = {"pt": "ãõ", "fr": "èêàùœ", "de": "äöüß", "pl": "ąęłńśźż", "tr": "ığş", "ht": "òè", "ro": "șțşă", "sq": "ë", "sh": "ćđ", "cs": "řěů", "sk": "ľĺŕô", "hu": "őű", "yo": "ṣ", "ig": "ṅ", "ha": "ɗƙɓƴ", "ff": "ŋ", "ak": "ɛɔ", "mh": "ļņ", "uz": "ʻ", "lt": "ėįų", "lv": "ēīģķ"};

# Per-language routing keywords. Keys: food, housing, healthcare, legal,
# self_harm, dv, urgent, homeless, children.
glob LEX: dict = {
    "zh": {
        "food": ["食物", "食品", "吃饭", "吃飯", "饿", "餓", "粮食", "糧食", "没饭吃", "沒飯吃", "食物银行", "食物銀行", "吃的"],
        "housing": ["住房", "房租", "租金", "租房", "租屋", "房子", "公寓", "找房", "房屋", "房贷", "房貸", "房东", "房東", "驱逐", "驅逐", "赶出", "趕出", "住的地方", "住处", "住處", "住所", "睡觉的地方", "睡覺的地方", "收容所", "庇护所", "庇護所", "电费", "電費", "水电费", "水電費", "暖气", "暖氣", "无家可归", "無家可歸"],
        "healthcare": ["医生", "醫生", "看病", "医院", "醫院", "药店", "藥局", "药物", "藥物", "医疗", "醫療", "保险", "保險", "生病", "牙医", "牙醫", "诊所", "診所", "心理"],
        "legal": ["律师", "律師", "法律", "法院", "移民", "驱逐出境", "驅逐出境", "政治庇护", "政治庇護", "签证", "簽證", "绿卡", "綠卡", "诈骗", "詐騙", "权利", "權利"],
        "self_harm": ["自杀", "自殺", "想死", "不想活", "结束生命", "結束生命"],
        "dv": ["家暴", "家庭暴力", "被打", "殴打", "毆打", "他打我", "她打我", "老公打", "丈夫打", "男朋友打", "打伤", "打傷", "打了我一", "虐待", "威胁我", "威脅我", "要杀我", "要殺我", "怕我老公", "怕我丈夫", "暴力"],
        "urgent": ["今天", "今晚", "马上", "馬上", "紧急", "緊急"],
        "homeless": ["无家可归", "無家可歸", "露宿", "睡在车", "睡在車"],
        "children": ["孩子", "小孩", "儿子", "兒子", "女儿", "女兒"]
    },
    "ja": {
        "food": ["食べ物", "食料", "食事", "お腹が空", "空腹", "フードバンク", "食べる"],
        "housing": ["家賃", "住む所", "住む場所", "住居", "住宅", "大家", "立ち退き", "追い出", "ホームレス", "シェルター", "電気代"],
        "healthcare": ["医者", "病院", "薬", "医療", "健康保険", "病気", "歯医者", "診療所"],
        "legal": ["弁護士", "法律", "裁判", "移民", "ビザ", "在留", "強制送還", "詐欺"],
        "self_harm": ["自殺", "死にたい"],
        "dv": ["家庭内暴力", "暴力を振る", "殴られ", "殴る", "叩かれ", "暴力", "虐待", "殺すと", "夫が怖"],
        "urgent": ["今日", "今夜", "すぐ", "緊急", "今すぐ"],
        "homeless": ["ホームレス", "住む所がない", "野宿"],
        "children": ["子供", "子ども", "息子", "娘"]
    },
    "ko": {
        "food": ["음식", "먹을", "식량", "배고", "굶", "푸드뱅크", "식사"],
        "housing": ["집세", "월세", "렌트", "집주인", "퇴거", "쫓겨", "살 곳", "주거", "쉼터", "전기세", "난방", "노숙"],
        "healthcare": ["의사", "병원", "약국", "처방", "의료", "보험", "아파요", "아파서", "아픕니다", "치과", "진료"],
        "legal": ["변호사", "법률", "법원", "이민", "추방", "비자", "영주권", "망명", "사기"],
        "self_harm": ["자살", "죽고 싶"],
        "dv": ["가정폭력", "때려", "때린", "폭력", "폭행", "학대", "죽이겠다", "협박", "남편이 무서"],
        "urgent": ["오늘", "당장", "긴급"],
        "homeless": ["노숙", "갈 곳이 없", "살 곳이 없"],
        "children": ["아이", "자녀", "아들", "딸"]
    },
    "vi": {
        "food": ["thức ăn", "đồ ăn", "thực phẩm", "đói", "bữa ăn", "ăn uống", "ngân hàng thực phẩm", "tem phiếu"],
        "housing": ["nhà ở", "tiền nhà", "tiền thuê", "thuê nhà", "chủ nhà", "đuổi", "chỗ ở", "chỗ ngủ", "nơi ở", "tiền điện", "vô gia cư"],
        "healthcare": ["bác sĩ", "bệnh viện", "thuốc", "bảo hiểm y tế", "y tế", "bị bệnh", "nha sĩ", "sức khỏe", "phòng khám"],
        "legal": ["luật sư", "pháp lý", "tòa án", "di trú", "trục xuất", "thẻ xanh", "tị nạn", "lừa đảo", "quyền lợi"],
        "self_harm": ["tự tử", "tự sát", "muốn chết"],
        "dv": ["bạo lực gia đình", "đánh tôi", "bạo hành", "đánh đập", "chồng đánh", "dọa giết", "bị đánh", "sợ chồng"],
        "urgent": ["hôm nay", "tối nay", "ngay lập tức", "khẩn cấp", "ngay bây giờ"],
        "homeless": ["vô gia cư", "ngủ ngoài đường", "không có chỗ ở"],
        "children": ["con tôi", "các con", "trẻ em", "con cái", "con trai", "con gái"]
    },
    "tl": {
        "food": ["pagkain", "gutom", "makakain", "kumain", "grocery"],
        "housing": ["bahay", "upahan", "renta", "pinapaalis", "pinalayas", "palayasin", "tirahan", "matutuluyan", "kuryente"],
        "healthcare": ["doktor", "ospital", "gamot", "may sakit", "klinika", "dentista", "ngipin", "kalusugan"],
        "legal": ["abogado", "korte", "hukuman", "imigrasyon", "karapatan", "deport"],
        "self_harm": ["magpakamatay", "patayin ang sarili", "gusto ko nang mamatay"],
        "dv": ["karahasan sa tahanan", "sinasaktan ako", "binubugbog", "sinasaktan", "pinagbabantaan", "sinasampal", "takot sa asawa"],
        "urgent": ["ngayong gabi", "agad", "kagyat"],
        "homeless": ["walang tirahan", "walang bahay", "sa kalye"],
        "children": ["anak", "mga bata"]
    },
    "ar": {
        "food": ["طعام", "أكل", "غذاء", "الجوع", "جائع", "جوعان", "جياع", "بنك الطعام"],
        "housing": ["سكن", "إيجار", "ايجار", "منزل", "بيت", "صاحب البيت", "طرد", "إخلاء", "مأوى", "كهرباء", "شقة"],
        "healthcare": ["طبيب", "دكتور", "مستشفى", "دواء", "علاج", "تأمين صحي", "مريض", "صحة", "أسنان", "عيادة"],
        "legal": ["محامي", "محام", "قانون", "محكمة", "هجرة", "ترحيل", "لجوء", "تأشيرة", "احتيال", "حقوق"],
        "self_harm": ["انتحار", "أقتل نفسي", "أريد أن أموت"],
        "dv": ["عنف أسري", "عنف منزلي", "يضربني", "ضربني", "يضرب", "يهددني", "يهدد بقتلي", "أخاف من زوجي", "اخاف من زوجي", "عنف"],
        "urgent": ["اليوم", "الليلة", "عاجل", "فورا"],
        "homeless": ["بلا مأوى", "مشرد", "في الشارع"],
        "children": ["أطفال", "اطفال", "أولادي", "ابني", "ابنتي"]
    },
    "fa": {
        "food": ["غذا", "خوراک", "گرسنه", "گرسنگی"],
        "housing": ["خانه", "اجاره", "صاحبخانه", "صاحب‌خانه", "تخلیه", "سرپناه", "برق"],
        "healthcare": ["دکتر", "پزشک", "بیمارستان", "دارو", "بیمه", "بیمار", "دندانپزشک", "درمان"],
        "legal": ["وکیل", "دادگاه", "قانونی", "مهاجرت", "اخراج", "پناهندگی", "ویزا"],
        "self_harm": ["خودکشی"],
        "dv": ["خشونت خانگی", "کتکم", "کتک", "منو میزنه", "من را می‌زند", "تهدید", "می‌ترسم از شوهرم", "خشونت"],
        "urgent": ["امروز", "امشب", "فوری"],
        "homeless": ["بی خانمان", "بی‌خانمان", "کارتن خواب"],
        "children": ["بچه", "فرزند", "پسرم", "دخترم"]
    },
    "ur": {
        "food": ["کھانا", "خوراک", "بھوک", "بھوکا", "راشن"],
        "housing": ["گھر", "کرایہ", "مکان", "مالک مکان", "نکال", "پناہ گاہ", "بجلی"],
        "healthcare": ["ڈاکٹر", "ہسپتال", "اسپتال", "دوائی", "دوا", "علاج", "بیمار", "انشورنس"],
        "legal": ["وکیل", "عدالت", "قانونی", "امیگریشن", "ملک بدر", "ویزا"],
        "self_harm": ["خودکشی"],
        "dv": ["گھریلو تشدد", "مارتا ہے", "مارتا", "پیٹتا", "دھمکی", "تشدد"],
        "urgent": ["آج", "فوری"],
        "homeless": ["بے گھر"],
        "children": ["بچے", "بچوں", "بیٹا", "بیٹی"]
    },
    "ru": {
        "food": ["еда", "еды", "продукт", "голод", "поесть", "питани"],
        "housing": ["жиль", "квартир", "аренд", "хозяин", "высел", "бездомн", "ночевать", "приют", "коммунал", "электричеств"],
        "healthcare": ["врач", "больниц", "лекарств", "лечени", "страховк", "болен", "болею", "стоматолог", "медицин"],
        "legal": ["адвокат", "юрист", "суд", "иммиграц", "депорт", "убежищ", "виза", "мошенни", "права"],
        "self_harm": ["самоубийств", "покончить с собой", "не хочу жить", "суицид"],
        "dv": ["домашнее насилие", "бьет меня", "бьёт меня", "избивает", "избил", "угрожает", "боюсь мужа", "насили"],
        "urgent": ["сегодня", "срочно", "немедленно"],
        "homeless": ["бездомн", "на улице", "негде жить"],
        "children": ["дети", "детей", "ребен", "ребён", "сын", "дочь"]
    },
    "uk": {
        "food": ["їжа", "їжі", "їсти", "голод", "продукт", "харчуванн"],
        "housing": ["житл", "квартир", "оренд", "господар", "виселенн", "безхатьк", "притулок", "електроенерг", "комунал"],
        "healthcare": ["лікар", "лікарн", "лік", "ліки", "лікуванн", "страхуванн", "хвор", "стоматолог"],
        "legal": ["адвокат", "юрист", "суд", "імміграц", "депорт", "притулку", "віза", "шахра", "права"],
        "self_harm": ["самогубств", "суїцид", "не хочу жити"],
        "dv": ["домашнє насильство", "б'є мене", "бʼє мене", "б'є", "бʼє", "побив", "погрожує", "боюся чоловіка", "насильств"],
        "urgent": ["сьогодні", "терміново"],
        "homeless": ["безхатьк", "на вулиці", "ніде жити"],
        "children": ["діти", "дітей", "дитин", "син", "донька"]
    },
    "hi": {
        "food": ["खाना", "खाने", "भोजन", "भूख", "भूखा", "भूखे", "राशन", "अन्न"],
        "housing": ["घर", "किराया", "किराए", "किराये", "मकान", "बेघर", "निकाल", "आश्रय", "रहने की जगह", "बिजली"],
        "healthcare": ["डॉक्टर", "डाक्टर", "अस्पताल", "दवा", "दवाई", "इलाज", "बीमार", "बीमा", "स्वास्थ्य", "दांत"],
        "legal": ["वकील", "अदालत", "कोर्ट", "कानून", "कानूनी", "इमिग्रेशन", "आप्रवासन", "वीज़ा", "वीजा", "निर्वासन", "धोखा"],
        "self_harm": ["आत्महत्या", "मरना चाहता", "मरना चाहती", "जान दे"],
        "dv": ["घरेलू हिंसा", "मारता है", "पीटता", "मारता", "पीटती", "धमकी", "मारपीट", "हिंसा"],
        "urgent": ["आज", "तुरंत", "जल्दी"],
        "homeless": ["बेघर", "सड़क पर", "रहने की जगह नहीं"],
        "children": ["बच्चे", "बच्चों", "बेटा", "बेटी"]
    },
    "mr": {
        "food": ["जेवण", "अन्न", "भूक", "खायला"],
        "housing": ["घर", "भाडे", "भाड्या", "घरमालक", "बेघर", "वीज"],
        "healthcare": ["डॉक्टर", "दवाखाना", "रुग्णालय", "औषध", "उपचार", "आजारी", "विमा"],
        "legal": ["वकील", "न्यायालय", "कोर्ट", "कायदा", "कायदेशीर", "व्हिसा"],
        "self_harm": ["आत्महत्या"],
        "dv": ["कौटुंबिक हिंसा", "मारहाण"],
        "urgent": ["आज", "लगेच", "तातडीने"],
        "homeless": ["बेघर"],
        "children": ["मुले", "मुलं", "मुलगा", "मुलगी"]
    },
    "ne": {
        "food": ["खाना", "खानेकुरा", "भोक", "भोजन"],
        "housing": ["घर", "भाडा", "घरबेटी", "बेघर", "बिजुली"],
        "healthcare": ["डाक्टर", "अस्पताल", "औषधि", "उपचार", "बिरामी", "बीमा"],
        "legal": ["वकिल", "अदालत", "कानुन", "अध्यागमन", "भिसा"],
        "self_harm": ["आत्महत्या"],
        "dv": ["घरेलु हिंसा", "कुट्छ", "पिट्छ", "धम्की", "हिंसा"],
        "urgent": ["आज", "तुरुन्त"],
        "homeless": ["बेघर"],
        "children": ["बच्चा", "छोरा", "छोरी", "केटाकेटी"]
    },
    "bn": {
        "food": ["খাবার", "খাদ্য", "ক্ষুধা", "খিদে", "ভাত"],
        "housing": ["বাড়ি", "বাসা", "ভাড়া", "বাড়িওয়ালা", "উচ্ছেদ", "আশ্রয়", "বিদ্যুৎ", "গৃহহীন"],
        "healthcare": ["ডাক্তার", "হাসপাতাল", "ওষুধ", "চিকিৎসা", "অসুস্থ", "বীমা", "স্বাস্থ্য"],
        "legal": ["উকিল", "আইনজীবী", "আদালত", "আইনি", "অভিবাসন", "ভিসা", "নির্বাসন"],
        "self_harm": ["আত্মহত্যা"],
        "dv": ["পারিবারিক সহিংসতা", "মারধর", "মারে", "হুমকি", "নির্যাতন"],
        "urgent": ["আজ", "জরুরি"],
        "homeless": ["গৃহহীন", "রাস্তায়"],
        "children": ["সন্তান", "বাচ্চা", "ছেলে", "মেয়ে"]
    },
    "ta": {
        "food": ["உணவு", "சாப்பா", "சாப்பிட", "பசி", "உண்ண", "அரிசி", "மளிகை"],
        "housing": ["வீடு", "வீட்டு", "வாடகை", "வெளியேற்ற", "தங்க இடம்", "தங்குவதற்கு", "தங்குமிடம்", "மின்சார", "வீடற்ற"],
        "healthcare": ["மருத்துவ", "மருந்து", "டாக்டர்", "மருத்துவமனை", "சிகிச்சை", "உடல்நல", "நோய்", "காப்பீடு"],
        "legal": ["வழக்கறிஞர்", "நீதிமன்ற", "சட்ட", "குடியேற்ற", "விசா", "நாடுகடத்த", "மோசடி"],
        "self_harm": ["தற்கொலை", "சாக வேண்டும்", "இறக்க விரும்பு"],
        "dv": ["குடும்ப வன்முறை", "அடிக்கிறார்", "அடிக்கிறான்", "அடிக்கிற", "மிரட்டு", "வன்முறை"],
        "urgent": ["இன்று", "இன்றிரவு", "உடனே", "அவசர"],
        "homeless": ["வீடற்ற", "தெருவில்", "தங்க இடம் இல்லை"],
        "children": ["குழந்தை", "பிள்ளை", "மகன்", "மகள்"]
    },
    "te": {
        "food": ["ఆహారం", "తిండి", "భోజనం", "ఆకలి", "అన్నం"],
        "housing": ["ఇల్లు", "ఇంటి", "అద్దె", "ఖాళీ చేయ", "ఆశ్రయం", "కరెంటు", "విద్యుత్", "నిరాశ్రయ"],
        "healthcare": ["డాక్టర్", "వైద్య", "ఆసుపత్రి", "మందు", "చికిత్స", "జబ్బు", "అనారోగ్య", "బీమా"],
        "legal": ["లాయర్", "న్యాయవాది", "కోర్టు", "న్యాయస్థానం", "చట్ట", "ఇమ్మిగ్రేషన్", "వీసా", "మోసం"],
        "self_harm": ["ఆత్మహత్య"],
        "dv": ["గృహ హింస", "కొడుతున్నా", "కొడతాడు", "కొడుతున్నాడు", "బెదిరి", "హింస"],
        "urgent": ["ఈరోజు", "ఇవాళ", "వెంటనే", "అత్యవసర"],
        "homeless": ["నిరాశ్రయ", "రోడ్డు మీద"],
        "children": ["పిల్లలు", "కొడుకు", "కూతురు"]
    },
    "kn": {
        "food": ["ಆಹಾರ", "ಊಟ", "ಹಸಿವು", "ಅನ್ನ"],
        "housing": ["ಮನೆ", "ಬಾಡಿಗೆ", "ಹೊರಹಾಕ", "ಆಶ್ರಯ", "ವಿದ್ಯುತ್", "ನಿರಾಶ್ರಿತ"],
        "healthcare": ["ವೈದ್ಯ", "ಡಾಕ್ಟರ್", "ಆಸ್ಪತ್ರೆ", "ಔಷಧ", "ಚಿಕಿತ್ಸೆ", "ಅನಾರೋಗ್ಯ", "ವಿಮೆ"],
        "legal": ["ವಕೀಲ", "ನ್ಯಾಯಾಲಯ", "ಕಾನೂನು", "ವಲಸೆ", "ವೀಸಾ", "ವಂಚನೆ"],
        "self_harm": ["ಆತ್ಮಹತ್ಯೆ"],
        "dv": ["ಕೌಟುಂಬಿಕ ದೌರ್ಜನ್ಯ"],
        "urgent": ["ಇಂದು", "ತಕ್ಷಣ", "ತುರ್ತು"],
        "homeless": ["ನಿರಾಶ್ರಿತ"],
        "children": ["ಮಕ್ಕಳು", "ಮಗ", "ಮಗಳು"]
    },
    "ml": {
        "food": ["ഭക്ഷണം", "ആഹാരം", "വിശപ്പ്", "ചോറ്"],
        "housing": ["വീട്", "വാടക", "കുടിയൊഴിപ്പി", "അഭയ", "വൈദ്യുതി", "ഭവനരഹിത"],
        "healthcare": ["ഡോക്ടർ", "ആശുപത്രി", "മരുന്ന്", "ചികിത്സ", "അസുഖ", "ഇൻഷുറൻസ്"],
        "legal": ["വക്കീൽ", "അഭിഭാഷക", "കോടതി", "നിയമ", "കുടിയേറ്റ", "വിസ"],
        "self_harm": ["ആത്മഹത്യ"],
        "dv": ["ഗാർഹിക പീഡന"],
        "urgent": ["ഇന്ന്", "ഉടൻ", "അടിയന്തര"],
        "homeless": ["ഭവനരഹിത"],
        "children": ["കുട്ടികൾ", "മകൻ", "മകൾ"]
    },
    "gu": {
        "food": ["ખોરાક", "ખાવાનું", "ભૂખ", "જમવા"],
        "housing": ["ઘર", "ભાડું", "ભાડા", "મકાનમાલિક", "કાઢી મૂક", "આશ્રય", "વીજળી", "બેઘર"],
        "healthcare": ["ડૉક્ટર", "ડોક્ટર", "હોસ્પિટલ", "દવા", "સારવાર", "બીમાર", "વીમો"],
        "legal": ["વકીલ", "કોર્ટ", "અદાલત", "કાયદ", "ઇમિગ્રેશન", "વિઝા"],
        "self_harm": ["આત્મહત્યા"],
        "dv": ["ઘરેલું હિંસા", "મારે છે", "મારપીટ", "ધમકી", "હિંસા"],
        "urgent": ["આજે", "તાત્કાલિક"],
        "homeless": ["બેઘર"],
        "children": ["બાળકો", "દીકરો", "દીકરી"]
    },
    "pa": {
        "food": ["ਖਾਣਾ", "ਭੋਜਨ", "ਭੁੱਖ", "ਰੋਟੀ"],
        "housing": ["ਘਰ", "ਕਿਰਾਇਆ", "ਕਿਰਾਏ", "ਮਕਾਨ ਮਾਲਕ", "ਬਿਜਲੀ", "ਬੇਘਰ"],
        "healthcare": ["ਡਾਕਟਰ", "ਹਸਪਤਾਲ", "ਦਵਾਈ", "ਇਲਾਜ", "ਬਿਮਾਰ", "ਬੀਮਾ"],
        "legal": ["ਵਕੀਲ", "ਅਦਾਲਤ", "ਕਾਨੂੰਨ", "ਇਮੀਗ੍ਰੇਸ਼ਨ", "ਵੀਜ਼ਾ"],
        "self_harm": ["ਖੁਦਕੁਸ਼ੀ", "ਆਤਮ ਹੱਤਿਆ"],
        "dv": ["ਘਰੇਲੂ ਹਿੰਸਾ", "ਕੁੱਟਦਾ", "ਮਾਰਦਾ", "ਧਮਕੀ", "ਕੁੱਟਮਾਰ", "ਹਿੰਸਾ"],
        "urgent": ["ਅੱਜ", "ਤੁਰੰਤ"],
        "homeless": ["ਬੇਘਰ"],
        "children": ["ਬੱਚੇ", "ਪੁੱਤਰ", "ਧੀ"]
    },
    "th": {
        "food": ["อาหาร", "หิว", "กินข้าว", "ของกิน"],
        "housing": ["บ้าน", "ค่าเช่า", "เจ้าของบ้าน", "ไล่ออก", "ที่พัก", "ค่าไฟ", "ไร้บ้าน"],
        "healthcare": ["หมอ", "แพทย์", "โรงพยาบาล", "รักษา", "ป่วย", "ประกันสุขภาพ", "ทันตแพทย์"],
        "legal": ["ทนาย", "ศาล", "กฎหมาย", "ตรวจคนเข้าเมือง", "วีซ่า", "เนรเทศ"],
        "self_harm": ["ฆ่าตัวตาย"],
        "dv": ["ความรุนแรงในครอบครัว", "ตีฉัน", "ทำร้าย", "ขู่", "ความรุนแรง"],
        "urgent": ["วันนี้", "คืนนี้", "ด่วน"],
        "homeless": ["ไร้บ้าน", "ไม่มีที่อยู่"],
        "children": ["ลูก", "เด็ก"]
    },
    "km": {
        "food": ["ម្ហូប", "អាហារ", "ឃ្លាន"],
        "housing": ["ផ្ទះ", "ជួល", "ម្ចាស់ផ្ទះ", "ភ្លើង"],
        "healthcare": ["គ្រូពេទ្យ", "មន្ទីរពេទ្យ", "ថ្នាំ", "ឈឺ"],
        "legal": ["មេធាវី", "តុលាការ", "ច្បាប់", "អន្តោប្រវេសន៍"],
        "self_harm": ["សម្លាប់ខ្លួន"],
        "dv": ["អំពើហិង្សាក្នុងគ្រួសារ", "វាយខ្ញុំ", "គំរាម", "ហិង្សា"],
        "urgent": ["ថ្ងៃនេះ", "បន្ទាន់"],
        "homeless": ["គ្មានផ្ទះ"],
        "children": ["កូន", "ក្មេង"]
    },
    "my": {
        "food": ["အစားအစာ", "ထမင်း", "ဗိုက်ဆာ"],
        "housing": ["အိမ်", "အိမ်ငှား", "အိမ်ရှင်"],
        "healthcare": ["ဆရာဝန်", "ဆေးရုံ", "ဆေး", "နေမကောင်း"],
        "legal": ["ရှေ့နေ", "တရားရုံး", "ဥပဒေ", "လူဝင်မှုကြီးကြပ်ရေး"],
        "self_harm": ["သတ်သေ"],
        "dv": ["အိမ်တွင်းအကြမ်းဖက်", "ခြိမ်းခြောက်", "အကြမ်းဖက်"],
        "urgent": ["ဒီနေ့", "ယနေ့", "အရေးပေါ်"],
        "homeless": ["အိမ်ခြေမဲ့"],
        "children": ["ကလေး", "သား", "သမီး"]
    },
    "am": {
        "food": ["ምግብ", "ረሃብ", "ራበኝ"],
        "housing": ["ቤት", "ኪራይ", "መጠለያ", "አከራይ", "መብራት"],
        "healthcare": ["ሐኪም", "ሀኪም", "ሆስፒታል", "መድሃኒት", "መድኃኒት", "ታምሜ", "ሕክምና"],
        "legal": ["ጠበቃ", "ፍርድ ቤት", "ሕግ", "ኢሚግሬሽን", "ቪዛ"],
        "self_harm": ["ራሴን ማጥፋት", "ራስን ማጥፋት"],
        "dv": ["የቤት ውስጥ ጥቃት", "ይደበድበኛል", "ይመታኛል", "ያስፈራራኛል", "ጥቃት"],
        "urgent": ["ዛሬ", "አስቸኳይ"],
        "homeless": ["ቤት የለኝም", "ጎዳና"],
        "children": ["ልጆች", "ልጄ"]
    },
    "he": {
        "food": ["אוכל", "מזון", "רעב"],
        "housing": ["דירה", "שכירות", "שכר דירה", "בעל הבית", "פינוי", "מקלט", "חשמל"],
        "healthcare": ["רופא", "בית חולים", "תרופה", "תרופות", "טיפול", "חולה", "ביטוח"],
        "legal": ["עורך דין", "עו\"ד", "בית משפט", "הגירה", "גירוש", "ויזה", "מקלט מדיני"],
        "self_harm": ["התאבדות", "להתאבד", "רוצה למות"],
        "dv": ["אלימות במשפחה", "מכה אותי"],
        "urgent": ["היום", "הלילה", "דחוף"],
        "homeless": ["חסר בית", "חסרת בית", "ברחוב"],
        "children": ["ילדים", "הבן שלי", "הבת שלי"]
    },
    "el": {
        "food": ["φαγητό", "τροφή", "πεινάω", "τρόφιμα"],
        "housing": ["σπίτι", "ενοίκιο", "σπιτονοικοκύρη", "έξωση", "άστεγ", "στέγη", "ρεύμα"],
        "healthcare": ["γιατρό", "νοσοκομείο", "φάρμακ", "θεραπεία", "άρρωστ", "ασφάλιση"],
        "legal": ["δικηγόρο", "δικαστήριο", "νομικ", "μετανάστευση", "απέλαση", "άσυλο", "βίζα"],
        "self_harm": ["αυτοκτον"],
        "dv": ["ενδοοικογενειακή βία", "με χτυπάει"],
        "urgent": ["σήμερα", "απόψε", "επείγον"],
        "homeless": ["άστεγ"],
        "children": ["παιδιά", "γιος", "κόρη"]
    },
    "hy": {
        "food": ["սնունդ", "ուտելիք", "սոված"],
        "housing": ["տուն", "բնակարան", "վարձ", "տանտեր", "վտարում", "ապաստան"],
        "healthcare": ["բժիշկ", "հիվանդանոց", "դեղ", "բուժում", "հիվանդ", "ապահովագր"],
        "legal": ["փաստաբան", "դատարան", "իրավական", "ներգաղթ", "արտաքսում", "վիզա"],
        "self_harm": ["ինքնասպան"],
        "dv": ["ընտանեկան բռնություն"],
        "urgent": ["այսօր", "շտապ"],
        "homeless": ["անօթևան"],
        "children": ["երեխաներ", "որդի", "դուստր"]
    },
    "ka": {
        "food": ["საკვები", "საჭმელი", "მშიერი"],
        "housing": ["სახლი", "ბინა", "ქირა", "გამოსახლება", "თავშესაფარი"],
        "healthcare": ["ექიმი", "საავადმყოფო", "წამალი", "მკურნალობა", "ავად"],
        "legal": ["ადვოკატი", "სასამართლო", "იურიდიული", "იმიგრაცია", "ვიზა"],
        "self_harm": ["თვითმკვლელობა"],
        "dv": ["ოჯახში ძალადობა"],
        "urgent": ["დღეს", "სასწრაფოდ"],
        "homeless": ["უსახლკარო"],
        "children": ["ბავშვები", "შვილი"]
    },
    "pt": {
        "food": ["comida", "fome", "alimento", "alimentação", "cesta básica", "banco de alimentos"],
        "housing": ["moradia", "aluguel", "senhorio", "proprietário", "despejo", "despejad", "sem-teto", "sem teto", "abrigo", "lugar para morar", "conta de luz", "habitação"],
        "healthcare": ["médico", "hospital", "remédio", "medicamento", "saúde", "plano de saúde", "doente", "dentista", "clínica"],
        "legal": ["advogad", "tribunal", "justiça", "imigração", "deportação", "asilo", "visto", "direitos", "golpe", "fraude"],
        "self_harm": ["suicídio", "me matar", "quero morrer", "tirar minha vida"],
        "dv": ["violência doméstica", "me bate", "me agride", "me ameaça", "violento comigo", "medo do meu marido"],
        "urgent": ["hoje", "hoje à noite", "urgente"],
        "homeless": ["sem-teto", "sem teto", "morando na rua", "na rua"],
        "children": ["filhos", "filho", "filha", "crianças"]
    },
    "fr": {
        "food": ["nourriture", "manger", "faim", "repas", "banque alimentaire", "aide alimentaire", "épicerie"],
        "housing": ["logement", "loyer", "propriétaire", "expuls", "sans-abri", "sans abri", "sdf", "hébergement", "refuge", "électricité", "chauffage", "appartement"],
        "healthcare": ["médecin", "docteur", "hôpital", "médicament", "santé", "assurance maladie", "malade", "dentiste", "clinique", "soins"],
        "legal": ["avocat", "tribunal", "juridique", "immigration", "asile", "titre de séjour", "papiers", "déportation", "arnaque", "fraude", "mes droits"],
        "self_harm": ["suicide", "me tuer", "envie de mourir", "en finir"],
        "dv": ["violence conjugale", "violence domestique", "me frappe", "me bat", "me menace", "violent avec moi", "peur de mon mari", "me tape"],
        "urgent": ["aujourd'hui", "ce soir", "urgent", "tout de suite"],
        "homeless": ["sans-abri", "sans abri", "sdf", "dans la rue"],
        "children": ["enfants", "enfant", "fils", "fille"]
    },
    "it": {
        "food": ["cibo", "mangiare", "fame", "pasti", "banco alimentare"],
        "housing": ["affitto", "padrone di casa", "proprietario", "sfratto", "senzatetto", "senza casa", "alloggio", "bollett"],
        "healthcare": ["medico", "dottore", "ospedale", "medicin", "farmac", "salute", "malato", "malata", "dentista", "assicurazione sanitaria"],
        "legal": ["avvocato", "tribunale", "legale", "immigrazione", "espulsione", "asilo", "permesso di soggiorno", "diritti", "truffa"],
        "self_harm": ["suicidio", "uccidermi", "voglio morire", "farla finita"],
        "dv": ["violenza domestica", "mi picchia"],
        "urgent": ["oggi", "stasera", "subito", "urgente"],
        "homeless": ["senzatetto", "senza casa", "per strada"],
        "children": ["figli", "figlio", "figlia", "bambini"]
    },
    "de": {
        "food": ["essen", "lebensmittel", "hunger", "hungrig", "tafel", "nahrung"],
        "housing": ["wohnung", "miete", "vermieter", "räumung", "obdachlos", "unterkunft", "strom", "heizung"],
        "healthcare": ["arzt", "ärztin", "krankenhaus", "medikament", "krankenversicherung", "krank", "zahnarzt", "gesundheit"],
        "legal": ["anwalt", "anwältin", "gericht", "rechtlich", "einwanderung", "abschiebung", "asyl", "visum", "betrug"],
        "self_harm": ["selbstmord", "suizid", "umbringen", "nicht mehr leben"],
        "dv": ["häusliche gewalt", "schlägt mich"],
        "urgent": ["heute", "heute nacht", "sofort", "dringend"],
        "homeless": ["obdachlos", "auf der straße"],
        "children": ["kinder", "kind", "sohn", "tochter"]
    },
    "pl": {
        "food": ["jedzeni", "głodn", "głód", "żywnoś", "bank żywności", "posiłek"],
        "housing": ["mieszkani", "czynsz", "wynajem", "właściciel", "eksmisj", "bezdomn", "schronisk", "noclegowni", "prąd", "ogrzewani"],
        "healthcare": ["lekarz", "szpital", "lekarstw", "leki", "zdrowi", "ubezpieczeni", "chory", "chora", "dentyst"],
        "legal": ["prawnik", "adwokat", "sąd", "prawn", "imigracj", "deportacj", "azyl", "wiza", "oszust"],
        "self_harm": ["samobójstw", "zabić się", "nie chcę żyć"],
        "dv": ["przemoc domowa", "bije mnie", "grozi mi", "przemoc", "boję się męża"],
        "urgent": ["dzisiaj", "dziś", "pilne", "natychmiast"],
        "homeless": ["bezdomn", "na ulicy"],
        "children": ["dzieci", "dziecko", "syn", "córka"]
    },
    "tr": {
        "food": ["yemek", "gıda", "açlık", "yiyecek", "aç kaldık"],
        "housing": ["kira", "ev sahibi", "tahliye", "evsiz", "barınak", "konut", "elektrik", "evden çıkar"],
        "healthcare": ["doktor", "hastane", "ilaç", "sağlık", "sigorta", "hasta", "diş"],
        "legal": ["avukat", "mahkeme", "hukuk", "göçmen", "sınır dışı", "iltica", "vize", "dolandırıcı"],
        "self_harm": ["intihar", "kendimi öldür"],
        "dv": ["aile içi şiddet", "beni dövüyor"],
        "urgent": ["bugün", "bu gece", "hemen", "acil"],
        "homeless": ["evsiz", "sokakta"],
        "children": ["çocuk", "oğlum", "kızım"]
    },
    "id": {
        "food": ["makanan", "lapar", "makan"],
        "housing": ["sewa", "pemilik rumah", "diusir", "tunawisma", "tempat tinggal", "listrik", "kontrakan"],
        "healthcare": ["dokter", "rumah sakit", "obat", "kesehatan", "asuransi", "sakit", "puskesmas"],
        "legal": ["pengacara", "pengadilan", "hukum", "imigrasi", "deportasi", "suaka", "penipuan"],
        "self_harm": ["bunuh diri"],
        "dv": ["kekerasan dalam rumah tangga", "kdrt", "memukul saya"],
        "urgent": ["hari ini", "malam ini", "segera", "darurat"],
        "homeless": ["tunawisma", "di jalan"],
        "children": ["anak"]
    },
    "ht": {
        "food": ["manje", "grangou"],
        "housing": ["kay", "lwaye", "pwopriyetè", "mete deyò", "san kay", "abri", "kouran"],
        "healthcare": ["doktè", "lopital", "medikaman", "renmèd", "maladi", "malad", "asirans", "dantis"],
        "legal": ["avoka", "tribinal", "imigrasyon", "depòte", "azil", "viza", "dwa"],
        "self_harm": ["touye tèt mwen", "swisid"],
        "dv": ["vyolans domestik", "bat mwen", "frape mwen", "menase mwen", "vyolans"],
        "urgent": ["jodi a", "aswè a", "ijan"],
        "homeless": ["san kay", "nan lari"],
        "children": ["pitit", "timoun"]
    },
    "sw": {
        "food": ["chakula", "njaa"],
        "housing": ["nyumba", "kodi", "mwenye nyumba", "kufukuzwa", "makazi", "umeme"],
        "healthcare": ["daktari", "hospitali", "dawa", "afya", "mgonjwa", "bima"],
        "legal": ["wakili", "mahakama", "sheria", "uhamiaji", "hifadhi", "visa"],
        "self_harm": ["kujiua"],
        "dv": ["unyanyasaji wa nyumbani", "ananipiga", "ananitishia", "unyanyasaji"],
        "urgent": ["leo", "usiku huu", "haraka", "dharura"],
        "homeless": ["bila makazi", "barabarani"],
        "children": ["watoto", "mtoto"]
    },
    "so": {
        "food": ["cunto", "gaajo", "raashin"],
        "housing": ["guri", "kiro", "hoy", "milkiilaha", "laga saaray", "koronto"],
        "healthcare": ["dhakhtar", "isbitaal", "daawo", "caafimaad", "xanuun"],
        "legal": ["qareen", "maxkamad", "sharci", "socdaal", "masaafuris", "magangelyo"],
        "self_harm": ["is dil", "isdil"],
        "dv": ["rabshad qoys", "i garaaca", "i garaacay", "iga hanjabay", "rabshad"],
        "urgent": ["maanta", "caawa", "degdeg"],
        "homeless": ["hoy la'aan", "guri la'aan"],
        "children": ["carruur", "caruur", "wiilka", "gabadha"]
    },
    "hi-Latn": {
        "food": ["khana", "khaana", "bhookh", "bhook", "bhukh", "ration", "anaaj"],
        "housing": ["kiraya", "kiraaya", "makaan malik", "makan malik", "ghar se nikal", "beghar", "bijli ka bill"],
        "healthcare": ["dawai", "dawa", "davai", "aspataal", "aspatal", "ilaaj", "ilaj", "bimaar", "bimar", "beemar"],
        "legal": ["vakeel", "vakil", "adalat", "police"],
        "self_harm": ["khudkushi", "aatmahatya", "marna chahta", "marna chahti"],
        "dv": ["maarta hai", "pitai", "marpeet"],
        "urgent": ["aaj", "turant"],
        "homeless": ["beghar", "sadak par"],
        "children": ["bacche", "bachche", "baccha", "beta", "beti"]
    },
    "ta-Latn": {
        "food": ["saapadu", "sappadu", "saapida", "sapida", "saapdu", "unavu", "pasi"],
        "housing": ["vaadagai", "vadagai", "veetu owner", "veettu owner", "veetai kaali", "thanga idam"],
        "healthcare": ["maruthuvar", "marundhu", "marunthu", "maruthuvamanai", "udambu sari illa", "udambu sariyilla"],
        "legal": ["vakeel", "vazhakkarinjar", "vazhakku"],
        "self_harm": ["thatkolai", "tharkolai", "saaganum"],
        "dv": ["adikkiraan", "adikkiraar"],
        "urgent": ["inniku", "indru", "udane"],
        "homeless": ["veedu illa", "veedu illai", "thanga idam illa"],
        "children": ["kuzhandhai", "kulandhai", "pasanga", "paiyan", "ponnu"]
    },
    "yue": {
        "food": ["食嘢", "食飯", "冇嘢食", "肚餓", "餓", "食物", "糧食", "食物銀行"],
        "housing": ["租金", "交租", "租", "業主", "趕走", "冇地方住", "住屋", "房屋", "庇護所", "電費"],
        "healthcare": ["睇醫生", "醫生", "醫院", "藥", "病", "保險", "牙醫", "診所"],
        "legal": ["律師", "法庭", "移民", "簽證", "綠卡", "呃錢", "權利"],
        "self_harm": ["自殺", "想死", "唔想生存"],
        "dv": ["家暴", "家庭暴力", "被打", "佢打我", "老公打", "虐待", "恐嚇我", "要殺我", "暴力"],
        "urgent": ["今日", "今晚", "即刻", "緊急"],
        "homeless": ["冇屋住", "露宿", "無家可歸"],
        "children": ["仔女", "細路", "小朋友", "個仔", "個女"]
    },
    "ps": {
        "food": ["خواړه", "خوراک", "ډوډۍ", "لوږه", "وږی"],
        "housing": ["کرایه", "د کور خاوند", "سرپناه", "کډوال"],
        "healthcare": ["ډاکټر", "روغتون", "درمل", "ناروغ", "درملنه"],
        "legal": ["وکیل", "محکمه", "مهاجرت", "ویزه", "پناه غوښتنه"],
        "self_harm": ["ځان وژنه", "ځان ووژنم"],
        "dv": ["کورنی تاوتریخوالی", "وهي مې", "ګواښ", "تاوتریخوالی"],
        "urgent": ["نن", "ژر", "بېړني"],
        "homeless": ["بې کوره"],
        "children": ["ماشومان", "زوی", "لور"]
    },
    "ckb": {
        "food": ["خواردن", "نان", "برسی", "برسێتی"],
        "housing": ["کرێ", "خاوەن ماڵ", "خانوو", "حەوانەوە"],
        "healthcare": ["دکتۆر", "نەخۆشخانە", "دەرمان", "نەخۆش"],
        "legal": ["پارێزەر", "دادگا", "کۆچ", "پەنابەری"],
        "self_harm": ["خۆکوشتن"],
        "dv": ["توندوتیژی خێزانی"],
        "urgent": ["ئەمڕۆ", "بەپەلە"],
        "homeless": ["بێ ماڵ", "بێ لانە"],
        "children": ["منداڵ"]
    },
    "kmr": {
        "food": ["xwarin", "birçî", "nan"],
        "housing": ["kirê", "xanî", "xwediyê malê", "stargeh"],
        "healthcare": ["doktor", "nexweşxane", "derman", "nexweş"],
        "legal": ["parêzer", "dadgeh", "koçberî", "penaberî"],
        "self_harm": ["xwekuştin"],
        "dv": ["tundiya malbatî"],
        "urgent": ["îro", "lezgîn"],
        "homeless": ["bê mal"],
        "children": ["zarok"]
    },
    "ti": {
        "food": ["መግቢ", "ጥሜት", "ጠሚአ"],
        "housing": ["ገዛ", "ክራይ", "መዕቆቢ"],
        "healthcare": ["ሓኪም", "ሆስፒታል", "መድሃኒት", "ሕማም", "ሕሙም"],
        "legal": ["ጠበቓ", "ቤት ፍርዲ", "ስደት", "ዑቕባ"],
        "self_harm": ["ርእሰ ቕትለት"],
        "dv": ["ዓመጽ ስድራ"],
        "urgent": ["ሎሚ", "ህጹጽ"],
        "homeless": ["ገዛ የብለይን", "ገዛ የብልናን"],
        "children": ["ቆልዑ", "ውላድ"]
    },
    "ro": {
        "food": ["mâncare", "mancare", "hrană", "foame", "alimente"],
        "housing": ["chirie", "chiria", "locuință", "locuinta", "proprietar", "evacuare", "evacuat", "adăpost", "fără adăpost"],
        "healthcare": ["medic", "doctor", "spital", "medicamente", "bolnav", "asigurare de sănătate"],
        "legal": ["avocat", "instanță", "tribunal", "imigrare", "azil", "viză", "drepturi", "înșelătorie"],
        "self_harm": ["sinucidere", "să mă sinucid", "vreau să mor"],
        "dv": ["violență domestică", "mă bate"],
        "urgent": ["azi", "astăzi", "urgent", "diseară"],
        "homeless": ["fără adăpost", "în stradă", "pe stradă"],
        "children": ["copii", "copilul", "fiul", "fiica"]
    },
    "sq": {
        "food": ["ushqim", "bukë", "kam uri", "urie"],
        "housing": ["qira", "qiranë", "pronari", "strehim", "dëbim", "strehë"],
        "healthcare": ["mjek", "doktor", "spital", "ilaç", "ilaçe", "i sëmurë", "e sëmurë", "sigurim shëndetësor"],
        "legal": ["avokat", "gjykatë", "imigrim", "azil", "vizë"],
        "self_harm": ["vetëvrasje"],
        "dv": ["dhunë në familje"],
        "urgent": ["sot", "sonte", "urgjent"],
        "homeless": ["pa strehë", "në rrugë"],
        "children": ["fëmijët", "fëmijë", "djali", "vajza"]
    },
    "sh": {
        "food": ["hran", "jelo", "gladan", "gladni", "gladna", "хран", "гладан"],
        "housing": ["stan", "kirija", "kirije", "stanarina", "najam", "stanodavac", "iseljenje", "sklonište", "кирија", "стан", "станодавац"],
        "healthcare": ["doktor", "ljekar", "lekar", "bolnica", "lijek", "lek", "lijekove", "lekove", "bolestan", "osiguranje", "доктор", "лекар", "болница", "лек"],
        "legal": ["advokat", "odvjetnik", "sud", "imigracija", "azil", "viza", "адвокат", "суд"],
        "self_harm": ["samoubistvo", "samoubojstvo", "самоубиство"],
        "dv": ["nasilje u porodici", "obiteljsko nasilje", "насиље у породици"],
        "urgent": ["danas", "večeras", "hitno", "данас", "хитно"],
        "homeless": ["beskućnik", "beskućnici", "бескућник"],
        "children": ["djeca", "deca", "dijete", "dete", "деца", "дете"]
    },
    "bg": {
        "food": ["храна", "гладен", "гладна", "гладни"],
        "housing": ["наем", "хазяин", "жилище", "изгонен", "подслон"],
        "healthcare": ["лекар", "болница", "лекарства", "болен", "болна", "осигуровка"],
        "legal": ["адвокат", "съд", "имиграция", "убежище", "виза"],
        "self_harm": ["самоубийство"],
        "dv": ["домашно насилие"],
        "urgent": ["днес", "спешно"],
        "homeless": ["бездомен", "бездомни"],
        "children": ["деца", "дете", "син", "дъщеря"]
    },
    "cs": {
        "food": ["jídlo", "jidlo", "hlad", "potraviny"],
        "housing": ["nájem", "najem", "pronajímatel", "vystěhování", "bydlení", "azylový dům"],
        "healthcare": ["lékař", "doktor", "nemocnice", "léky", "nemocný", "pojištění"],
        "legal": ["právník", "advokát", "soud", "imigrace", "azyl", "vízum"],
        "self_harm": ["sebevražda"],
        "dv": ["domácí násilí"],
        "urgent": ["dnes", "naléhavé", "ihned"],
        "homeless": ["bezdomovec", "bez domova"],
        "children": ["děti", "dítě", "syn", "dcera"]
    },
    "sk": {
        "food": ["jedlo", "hlad", "potraviny"],
        "housing": ["nájom", "prenajímateľ", "vysťahovanie", "bývanie", "útulok"],
        "healthcare": ["lekár", "doktor", "nemocnica", "lieky", "chorý", "poistenie"],
        "legal": ["právnik", "advokát", "súd", "imigrácia", "azyl", "víza"],
        "self_harm": ["samovražda"],
        "dv": ["domáce násilie"],
        "urgent": ["dnes", "naliehavé", "ihneď"],
        "homeless": ["bezdomovec", "bez domova"],
        "children": ["deti", "dieťa", "syn", "dcéra"]
    },
    "hu": {
        "food": ["étel", "élelmiszer", "éhes", "enni"],
        "housing": ["lakbér", "bérleti díj", "főbérlő", "kilakoltat", "lakás", "szállás"],
        "healthcare": ["orvos", "kórház", "gyógyszer", "beteg", "biztosítás"],
        "legal": ["ügyvéd", "bíróság", "bevándorlás", "menedékjog", "vízum"],
        "self_harm": ["öngyilkos"],
        "dv": ["családon belüli erőszak"],
        "urgent": ["ma este", "sürgős", "azonnal"],
        "homeless": ["hajléktalan"],
        "children": ["gyerekek", "gyerek", "fiam", "lányom"]
    },
    "nl": {
        "food": ["eten", "voedsel", "honger", "voedselbank"],
        "housing": ["huur", "huisbaas", "verhuurder", "uitzetting", "woning", "opvang", "dakloos"],
        "healthcare": ["dokter", "arts", "ziekenhuis", "medicijnen", "ziek", "zorgverzekering"],
        "legal": ["advocaat", "rechtbank", "immigratie", "asiel", "visum"],
        "self_harm": ["zelfmoord"],
        "dv": ["huiselijk geweld"],
        "urgent": ["vandaag", "vanavond", "dringend"],
        "homeless": ["dakloos"],
        "children": ["kinderen", "kind", "zoon", "dochter"]
    },
    "mn": {
        "food": ["хоол", "хүнс", "өлсөж", "өлссөн"],
        "housing": ["түрээс", "байр", "орон сууц", "байрны эзэн"],
        "healthcare": ["эмч", "эмнэлэг", "эм", "өвчтэй", "даатгал"],
        "legal": ["өмгөөлөгч", "шүүх", "цагаачлал", "виз"],
        "self_harm": ["амиа хорлох"],
        "dv": ["гэр бүлийн хүчирхийлэл"],
        "urgent": ["өнөөдөр", "яаралтай"],
        "homeless": ["орон гэргүй"],
        "children": ["хүүхэд"]
    },
    "kk": {
        "food": ["тамақ", "азық", "аш"],
        "housing": ["пәтер", "жалдау", "баспана", "үй иесі"],
        "healthcare": ["дәрігер", "аурухана", "дәрі", "ауру", "сақтандыру"],
        "legal": ["адвокат", "сот", "көші-қон", "виза"],
        "self_harm": ["өзін-өзі өлтіру"],
        "dv": ["тұрмыстық зорлық"],
        "urgent": ["бүгін", "шұғыл"],
        "homeless": ["баспанасыз"],
        "children": ["балалар", "бала"]
    },
    "uz": {
        "food": ["ovqat", "oziq-ovqat", "ochman", "ochmiz", "non"],
        "housing": ["ijara", "uy egasi", "kvartira", "boshpana"],
        "healthcare": ["shifokor", "doktor", "kasalxona", "dori", "kasal", "sug'urta"],
        "legal": ["advokat", "sud", "immigratsiya", "viza"],
        "self_harm": ["o'z joniga qasd"],
        "dv": ["oiladagi zo'ravonlik"],
        "urgent": ["bugun", "shoshilinch", "tezda"],
        "homeless": ["uysiz"],
        "children": ["bolalar", "bola", "o'g'il", "qiz"]
    },
    "yo": {
        "food": ["oúnjẹ", "ounjẹ", "ounje", "ebi n pa", "ebi"],
        "housing": ["owó ilé", "owo ile", "ibùgbé", "ibugbe", "onílé"],
        "healthcare": ["dókítà", "dokita", "ilé ìwòsàn", "ile iwosan", "oògùn", "oogun", "àìsàn", "aisan"],
        "legal": ["agbẹjọ́rò", "agbejoro", "ilé ẹjọ́", "ile ejo"],
        "self_harm": ["pa ara mi"],
        "urgent": ["lónìí", "loni", "kíákíá"],
        "children": ["àwọn ọmọ", "awon omo", "ọmọ mi"]
    },
    "ig": {
        "food": ["nri", "agụụ", "agu"],
        "housing": ["ụgwọ ụlọ", "ugwo ulo", "onye nwe ụlọ", "ebe obibi"],
        "healthcare": ["dọkịta", "dokita", "ụlọ ọgwụ", "ulo ogwu", "ọgwụ", "ogwu", "ọrịa", "oria"],
        "legal": ["ọkàiwu", "ọka iwu", "oka iwu", "ụlọikpe", "ulo ikpe"],
        "urgent": ["taa", "ngwa ngwa"],
        "children": ["ụmụ m", "umu m", "nwa m"]
    },
    "ha": {
        "food": ["abinci", "yunwa"],
        "housing": ["haya", "kuɗin haya", "mai gida", "matsuguni"],
        "healthcare": ["likita", "asibiti", "magani", "rashin lafiya"],
        "legal": ["lauya", "kotu", "shige da fice"],
        "urgent": ["yau", "gaggawa"],
        "children": ["yara", "ɗana", "'yata"]
    },
    "wo": {
        "food": ["lekk", "ñam", "xiif"],
        "housing": ["kër", "néeg", "luwaas"],
        "healthcare": ["doktoor", "opitaal", "garab", "feebar"],
        "legal": ["awokaa", "àttekaay"],
        "urgent": ["tey", "gaaw"],
        "children": ["xale yi", "doom"]
    },
    "rw": {
        "food": ["ibiryo", "ibifungurwa", "inzara"],
        "housing": ["ubukode", "nyir'inzu", "icumbi"],
        "healthcare": ["muganga", "ibitaro", "umuti", "imiti", "ndarwaye"],
        "legal": ["umwavoka", "urukiko", "ubuhungiro"],
        "urgent": ["uyu munsi", "byihutirwa"],
        "children": ["abana", "umwana"]
    },
    "om": {
        "food": ["nyaata", "beela"],
        "housing": ["kiraa", "abbaa manaa", "mana jireenyaa"],
        "healthcare": ["doktora", "hakiima", "hospitaala", "qoricha", "dhukkuba", "dhukkubsataa"],
        "legal": ["abukaatoo", "mana murtii", "godaansa"],
        "urgent": ["har'a", "ariifachiisaa"],
        "children": ["ijoollee", "daa'ima"]
    },
    "ceb": {
        "food": ["pagkaon", "gutom", "makaon"],
        "housing": ["abang", "tag-iya sa balay", "gipapahawa", "puy-anan"],
        "healthcare": ["doktor", "ospital", "tambal", "masakiton", "sakit"],
        "legal": ["abogado", "korte", "imigrasyon"],
        "urgent": ["dayon", "karon dayon"],
        "homeless": ["walay balay"],
        "children": ["mga anak", "bata"]
    },
    "ilo": {
        "food": ["taraon", "mabisin", "makan"],
        "housing": ["abang", "pagtaengan", "akinbalay"],
        "healthcare": ["doktor", "ospital", "agas", "masakit"],
        "legal": ["abogado", "korte"],
        "urgent": ["ita nga aldaw"],
        "homeless": ["awan ti balay"],
        "children": ["annak", "ubbing"]
    },
    "sm": {
        "food": ["meaai", "fia 'ai", "fiaai"],
        "housing": ["totogi fale", "nofoaga"],
        "healthcare": ["foma'i", "fomai", "falemai", "vailaau", "ma'i"],
        "legal": ["loia", "faamasinoga"],
        "urgent": ["aso nei", "vave"],
        "children": ["fanau", "tamaiti"]
    },
    "to": {
        "food": ["meʻakai", "me'akai", "fiekaia"],
        "housing": ["totongi fale", "nofoʻanga"],
        "healthcare": ["toketā", "toketa", "falemahaki", "faitoʻo", "faito'o", "puke"],
        "legal": ["loea", "fakamaauʻanga"],
        "children": ["fānau", "fanau"]
    },
    "kea": {
        "food": ["kumida", "fomi"],
        "housing": ["renda", "donu di kasa"],
        "healthcare": ["médiku", "mediku", "ospital", "rimédiu", "remédiu", "duenti"],
        "legal": ["advogadu", "tribunal"],
        "children": ["fidjus", "mininus", "fidju"]
    },
    "jam": {
        "food": ["nyam", "sinting fi nyam", "belly a hurt"],
        "housing": ["rent", "landlord", "yaad"],
        "healthcare": ["docta", "doctor", "hospital", "medicine"],
        "legal": ["lawyer", "court", "immigration"],
        "children": ["pickney", "pickneys"]
    },
    "yi": {
        "food": ["עסן", "הונגעריק", "שפּייַז"],
        "housing": ["דירה", "רענט", "באַלעבאָס"],
        "healthcare": ["דאָקטער", "שפּיטאָל", "מעדיצין", "קראַנק"],
        "legal": ["אַדוואָקאַט", "געריכט"],
        "children": ["קינדער"]
    },
    "lo": {
        "dv": ["ຕີຂ້ອຍ", "ທຳຮ້າຍ", "ຄວາມຮຸນແຮງ"],
        "food": ["ອາຫານ", "ຫິວເຂົ້າ", "ຫິວ"],
        "housing": ["ຄ່າເຊົ່າ", "ເຈົ້າຂອງເຮືອນ", "ທີ່ພັກ"],
        "healthcare": ["ທ່ານໝໍ", "ໂຮງໝໍ", "ເຈັບປ່ວຍ"],
        "legal": ["ທະນາຍຄວາມ"],
        "urgent": ["ມື້ນີ້", "ດ່ວນ"],
        "children": ["ລູກ"]
    },
    "ff": {
        "food": ["ñaamdu", "ñaameede", "heege"],
        "housing": ["suudu"],
        "healthcare": ["doktoor", "lopitaal", "lekki"],
        "children": ["ɓiɓɓe"]
    },
    "ln": {
        "food": ["bilei", "nzala"],
        "housing": ["lifuti ya ndako", "ndako"],
        "healthcare": ["monganga", "lopitalo", "nkisi", "kobela"],
        "legal": ["avoka", "esambiselo"],
        "children": ["bana"]
    },
    "ak": {
        "food": ["aduane", "ɛkɔm"],
        "housing": ["ofie", "dan ka"],
        "healthcare": ["dɔkota", "ayaresabea", "aduro", "yare"],
        "legal": ["mmaranimfo", "asɛnnibea"],
        "children": ["mma"]
    },
    "qu": {
        "food": ["mikhuna", "mikuna", "mikuy", "yarqay", "yarqasqa"],
        "housing": ["wasi"],
        "healthcare": ["hampiq", "hampi", "unquy", "onqoy"],
        "children": ["wawakuna", "wawa"]
    },
    "hmn": {
        "food": ["zaub mov", "tshaib"],
        "housing": ["xauj tsev", "tsev nyob", "raug ntiab"],
        "healthcare": ["kws kho mob", "tsev kho mob", "tshuaj"],
        "legal": ["kws lij choj", "tsev hais plaub"],
        "self_harm": ["tua kuv tus kheej"],
        "dv": ["ntaus kuv", "hem kuv"],
        "urgent": ["hnub no"],
        "homeless": ["tsis muaj tsev"],
        "children": ["menyuam"]
    }
};

# Scripts written without spaces (or so agglutinative that a word-start match
# misses inflected forms) are matched as substrings.
glob SUBSTRING_LANGS: list = ["zh", "yue", "ja", "ko", "th", "km", "my", "lo", "bo", "ta", "te", "kn", "ml", "am", "ti", "bn", "gu", "pa", "hi", "mr", "ne", "ar", "fa", "ur", "ps", "ckb", "he", "yi", "si", "or"];

# Short yes / no replies to the agent's follow-up question.
glob YES_WORDS: list = ["yes", "yeah", "yep", "sí", "si", "claro", "是", "是的", "对", "對", "有", "はい", "ええ", "네", "예", "có", "vâng", "dạ", "oo", "opo", "نعم", "أجل", "بله", "آره", "ہاں", "جی", "да", "так", "हाँ", "हां", "जी", "ஆம்", "ஆமாம்", "ஆமா", "అవును", "ಹೌದು", "അതെ", "হ্যাঁ", "હા", "ਹਾਂ", "sim", "oui", "wi", "ja", "sì", "tak", "evet", "ya", "iya", "ndiyo", "haa", "ใช่", "បាទ", "ចាស", "ဟုတ်", "አዎ", "כן", "ναι", "այո", "დიახ", "yog"];
glob NO_WORDS: list = ["no", "nope", "nah", "不", "不是", "没有", "沒有", "いいえ", "아니", "아니요", "không", "hindi", "wala", "لا", "نه", "نہیں", "нет", "ні", "नहीं", "நஹி", "இல்லை", "లేదు", "ಇಲ್ಲ", "ഇല്ല", "না", "ના", "ਨਹੀਂ", "não", "nao", "non", "nein", "nie", "hayır", "tidak", "hapana", "maya", "ไม่", "ទេ", "မဟုတ်", "አይ", "לא", "όχι", "ոչ", "არა", "tsis"];

"""Script of one code point, or "" for Latin/digits/punctuation."""
def script_of(ch: str) -> str {
    o = ord(ch);
    if o < 0x0370 {
        return "";
    }
    i = bisect.bisect_right(RANGE_STARTS, o) - 1;
    if i >= 0 and o <= int(SCRIPT_RANGES[i][1]) {
        return str(SCRIPT_RANGES[i][2]);
    }
    return "";
}

"""Language from the dominant non-Latin script. Returns (code, confidence) or ("", 0.0)."""
def detect_script(text: str) -> tuple {
    counts: dict = {};
    letters = 0;
    for ch in text {
        if ch.isspace() or ch.isdigit() {
            continue;
        }
        sc = script_of(ch);
        if sc {
            counts[sc] = int(counts.get(sc, 0)) + 1;
            letters += 1;
        } elif ch.isalpha() {
            counts["latin"] = int(counts.get("latin", 0)) + 1;
            letters += 1;
        }
    }
    if letters == 0 {
        return ("", 0.0);
    }
    non_latin = {k: v for (k, v) in counts.items() if k != "latin"};
    if not non_latin {
        return ("", 0.0);
    }
    top = max(non_latin, key=lambda k: str : int(non_latin[k]));
    share = float(sum(non_latin.values())) / float(letters);
    if share < 0.3 {
        return ("", 0.0);
    }
    conf = round(min(0.99, 0.6 + 0.4 * share), 2);
    code = top;
    if top in ["han", "kana", "hangul"] {
        if int(counts.get("hangul", 0)) > 0 {
            code = "ko";
        } elif int(counts.get("kana", 0)) > 0 {
            code = "ja";
        } elif len(re.findall(r"[係冇唔嘅咗啲喺佢哋嘢睇咩乜]", text)) >= 2 {
            # Written Cantonese: colloquial characters Mandarin doesn't use.
            code = "yue";
        } else {
            code = "zh";
        }
    } elif top == "arabic" {
        if re.search(r"[ڕڵۆێ]", text) {
            code = "ckb";
        } elif re.search(r"[ټډړښږځڅۍګڼ]", text) {
            code = "ps";
        } elif re.search(r"[ٹڈڑںےھۓ]", text) {
            code = "ur";
        } elif re.search(r"[پچژگ]", text) or re.search(r"[کی]", text) and not re.search(r"[كي]", text) {
            code = "fa";
        } else {
            code = "ar";
        }
    } elif top == "cyrillic" {
        if re.search(r"[әғқңұһӘҒҚҢҰҺ]", text) {
            code = "kk";
        } elif re.search(r"[өүӨҮ]", text) {
            code = "mn";
        } elif re.search(r"[іїєґІЇЄҐ]", text) {
            code = "uk";
        } elif re.search(r"[ђћљњџјЂЋЉЊЏЈ]", text) {
            code = "sh";
        } elif re.search(r"[ѓќѕЃЌЅ]", text) {
            code = "mk";
        } elif re.search(r"ў", text) {
            code = "be";
        } elif len(re.findall(r"ъ", text.lower())) >= 2 or re.search(r"\b(?:съм|ще|във|със|аз)\b", text.lower()) {
            code = "bg";
        } else {
            code = "ru";
        }
    } elif top == "devanagari" {
        # Nepali first: its "मलाई" contains Marathi's "मला".
        if re.search(r"छ[।\s]|छु|छैन|मलाई|हुन्छ|छौं|चाहिन्छ", text) {
            code = "ne";
        } elif re.search(r"आहे|नाही|मला|आम्ही|आहोत|आहेत", text) {
            code = "mr";
        } else {
            code = "hi";
        }
    } elif top == "greek" {
        code = "el";
    } elif top == "armenian" {
        code = "hy";
    } elif top == "hebrew" {
        code = "yi" if re.search(r"[װױײ]|אַ|אָ|\bאיך\b|נישט|\bמיר\b", text) else "he";
    } elif top == "am" {
        # Tigrinya and Amharic share Ethiopic script; their pronouns and
        # copulas differ (ኣነ / ኣለኹ / እየ vs እኔ / ነኝ / አለኝ).
        ti_hits = len(re.findall(r"ኣነ|ኣለኹ|እየ|ኢዩ|የብለይን|ኣሎ|ክንደይ|ብኽብረት|ኣይ", text));
        am_hits = len(re.findall(r"እኔ|ነኝ|አለኝ|የለኝም|ነው|እባክ|እፈልጋለሁ", text));
        code = "ti" if ti_hits > am_hits else "am";
    } elif top == "my" {
        # S'gaw Karen extends the Myanmar script with its own letters.
        code = "ksw" if re.search(r"[\u105A-\u1071]", text) else "my";
    }
    return (code, conf);
}

"""Best non-EN/ES Latin-script language from marker words and diacritics. Returns (code, hits)."""
def detect_latin_other(low: str) -> tuple {
    # "đ" is also Bosnian/Croatian/Serbian; Vietnamese never uses č ć š ž.
    bcs = any([c in low for c in "čćšž"]);
    vi_strong = len([c for c in low if c in VI_STRONG and not (c == "đ" and bcs)]);
    vi_hits = vi_strong + len([c for c in low if c in VI_WEAK]);
    if vi_strong >= 1 and vi_hits >= 2 {
        return ("vi", 4 + vi_hits);
    }
    # Mayan orthographies (Mam, K'iche', Q'anjob'al, Q'eqchi', ...) mark
    # glottalized consonants with an apostrophe: tx', tz', ch', q', k', b'.
    if len(re.findall(r"\b\w*(?:tx|tz|ch|[qkb])['’]\w*", low)) >= 2 and not re.search(r"\b(?:the|and|you|i'm|don't|can't)\b", low) {
        return ("myn", 6);
    }
    words = re.findall(r"[^\W\d_]+(?:'[^\W\d_]+)?", low);
    wset = set(words);
    best = "";
    best_hits = 0;
    for (code, markers) in LATIN_MARKERS.items() {
        hits = 0;
        for m in markers {
            if " " in m {
                if m in low { hits += 1; }
            } elif m in wset {
                hits += 1;
            }
        }
        # Letters alone are not evidence (Estonian "süüa" is not German):
        # they only strengthen at least one marker-word hit.
        hint = str(LATIN_CHAR_HINTS.get(code, ""));
        if hits >= 1 and hint and any([c in low for c in hint]) {
            hits += 2;
        }
        if hits > best_hits {
            best = code;
            best_hits = hits;
        }
    }
    return (best, best_hits);
}

# Generic words for "home/house". In most languages they are used as a
# location ("no food at home", "घर में खाना नहीं है", "walang pagkain sa
# bahay"), so on their own they are weak housing evidence.
glob WEAK_HOUSING: list = ["wasi", "ndako", "suudu", "kër", "ofie", "yaad", "ገዛ", "خانوو", "xanî", "ile", "ụlọ", "gida", "balay", "घर", "வீடு", "வீட்டு", "بيت", "منزل", "bahay", "kay", "বাড়ি", "বাসা", "گھر", "خانه", "ઘર", "ਘਰ", "ಮನೆ", "വീട്", "ఇల్లు", "ఇంటి", "σπίτι", "guri", "nyumba", "ផ្ទះ", "အိမ်", "ቤት", "บ้าน", "տուն", "სახლი", "tsev nyob"];

"""Find lexicon hits for one key. Returns [(start, end)] of matches in `low`."""
def _hits(code: str, words: list, low: str) -> list {
    out: list = [];
    sub = code in SUBSTRING_LANGS;
    for w in words {
        wl = str(w).lower();
        if sub {
            i = low.find(wl);
            if i >= 0 {
                out.append((i, i + len(wl)));
            }
        } else {
            m = re.search("(?<![^\\W\\d_])" + re.escape(wl), low);
            if m {
                out.append((m.start(), m.end()));
            }
        }
    }
    return out;
}

"""Like _hits, for category words."""
def _hits_w(code: str, words: list, low: str) -> list {
    return _hits(code, words, low);
}

"""Route a message with the language's own lexicon.

Returns {scores, flags, urgent, spans: [{field, value, start, end}]}; empty
scores when the language has no lexicon.
"""
def route_i18n(code: str, low: str) -> dict {
    out: dict = {"scores": {"food": 0.0, "housing": 0.0, "healthcare": 0.0, "legal": 0.0}, "flags": [], "urgent": False, "spans": []};
    lex = LEX.get(code);
    if not lex {
        return out;
    }
    for cat in ["food", "housing", "healthcare", "legal"] {
        words = list(lex.get(cat, []));
        for (s, e) in _hits_w(code, words, low) {
            if negated(low, s, e) { continue; }
            w = 1.0 if low[s:e] in WEAK_HOUSING else 2.0;
            if need_focus(low, s, e) { w = w + 1.0; }
            out["scores"][cat] = float(out["scores"][cat]) + w;
            out["spans"].append({"field": "category", "value": cat, "start": s, "end": e});
        }
    }
    for (key, flag) in [("self_harm", "self_harm"), ("dv", "dv"), ("homeless", "homeless"), ("children", "children")] {
        # Crisis and violence flags are never negated away, as in parse.jac:
        # a false alarm shows a hotline, a miss hides one.
        h = [x for x in _hits(code, list(lex.get(key, [])), low) if key in ["self_harm", "dv"] or not negated(low, x[0], x[1])];
        if h {
            out["flags"].append(flag);
            out["spans"].append({"field": "flag", "value": flag, "start": h[0][0], "end": h[0][1]});
        }
    }
    u = _hits(code, list(lex.get("urgent", [])), low);
    if u {
        out["urgent"] = True;
        out["spans"].append({"field": "urgency", "value": "immediate", "start": u[0][0], "end": u[0][1]});
    }
    return out;
}

"""'yes' / 'no' / '' for a short reply in any supported language."""
def yes_no(text: str) -> str {
    t = str(text).strip().lower().strip(" .!?¡¿。！？،؟");
    if not t {
        return "";
    }
    first = t.split()[0] if t.split() else t;
    if t in NO_WORDS or first in NO_WORDS {
        return "no";
    }
    if t in YES_WORDS or first in YES_WORDS {
        return "yes";
    }
    for w in NO_WORDS {
        if len(w) >= 2 and not w.isascii() and t.startswith(w) { return "no"; }
    }
    for w in YES_WORDS {
        if len(w) >= 2 and not w.isascii() and t.startswith(w) { return "yes"; }
    }
    return "";
}

"""Characters from scripts written without spaces (Han, Kana, Hangul, Thai, ...)."""
def unspaced_chars(text: str) -> int {
    n = 0;
    for ch in text {
        sc = script_of(ch);
        if sc in ["han", "kana", "hangul", "th", "km", "my", "lo", "bo"] {
            n += 1;
        }
    }
    return n;
}

"""[English name, endonym] for a language code; code itself if unknown."""
def language_name(code: str) -> list {
    c = str(code or "");
    if c in LANG_NAMES {
        return list(LANG_NAMES[c]);
    }
    return [c, c];
}

"""Languages with a routing lexicon (plus English and Spanish in parse.jac)."""
def routed_languages -> list {
    return ["en", "es"] + sorted([k for k in LEX.keys() if not k.endswith("-Latn")]);
}

# ---------- negation & need focus (shared by parse.jac and route_i18n) ----------
# A keyword the person says they DON'T need, or already HAVE, is not a need:
#   "we're not homeless", "I don't need a lawyer", "we have food",
#   "no necesito comida", "ya tenemos casa", "我不需要食物", "我有住的地方".
# Lacking something stays a need: "no food", "I have no food", "haven't
# eaten", "no tengo casa", "我没有食物", "घर में खाना नहीं है".
glob NEG_LEFT: str = "(?:\\b(?:do not|don'?t|doesn'?t|didn'?t|does not)\\s+(?:really\\s+)?(?:need|want)\\s+(?:a\\s+|an\\s+|any\\s+|the\\s+|more\\s+|help with\\s+|help\\s+)?|\\b(?:not|never|no longer|isn'?t|aren'?t|'m not|'re not)\\s+(?:really\\s+|actually\\s+|looking for\\s+|asking (?:for|about)\\s+|about\\s+)?(?:a\\s+|an\\s+|any\\s+|the\\s+)?|\\b(?:i|we)(?:\\s+already|\\s+do)?\\s+(?:have|'ve got)\\s+(?:a\\s+|an\\s+|some\\s+|enough\\s+|our\\s+|my\\s+|plenty of\\s+)?|\\bno\\s+(?:necesito|necesitamos|quiero|queremos|busco|buscamos|estoy buscando|es|estoy|estamos)\\s+(?:un\\s+|una\\s+|el\\s+|la\\s+|los\\s+|las\\s+|ayuda con\\s+(?:la\\s+|el\\s+)?)?|(?<!no )\\b(?:ya\\s+)?(?:tengo|tenemos)\\s+(?:un\\s+|una\\s+|el\\s+|la\\s+|algo de\\s+|suficiente\\s+)?|不需要|不要|不用|不是要|(?<!没)(?<!沒)我有|(?<!没)(?<!沒)我们有|(?<!没)(?<!沒)我們有|已经有|已經有)$";
glob NEG_RIGHT: str = "^\\s*(?:(?:isn'?t|is not|aren'?t|are not)\\s+(?:the |a |an |our |my )?(?:problem|issue|concern)|(?:is|are)\\s+(?:fine|ok|okay|covered|taken care of|not (?:a|the) problem)|no es (?:el )?problema|नहीं चाहिए|नही चाहिए|नहीं चाहिये|नको|चाहिँदैन|نہیں چاہیے|வேண்டாம்|వద్దు|ಬೇಡ|വേണ്ട|লাগবে না|দরকার নেই|જોઈતું નથી|ਨਹੀਂ ਚਾਹੀਦਾ|いらない|要らない|は必要ない|は必要ありません|필요 없|필요없|은 필요 없|는 필요 없|istemiyorum|gerek yok|ihtiyacım yok|nahi chahiye|nahin chahiye|venaam|vendaam)";
glob POSSESSION_UNDONE: str = "\\b(?:but|though|pero)\\b[^.!?]{0,30}(?:ran out|run out|running out|not enough|isn'?t enough|aren'?t enough|don'?t last|doesn'?t last|(?:was|were|got|is|are) (?:cut|stopped|cancell?ed|denied|expired)|stopped|expired|se acab|no alcanza|no es suficiente|no me alcanza)";
# Verbs of asking. A keyword right after one is what the person wants; for
# verb-final languages the asking verb follows the keyword.
glob NEED_LEFT: str = "(?:\\b(?:need|needs|needed|looking for|help with|help paying|help me find|want|asking for|where can i get|how do i get|necesito|necesitamos|busco|buscamos|ayuda con|ayuda para)\\b[^.!?;]{0,24}|需要|想要|要找)$";
glob NEED_RIGHT: str = "^[^.!?;।]{0,14}(?:चाहिए|चाहिये|हवे|चाहिन्छ|چاہیے|வேண்டும்|வேணும்|வேண்டு|కావాలి|ಬೇಕು|വേണം|দরকার|লাগবে|જોઈએ|ਚਾਹੀਦ|が必要|がほしい|が欲しい|필요해|필요합니다|필요해요|lazım|gerek|chahiye|venum|vendum)";
# Keywords that are about not having / not eating: negation makes them MORE of a need.
glob NEG_IMMUNE: str = "^(?:eat|eaten|comer|comido|hungry|hunger|hambre)$";

"""True when the keyword at low[start:end] is negated or already possessed."""
def negated(low: str, start: int, end: int) -> bool {
    kw = low[start:end];
    if re.search(NEG_IMMUNE, kw) {
        return False;
    }
    left = low[max(0, start - 40):start];
    if re.search(NEG_LEFT, left) {
        # "I have food stamps but they ran out" — having it isn't enough.
        return not re.search(POSSESSION_UNDONE, low[end:end + 60]);
    }
    right = low[end:end + 40];
    return bool(re.search(NEG_RIGHT, right));
}

"""True when the keyword is the thing being asked for ("I need a doctor", "खाना चाहिए")."""
def need_focus(low: str, start: int, end: int) -> bool {
    left = low[max(0, start - 40):start];
    if re.search(NEED_LEFT, left) {
        return True;
    }
    return bool(re.search(NEED_RIGHT, low[end:end + 30]));
}

# ---------- language registry: what CivicMesh does for each language ----------
# Languages and dialects spoken by immigrants and refugees in the U.S.:
# Census ACS S1601 "language spoken at home", EOIR immigration-court language
# counts (FY2024: Spanish, Portuguese, Haitian Creole, Russian, Mandarin,
# Punjabi, Turkish, Arabic, Mam, …) and refugee arrival languages.
#   tier "instant"      routed by the engine with no model (lexicon above)
#   tier "translate"    full answer machine-translated by NVIDIA Riva Translate v2
#   tier "llm"          routed/narrated by a multilingual LLM (Gemma 4: 140+ languages)
#   tier "interpreter"  mostly spoken languages machines don't handle reliably:
#                       answer in `fallback` + a card asking for a free interpreter
# [code, English name, endonym, note, fallback]
glob IMMIGRANT_LANGUAGES: list = [
    ["en", "English", "English", "", ""], ["es", "Spanish", "Español", "all regional varieties", ""],
    ["zh", "Chinese (Mandarin)", "中文（普通话）", "Simplified & Traditional", ""], ["yue", "Cantonese", "粵語", "incl. Taishanese speakers", ""],
    ["tl", "Tagalog / Filipino", "Tagalog", "", ""], ["ceb", "Cebuano (Bisaya)", "Binisaya", "", ""], ["ilo", "Ilocano", "Ilokano", "", ""],
    ["vi", "Vietnamese", "Tiếng Việt", "", ""], ["ar", "Arabic", "العربية", "Levantine, Egyptian, Iraqi, Maghrebi, Sudanese", ""],
    ["fr", "French", "Français", "incl. West & Central African French", ""], ["ht", "Haitian Creole", "Kreyòl ayisyen", "", ""],
    ["ko", "Korean", "한국어", "", ""], ["ru", "Russian", "Русский", "", ""], ["uk", "Ukrainian", "Українська", "", ""],
    ["pt", "Portuguese", "Português", "Brazilian & European", ""], ["kea", "Cape Verdean Creole", "Kriolu", "", ""],
    ["de", "German", "Deutsch", "", ""], ["it", "Italian", "Italiano", "", ""], ["pl", "Polish", "Polski", "", ""],
    ["hi", "Hindi", "हिन्दी", "", ""], ["hi-Latn", "Hindi / Urdu (romanized)", "Hinglish", "", ""], ["ur", "Urdu", "اردو", "", ""],
    ["pa", "Punjabi", "ਪੰਜਾਬੀ", "Gurmukhi script", ""], ["bn", "Bengali", "বাংলা", "incl. Sylheti speakers", ""],
    ["gu", "Gujarati", "ગુજરાતી", "", ""], ["te", "Telugu", "తెలుగు", "", ""], ["ta", "Tamil", "தமிழ்", "", ""],
    ["ta-Latn", "Tamil (romanized)", "Tanglish", "", ""], ["ml", "Malayalam", "മലയാളം", "", ""], ["kn", "Kannada", "ಕನ್ನಡ", "", ""],
    ["mr", "Marathi", "मराठी", "", ""], ["ne", "Nepali", "नेपाली", "incl. Bhutanese refugees", ""], ["si", "Sinhala", "සිංහල", "", ""],
    ["fa", "Persian (Farsi / Dari)", "فارسی / دری", "Iranian & Afghan", ""], ["ps", "Pashto", "پښتو", "", ""],
    ["ckb", "Kurdish (Sorani)", "کوردی", "", ""], ["kmr", "Kurdish (Kurmanji)", "Kurmancî", "", ""],
    ["tr", "Turkish", "Türkçe", "", ""], ["he", "Hebrew", "עברית", "", ""], ["yi", "Yiddish", "ייִדיש", "", ""],
    ["el", "Greek", "Ελληνικά", "", ""], ["hy", "Armenian", "Հայերեն", "Eastern & Western", ""], ["ka", "Georgian", "ქართული", "", ""],
    ["ro", "Romanian / Moldovan", "Română", "", ""], ["sq", "Albanian", "Shqip", "", ""], ["sh", "Bosnian / Croatian / Serbian", "BCS / Српски", "Latin & Cyrillic", ""],
    ["bg", "Bulgarian", "Български", "", ""], ["mk", "Macedonian", "Македонски", "", ""], ["be", "Belarusian", "Беларуская", "", ""],
    ["cs", "Czech", "Čeština", "", ""], ["sk", "Slovak", "Slovenčina", "", ""], ["hu", "Hungarian", "Magyar", "", ""],
    ["lt", "Lithuanian", "Lietuvių", "", ""], ["lv", "Latvian", "Latviešu", "", ""], ["nl", "Dutch", "Nederlands", "", ""],
    ["kk", "Kazakh", "Қазақша", "", ""], ["uz", "Uzbek", "Oʻzbekcha", "", ""], ["ky", "Kyrgyz", "Кыргызча", "", ""], ["tg", "Tajik", "Тоҷикӣ", "", ""],
    ["mn", "Mongolian", "Монгол", "", ""], ["ja", "Japanese", "日本語", "", ""], ["th", "Thai", "ไทย", "", ""],
    ["lo", "Lao", "ລາວ", "", ""], ["km", "Khmer", "ខ្មែរ", "", ""], ["my", "Burmese", "မြန်မာ", "", ""],
    ["ksw", "Karen (S'gaw)", "ကညီ", "Burmese refugees", ""], ["cnh", "Chin (Hakha)", "Laiholh", "Burmese refugees", "en"],
    ["kac", "Kachin (Jingpho)", "Jinghpaw", "", "en"], ["hmn", "Hmong", "Hmoob", "White & Green Hmong", ""],
    ["id", "Indonesian", "Bahasa Indonesia", "", ""], ["ms", "Malay", "Bahasa Melayu", "", ""],
    ["am", "Amharic", "አማርኛ", "", ""], ["ti", "Tigrinya", "ትግርኛ", "Eritrean & Ethiopian", ""], ["om", "Oromo", "Afaan Oromoo", "", ""],
    ["so", "Somali", "Soomaali", "", ""], ["sw", "Swahili", "Kiswahili", "", ""], ["rw", "Kinyarwanda / Kirundi", "Ikinyarwanda", "", ""],
    ["ln", "Lingala", "Lingála", "", ""], ["yo", "Yoruba", "Yorùbá", "", ""], ["ig", "Igbo", "Igbo", "", ""],
    ["ha", "Hausa", "Hausa", "", ""], ["ak", "Twi (Akan)", "Twi", "", ""], ["ee", "Ewe", "Eʋegbe", "", "en"],
    ["wo", "Wolof", "Wolof", "", ""], ["ff", "Fula (Pulaar)", "Pulaar", "", ""], ["bm", "Bambara / Mandinka", "Bamanankan", "", "fr"],
    ["din", "Dinka", "Thuɔŋjäŋ", "South Sudanese", "en"], ["nus", "Nuer", "Thok Naath", "South Sudanese", "en"],
    ["sm", "Samoan", "Gagana Sāmoa", "", ""], ["to", "Tongan", "Lea faka-Tonga", "", ""], ["mh", "Marshallese", "Kajin M̧ajeļ", "COFA community", "en"],
    ["chk", "Chuukese", "Chuuk", "COFA community", "en"], ["ch", "Chamorro", "Chamoru", "", "en"],
    ["jam", "Jamaican Patois", "Patwa", "", ""], ["qu", "Quechua", "Runa Simi", "", "es"],
    ["mam", "Mam", "Qyol Mam", "Guatemala — top-10 immigration-court language", "es"], ["quc", "K'iche'", "K'iche'", "Guatemala", "es"],
    ["kjb", "Q'anjob'al", "Q'anjob'al", "Guatemala", "es"], ["kek", "Q'eqchi'", "Q'eqchi'", "Guatemala, Belize", "es"],
    ["cak", "Kaqchikel", "Kaqchikel", "Guatemala", "es"], ["knj", "Akateko", "Akateko", "Guatemala", "es"], ["cac", "Chuj", "Chuj", "Guatemala", "es"],
    ["ixl", "Ixil", "Ixil", "Guatemala", "es"], ["mix", "Mixtec", "Tu'un Savi", "Mexico", "es"], ["zap", "Zapotec", "Diidxazá", "Mexico", "es"],
    ["trs", "Triqui", "Triqui", "Mexico", "es"], ["nah", "Nahuatl", "Nāhuatl", "Mexico", "es"], ["tsz", "Purépecha", "P'urhépecha", "Mexico", "es"],
    ["tzh", "Tseltal / Tsotsil", "Bats'il k'op", "Chiapas", "es"], ["cab", "Garifuna", "Garifuna", "Honduras, Belize", "es"],
    ["myn", "Mayan language (unspecified)", "Maya", "pick yours below", "es"]
];
# Languages whose full answer NVIDIA Riva Translate v2 translates (English → 36).
glob RIVA_CODES: dict = {"cs": "cs", "da": "da", "de": "de", "el": "el", "es": "es-us", "fi": "fi", "fr": "fr", "hu": "hu", "it": "it", "lt": "lt", "lv": "lv", "nl": "nl", "no": "no", "pl": "pl", "pt": "pt-br", "ro": "ro", "ru": "ru", "sk": "sk", "sv": "sv", "zh": "zh-cn", "yue": "zh-tw", "ja": "ja", "hi": "hi", "ko": "ko", "et": "et", "sl": "sl", "bg": "bg", "uk": "uk", "sh": "hr", "ar": "ar", "vi": "vi", "tr": "tr", "id": "id", "th": "th"};
# Mostly spoken languages without reliable machine translation today.
glob INTERPRETER_CODES: list = ["mam", "quc", "kjb", "kek", "cak", "knj", "cac", "ixl", "mix", "zap", "trs", "nah", "tsz", "tzh", "cab", "myn", "qu", "din", "nus", "chk", "mh", "ch", "cnh", "kac", "bm", "ee"];

"""Registry row + support tier for a language code."""
def language_info(code: str) -> dict {
    c = str(code or "");
    row: list = [];
    for r in IMMIGRANT_LANGUAGES {
        if r[0] == c { row = r; break; }
    }
    names = language_name(c);
    tier = "llm";
    if c in ["en", "es"] or c in LEX { tier = "instant"; }
    elif c in RIVA_CODES { tier = "translate"; }
    if c in INTERPRETER_CODES { tier = "interpreter"; }
    return {
        "code": c, "name": str(row[1]) if row else str(names[0]), "endonym": str(row[2]) if row else str(names[1]),
        "note": str(row[3]) if row else "", "fallback": (str(row[4]) if row and row[4] else ("es" if tier == "interpreter" else "")),
        "tier": tier, "riva": str(RIVA_CODES.get(c, "")),
        # A message catalog (data/i18n): the whole answer is composed in this
        # language on the first response, not translated afterwards.
        "catalog": bool(c and has_messages(c) and tier != "interpreter"),
        "catalog_review": (catalog_review(c) if (c and tier != "interpreter") else "")
    };
}

"""Picker list for the client: every registry language with its tier."""
def language_catalog -> list {
    return [language_info(str(r[0])) for r in IMMIGRANT_LANGUAGES];
}

"""Interpreter request card, deterministic, in English and the fallback language."""
def interpreter_card(code: str) -> dict {
    info = language_info(code);
    name = str(info["name"]).replace(" (unspecified)", "");
    card: dict = {
        "language": name, "endonym": str(info["endonym"]),
        "en": "I speak " + name + ". Please get me a free " + name + " interpreter.",
        "es": "Hablo " + name + ". Por favor, necesito un intérprete de " + name + " gratuito.",
        "basis": "Title VI of the Civil Rights Act bars national-origin discrimination in federally funded programs, and courts have held that includes language (Lau v. Nichols, 1974). SNAP offices must have bilingual staff or interpreters where many households speak your language (7 CFR 272.4(b)); health programs must offer free interpreters (ACA §1557). The 2025 order naming English the official language (EO 14224) did not change these laws.",
        "tip": "Call 211 and ask for a " + name + " interpreter — they connect you to local help through an interpreter line."
    };
    return card;
}

"""Map any Unicode decimal digit to ASCII: '٩٨٨' / '९८८' → '988'.

Guards compare numbers across scripts; a narrator or translator writing the
988 line in Arabic-Indic or Devanagari digits is not inventing a number.
"""
def ascii_digits(t: str) -> str {
    out: list = [];
    for c in str(t) {
        if (not c.isascii()) and unicodedata.decimal(c, None) is not None {
            out.append(str(unicodedata.decimal(c)));
        } else {
            out.append(c);
        }
    }
    return "".join(out);
}
