# NextStep: build handoff (v0.1)

NextStep (working name) is an open-source, voice-first WhatsApp assistant from Alamz Tech Ltd. It helps adolescent girls and young women aged 15–24 in Nigeria move from "I might be at risk of HIV" to an HIV test or a PrEP visit. This handoff covers the WhatsApp bot, a web demo simulator and an aggregate impact dashboard.

> **Safety gate.** Every string listed in a flow's `_draft` array in `copy.json` is **draft health copy for clinician review**. Pidgin copy also needs review by native speakers aged 15–24. Every `[BRACKETED]` value is a placeholder: never ship invented helplines, clinics or retention periods.

## Files in this folder

| File | What it is |
|---|---|
| `copy.json` | Every user-facing string. Shape: `flow → en \| pcm → key`. `_draft` lists keys needing clinician sign-off. `_meta.limits` holds the WhatsApp limits. |
| `tokens.json` | Colours (light + dark), fonts, type scale, spacing, radius, sizes, logo geometry, icon SVG paths. |
| `HANDOFF.md` | This file: architecture, screen specs, components, events, acceptance checks. |

The visual source of truth is the Design canvas "NextStep Design System & Flows" (brand board, 9 flow boards, simulator, dashboard).

## Scope rules (enforce in code, not just copy)

- HIV prevention only. Basic STI questions are answered from the approved answer bank, then referred.
- **Never** diagnose, interpret test results, or give medicine names with amounts, schedules or how to start or stop ART/PrEP/PEP. Route to `cant_help.dose`.
- Crisis detection runs **before** every other handler, in every state.
- Answers come from a clinician-approved answer bank (retrieval and templating). No free-form LLM generation goes to users without that bank.
- Lock-screen safe: the first line of any bot-initiated message must reveal nothing (see `followup.ping`).

## Suggested architecture

```
/packages/core        conversation engine (pure TS state machine + router), copy loader, scoring, events
/apps/whatsapp        WhatsApp Cloud API webhook → core; media (voice) in/out; templates
/apps/simulator       web chat UI → same core in the browser (no backend needed for demo)
/apps/dashboard       read-only aggregate views from the events table
/content              copy.json, answer bank, services.json
```

- The core engine is channel-agnostic. It emits abstract messages: `text`, `buttons` (≤3), `list` (≤10 rows), `media_card`, `audio`, `location_request`, `system`. Each channel adapter renders them.
- Message refs are `[flow, key]`. Resolve them at render time with the current language, so switching language re-renders the history (the simulator does this).
- Validate `copy.json` in CI: key parity between en and pcm, buttons ≤20 chars, row titles ≤24, row descriptions ≤72.

## Conversation state machine

```
idle ──Hi──▶ consent ──agree──▶ age ──15–17/18–24──▶ menu
                │                 └─under 15──▶ closed (helpline, data deleted)
                └─not now──▶ idle (nothing stored)
menu ─▶ qa | check | find (loc) | lang
check: q1…q6 ─▶ result ─▶ find / selftest / menu
find: loc ─▶ card ─▶ directions | another | remind ─(72h template)─▶ followup
followup: yes (visit_confirmed) | not yet | help ─▶ barrier list
ANY STATE: crisis detector ─▶ crisis (violence | self_harm) ; STOP ; DELETE ; MENU ; HELP
```

### Router order for free text
1. Global keywords (en + pcm, case-insensitive): STOP, DELETE, MENU, HELP.
2. Crisis detector: self-harm, then violence/abuse. If sexual violence is possible, also send `crisis.pep`.
3. Out-of-scope: medicine dose → `cant_help.dose`; off-topic → `cant_help.offtopic`.
4. State-specific handling (e.g. `loc` treats text as an area).
5. Answer-bank match → answer (with voice); no match → `qa.unknown`.
6. `global.fallback`.

## Screen specs: WhatsApp flows

Button IDs are `snake_case` and stable across languages. Copy keys refer to `copy.json`.

