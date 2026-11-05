"""More ways of saying "I am in danger", from the 2026-11 blind audit's misses.

The audit's 1,036 messages caught 55% of English self-harm and 31% of medical
emergencies. These lists were written after reading its misses, so that set is
now a development set: it can't measure recall any more. tests/check_external.py
on the held-out half of the psychiatrist-graded posts still can.

All of this only ever adds a flag. A false alarm shows a hotline; a miss hides one.

The non-English phrases are machine-drafted like the catalogs, and no native
speaker has checked them. Each is a whole phrase, because a single word in one
language can be an ordinary word in another.
"""

import re;
import unicodedata;

"""Text the way a person meant it, for the danger scan only: what phones and
pasting add (zero-width characters, non-breaking spaces, fullwidth letters, line
breaks), accents, and the commonest ways of misspelling the words that matter."""
glob TYPOS: list = [
    (r"\bwan2die\b", "want to die"),
    (r"\b(?:want|wnat|wana|wanna|wan)\s*(?:to|too|2|t)?\s*(?:die+|dei|ded)\b", "want to die"),
    (r"\b(?:wanna|want to) dye(?=\s*(?:$|[.!?,]))", "want to die"),
    (r"\bk\*ll\b", "kill"),
    (r"\bk[i1!]l+\b", "kill"),
    (r"\bmy self\b", "myself"),
    (r"\bs\*icid", "suicid"),
    (r"\bsu[iy]?[cs]+[iy]?d(e|al)\b", r"suicid\1"),
    (r"\bd\*e\b", "die"),
    (r"\bkms\b", "kill myself"),
    (r"\bl[iy]?fe\b", "life"),
    (r"\bending it al\b", "ending it all"),
    (r"\bi want to kill myself to\b", "i want to kill myself"),
];

def fold_latin(text: str) -> str {
    out: list = [];
    for c in unicodedata.normalize("NFKD", str(text)) {
        if unicodedata.combining(c) and out and ord(out[-1][0]) < 0x250 { continue; }
        out.append(c);
    }
    return unicodedata.normalize("NFC", "".join(out));
}

def danger_normalize(low: str) -> str {
    t = unicodedata.normalize("NFKC", str(low)).lower();
    t = re.sub("[­​-‏ - ⁠-⁯﻿]", "", t);
    t = re.sub("\\s+", " ", t).strip();
    t = fold_latin(t);
    for (pat, to) in TYPOS {
        t = re.sub(pat, to, t);
    }
    return t;
}

"""A message with no words: the audit's crying, pill, knife and skull emoji."""
glob DISTRESS_EMOJI: str = "[\U0001F48A\U0001F52A\U0001F480☠\U0001FA78\U0001F62D\U0001F622⚰\U0001FAA6\U0001F52B]";

def distress_emoji(text: str) -> bool {
    t = re.sub("[\\s️‍]", "", str(text));
    if not t { return False; }
    only = re.sub(DISTRESS_EMOJI, "", t) == "";
    pills = bool(re.search("\U0001F48A", t)) and bool(re.search("(?i)tonight|all of|last|enough|hoy|todas", t));
    return only or pills;
}

