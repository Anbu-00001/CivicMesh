# Translation review

CivicMesh composes whole answers in 50 languages besides English from message
catalogs (`civicmesh/data/i18n/<code>.json`, 92 strings each). **All 50 were
drafted by machine, and none has been reviewed by a native speaker yet.** That
matters because the people reading them may be in a crisis. This page explains
what the app does until a catalog is reviewed, and how to review one.

## What the app does with an unreviewed (draft) catalog

HHS guidance under Section 1557 says machine-translated content that is critical
to someone's rights or benefits must be reviewed by a qualified human translator.
Until that review happens, the translation should warn that it may contain errors.
CivicMesh follows that guidance:

| Safeguard | Where |
|---|---|
| A notice in the user's own language under every answer: "machine translation, not yet checked by a native speaker, may contain mistakes; names, amounts and phone numbers are exact" | `ui.mt_draft`, chat bubble |
| The English original of the same answer, one tap away, so a bilingual friend, caseworker or librarian can check it | `reply_en` from the engine; "Show the English original" |
| Crisis lines (988, the domestic-violence hotline) always show the English sentence under the translation. They also say interpreters are free and tell the person which word to say when someone answers | `lead_line_en`, `esc.interp` |
| Phone numbers, dollar amounts and program names are never translated: they are filled into the templates from the engine's data. A test fails if any catalog adds, drops or changes a number | `tests/check_messages.jac` |
| "Report a translation mistake" opens a pre-filled GitHub issue for that language | `.github/ISSUE_TEMPLATE/translation.yml` |

A catalog stops showing the notice when its `_meta.review` starts with
`reviewed`, for example `"reviewed by @handle (native speaker), 2026-10-02"`.

## Review order

The order follows who is most likely to need the app. By American Community
Survey counts of people with limited English proficiency, the top five languages
are Spanish, Chinese (Mandarin and Cantonese), Vietnamese, Korean and Tagalog.
Russian, Arabic, Haitian Creole, Portuguese and French come next.

| Priority | Catalogs |
|---|---|
| 1 | `es` (Spanish answers come from hand-written code; the catalog covers chips and labels), `zh`, `yue`, `vi`, `ko`, `tl` |
| 2 | `ru`, `ar`, `ht`, `pt`, `fr` |
| 3 | Everything else, especially languages of recent arrivals: `uk`, `fa`, `ps`, `so`, `ti`, `am`, `my`, `hmn` |

## How to review a language

1. Print the sheet: `python3 civicmesh/tools/review_sheet.py zh > zh-review.md`.
   Rows marked ⚠ are safety-critical (crisis lines, the safety question,
   immigration status, the machine-translation notice). They come first.
2. For each row, check three things:
   - the meaning is the same;
   - the tone is plain and respectful, with no legal promises;
   - every `{placeholder}`, number and `**bold**` marker survives.
3. Either edit `civicmesh/data/i18n/<code>.json` and open a pull request, or
   paste your corrections into a "Translation review" issue.
4. Run the checks: `jac run tests/check_messages.jac` (from `civicmesh/`). CI
   also runs it on every pull request.
5. To mark a catalog reviewed, set `_meta.review` to
   `"reviewed by <handle> (<native speaker | certified translator>), <date>"`.
   For priority-1 languages, the ⚠ rows need a second reviewer before that.

`python3 civicmesh/tools/review_sheet.py --status` lists the state of every catalog.

## Sources

- HHS, Section 1557 final rule (2024), 45 CFR 92.201: machine translation of critical content must be reviewed by a qualified human translator. [Summary (Morgan Lewis)](https://www.morganlewis.com/blogs/healthlawscan/2025/01/affordable-care-act-section-1557-new-language-accessibility-requirements) · [ATA explainer](https://www.atanet.org/client-assistance/blog-section-1557-of-the-affordable-care-act-and-language-access-who-what-how/)
- Top languages of people with limited English proficiency (ACS): [U.S. Commission on Civil Rights LEP plan](https://www.usccr.gov/limited-english-proficiency-plan)
- Digital.gov, [Introduction to translation technology](https://digital.gov/resources/introduction-to-translation-technology): human review of machine-translated vital content
