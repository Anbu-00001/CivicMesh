"""Facts in other languages — income, household size, age, status, location.

parse.jac reads these facts with English/Spanish patterns, so a Chinese
speaker who wrote "我住在休斯顿，每月收入1500美元，家里3个人" got their need
routed but was then asked where they live and what they earn. These tables
read the same five facts in the most-spoken immigrant languages: currency and
pay-period words, counts of people and children (digits or number words),
"I am N years old" phrasings, immigration-status terms (checked
most-specific first, so "not a citizen" never reads as "citizen"), and US
city/state names as they are written in other scripts.

Digits in any script are mapped to ASCII first (same length, so evidence
spans still point at the user's own text). Every table is data; a language
missing here simply falls back to the follow-up questions.
"""

import re;
import from engine.i18n { ascii_digits }

glob NUM_WORDS: dict = {
    "zh": {"一": 1, "二": 2, "两": 2, "兩": 2, "俩": 2, "倆": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10},
    "ko": {"한": 1, "하나": 1, "두": 2, "둘": 2, "세": 3, "셋": 3, "네": 4, "넷": 4, "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8},
    "ja": {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8},
    "vi": {"một": 1, "hai": 2, "ba": 3, "bốn": 4, "năm": 5, "sáu": 6, "bảy": 7, "tám": 8},
    "tl": {"isa": 1, "dalawa": 2, "tatlo": 3, "apat": 4, "lima": 5, "anim": 6, "pito": 7, "walo": 8},
    "ru": {"один": 1, "одна": 1, "два": 2, "две": 2, "двое": 2, "три": 3, "трое": 3, "четыре": 4, "четверо": 4, "пять": 5, "пятеро": 5, "шесть": 6, "шестеро": 6},
    "uk": {"один": 1, "одна": 1, "два": 2, "дві": 2, "двоє": 2, "три": 3, "троє": 3, "чотири": 4, "четверо": 4, "п'ять": 5, "п’ять": 5, "п'ятеро": 5},
    "ar": {"واحد": 1, "اثنان": 2, "اثنين": 2, "ثلاثة": 3, "ثلاث": 3, "أربعة": 4, "اربعة": 4, "أربع": 4, "خمسة": 5, "خمس": 5, "ستة": 6, "سبعة": 7},
    "fa": {"یک": 1, "دو": 2, "سه": 3, "چهار": 4, "پنج": 5, "شش": 6, "هفت": 7},
    "ur": {"ایک": 1, "دو": 2, "تین": 3, "چار": 4, "پانچ": 5, "چھ": 6, "سات": 7},
    "hi": {"एक": 1, "दो": 2, "तीन": 3, "चार": 4, "पांच": 5, "पाँच": 5, "छह": 6, "छः": 6, "सात": 7},
    "bn": {"এক": 1, "দুই": 2, "তিন": 3, "চার": 4, "পাঁচ": 5, "ছয়": 6, "সাত": 7},
    "pa": {"ਇੱਕ": 1, "ਦੋ": 2, "ਤਿੰਨ": 3, "ਚਾਰ": 4, "ਪੰਜ": 5, "ਛੇ": 6},
    "gu": {"એક": 1, "બે": 2, "ત્રણ": 3, "ચાર": 4, "પાંચ": 5, "છ": 6},
    "te": {"ఒక": 1, "ఒకటి": 1, "రెండు": 2, "మూడు": 3, "నాలుగు": 4, "ఐదు": 5},
    "ta": {"ஒரு": 1, "ஒன்று": 1, "இரண்டு": 2, "மூன்று": 3, "நான்கு": 4, "ஐந்து": 5},
    "fr": {"un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7},
    "ht": {"youn": 1, "de": 2, "twa": 3, "kat": 4, "senk": 5, "sis": 6},
    "pt": {"um": 1, "uma": 1, "dois": 2, "duas": 2, "três": 3, "tres": 3, "quatro": 4, "cinco": 5, "seis": 6},
    "pl": {"jeden": 1, "jedna": 1, "dwa": 2, "dwie": 2, "dwoje": 2, "trzy": 3, "troje": 3, "cztery": 4, "czworo": 4, "pięć": 5, "pięcioro": 5}
};

# Per language: money / month / year / week / hour words, income and expense
# cues (an amount in the same clause as "rent" is not income), no-income
# phrases, household and children patterns — (N) is a count; a pattern with a
# fixed value is [regex, n] — partner and living-alone phrases, age patterns
# and status rules checked in order.
glob FACTS: dict = {
    "zh": {
        "money": r"美元|美金|块钱|塊錢|块|塊|元|刀",
        "month": r"每个月|每個月|每月|一个月|一個月|月薪|月入|月收入|个月|個月|月",
        "year": r"每年|一年|年薪|年收入|年",
        "week": r"每周|每週|每星期|每礼拜|每禮拜|一周|一週|周薪|週薪",
        "hour": r"每小时|每小時|一小时|一小時|时薪|時薪|小时|小時",
        "income": r"收入|工资|工資|挣|掙|赚|賺|薪水|薪|领|領|拿",
        "expense": r"房租|租金|欠|债|債|账单|帳單|罚款|罰款|押金|医药费|醫藥費|电费|電費|费用|費用",
        "no_income": r"没有收入|沒有收入|没收入|沒收入|没有工作|沒有工作|没工作|沒工作|失业|失業|丢了工作|丟了工作|无业|無業",
        "household": [r"(?:家里|家裡|家中|我们|我們|我家|全家|一家)(?:有|一共|共|总共|總共)?\s*(N)\s*(?:个人|個人|口人|口|人)", r"一家\s*(N)\s*口", r"(N)\s*口之家", r"(N)\s*口人"],
        "kids": [r"(N)\s*(?:个|個)\s*(?:孩子|小孩|儿子|兒子|女儿|女兒|娃|宝宝|寶寶)", r"(?:孩子|小孩)\s*(N)\s*(?:个|個)"],
        "partner": r"丈夫|老公|妻子|老婆|太太|爱人|愛人",
        "alone": r"一个人住|一個人住|独居|獨居|自己住|就我一个|就我一個|只有我一个|只有我一個",
        "age": [r"(\d{2,3})\s*(?:岁|歲)", r"(?:今年|年龄|年齡)\s*(\d{2,3})"],
        "cit": [
            [r"不是公民|不是美国公民|不是美國公民|没有身份|沒有身份|没身份|沒身份|无证|無證|非法移民|黑户|黑戶|没有合法身份|沒有合法身份|没有证件|沒有證件|没有绿卡|沒有綠卡|签证过期|簽證過期|申请庇护|申請庇護", "non_citizen"],
            [r"难民|難民|庇护|庇護|人道主义假释|人道主義假釋", "humanitarian"],
            [r"绿卡|綠卡|永久居民", "eligible_immigrant"],
            [r"美国公民|美國公民|公民|入籍|在美国出生|在美國出生", "citizen"]
        ]
    },
    "yue": {
        "money": r"蚊|文",
        "income": r"搵|人工|糧",
        "no_income": r"冇工作|冇收入|冇工開|失咗業|冇咗份工|冇工做",
        "household": [r"屋企(?:有)?\s*(N)\s*(?:個人|个人|口人)", r"(N)\s*個人住"],
        "kids": [r"(N)\s*個\s*(?:仔|女|細路|BB)"],
        "partner": r"老公|老婆",
        "alone": r"一個人住|自己一個住",
        "cit": [[r"冇身份|冇證件|冇綠卡|黑市居留", "non_citizen"]]
    },
    "ko": {
        "money": r"달러|불",
        "month": r"한\s?달에|매달|매월|월급|월\s?수입|달에|월",
        "year": r"1년에|일\s?년에|매년|연봉|연\s?수입|년에",
        "week": r"일주일에|매주|주급|주에",
        "hour": r"시간당|시급|한\s?시간에",
        "income": r"수입|월급|소득|벌어|벌고|번다|급여|연봉|시급|받아|받고",
        "expense": r"월세|집세|렌트|빚|청구서|보증금|요금|병원비|공과금",
        "no_income": r"수입이\s?없|소득이\s?없|직장이\s?없|일자리가\s?없|일이\s?없|실직|무직|해고|일을\s?잃",
        "household": [r"(?:가족|식구|우리)(?:은|는|이|가)?\s*(N)\s*(?:명|식구|인)", r"(N)\s*식구", r"(N)\s*인\s?가족", r"(N)\s*명이\s?(?:살|같이)"],
        "kids": [r"(?:아이|아이들|애|애들|자녀|아들|딸)(?:이|가|은|는)?\s*(N)\s*명", r"(N)\s*명의\s*(?:아이|자녀)"],
        "partner": r"남편|아내|와이프|배우자",
        "alone": r"혼자\s?살|혼자\s?사|독거",
        "age": [r"(\d{2,3})\s*(?:세|살)"],
        "cit": [
            [r"시민권이\s?없|시민이\s?아니|영주권이\s?없|서류\s?미비|불법\s?체류|불법\s?이민|체류\s?자격이\s?없|신분이\s?없|망명\s?신청", "non_citizen"],
            [r"난민|망명", "humanitarian"],
            [r"영주권|그린\s?카드", "eligible_immigrant"],
            [r"미국\s?시민|시민권자|시민권", "citizen"]
        ]
    },
    "ja": {
        "money": r"ドル|弗",
        "month": r"毎月|月に|月収|ひと月|一ヶ月|1ヶ月|か月|ヶ月|月",
        "year": r"毎年|年に|年収|一年|1年|年",
        "week": r"毎週|週に|週給|週",
        "hour": r"時給|1時間|一時間|時間に",
        "income": r"収入|給料|稼|月収|年収|時給|もらって|手取り",
        "expense": r"家賃|借金|請求|料金|医療費|光熱費|ローン",
        "no_income": r"収入がない|収入が無い|収入なし|仕事がない|無職|失業|仕事を失|解雇",
        "household": [r"(N)\s*人(?:家族|暮らし|で(?:住|暮))", r"家族(?:は|が)?\s*(N)\s*人", r"(N)\s*人家族"],
        "kids": [r"(?:子供|子ども|こども|息子|娘)(?:が|は)?\s*(N)\s*人", r"(N)\s*人の(?:子供|子ども|こども)"],
        "partner": r"夫が|夫と|夫は|妻が|妻と|妻は|主人|旦那|配偶者",
        "alone": r"一人暮らし|ひとり暮らし|独り暮らし|一人で住",
        "age": [r"(\d{2,3})\s*(?:歳|才)"],
        "cit": [
            [r"市民権がない|市民ではない|不法滞在|書類がない|在留資格がない|ビザが切れ|亡命申請", "non_citizen"],
            [r"難民|亡命", "humanitarian"],
            [r"グリーンカード|永住権|永住者", "eligible_immigrant"],
            [r"アメリカ市民|米国市民|市民権", "citizen"]
        ]
    },
    "vi": {
        "money": r"đô(?:\s?la)?|mỹ kim|usd",
        "month": r"mỗi tháng|một tháng|hàng tháng|tháng",
        "year": r"mỗi năm|một năm|hàng năm|năm",
        "week": r"mỗi tuần|một tuần|hàng tuần|tuần",
        "hour": r"mỗi giờ|một giờ|giờ",
        "income": r"thu nhập|lương|kiếm|làm được|được trả|lãnh|lĩnh",
        "expense": r"tiền nhà|tiền thuê|thuê nhà|nợ|hóa đơn|hoá đơn|tiền điện|tiền cọc|phí",
        "no_income": r"không có thu nhập|không có việc|mất việc|thất nghiệp|bị sa thải",
        "household": [r"(?:gia đình|nhà)(?:\s+(?:tôi|em|mình|chúng tôi))?\s+(?:có\s+)?(N)\s+người", r"(?:chúng tôi|tụi tôi|chúng em)\s+(?:có\s+)?(N)\s+người", r"(N)\s+người\s+(?:trong|sống)"],
        "kids": [r"(N)\s+(?:đứa\s+)?(?:con|đứa con|đứa trẻ|cháu|em bé)(?![a-zà-ỹ])", r"có\s+(N)\s+đứa"],
        "partner": r"chồng|vợ|bạn đời",
        "alone": r"sống một mình|ở một mình|chỉ mình tôi",
        "age": [r"(\d{2,3})\s+tuổi"],
        "cit": [
            [r"không có giấy tờ|không giấy tờ|bất hợp pháp|không phải công dân|quá hạn visa|xin tị nạn|xin tỵ nạn", "non_citizen"],
            [r"tị nạn|tỵ nạn|tạm dung nhân đạo", "humanitarian"],
            [r"thẻ xanh|thường trú nhân|thường trú", "eligible_immigrant"],
            [r"công dân mỹ|công dân|nhập tịch|quốc tịch mỹ|sinh ra ở mỹ", "citizen"]
        ]
    },
    "tl": {
        "money": r"dolyar|dolar",
        "month": r"kada buwan|isang buwan|bawat buwan|buwan-buwan|buwan",
        "year": r"kada taon|isang taon|bawat taon|taon",
        "week": r"kada linggo|isang linggo|bawat linggo",
        "hour": r"kada oras|isang oras|bawat oras|oras",
        "income": r"kita|kumikita|sahod|sweldo|suweldo|natatanggap|kinikita",
        "expense": r"upa|renta|utang|bayarin|singil|deposito",
        "no_income": r"walang trabaho|walang kita|nawalan ng trabaho|natanggal sa trabaho|walang sahod",
        "household": [r"(N)\s+(?:kami|kaming)(?![a-z])", r"kami\s+ay\s+(N)", r"(N)\s+(?:katao|tao)\s+(?:kami|sa\s+bahay)", r"pamilya\s+(?:ng|na)\s+(N)"],
        "kids": [r"(N)\s+(?:na\s+|ang\s+)?(?:anak|bata)(?![a-z])"],
        "partner": r"asawa|mister|misis",
        "alone": r"mag-isa|nag-iisa|mag isa|ako lang",
        "age": [r"(\d{2,3})\s+(?:taong gulang|taon gulang|taon na ako|anyos)", r"edad\s+(?:ko\s+)?(?:ay\s+)?(\d{2,3})"],
        "cit": [
            [r"walang papeles|walang dokumento|tnt|hindi mamamayan|overstay|nag-apply ng asylum", "non_citizen"],
            [r"refugee|asylee|asylum", "humanitarian"],
            [r"green card|permanenteng residente|permanent resident", "eligible_immigrant"],
            [r"mamamayang amerikano|mamamayan|us citizen|citizen", "citizen"]
        ]
    },
    "ru": {
        "money": r"доллар\w*|долл\.?|бакс\w*",
        "month": r"в месяц|ежемесячно|за месяц|месяц\w*|в мес",
        "year": r"в год|за год|ежегодно|год\w*",
        "week": r"в неделю|за неделю|еженедельно|недел\w*",
        "hour": r"в час|за час|час\w*",
        "income": r"доход\w*|зарплат\w*|зарабат\w*|получа\w*|пенси\w*|пособи\w*",
        "expense": r"аренд\w*|квартплат\w*|долг\w*|задолж\w*|сч[её]т\w*|штраф\w*|залог\w*|коммунал\w*",
        "no_income": r"нет дохода|без дохода|нет работы|без работы|потерял\w* работу|безработн\w*|уволил\w*|уволен\w*",
        "household": [r"нас\s+(N)", r"семья\s+из\s+(N)", r"в\s+семье\s+(N)", r"(N)\s+человек(?![а-яё])"],
        "kids": [r"(N)\s+(?:детей|ребенка|ребёнка|ребенок|ребёнок|сына|сыновей|дочери|дочерей|дочки|дочек)"],
        "partner": r"(?<![а-яё])(?:муж|жена|мужем|женой|супруг\w*)(?![а-яё])",
        "alone": r"живу один|живу одна|живу сам|живу сама",
        "age": [r"мне\s+(\d{2,3})(?:\s+(?:лет|год|года))?", r"возраст\w*\s+(\d{2,3})"],
        "cit": [
            [r"без документов|нелегал\w*|не гражданин|не гражданка|нет статуса|без статуса|просроч\w* виз\w*|прошу убежищ\w*|подал\w* на убежищ\w*|ищу убежищ\w*|tps", "non_citizen"],
            [r"беженец|беженка|беженц\w*|убежищ\w*|гуманитарн\w* пароль|u4u", "humanitarian"],
            [r"грин[\s-]?карт\w*|вид на жительство|постоянн\w* жител\w*", "eligible_immigrant"],
            [r"гражданин|гражданка|гражданство", "citizen"]
        ]
    },
    "uk": {
        "money": r"долар\w*|дол\.?",
        "month": r"на місяць|щомісяця|за місяць|місяц\w*|місяць",
        "year": r"на рік|за рік|щороку|рік|року",
        "week": r"на тиждень|щотижня|тижд\w*",
        "hour": r"на годину|за годину|годин\w*",
        "income": r"дохід|доход\w*|зарплат\w*|заробля\w*|отриму\w*|пенсі\w*",
        "expense": r"оренд\w*|квартплат\w*|борг\w*|рахун\w*|штраф\w*|застав\w*|комунал\w*",
        "no_income": r"немає доходу|без доходу|немає роботи|без роботи|втратив\w* роботу|безробітн\w*|звільнил\w*",
        "household": [r"нас\s+(N)", r"сім['’]я\s+з\s+(N)", r"(N)\s+(?:людей|людини|осіб|особи)"],
        "kids": [r"(N)\s+(?:дітей|дитини|дитина|сина|синів|доньки|дочки|доньок)"],
        "partner": r"(?:мій|моя|з)\s+(?:чоловік\w*|дружин\w*)",
        "alone": r"живу сам|живу сама|живу один|живу одна",
        "age": [r"мені\s+(\d{2,3})", r"вік\w*\s+(\d{2,3})"],
        "cit": [
            [r"без документів|нелегал\w*|не громадян\w*|немає статусу|без статусу|прошу притулку|тимчасов\w* захист|tps", "non_citizen"],
            [r"біженець|біженка|біженц\w*|притул\w*|u4u|гуманітарн\w* пароль", "humanitarian"],
            [r"грін[\s-]?карт\w*|постійн\w* мешкан\w*", "eligible_immigrant"],
            [r"громадянин|громадянка|громадянство", "citizen"]
        ]
    },
    "ar": {
        "money": r"دولار\w*|دولارات",
        "month": r"شهري[اًا]?|في الشهر|بالشهر|كل شهر|شهر\w*",
        "year": r"سنوي[اًا]?|في السنة|بالسنة|كل سنة|في العام|سنة|عام",
        "week": r"أسبوعي[اًا]?|في الأسبوع|بالأسبوع|كل أسبوع|أسبوع",
        "hour": r"في الساعة|بالساعة|ساعة",
        "income": r"دخل\w*|راتب\w*|أكسب|اكسب|أتقاضى|اتقاضى|أحصل|احصل|معاش|أجر\w*|نكسب",
        "expense": r"إيجار|ايجار|الإيجار|الايجار|دين|ديون|فاتورة|فواتير|غرامة",
        "no_income": r"لا دخل|بدون دخل|ليس لدي دخل|ليس عندي دخل|ما عندي دخل|بلا عمل|بدون عمل|ليس لدي عمل|ما عندي شغل|عاطل|فقدت عملي|فقدت وظيفتي|طردت من العمل",
        "household": [r"(?:نحن|عائلتي|أسرتي|اسرتي|عائلة من|أسرة من)\s+(N)", r"(N)\s+(?:أشخاص|اشخاص|أفراد|افراد)"],
        "kids": [r"(N)\s+(?:أطفال|اطفال|أولاد|اولاد|أبناء|ابناء|بنات)", [r"طفلان|طفلين|ولدين|ولدان", 2]],
        "partner": r"زوجي|زوجتي",
        "alone": r"أعيش وحدي|اعيش وحدي|أعيش بمفردي|اعيش بمفردي",
        "age": [r"عمري\s+(\d{2,3})", r"(\d{2,3})\s+(?:عاما|عامًا|سنة)\s+من العمر"],
        "cit": [
            [r"بدون أوراق|بدون اوراق|بلا أوراق|غير موثق|غير شرعي|لست مواطن|ليس لدي إقامة|طالب لجوء|طلب لجوء|أطلب اللجوء", "non_citizen"],
            [r"لاجئ|لاجئة|لجوء", "humanitarian"],
            [r"جرين كارد|غرين كارد|البطاقة الخضراء|الكرت الأخضر|إقامة دائمة|اقامة دائمة|مقيم دائم", "eligible_immigrant"],
            [r"مواطن أمريكي|مواطنة أمريكية|الجنسية الأمريكية|مواطن|مواطنة", "citizen"]
        ]
    },
    "fa": {
        "money": r"دلار",
        "month": r"ماهانه|در ماه|ماهی|هر ماه|ماه",
        "year": r"سالانه|در سال|سالی|هر سال|سال",
        "week": r"هفتگی|در هفته|هر هفته|هفته",
        "hour": r"ساعتی|در ساعت|ساعت",
        "income": r"درآمد|حقوق|درمیارم|در میارم|می‌گیرم|میگیرم",
        "expense": r"اجاره|کرایه|بدهی|قرض|قبض|جریمه|ودیعه",
        "no_income": r"درآمد ندارم|بی‌درآمد|بدون درآمد|کار ندارم|بیکار|بی‌کار|اخراج شدم",
        "household": [r"(N)\s*(?:نفر|نفریم|نفره)(?!\s*(?:بچه|فرزند))", r"خانواده\s*(?:ی|ام|مان)?\s*(N)\s*نفر"],
        "kids": [r"(N)\s*(?:تا\s*)?(?:بچه|فرزند|پسر|دختر)"],
        "partner": r"همسرم|شوهرم|زنم",
        "alone": r"تنها زندگی|تنهایی زندگی",
        "age": [r"(\d{2,3})\s*سالمه", r"(\d{2,3})\s*سال\s*(?:دارم|سن)", r"سنم\s*(\d{2,3})"],
        "cit": [
            [r"بدون مدرک|بی‌مدرک|غیرقانونی|شهروند نیستم|اقامت ندارم|درخواست پناهندگی|پناهجو", "non_citizen"],
            [r"پناهنده|پناهندگی", "humanitarian"],
            [r"گرین کارت|گرین‌کارت|اقامت دائم", "eligible_immigrant"],
            [r"شهروند آمریکا|تابعیت آمریکا|شهروند", "citizen"]
        ]
    },
    "ur": {
        "money": r"ڈالر",
        "month": r"ماہانہ|ہر مہینے|مہینے|مہینہ|ماہ",
        "year": r"سالانہ|سال",
        "week": r"ہفتہ وار|ہفتے|ہفتہ",
        "hour": r"گھنٹہ|گھنٹے",
        "income": r"آمدنی|آمدن|تنخواہ|کماتا|کماتی|کماتے|کمائی",
        "expense": r"کرایہ|قرض|جرمانہ",
        "no_income": r"کوئی آمدنی نہیں|آمدنی نہیں|نوکری نہیں|بے روزگار|بےروزگار|کام نہیں|نوکری چلی گئی",
        "household": [r"ہم\s*(N)\s*(?:لوگ|افراد)", r"(N)\s*افراد"],
        "kids": [r"(N)\s*(?:بچے|بچوں|بچہ|بیٹے|بیٹیاں)"],
        "partner": r"شوہر|بیوی|اہلیہ",
        "alone": r"اکیلا رہتا|اکیلی رہتی|اکیلے رہتا|اکیلے رہتی",
        "age": [r"میری عمر\s*(\d{2,3})", r"(\d{2,3})\s*سال\s*(?:کا|کی)"],
        "cit": [
            [r"کاغذات نہیں|بغیر کاغذات|غیر قانونی|شہری نہیں|سیاسی پناہ کی درخواست", "non_citizen"],
            [r"پناہ گزین|سیاسی پناہ", "humanitarian"],
            [r"گرین کارڈ|مستقل رہائش", "eligible_immigrant"],
            [r"امریکی شہری|شہریت|شہری", "citizen"]
        ]
    },
    "hi": {
        "money": r"डॉलर|डालर",
        "month": r"हर महीने|प्रति माह|महीने|महीना|मासिक|माह",
        "year": r"सालाना|प्रति वर्ष|वार्षिक|साल|वर्ष",
        "week": r"हर हफ्ते|हफ्ते|हफ़्ते|सप्ताह",
        "hour": r"प्रति घंटा|घंटे|घंटा",
        "income": r"कमाई|कमाता|कमाती|कमाते|आमदनी|आय|तनख्वाह|तनख़्वाह|वेतन|सैलरी|पेंशन",
        "expense": r"किराया|किराए|कर्ज|कर्ज़|क़र्ज़|उधार|जुर्माना",
        "no_income": r"कोई आय नहीं|आमदनी नहीं|आय नहीं|कमाई नहीं|नौकरी नहीं|काम नहीं|बेरोजगार|बेरोज़गार|नौकरी चली गई|नौकरी छूट",
        "household": [r"हम\s*(N)\s*(?:लोग|सदस्य|जन)", r"परिवार\s*में\s*(N)", r"(N)\s*(?:लोग|सदस्य)\s*(?:हैं|रहते)"],
        "kids": [r"(N)\s*(?:बच्चे|बच्चों|बच्चा|बेटे|बेटियां|बेटियाँ|बेटा|बेटी)"],
        "partner": r"पति|पत्नी|घरवाली|घरवाला",
        "alone": r"अकेला रहता|अकेली रहती|अकेले रहता|अकेले रहती",
        "age": [r"मेरी उम्र\s*(\d{2,3})", r"(\d{2,3})\s*साल\s*(?:का|की)", r"उम्र\s*(\d{2,3})"],
        "cit": [
            [r"कागजात नहीं|काग़ज़ात नहीं|बिना कागज|गैरकानूनी|ग़ैरक़ानूनी|नागरिक नहीं|शरण के लिए आवेदन|शरण मांग", "non_citizen"],
            [r"शरणार्थी|शरण", "humanitarian"],
            [r"ग्रीन कार्ड|स्थायी निवासी", "eligible_immigrant"],
            [r"अमेरिकी नागरिक|नागरिकता|नागरिक", "citizen"]
        ]
    },
    "bn": {
        "money": r"ডলার",
        "month": r"প্রতি মাসে|মাসে|মাসিক|মাস",
        "year": r"প্রতি বছর|বছরে|বার্ষিক|বছর",
        "week": r"প্রতি সপ্তাহে|সপ্তাহে|সপ্তাহ",
        "hour": r"প্রতি ঘণ্টা|ঘণ্টায়|ঘণ্টা",
        "income": r"আয়|আয়|রোজগার|বেতন|কামাই|উপার্জন",
        "expense": r"ভাড়া|ঋণ|দেনা|জরিমানা",
        "no_income": r"কোনো আয় নেই|আয় নেই|আয় নেই|চাকরি নেই|কাজ নেই|বেকার|চাকরি চলে গেছে|চাকরি হারিয়েছি",
        "household": [r"আমরা\s*(N)\s*জন", r"পরিবারে\s*(N)\s*জন", r"(N)\s*জন\s*(?:মানুষ|সদস্য)"],
        "kids": [r"(N)\s*(?:টি|টা|জন)?\s*(?:বাচ্চা|সন্তান|ছেলে|মেয়ে|মেয়ে)"],
        "partner": r"স্বামী|স্ত্রী",
        "alone": r"একা থাকি|একাই থাকি",
        "age": [r"বয়স\s*(\d{2,3})", r"বয়স\s*(\d{2,3})"],
        "cit": [
            [r"কাগজপত্র নেই|কাগজ নেই|অবৈধ|নাগরিক নই|আশ্রয়ের আবেদন|আশ্রয়প্রার্থী", "non_citizen"],
            [r"শরণার্থী", "humanitarian"],
            [r"গ্রিন কার্ড|গ্রীন কার্ড|স্থায়ী বাসিন্দা", "eligible_immigrant"],
            [r"মার্কিন নাগরিক|আমেরিকান নাগরিক|নাগরিক", "citizen"]
        ]
    },
    "pa": {
        "money": r"ਡਾਲਰ",
        "month": r"ਹਰ ਮਹੀਨੇ|ਮਹੀਨੇ|ਮਹੀਨਾ",
        "year": r"ਸਾਲਾਨਾ|ਸਾਲ",
        "week": r"ਹਫ਼ਤੇ|ਹਫਤੇ|ਹਫ਼ਤਾ",
        "hour": r"ਘੰਟੇ|ਘੰਟਾ",
        "income": r"ਕਮਾਈ|ਕਮਾਉਂਦਾ|ਕਮਾਉਂਦੀ|ਤਨਖਾਹ|ਤਨਖ਼ਾਹ|ਆਮਦਨ|ਆਮਦਨੀ",
        "expense": r"ਕਿਰਾਇਆ|ਕਿਰਾਏ|ਕਰਜ਼|ਕਰਜ਼ਾ",
        "no_income": r"ਕੋਈ ਆਮਦਨ ਨਹੀਂ|ਆਮਦਨ ਨਹੀਂ|ਨੌਕਰੀ ਨਹੀਂ|ਕੰਮ ਨਹੀਂ|ਬੇਰੁਜ਼ਗਾਰ|ਨੌਕਰੀ ਚਲੀ ਗਈ|ਨੌਕਰੀ ਛੁੱਟ",
        "household": [r"ਅਸੀਂ\s*(N)\s*(?:ਜੀਅ|ਜਣੇ|ਲੋਕ)", r"ਪਰਿਵਾਰ\s*ਵਿੱਚ\s*(N)", r"(N)\s*(?:ਜੀਅ|ਜਣੇ|ਮੈਂਬਰ)"],
        "kids": [r"(N)\s*(?:ਬੱਚੇ|ਬੱਚਾ|ਬੱਚਿਆਂ|ਪੁੱਤਰ|ਧੀਆਂ|ਮੁੰਡੇ|ਕੁੜੀਆਂ)"],
        "partner": r"ਪਤੀ|ਪਤਨੀ|ਘਰਵਾਲੀ|ਘਰਵਾਲਾ",
        "alone": r"ਇਕੱਲਾ ਰਹਿੰਦਾ|ਇਕੱਲੀ ਰਹਿੰਦੀ",
        "age": [r"ਮੇਰੀ ਉਮਰ\s*(\d{2,3})", r"ਉਮਰ\s*(\d{2,3})", r"(\d{2,3})\s*ਸਾਲ\s*(?:ਦਾ|ਦੀ)"],
        "cit": [
            [r"ਕਾਗਜ਼ ਨਹੀਂ|ਬਿਨਾਂ ਕਾਗਜ਼|ਗੈਰ-ਕਾਨੂੰਨੀ|ਗੈਰ ਕਾਨੂੰਨੀ|ਨਾਗਰਿਕ ਨਹੀਂ|ਅਸਾਇਲਮ|ਸ਼ਰਨ ਲਈ", "non_citizen"],
            [r"ਸ਼ਰਨਾਰਥੀ|ਰਫਿਊਜੀ", "humanitarian"],
            [r"ਗ੍ਰੀਨ ਕਾਰਡ|ਗਰੀਨ ਕਾਰਡ", "eligible_immigrant"],
            [r"ਅਮਰੀਕੀ ਨਾਗਰਿਕ|ਸਿਟੀਜ਼ਨ|ਨਾਗਰਿਕ", "citizen"]
        ]
    },
    "gu": {
        "money": r"ડોલર|ડૉલર",
        "month": r"દર મહિને|મહિને|મહિનો|માસિક",
        "year": r"વાર્ષિક|વર્ષે|વર્ષ",
        "week": r"અઠવાડિયે|અઠવાડિયું|સપ્તાહ",
        "hour": r"કલાકે|કલાક",
        "income": r"આવક|પગાર|કમાણી|કમાઉં|કમાઉ",
        "expense": r"ભાડું|ભાડા|દેવું|લોન",
        "no_income": r"કોઈ આવક નથી|આવક નથી|નોકરી નથી|કામ નથી|બેરોજગાર|નોકરી છૂટી|નોકરી ગઈ",
        "household": [r"અમે\s*(N)\s*(?:જણ|લોકો|સભ્યો)", r"પરિવારમાં\s*(N)", r"(N)\s*(?:જણ|સભ્યો)"],
        "kids": [r"(N)\s*(?:બાળકો|બાળક|છોકરા|છોકરી|દીકરા|દીકરી)"],
        "partner": r"પતિ|પત્ની|વાઇફ|હસબન્ડ",
        "alone": r"એકલો રહું|એકલી રહું",
        "age": [r"મારી ઉંમર\s*(\d{2,3})", r"ઉંમર\s*(\d{2,3})", r"(\d{2,3})\s*વર્ષ\s*(?:નો|ની)"],
        "cit": [
            [r"કાગળો નથી|દસ્તાવેજ નથી|ગેરકાયદેસર|નાગરિક નથી|આશ્રય માટે અરજી", "non_citizen"],
            [r"શરણાર્થી|રેફ્યુજી", "humanitarian"],
            [r"ગ્રીન કાર્ડ|કાયમી રહેવાસી", "eligible_immigrant"],
            [r"અમેરિકન નાગરિક|સિટીઝન|નાગરિક", "citizen"]
        ]
    },
    "te": {
        "money": r"డాలర్లు|డాలర్",
        "month": r"ప్రతి నెల|నెలకు|నెలకి|నెల",
        "year": r"సంవత్సరానికి|ఏడాదికి|సంవత్సరం|ఏడాది",
        "week": r"వారానికి|వారం",
        "hour": r"గంటకు|గంటకి|గంట",
        "income": r"ఆదాయం|జీతం|సంపాదన|సంపాదిస్తా",
        "expense": r"అద్దె|అప్పు|బిల్లు|రుణం",
        "no_income": r"ఆదాయం లేదు|ఉద్యోగం లేదు|పని లేదు|నిరుద్యోగ|ఉద్యోగం పోయింది",
        "household": [r"మేము\s*(N)\s*(?:మంది|మందిమి)", r"కుటుంబంలో\s*(N)\s*మంది", r"(N)\s*మంది(?!\s*(?:పిల్ల|బిడ్డ|కొడుకు|కూతు))"],
        "kids": [r"(N)\s*(?:మంది\s*)?(?:పిల్లలు|బిడ్డలు|కొడుకులు|కూతుళ్లు)"],
        "partner": r"భర్త|భార్య",
        "alone": r"ఒంటరిగా ఉంటాను|ఒక్కడినే|ఒక్కదాన్నే",
        "age": [r"నా వయసు\s*(\d{2,3})", r"వయసు\s*(\d{2,3})", r"(\d{2,3})\s*సంవత్సరాల"],
        "cit": [
            [r"పత్రాలు లేవు|డాక్యుమెంట్లు లేవు|అక్రమ|పౌరుడిని కాదు|ఆశ్రయం కోసం", "non_citizen"],
            [r"శరణార్థి", "humanitarian"],
            [r"గ్రీన్ కార్డ్|శాశ్వత నివాసి", "eligible_immigrant"],
            [r"అమెరికా పౌరుడు|అమెరికా పౌరురాలు|పౌరసత్వం|పౌరుడు", "citizen"]
        ]
    },
    "ta": {
        "money": r"டாலர",
        "month": r"ஒவ்வொரு மாதமும்|மாதத்திற்கு|மாதத்துக்கு|மாதம்|மாத",
        "year": r"வருடத்திற்கு|ஆண்டுக்கு|வருடம்|ஆண்டு|வருட",
        "week": r"வாரத்திற்கு|வாரம்|வார",
        "hour": r"மணி நேரத்திற்கு|மணிக்கு",
        "income": r"வருமானம்|சம்பளம்|சம்பாதி|வருவாய்",
        "expense": r"வாடகை|கடன்|அபராதம்",
        "no_income": r"வருமானம் இல்லை|வேலை இல்லை|வேலையில்லை|வேலை போய்விட்டது|வேலையை இழந்த",
        "household": [r"நாங்கள்\s*(N)\s*(?:பேர்|நபர்)", r"குடும்பத்தில்\s*(N)\s*(?:பேர்|நபர்)", r"(N)\s*(?:பேர்|நபர்கள்)(?!\s*(?:குழந்தை|பிள்ளை))"],
        "kids": [r"(N)\s*(?:குழந்தை|பிள்ளை|மகன்|மகள்)"],
        "partner": r"கணவர்|கணவன்|மனைவி",
        "alone": r"தனியாக வசிக்கிறேன்|தனியாக இருக்கிறேன்",
        "age": [r"எனக்கு\s*(\d{2,3})\s*வயது", r"வயது\s*(\d{2,3})", r"(\d{2,3})\s*வயது"],
        "cit": [
            [r"ஆவணங்கள் இல்லை|ஆவணம் இல்லை|சட்டவிரோத|குடிமகன் இல்லை|தஞ்சம் கோரி", "non_citizen"],
            [r"அகதி", "humanitarian"],
            [r"கிரீன் கார்டு|கிரீன் கார்ட்|நிரந்தர குடியுரிமை|நிரந்தர வசிப்பிட", "eligible_immigrant"],
            [r"அமெரிக்க குடிமகன்|அமெரிக்க குடியுரிமை|குடிமகன்|குடியுரிமை", "citizen"]
        ]
    },
    "fr": {
        "money": r"dollars?",
        "month": r"par mois|chaque mois|mensuel\w*|/mois|mois",
        "year": r"par an|par année|chaque année|annuel\w*|/an|ans?(?![a-z])",
        "week": r"par semaine|chaque semaine|hebdomadaire|semaine",
        "hour": r"de l'heure|par heure|/h(?![a-z])|heure",
        "income": r"gagne|gagnons|revenus?|salaire|touche|pension|allocations?",
        "expense": r"loyer|dettes?|factures?|amende|caution|dois",
        "no_income": r"pas de revenus?|aucun revenu|sans revenus?|sans emploi|pas de travail|chômage|chômeur|chômeuse|perdu mon (?:travail|emploi)|licencié\w*",
        "household": [r"nous sommes\s+(N)", r"famille de\s+(N)", r"foyer de\s+(N)", r"(N)\s+personnes\s+(?:à la maison|dans (?:la|ma) famille|chez nous)"],
        "kids": [r"(N)\s+(?:enfants?|fils|filles?|bébés?|gosses)(?![a-z])"],
        "partner": r"mon mari|ma femme|mon époux|mon épouse|mon conjoint|ma conjointe",
        "alone": r"je vis seule?|j['’]habite seule?",
        "age": [r"j['’]ai\s+(\d{2,3})\s+ans", r"âgée?\s+de\s+(\d{2,3})"],
        "cit": [
            [r"sans[\s-]papiers|pas de papiers|sans statut|pas citoyenne?|demande d['’]asile|demandeu(?:r|se) d['’]asile|situation irrégulière", "non_citizen"],
            [r"réfugiée?|asile accordé|asilée?", "humanitarian"],
            [r"carte verte|green card|résidente? permanente?", "eligible_immigrant"],
            [r"citoyenne? américaine?|citoyenne?", "citizen"]
        ]
    },
    "ht": {
        "money": r"dola|dolà",
        "month": r"pa mwa|chak mwa|mwa",
        "year": r"pa ane|chak ane|lane|ane",
        "week": r"pa semèn|chak semèn|semèn",
        "hour": r"pa lè",
        "income": r"touche|salè|revni|pansyon|m fè|mwen fè",
        "expense": r"lwaye|dèt|bòdwo|amann|kosyon",
        "no_income": r"pa gen travay|pa gen revni|san travay|pèdi travay|chomaj|m pa travay",
        "household": [r"nou\s+(N)\s+(?:moun|nan fanmi)", r"fanmi\s+(?:mwen\s+)?(?:gen\s+)?(N)\s+moun", r"(N)\s+moun\s+(?:lakay|nan kay)"],
        "kids": [r"(N)\s+(?:timoun|pitit|ti moun)"],
        "partner": r"mari m|mari mwen|madanm mwen|madanm m",
        "alone": r"poukont mwen|pou kont mwen",
        "age": [r"(?:mwen|m)\s+gen\s+(\d{2,3})\s+an"],
        "cit": [
            [r"san papye|pa gen papye|pa sitwayen|pa gen estati|mande azil|demann azil", "non_citizen"],
            [r"refijye|azil|parol imanitè|paròl imanitè", "humanitarian"],
            [r"kat vèt|green card|rezidan pèmanan", "eligible_immigrant"],
            [r"sitwayen ameriken|sitwayen|natiralize", "citizen"]
        ]
    },
    "pt": {
        "money": r"dólares?|dolares?",
        "month": r"por mês|ao mês|mensal\w*|/mês|mês",
        "year": r"por ano|ao ano|anual\w*|/ano|ano(?![a-z])",
        "week": r"por semana|semanal\w*|semana",
        "hour": r"por hora|/hora|hora",
        "income": r"ganho|ganhamos|recebo|recebemos|renda|salário|salario|aposentadoria|pensão",
        "expense": r"aluguel|aluguer|renda de casa|dívida|divida|contas?|multa|caução|devo",
        "no_income": r"sem renda|sem trabalho|sem emprego|desempregad[oa]|perdi (?:o|meu) (?:emprego|trabalho)|não tenho (?:renda|trabalho|emprego)|nao tenho (?:renda|trabalho|emprego)",
        "household": [r"somos\s+(N)", r"família de\s+(N)", r"(N)\s+pessoas\s+(?:em casa|na (?:minha )?família)"],
        "kids": [r"(N)\s+(?:filhos?|filhas?|crianças|bebês?)(?![a-z])"],
        "partner": r"meu marido|minha esposa|minha mulher|meu esposo|meu companheiro|minha companheira",
        "alone": r"moro sozinh[oa]|vivo sozinh[oa]",
        "age": [r"tenho\s+(\d{2,3})\s+anos", r"(\d{2,3})\s+anos de idade"],
        "cit": [
            [r"sem documentos|indocumentad[oa]|sem papéis|ilegal|não sou cidad(?:ão|ã)|pedido de asilo|pedindo asilo|solicitante de asilo", "non_citizen"],
            [r"refugiad[oa]|asilad[oa]|asilo concedido", "humanitarian"],
            [r"green card|cartão verde|residente permanente", "eligible_immigrant"],
            [r"cidad(?:ão|ã) american[oa]|cidad(?:ão|ã)|cidadania", "citizen"]
        ]
    },
    "pl": {
        "money": r"dolar\w*",
        "month": r"miesięcznie|na miesiąc|co miesiąc|miesiąc\w*|mies\.",
        "year": r"rocznie|na rok|co roku|rok\w*",
        "week": r"tygodniowo|na tydzień|tydzień|tygodni\w*",
        "hour": r"na godzinę|za godzinę|godzin\w*",
        "income": r"zarabiam\w*|dochód|dochodu|pensj\w*|wynagrodzeni\w*|emerytur\w*|dostaję",
        "expense": r"czynsz\w*|dług\w*|rachun\w*|opłat\w*|kaucj\w*|mandat\w*",
        "no_income": r"bez dochodu|nie mam dochodu|nie mam pracy|bez pracy|bezrobotn\w*|straciłe[mś] pracę|straciłam pracę|zwolnion\w*",
        "household": [r"jest nas\s+(N)", r"rodzina\s+(N)[\s-]*osobowa", r"(N)\s+os(?:oby|ób)\s+w\s+domu"],
        "kids": [r"(N)\s+(?:dzieci|dziecko|synów|syna|córki|córek)"],
        "partner": r"mój mąż|moja żona|mąż|żona",
        "alone": r"mieszkam sam|mieszkam sama",
        "age": [r"mam\s+(\d{2,3})\s+lat", r"wiek\w*\s+(\d{2,3})"],
        "cit": [
            [r"bez dokumentów|nielegaln\w*|nie jestem obywatel\w*|bez statusu|ubiegam się o azyl", "non_citizen"],
            [r"uchodźc\w*|azyl\w*", "humanitarian"],
            [r"zielon\w* kart\w*|green card|stał\w* rezydent\w*", "eligible_immigrant"],
            [r"obywatel\w*", "citizen"]
        ]
    }
};

# US cities and states as written in other scripts → (city, state).
# Longer names are matched first ("纽约州" is the state, "纽约" the city).
glob PLACES: dict = {
    "休斯顿": ["Houston", "TX"], "休士頓": ["Houston", "TX"], "侯斯頓": ["Houston", "TX"], "达拉斯": ["Dallas", "TX"], "達拉斯": ["Dallas", "TX"],
    "奥斯汀": ["Austin", "TX"], "奧斯汀": ["Austin", "TX"], "圣安东尼奥": ["San Antonio", "TX"], "聖安東尼奧": ["San Antonio", "TX"],
    "洛杉矶": ["Los Angeles", "CA"], "洛杉磯": ["Los Angeles", "CA"], "旧金山": ["San Francisco", "CA"], "舊金山": ["San Francisco", "CA"], "三藩市": ["San Francisco", "CA"],
    "圣地亚哥": ["San Diego", "CA"], "聖地牙哥": ["San Diego", "CA"], "圣何塞": ["San Jose", "CA"], "聖荷西": ["San Jose", "CA"], "奥克兰": ["Oakland", "CA"], "奧克蘭": ["Oakland", "CA"],
    "萨克拉门托": ["Sacramento", "CA"], "沙加緬度": ["Sacramento", "CA"], "圣盖博": ["San Gabriel", "CA"], "聖蓋博": ["San Gabriel", "CA"],
    "纽约州": ["", "NY"], "紐約州": ["", "NY"], "纽约": ["New York", "NY"], "紐約": ["New York", "NY"], "布鲁克林": ["Brooklyn", "NY"], "布魯克林": ["Brooklyn", "NY"],
    "皇后区": ["Queens", "NY"], "皇后區": ["Queens", "NY"], "法拉盛": ["Flushing", "NY"], "芝加哥": ["Chicago", "IL"], "迈阿密": ["Miami", "FL"], "邁阿密": ["Miami", "FL"],
    "奥兰多": ["Orlando", "FL"], "奧蘭多": ["Orlando", "FL"], "凤凰城": ["Phoenix", "AZ"], "鳳凰城": ["Phoenix", "AZ"], "亚特兰大": ["Atlanta", "GA"], "亞特蘭大": ["Atlanta", "GA"],
    "西雅图": ["Seattle", "WA"], "西雅圖": ["Seattle", "WA"], "波士顿": ["Boston", "MA"], "波士頓": ["Boston", "MA"], "费城": ["Philadelphia", "PA"], "費城": ["Philadelphia", "PA"],
    "底特律": ["Detroit", "MI"], "丹佛": ["Denver", "CO"], "拉斯维加斯": ["Las Vegas", "NV"], "拉斯維加斯": ["Las Vegas", "NV"], "波特兰": ["Portland", "OR"], "波特蘭": ["Portland", "OR"],
    "明尼阿波利斯": ["Minneapolis", "MN"], "巴尔的摩": ["Baltimore", "MD"], "檀香山": ["Honolulu", "HI"],
    "加州": ["", "CA"], "加利福尼亚": ["", "CA"], "加利福尼亞": ["", "CA"], "德州": ["", "TX"], "得克萨斯": ["", "TX"], "德克萨斯": ["", "TX"], "德克薩斯": ["", "TX"],
    "佛州": ["", "FL"], "佛罗里达": ["", "FL"], "佛羅里達": ["", "FL"], "伊利诺伊": ["", "IL"], "伊利諾": ["", "IL"], "新泽西": ["", "NJ"], "新澤西": ["", "NJ"],
    "华盛顿州": ["", "WA"], "華盛頓州": ["", "WA"], "麻州": ["", "MA"], "马萨诸塞": ["", "MA"], "宾州": ["", "PA"], "賓州": ["", "PA"], "宾夕法尼亚": ["", "PA"],
    "佐治亚": ["", "GA"], "乔治亚": ["", "GA"], "喬治亞": ["", "GA"], "弗吉尼亚": ["", "VA"], "維吉尼亞": ["", "VA"], "马里兰": ["", "MD"], "馬里蘭": ["", "MD"],
    "密歇根": ["", "MI"], "密西根": ["", "MI"], "明尼苏达": ["", "MN"], "亚利桑那": ["", "AZ"], "北卡": ["", "NC"], "俄亥俄": ["", "OH"], "内华达": ["", "NV"], "內華達": ["", "NV"],
    "科罗拉多": ["", "CO"], "俄勒冈": ["", "OR"], "夏威夷": ["", "HI"],
    "휴스턴": ["Houston", "TX"], "댈러스": ["Dallas", "TX"], "달라스": ["Dallas", "TX"], "오스틴": ["Austin", "TX"], "로스앤젤레스": ["Los Angeles", "CA"], "엘에이": ["Los Angeles", "CA"],
    "샌프란시스코": ["San Francisco", "CA"], "샌디에이고": ["San Diego", "CA"], "산호세": ["San Jose", "CA"], "새너제이": ["San Jose", "CA"], "오클랜드": ["Oakland", "CA"],
    "la에": ["Los Angeles", "CA"], "la에서": ["Los Angeles", "CA"], "뉴욕주": ["", "NY"], "뉴욕": ["New York", "NY"], "브루클린": ["Brooklyn", "NY"], "퀸즈": ["Queens", "NY"], "플러싱": ["Flushing", "NY"], "시카고": ["Chicago", "IL"],
    "마이애미": ["Miami", "FL"], "애틀랜타": ["Atlanta", "GA"], "시애틀": ["Seattle", "WA"], "보스턴": ["Boston", "MA"], "필라델피아": ["Philadelphia", "PA"],
    "덴버": ["Denver", "CO"], "라스베이거스": ["Las Vegas", "NV"], "포틀랜드": ["Portland", "OR"], "호놀룰루": ["Honolulu", "HI"], "피닉스": ["Phoenix", "AZ"],
    "캘리포니아": ["", "CA"], "텍사스": ["", "TX"], "플로리다": ["", "FL"], "일리노이": ["", "IL"], "뉴저지": ["", "NJ"], "워싱턴주": ["", "WA"],
    "매사추세츠": ["", "MA"], "펜실베이니아": ["", "PA"], "조지아주": ["", "GA"], "버지니아": ["", "VA"], "메릴랜드": ["", "MD"], "하와이": ["", "HI"],
    "ヒューストン": ["Houston", "TX"], "ダラス": ["Dallas", "TX"], "ロサンゼルス": ["Los Angeles", "CA"], "サンフランシスコ": ["San Francisco", "CA"], "サンディエゴ": ["San Diego", "CA"],
    "サンノゼ": ["San Jose", "CA"], "ニューヨーク": ["New York", "NY"], "シカゴ": ["Chicago", "IL"], "マイアミ": ["Miami", "FL"], "シアトル": ["Seattle", "WA"], "ボストン": ["Boston", "MA"],
    "ホノルル": ["Honolulu", "HI"], "カリフォルニア": ["", "CA"], "テキサス": ["", "TX"], "フロリダ": ["", "FL"], "ハワイ": ["", "HI"], "ニュージャージー": ["", "NJ"],
    "хьюстон": ["Houston", "TX"], "х'юстон": ["Houston", "TX"], "г'юстон": ["Houston", "TX"], "даллас": ["Dallas", "TX"], "лос-анджелес": ["Los Angeles", "CA"], "лос-анджелесі": ["Los Angeles", "CA"],
    "сан-франциско": ["San Francisco", "CA"], "сан-диего": ["San Diego", "CA"], "сакраменто": ["Sacramento", "CA"], "нью-йорк": ["New York", "NY"], "бруклин": ["Brooklyn", "NY"],
    "бруклін": ["Brooklyn", "NY"], "чикаго": ["Chicago", "IL"], "майами": ["Miami", "FL"], "маямі": ["Miami", "FL"], "сиэтл": ["Seattle", "WA"], "сіетл": ["Seattle", "WA"],
    "бостон": ["Boston", "MA"], "филадельфи": ["Philadelphia", "PA"], "філадельфі": ["Philadelphia", "PA"], "денвер": ["Denver", "CO"], "портленд": ["Portland", "OR"],
    "калифорни": ["", "CA"], "каліфорні": ["", "CA"], "техас": ["", "TX"], "флорид": ["", "FL"], "нью-джерси": ["", "NJ"], "нью-джерсі": ["", "NJ"], "иллинойс": ["", "IL"],
    "пенсильвани": ["", "PA"], "пенсільвані": ["", "PA"], "вашингтон": ["", "WA"],
    "هيوستن": ["Houston", "TX"], "دالاس": ["Dallas", "TX"], "لوس أنجلوس": ["Los Angeles", "CA"], "لوس انجلوس": ["Los Angeles", "CA"], "سان فرانسيسكو": ["San Francisco", "CA"],
    "سان دييغو": ["San Diego", "CA"], "نيويورك": ["New York", "NY"], "شيكاغو": ["Chicago", "IL"], "ميامي": ["Miami", "FL"], "سياتل": ["Seattle", "WA"], "بوسطن": ["Boston", "MA"],
    "فيلادلفيا": ["Philadelphia", "PA"], "ديترويت": ["Detroit", "MI"], "ديربورن": ["Dearborn", "MI"], "مينيابوليس": ["Minneapolis", "MN"], "أتلانتا": ["Atlanta", "GA"],
    "كاليفورنيا": ["", "CA"], "تكساس": ["", "TX"], "فلوريدا": ["", "FL"], "ميشيغان": ["", "MI"], "نيوجيرسي": ["", "NJ"], "نيو جيرسي": ["", "NJ"], "فرجينيا": ["", "VA"], "أوهايو": ["", "OH"],
    "هیوستون": ["Houston", "TX"], "لس‌آنجلس": ["Los Angeles", "CA"], "لس آنجلس": ["Los Angeles", "CA"], "سان فرانسیسکو": ["San Francisco", "CA"], "سن دیگو": ["San Diego", "CA"],
    "سن خوزه": ["San Jose", "CA"], "نیویورک": ["New York", "NY"], "شیکاگو": ["Chicago", "IL"], "سیاتل": ["Seattle", "WA"], "کالیفرنیا": ["", "CA"], "تگزاس": ["", "TX"],
    "ویرجینیا": ["", "VA"], "مریلند": ["", "MD"],
    "ہیوسٹن": ["Houston", "TX"], "نیویارک": ["New York", "NY"], "شکاگو": ["Chicago", "IL"], "کیلیفورنیا": ["", "CA"], "ٹیکساس": ["", "TX"], "نیو جرسی": ["", "NJ"],
    "ह्यूस्टन": ["Houston", "TX"], "डलास": ["Dallas", "TX"], "लॉस एंजिल्स": ["Los Angeles", "CA"], "सैन फ्रांसिस्को": ["San Francisco", "CA"], "न्यूयॉर्क": ["New York", "NY"],
    "न्यू यॉर्क": ["New York", "NY"], "शिकागो": ["Chicago", "IL"], "सिएटल": ["Seattle", "WA"], "बोस्टन": ["Boston", "MA"], "अटलांटा": ["Atlanta", "GA"],
    "कैलिफ़ोर्निया": ["", "CA"], "कैलिफोर्निया": ["", "CA"], "टेक्सास": ["", "TX"], "फ्लोरिडा": ["", "FL"], "न्यू जर्सी": ["", "NJ"], "न्यूजर्सी": ["", "NJ"],
    "হিউস্টন": ["Houston", "TX"], "নিউ ইয়র্ক": ["New York", "NY"], "নিউইয়র্ক": ["New York", "NY"], "ব্রুকলিন": ["Brooklyn", "NY"], "কুইন্স": ["Queens", "NY"],
    "ব্রঙ্কস": ["Bronx", "NY"], "ডেট্রয়েট": ["Detroit", "MI"], "ক্যালিফোর্নিয়া": ["", "CA"], "টেক্সাস": ["", "TX"], "মিশিগান": ["", "MI"],
    "ਨਿਊਯਾਰਕ": ["New York", "NY"], "ਫਰਿਜ਼ਨੋ": ["Fresno", "CA"], "ਸੈਕਰਾਮੈਂਟੋ": ["Sacramento", "CA"], "ਯੂਬਾ ਸਿਟੀ": ["Yuba City", "CA"], "ਕੈਲੀਫੋਰਨੀਆ": ["", "CA"],
    "ਨਿਊ ਜਰਸੀ": ["", "NJ"], "ਟੈਕਸਾਸ": ["", "TX"],
    "ન્યૂયોર્ક": ["New York", "NY"], "શિકાગો": ["Chicago", "IL"], "એડિસન": ["Edison", "NJ"], "ન્યૂ જર્સી": ["", "NJ"], "ન્યુ જર્સી": ["", "NJ"], "ટેક્સાસ": ["", "TX"], "કેલિફોર્નિયા": ["", "CA"],
    "హ్యూస్టన్": ["Houston", "TX"], "డల్లాస్": ["Dallas", "TX"], "న్యూయార్క్": ["New York", "NY"], "న్యూజెర్సీ": ["", "NJ"], "కాలిఫోర్నియా": ["", "CA"], "టెక్సాస్": ["", "TX"],
    # Tamil case endings replace a name's final virama ("டல்லாஸ்" → "டல்லாஸில்"), so stems.
    "ஹூஸ்டன": ["Houston", "TX"], "டல்லாஸ": ["Dallas", "TX"], "நியூயார்க": ["New York", "NY"], "நியூ ஜெர்சி": ["", "NJ"], "கலிபோர்னியா": ["", "CA"], "டெக்சாஸ": ["", "TX"],
    "சிகாகோ": ["Chicago", "IL"], "சியாட்டில": ["Seattle", "WA"], "சான் பிரான்சிஸ்கோ": ["San Francisco", "CA"],
    "nouyòk": ["New York", "NY"], "nou yòk": ["New York", "NY"], "mayami": ["Miami", "FL"], "florid": ["", "FL"], "nova york": ["New York", "NY"], "nova iorque": ["New York", "NY"],
    "califórnia": ["", "CA"], "flórida": ["", "FL"], "nowy jork": ["New York", "NY"], "kalifornia": ["", "CA"], "floryda": ["", "FL"], "teksas": ["", "TX"],
    "la nouvelle-orléans": ["New Orleans", "LA"], "nouvelle-orléans": ["New Orleans", "LA"], "californie": ["", "CA"], "floride": ["", "FL"]
};

"""Regex group for a count in `lang`: 1–2 ASCII digits or a number word."""
def count_group(lang: str) -> str {
    words = sorted(list(NUM_WORDS.get(lang, {}).keys()), key=lambda w: str : -len(w));
    alt = "|".join([re.escape(w) for w in words]);
    return "(\\d{1,2}" + ("|" + alt if alt else "") + ")";
}

"""Integer value of a count token (digits or number word), 0 if unknown."""
def count_value(lang: str, tok: str) -> int {
    t = str(tok or "").strip();
    if t.isdigit() { return int(t); }
    return int(NUM_WORDS.get(lang, {}).get(t, 0));
}

"""The table for `lang`; Cantonese extends the Chinese one."""
def facts_table(lang: str) -> dict {
    if lang == "yue" {
        base = dict(FACTS["zh"]);
        extra = FACTS["yue"];
        for (k, v) in extra.items() {
            if isinstance(v, str) { base[k] = v + "|" + str(base.get(k, "")) if base.get(k) else v; }
            else { base[k] = list(v) + list(base.get(k, [])); }
        }
        return base;
    }
    return dict(FACTS.get(lang, {}));
}

"""First non-empty group of a match (patterns may have alternatives)."""
def _group(m: any) -> str {
    for g in m.groups() {
        if g { return str(g); }
    }
    return "";
}

"""An amount string ("1,500", "1.500", "2 000", "1500.50") as a float."""
def _amount(raw: str) -> float {
    s = re.sub(r"\s", "", str(raw));
    if re.match(r"^\d{1,3}(?:[.,]\d{3})+$", s) {
        return float(re.sub(r"[.,]", "", s));
    }
    return float(s.replace(",", "."));
}

"""Annual income from a message in `lang`: (annual, start, end), (-1, -1, -1) if none.

An amount counts when it carries a currency mark and either an income cue
or a pay period in its clause, and no expense word ("rent is $900") shares
that clause. No period and under $5,000 reads as monthly, as in parse.jac.
"""
def income_i18n(lang: str, t: str) -> tuple {
    f = facts_table(lang);
    if f.get("no_income") {
        m0 = re.search(str(f["no_income"]), t);
        if m0 { return (0, m0.start(), m0.end()); }
    }
    cur = "(?:\\$|usd|us\\$|dollars?|dólares?|dolares?" + ("|" + str(f["money"]) if f.get("money") else "") + ")";
    num = "(\\d{1,3}(?:[,.\\s]\\d{3})+|\\d+(?:[.,]\\d+)?)\\s*(k|千|万|萬|천|만)?";
    best: tuple = (-1, -1, -1);
    best_score = -1;
    for pat in ["(?:\\$|usd|us\\$)\\s?" + num, num + "\\s*" + cur] {
        for m in re.finditer(pat, t) {
            try {
                amount = _amount(m.group(1));
            } except Exception as _ex {
                continue;
            }
            mult = str(m.group(2) or "");
            if mult in ["k", "千", "천"] { amount = amount * 1000.0; }
            elif mult in ["万", "萬", "만"] { amount = amount * 10000.0; }
            head = re.split(r"[,.;!?，。；！？、\n]", t[max(0, m.start() - 28):m.start()])[-1];
            tail = re.split(r"[,.;!?，。；！？、\n]", t[m.end():m.end() + 16])[0];
            clause = head + " " + tail;
            if f.get("expense") and re.search(str(f["expense"]), clause) { continue; }
            period = "";
            for p in ["hour", "week", "month", "year"] {
                if f.get(p) and (re.search(str(f[p]), tail) or re.search(str(f[p]), head)) {
                    period = p;
                    break;
                }
            }
            cue = bool(f.get("income") and re.search(str(f["income"]), clause));
            if not cue and not period { continue; }
            annual = amount;
            if period == "hour" { annual = amount * 2080.0; }
            elif period == "week" { annual = amount * 52.0; }
            elif period == "month" { annual = amount * 12.0; }
            elif period == "" and amount < 5000.0 { annual = amount * 12.0; }
            score = (2 if cue else 0) + (1 if period else 0);
            if score > best_score {
                best_score = score;
                best = (int(round(annual)), m.start(), m.end());
            }
        }
    }
    return best;
}

"""Household size: explicit count, else 1 + children (+ partner), else alone."""
def household_i18n(lang: str, t: str, flags: list) -> tuple {
    f = facts_table(lang);
    n_re = count_group(lang);
    for p in list(f.get("household", [])) {
        m = re.search(str(p).replace("(N)", n_re), t);
        if m {
            n = count_value(lang, _group(m));
            if n > 0 and n < 20 { return (n, m.start(), m.end(), 0); }
        }
    }
    kids = 0;
    span: tuple = (-1, -1);
    for p in list(f.get("kids", [])) {
        if isinstance(p, list) {
            m = re.search(str(p[0]), t);
            if m { kids = int(p[1]); span = (m.start(), m.end()); break; }
        } else {
            m = re.search(str(p).replace("(N)", n_re), t);
            if m {
                k = count_value(lang, _group(m));
                if k > 0 and k < 15 { kids = k; span = (m.start(), m.end()); break; }
            }
        }
    }
    # Someone fleeing an abusive partner is not in that partner's household.
    partner = 1 if (f.get("partner") and re.search(str(f["partner"]), t) and "dv" not in flags) else 0;
    if kids > 0 { return (1 + kids + partner, span[0], span[1], kids); }
    if f.get("alone") {
        ma = re.search(str(f["alone"]), t);
        if ma { return (1, ma.start(), ma.end(), 0); }
    }
    return ((2, -1, -1, 0) if partner else (0, -1, -1, 0));
}

"""Age 14–110 from "I am N" phrasings: (age, start, end)."""
def age_i18n(lang: str, t: str) -> tuple {
    for p in list(facts_table(lang).get("age", [])) {
        m = re.search(str(p), t);
        if m {
            g = _group(m);
            a = int(g) if g.isdigit() else 0;
            if a >= 14 and a <= 110 { return (a, m.start(), m.end()); }
        }
    }
    return (0, -1, -1);
}

"""Immigration status, most specific rule first: (status, start, end)."""
def citizenship_i18n(lang: str, t: str) -> tuple {
    for rule in list(facts_table(lang).get("cit", [])) {
        m = re.search(str(rule[0]), t);
        if m { return (str(rule[1]), m.start(), m.end()); }
    }
    return ("", -1, -1);
}

glob PLACE_ORDER: list = [];

"""US city/state written in another script: (city, state, start, end)."""
def place_i18n(t: str) -> tuple {
    if not PLACE_ORDER {
        PLACE_ORDER.extend(sorted(list(PLACES.keys()), key=lambda k: str : -len(k)));
    }
    for name in PLACE_ORDER {
        i = t.find(name);
        if i >= 0 {
            v = PLACES[name];
            return (str(v[0]), str(v[1]), i, i + len(name));
        }
    }
    return ("", "", -1, -1);
}

"""All five facts for a message in `lang`; -1 / 0 / "" where not found.

`low` is the lower-cased message (same length as the original, so spans
match it); digits in other scripts are mapped to ASCII here.
"""
def facts_i18n(lang: str, low: str, flags: list) -> dict {
    t = ascii_digits(str(low));
    (inc, i0, i1) = income_i18n(lang, t);
    (hh, h0, h1, kids) = household_i18n(lang, t, flags);
    (age, a0, a1) = age_i18n(lang, t);
    (cit, c0, c1) = citizenship_i18n(lang, t);
    (city, state, p0, p1) = place_i18n(t);
    return {
        "income_annual": inc, "income_span": [i0, i1],
        "household_size": hh, "household_span": [h0, h1], "kids": kids,
        "age": age, "age_span": [a0, a1],
        "citizenship": cit, "citizenship_span": [c0, c1],
        "city": city, "state": state, "place_span": [p0, p1]
    };
}

"""Languages with a fact table (for tests and the README)."""
def fact_languages -> list {
    return sorted(list(FACTS.keys()));
}