glob EXTRA_SELF_HARM: list = [
    # A veteran's way of saying it (blind audit, 2026-11).
    r"(?:my |the )?(?:service (?:weapon|pistol|rifle)|gun|pistol|rifle|firearm)\b[^.?!]{0,40}\b(?:think|thinking|thought) (?:about|of) using it\b", r"\b(?:think|thinking|thought) (?:about|of) using (?:my|the) (?:service weapon|gun|pistol|rifle|firearm)\b(?! (?:at|for|to (?:hunt|protect))|\s+range)",
    r"(?:going to|gonna|about to|will|want to|wanna) (?:shoot|hang|drown|stab|poison) myself",
    r"i'?m about to jump", r"(?:yeet|throw|fling|hurl) myself", r"i?wantt?odie", r"killmyself", r"endmylife",
    r"i'?m (?:just )?(?:ending|gonna end) it", r"ending it all", r"(?:tonight|today) is the night",
    r"(?:written|wrote) (?:my|a) (?:suicide |goodbye |last )?(?:note|letter)",
    r"how many (?:\w+ ){0,3}(?:pills|tablets|tylenol|advil|ibuprofen|aspirin)\b[^.!?]{0,20}(?:does it take|would it take|it takes|to die|kill)",
    r"how (?:much|many) (?:\w+ ){0,3}(?:is|are) (?:lethal|fatal|deadly)", r"how much (?:tylenol|ibuprofen|advil|aspirin|insulin) is too much",
    r"how long does it take to (?:bleed out|die|drown|suffocate)", r"how to (?:tie a noose|hang myself|overdose|kill myself)",
    r"does it hurt to die", r"i only need it once", r"(?:pills|meds) saved up", r"i'?ve got the (?:rope|pills|gun)", r"i (?:have|got|bought) (?:a |the )rope(?! (?:for|to go)\b)",
    r"(?:stood|standing|sitting) (?:on|at) the (?:bridge|train tracks|tracks|ledge|roof)", r"going off the bridge", r"off (?:a|the) bridge", r"thinking about the bridge",
    r"in the garage with the car running", r"(?:6|six) feet under", r"check(?:ing)? out (?:for good|permanently)",
    r"this is my last (?:night|day)", r"(?:would )?(?:'d )?rather (?:die|be dead)(?! than (?:call|talk|go to|ask|sit|wait))",
    r"might as well be dead", r"might just not wake up", r"hope i (?:die|don'?t wake up)", r"(?:wouldn'?t|would not) care if a (?:car|truck|bus) hit me",
    r"(?:no|any) reason to (?:stay alive|keep living|be alive)", r"disappear forever", r"(?:i )?(?:burn|burning|cut|cutting) myself", r"cutting (?:herself|himself|themselves)",
    r"(?:wanna|want to) not exist", r"not being alive", r"(?:service weapon|my gun)\b[^.!?]{0,40}(?:using it|thinking about it|every night)",
    r"sits with his gun", r"wish(?:es)? (?:i|she|he) (?:wouldn'?t|would not) wake up", r"doesn'?t want to live", r"(?:life|living) is (?:so )?(?:ass|pointless)[^.!?]{0,20}(?:done|end)",
    r"quiero (?:sui?[cs]idarme|morirme|matarme|aventarme|colgarme)", r"me (?:voy a|quiero) (?:matar|colgar|aventar|tirar|suicidar|morir)", r"ojal[aá] (?:no despertara|me muriera)",
    r"(?:estar[ií]a|estoy) mejor muert[ao]", r"mejor me muero", r"me (?:corto|estoy cortando)", r"me hago da[nñ]o", r"ya no (?:quiero|kiero) (?:vivir|seguir|existir)",
    r"(?:me )?kiero (?:morir|matar)", r"carta de despedida", r"mi [uú]ltima noche", r"quisiera (?:dormir y no despertar|ya no existir)", r"harta de vivir", r"harto de vivir",
];

glob EXTRA_CONCERN: list = [
    r"(?:just )?want (?:it all|everything|the pain|this) to stop", r"won'?t have to worry about me", r"soon it won'?t matter", r"won'?t be here(?: much longer| soon| anymore)?",
    r"tell my (?:kids|children|mom|family) i love them", r"if i (?:was|were|wasn'?t) (?:gone|here)", r"(?:nobody|no one) would miss me", r"(?:nobody|no one) (?:needs|cares about) me",
    r"(?:should|could) just disappear", r"want to disappear", r"(?:maybe )?(?:it'?s )?time for me to go", r"can'?t see a future", r"no hope for me", r"(?:they'?d|we'?d|they would|we would|would) be (?:better off|happier)(?: without| if i)?",
    r"better off without (?:me|him|her)", r"i'?m so done", r"(?:said|posted|saying|says) (?:a )?goodbye", r"gave away (?:all )?(?:her|his|my)", r"(?:world|place) would be (?:a )?better(?: place)? without me",
    r"waste of space", r"affairs in order", r"made my peace", r"go to sleep and not", r"end of my rope", r"i can'?t anymore", r"picked the date",
    r"(?:life )?insurance\b[^.!?]{0,40}(?:if i was gone|than i can|more for my)", r"(?:don'?t|dont) (?:really )?see the point", r"see the point of going on", r"go away for good",
    r"relapsed on sh", r"been sh-?ing", r"s/h\b", r"bought a gun and seems calm", r"i'?m dying(?! to\b| for\b| of (?:laughter|embarrassment|boredom)\b)",
    r"ya no aguanto", r"no puedo m[aá]s", r"quiero desaparecer", r"ya me quiero ir de este mundo", r"no le hallo sentido", r"nadie me va a extra[nñ]ar", r"no tengo raz[oó]n para vivir",
    r"ya s[eé] lo que voy a hacer",
];