| Flow | Messages (in order) | Interactive | Event(s) |
|---|---|---|---|
| **2a Consent** | `consent.intro` → `consent.body` → (`consent.data`) → `consent.agreed` | buttons: `consent_agree`, `consent_not_now`, `consent_data` | `conversation_started(lang)` |
| **2b Age** | `age.ask` → `age.teen` / `age.adult` / `age.under15`; typed 25+ → `age.over24` | buttons: `age_15_17`, `age_18_24`, `age_under15` | `age_tier_selected(tier)` |
| **2c Menu** | `menu.prompt` (list, button `global.list_button`) | rows: `menu_ask`, `menu_check`, `menu_find`, `menu_lang`; lang buttons `lang_en`, `lang_pcm` | – |
| **2d Q&A** | `qa.prompt` → [user voice] → `qa.heard` → bot audio → `qa.answer_*` → `qa.protect` | buttons: `qa_protect`, `qa_another`, `menu` | `question_asked(topic, input)` |
| **2e Private check** | `check.intro` → `check.q1…q6` (each prefixed `check.progress`) → `check.result_sti`? → `check.result_next` / `check.result_low` → `check.selftest` | 3 buttons per question (yes/no/not_sure or rather_not) | `check_started`, `check_completed(band)` |
| **2f Referral** | `referral.ask_location` → `referral.intro` → media card (image + `referral.expect`) → `referral.remind_ok` | buttons: `ref_directions` (CTA URL), `ref_another`, `ref_remind` | `referral_given(state, type)`, `reminder_opt_in` |
| **2g Follow-up** | template: `followup.ping` + `followup.ask` → `yes` / `not_yet` / `help` (list) → `help_*` | buttons `fu_yes`, `fu_not_yet`, `fu_help`; rows `fu_cost`, `fu_scared`, `fu_blocked`, `fu_other` | `visit_confirmed`, `visit_not_yet`, `barrier_reported(type)` |
| **2h Crisis** | `crisis.violence` (+ `crisis.pep`) or `crisis.selfharm` → `crisis.safe_now` | `crisis_call` (tel: CTA), `crisis_safe`, `menu` | `crisis_escalation(type)` |
| **2i Can't help** | `cant_help.dose` / `cant_help.offtopic` | `find`, `ask`, `menu` | `out_of_scope(kind)` |

### Private check: draft scoring (placeholder)
q1 Yes +2 · q2 No/Not sure +1 · q3 No/Not sure +1 · q6 Yes +2. Score ≥2 → `result_next`, else `result_low`. q4 Yes → also `result_sti`. q5 Yes → `q5_yes` immediately, then crisis contacts after the result. "Rather not say" counts 0. **Replace with a validated AGYW risk tool chosen by the clinical team.** Answers live in memory only and are never persisted.

### Referral card
- Generated header image, 1200×628 PNG: primary background, logo tile, the label "Youth health service", tags "FREE" (highlight) and "Youth-friendly" (white). Never print the clinic's programme name on the image.
- Caption body: name, address · distance, hours, "What to expect" + `referral.expect`.
- `services.json` record: `id, name, address, area, state, lat, lng, days, hours, is_free, youth_friendly, accepts_under_18, services[], verified_at`. Show only records verified in the last 90 days. For 15–17 users, filter on `accepts_under_18`.

### WhatsApp platform notes
- Reply buttons ≤3, ≤20 chars. Lists ≤10 rows, title ≤24, description ≤72, list button ≤20.
- The day-3 follow-up is outside the 24-hour window, so it needs a pre-approved utility template. Send 10:00–18:00 WAT, once only.
- Profile: display name "NextStep", About "Here to help, privately.", category Education, logo-tile profile photo. No health words on the public profile.
- Voice: STT on inbound audio (en + pcm), TTS for replies (send audio first, then text). Delete audio after processing.

## Screen specs: web simulator

Fluid page (≥320px). Layout: a yellow `role=status` demo banner, a header (logo, language toggle, dark mode, restart), a chat card (max 560px wide, 600px scroll area) and a side panel (shortcuts + session counters) that stacks below on phones.

- The banner (`sim.banner`) is always visible and never dismissible.
- The language toggle re-renders the whole transcript in the selected language.
- Only the latest bot message's buttons are enabled; older ones are dimmed and disabled.
- The composer has a text input, a demo voice-note button (sends `qa.user_voice`) and Send. Enter submits the form.
- Shortcuts: voice kissing question, private check, find a service, skip 3 days, crisis (violence), crisis (self-harm), dose question, off-topic.
- Session counters mirror the dashboard events. They are in-memory only, with no storage and no network beyond loading `copy.json`.
- Draft-copy chips ("DRAFT · clinician review") appear under bubbles whose key is in `_draft`. Safety responses get a blue "Safety response" chip and a support-coloured border.
- Respect `prefers-color-scheme`; use the tokens' light and dark sets.