glob EXTRA_DV: list = [
    r"(?:he'?s|she'?s|he is|she is) dangerous", r"(?:he'?s|she'?s|he is|she is) looking for me", r"hiding from (?:him|her|my (?:husband|wife|partner|boyfriend|girlfriend|ex))",
    r"(?:gun|knife)\b[^.!?]{0,30}said (?:he|she)'?d use it", r"no one will believe me", r"(?:he|she|husband|wife|boyfriend|girlfriend|partner|ex) broke my \w+", r"threw me against", r"gave me a black eye",
    r"i have bruises", r"threatens to hurt (?:the|my) (?:dog|cat|kids?|pet)", r"send me back to my country", r"hand over my paycheck",
    r"(?:he|she)(?:'s| is)? (?:going to|gonna|will|said (?:he|she)'?d|threatened to) kill me(?! if i)", r"(?:he|she)(?:'s| is) outside my door", r"(?:he|she) broke in", r"banging on my door",
    r"partner is hurting me", r"(?:posted|shared|send|sent) my nudes", r"tracker on my car", r"follows me everywhere", r"caregiver (?:slaps|hits|hurts|beats)", r"(?:aide|nurse|caregiver)\b[^.!?]{0,30}hurting my",
    r"me dijo que si me voy me mata", r"me amenaza con", r"me revisa el tel[eé]fono", r"sufro violencia", r"me golpe[oó]", r"tengo moretones", r"me quit[oó] mis papeles y dice",
];

glob EXTRA_ASSAULT: str = r"\b(?:someone assaulted me|(?:attacked|grabbed) and assaulted|i was drugged|think i was drugged|woke up with no clothes|he was on top of me|forced (?:himself|herself) on me|said no but (?:he|she|they) (?:didn'?t|did not|kept)|wouldn'?t stop when i told|rape kit|pregnant from rape|tried to pull my pants|(?:evict me|fire me|lose my job)\b[^.!?]{0,30}(?:sleep with|have sex)|if i don'?t sleep with him|(?:boss|landlord|supervisor|manager) touches me|me violaron|abusaron de m[ií]|me abus[oó]\b|me forz[oó] a tener|v[ií]ctima de violaci[oó]n)\b";

glob EXTRA_TRAFFICKING: str = r"\b(?:(?:they|he|she) (?:keep|keeps|kept|took|take|takes) (?:my|our) (?:papers|documents|passports?)|(?:sleep|have sex) with (?:men|guys|strangers) for money|my pimp|force[sd]? me to (?:work|sell)|forcing me to (?:work|sell)|threaten(?:s|ed)? to call immigration|won'?t let me (?:go|leave)|not allowed outside|selling my (?:daughter|son)|making her see men|get out of the life|locks? us in|charged me \$?[\d,]+ and i can'?t quit|owe (?:him|them)\b[^.!?]{0,50}(?:won'?t let|knows where my family|can'?t leave)|work to pay off my debt|me quit[oó] el pasaporte|quitaron los papeles|acostarme con hombres por dinero|no me dejan salir|me hacen trabajar sin pagar\w*|me obligan a trabajar)\b";

glob EXTRA_CHILD: str = r"\b(?:(?:stepdad|stepfather|uncle)\b[^.!?]{0,20}comes into my room|comes into my room at night|locks? me in (?:the |a )?closet|parents don'?t feed me|(?:stepfather|stepdad|uncle|coach|teacher)\b[^.!?]{0,15}touching (?:her|him|me)|child is being beaten|kid left alone in a car|shook the baby|makes me do (?:stuff|things) to him|sending her naked pictures|(?:making|asking) my \d+ year old send|kids? alone for days|kid is being abused|about my bruises|(?:brother|cousin) touches me|comes home drunk and beats|mi (?:pap[aá]|padre|mam[aá]|madre|padrastro|madrastra|t[ií]o) me (?:pega|golpea|toca|toc[oó]|viola|peg[oó])|golpea a su hijo)\b";

# "I want to die my hair": a spelling slip for dye, right after the matched words.
glob DYE_SENSE: str = r"^\s+(?:my|her|his|our|the)\s+(?:\w+\s+)?(?:hair|beard|roots|clothes|shirt|fabric)\b";

glob EXTRA_EMERGENCY: str = r"\b(?:can'?t breathe(?! easy)|cannot breathe(?! easy)|can'?t catch my breath|not moving|isn'?t moving|collapsed|isn'?t responding|not responding|passed out|choking|chest (?:pain|hurts?)|face is drooping|slurring (?:his|her|my) words|can'?t move (?:his|her|my) arm|can'?t talk right|throat is closing|lips are swelling|anaphyla\w+|baby is coming|water broke|soaking through pads|\d+ (?:day|week) old\b[^.!?]{0,20}fever|(?:got|been|just) shot|(?:been|got|just) stabbed|bleeding out|severe bleeding|is on fire|i smell gas|carbon monoxide alarm|has been hit by a car|hit (?:his|her|my) head\b[^.!?]{0,30}confused|stopped sweating|cold and limp|took \d+ (?:\w+ )?(?:pills|tablets|tylenol|advil|ibuprofen|xanax)|(?:took|on) fentanyl|(?:he|she)'?s blue|is blue\b|narcan|i think i od'?d|od'?d\b|swallowed (?:(?!my\b)\w+ )?(?:pills|medicine)|(?:he|she|son|daughter|kid|baby|child|toddler|boy|girl|mom|dad|mother|father|husband|wife|grandma|grandpa) (?:just )?swallowed my (?:\w+ )?(?:pills|medicine)|ate some of \w+'?s? (?:\w+ )?pills|mixed bleach and ammonia|took too much \w+|took double|can'?t stay awake|(?:no|out of) insulin\b[^.!?]{0,30}(?:vomit\w*|sugar|sick)|sugar is over [3-9]\d\d|worst headache of my life|call 911|i need an ambulance|help me please i am dying|me (?:duele|duele mucho) el pecho|no puedo respirar|no responde|se desmay[oó]|est[aá] convulsionando|est[aá] sangrando mucho|me est[aá] dando un infarto|tiene la cara ca[ií]da)\b";

"""Someone else's threat: "il menace de me tuer" read as wanting to kill oneself."""
glob THREAT_BY_OTHER: str = "menace de me tuer|ameaçou me matar|ameacou me matar|amenaza con matarme|me amenazó con matarme|grozil mne ubit|угрожает убить меня|هددني بالقتل|li menase touye m|tinatakot niya akong papatayin";