## Screen specs: impact dashboard

Fluid desktop-first page that works at phone width.
- Header: title, "Anonymised aggregate data" badge (lock icon), plus a "Sample data" badge until real data exists.
- Date filter: Last 7 / 30 / 90 days / Since pilot start (segmented, `aria-pressed`), and the active range as text.
- KPI tiles: conversations, private checks, referrals given, visits confirmed (accent), crisis escalations (support colour).
- Funnel: conversations → private checks → referrals given → visits confirmed. Horizontal bars as % of conversations, with conversion from the previous step shown alongside.
- Breakdowns: conversations by age tier (18–24, 15–17, under-15 exited) and by language (English, Pidgin), plus the voice share of questions.
- Crisis card: a single count only, with a "count only" explanation.
- Privacy footer. **Small-cell suppression:** any count <5 renders as "<5".
- Data source: an `events` table with columns `date (day), event, dimension_1, dimension_2, count`. No user ID, phone, message text or timestamps finer than a day ever reaches the dashboard database.

## Component list

**Shared (simulator + dashboard)**
- `Logo` (tile | wordmark | profile circle; light/dark)
- `Icon` (name from tokens.icons; always with a label or `aria-label`)
- `Button` (primary, secondary-outline, support; min 44–48px; icon + label)
- `SegmentedToggle` (language, date range; `aria-pressed`)
- `Badge` (draft, safety, anonymised, sample, free, youth-friendly)
- `DemoBanner`
- `ThemeProvider` (light/dark tokens, OS preference + manual toggle)

**Chat**
- `ChatWindow` (header, scroll area with `aria-live=polite`, composer)
- `BotBubble` (text, kicker e.g. "Question 2 of 6", draft/safety chips)
- `UserBubble` (text)
- `VoiceNoteBubble` (inbound/outbound, waveform, duration, transcript echo)
- `ReplyButtons` (≤3; active/disabled)
- `ListMessage` (list button + rows, ≤10)
- `ServiceCard` (media header + details + 3 buttons)
- `SystemPill` (e.g. "3 days later")
- `Composer` (input with label, voice button, send)

**Dashboard**
- `KpiTile`, `FunnelBar`, `BreakdownBar`, `CrisisCountCard`, `DateRangeFilter`, `PrivacyNote`

**Core (no UI)**
- `CopyStore` (load, resolve `[flow,key]` by lang, validate limits)
- `Router` (keyword → crisis → scope → state → answer bank → fallback)
- `CheckScorer` (pluggable, swap for validated tool)
- `EventLogger` (aggregate-only emit: `event`, `dim1`, `dim2`, day)
- `ServiceFinder` (geo search over verified services)

## Aggregate events (the only thing stored about usage)

`conversation_started(lang)`, `age_tier_selected(tier)`, `question_asked(topic, input)`, `check_started`, `check_completed(band)`, `referral_given(state, service_type)`, `reminder_opt_in`, `visit_confirmed`, `visit_not_yet`, `barrier_reported(type)`, `crisis_escalation(type)`, `out_of_scope(kind)`.

## Accessibility and acceptance checks

- [ ] All text pairs meet WCAG AA 4.5:1 (see `tokens.json → color.contrast_checked`).
- [ ] Every interactive element is a real `<button>`, `<a>` or `<input>` with a label; tab order follows the visual order.
- [ ] Every icon has a text label or `aria-label`; decorative SVGs are `aria-hidden`.
- [ ] Minimum body text 16px; targets ≥44px.
- [ ] `copy.json` CI check passes (key parity, character limits).
- [ ] Crisis detector unit tests cover en + pcm phrases and run before every handler.
- [ ] Dose questions never return a number, schedule or regimen (red-team tests in en + pcm).
- [ ] Under-15 path stores nothing beyond the aggregate count.
- [ ] No placeholder `[…]` values remain in production config.
- [ ] Clinician and safeguarding sign-off recorded for every `_draft` key.