glob CRISIS_WORDS: dict = {
    "self_harm": [
        "መሞት እፈልጋለሁ", "لا أريد أن أعيش", "عايز أموت", "نفسي أموت", "لا أريد الحياة", "ana 3ayez amoot", "bedi moot", "3ayza amoot", "আমি মরতে চাই", "আমি বাঁচতে চাই না",
        "ich will sterben", "ich bringe mich um", "ich will mich umbringen", "θέλω να πεθάνω", "i want to morir", "me quiero kill", "no quiero estar alive", "ya no quiero live", "می‌خواهم بمیرم", "نمی‌خواهم زندگی کنم",
        "je ne veux plus vivre", "je veux mourir", "je veux me tuer", "j'en peux plus de vivre", "મારે મરી જવું છે", "હું આપઘાત કરવા માંગુ છું", "mujhe jeena nahi hai", "mujhe mar jana hai", "aatmahatya karna chahta", "i want to mar jana", "ab jeene ka mann nahi",
        "kuv xav tuag", "mwen pa vle viv ankò", "mwen vle touye tet mwen", "mwen vle touye tèt mwen", "ուզում եմ մեռնել", "saya ingin mati", "non voglio più vivere", "voglio uccidermi", "消えたい", "生きていたくない", "ខ្ញុំចង់ស្លាប់",
        "살고 싶지 않아", "죽고싶다", "죽고 싶어", "ຂ້ອຍຢາກຕາຍ", "എനിക്ക് മരിക്കണം", "သေချင်တယ်", "म मर्न चाहन्छु", "ik wil dood", "ਮੈਂ ਮਰਨਾ ਚਾਹੁੰਦਾ", "chcę umrzeć", "زه غواړم مړ شم",
        "não quero mais viver", "nao quero mais viver", "quero acabar com tudo", "estou pensando em suicídio", "quero me matar", "nu mai vreau să trăiesc", "hochu umeret", "ne hochu zhit", "я покончу с собой", "хочу умереть", "не хочу жить",
        "želim da umrem", "hoću da se ubijem", "waxaan rabaa inaan dhinto", "waxaan doonayaa inaan is dilo", "ma rabo inaan noolaado", "dua të vdes", "nataka kufa", "nataka kujiua", "நான் சாக விரும்புகிறேன்", "నాకు చనిపోవాలని ఉంది", "อยากตาย",
        "ክመውት ደሊየ", "ርእሰይ ክቐትል ደሊየ", "magpapakamatay ako", "pagod na akong mabuhay", "ölmek istiyorum", "intihar etmek istiyorum", "yaşamak istemiyorum", "хочу вбити себе", "میں مرنا چاہتا", "میں جینا نہیں چاہتا",
        "tôi muốn kết thúc cuộc đời", "tôi muốn chết", "唔想再活落去", "死咗算啦", "我想结束自己的生命", "想一了百了", "我想轻生", "我想輕生", "睡过去不再醒来", "死了算了",
    ],
    "self_harm_concern": [
        "الجميع سيكون أفضل بدوني", "tout le monde serait mieux sans moi", "mwen pa ka kontinye ankò", "내가 없으면 모두", "todos ficariam melhor sem mim", "wala na akong silbi", "mọi người sẽ tốt hơn nếu không có tôi", "我撑不下去了", "大家没有我会过得更好", "我是家人的负担",
    ],
    "emergency": [
        "طفلي لا يتنفس", "لا أستطيع التنفس", "أخذت كل الحبوب", "আমার বাচ্চা শ্বাস নিচ্ছে না", "tomé muchas pastillas", "me tomé todas las pastillas", "se tragó unas pastillas", "tomó cloro", "veneno para ratas", "embarazada y estoy sangrando",
        "ne respire plus", "je ne peux plus respirer", "j'ai pris tous les médicaments", "सांस नहीं ले रहा", "saans nahi aa rahi", "tibebe m pa respire", "pa ka respire", "赤ちゃんが息をしていない", "숨을 안 쉬어요", "숨을 못 쉬겠어요", "약을 많이 먹었어요",
        "não está respirando", "nao esta respirando", "não consigo respirar", "nao consigo respirar", "tomei todos os remédios", "ребёнок не дышит", "ребенок не дышит", "не могу дышать", "выпила все таблетки", "hindi humihinga", "hindi ako makahinga", "nefes almıyor", "дитина не дихає",
        "سانس نہیں لے رہا", "không thở", "không thở được", "tôi uống hết thuốc", "没有呼吸了", "喘不过气", "不省人事", "晕倒了叫不醒", "流了很多血", "吞了药片", "吃了很多药", "吃了一整瓶药",
    ],
    "dv": [
        "zawji yadribuni", "gozy bydrabny", "mi boyfriend me hit", "mera pati mujhe marta", "mera husband mujhe hit", "मेरे पति मुझे पीटते", "mere pati mujhe peet", "mwen pè mari m", "ကျွန်မယောက်ျားက ရိုက်တယ်", "mąż mnie bije", "میړه مې ما وهي",
        "muzh menya b'yot", "mume wangu ananipiga", "mera shohar mujhe marta", "chong toi danh toi", "他掐我的脖子", "menace de me tuer", "ameaçou me matar", "ameacou me matar", "هددني بالقتل", "li menase touye m", "tinatakot niya akong papatayin",
    ],
    "sexual_assault": [
        "تعرضت للاغتصاب", "اغتصبني", "j'ai été violée", "मेरे साथ बलात्कार हुआ", "mere saath rape hua", "yo kadejak mwen", "yo vyole m", "レイプされた", "강간당했어요", "성폭행을 당했어요", "fui estuprada", "fui violentada",
        "меня изнасиловали", "ginahasa ako", "tecavüze uğradım", "мене зґвалтували", "tôi bị hiếp dâm", "tôi bị cưỡng hiếp", "我被强奸", "我被人强奸", "我被性侵", "我被強姦", "被性侵了",
    ],
    "trafficking": [
        "أخذ جواز سفري", "a pris mon passeport", "여권을 빼앗", "забрал мой паспорт", "giữ hộ chiếu của tôi", "扣了我的护照", "拿走了我的证件", "人口贩卖", "pegou meu passaporte",
    ],
    "child_abuse": [
        "我爸打我", "我继父摸我", "邻居打孩子", "继父打我", "我妈打我",
    ]
};
