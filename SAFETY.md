# NextStep safety summary

Prototype, November 2026. Not piloted. All health wording is **draft pending clinician review**.

## Consent and age
* The learner chat shows the design's consent message before anything else. "Not now" saves nothing.
* Age tier is asked next. **Under 15:** a kind exit screen with a trusted-adult message and a child helpline
  placeholder; only an aggregate count is recorded and the app keeps nothing.
* 15–17 and 18–24 get separate referral filtering (services that accept under-18s only) and tier-tagged content.
* STOP or DELETE at any time erases the conversation state and the device's stored data.
* Facilitator sessions accept **15–17 or 18–24 audiences only**. School sessions show a reminder checklist
  (permission, consent requirements, safeguarding contact, support contacts). It is a reminder, not legal advice.

## Crisis flow
Runs **before every other handler**: learner Ask, every question-box submission, the private check (q5) and the
follow-up "someone won't let me" barrier.
1. Layer (a): English and Pidgin keyword patterns (`config/crisis.yaml`) for self-harm, sexual violence and violence.
   Designed for recall: a false alarm shows support; a miss could cost a life.
2. Layer (b): an LLM classifier (when an LLM is configured) catches what keywords miss. User text is wrapped as data.
3. On trigger: the normal flow stops and the chat shows the design's calm crisis messages (blue "Safety response" border), the PEP message for
   possible sexual violence, and contacts from `config/contacts.yaml` only. **No helpline number is ever generated;**
   until a verified number is entered the screen shows `[VERIFIED HELPLINE 1]`.
4. Question box: the student sees the crisis screen immediately; the text is **not stored**. The facilitator sees only
   a count and a prompt to remind the whole group of support options. Nobody can be identified.

## Guardrails
* **Grounded answers only.** BM25 retrieval over `content/kb`; with no LLM the reviewed chunk text is returned verbatim.
  With an LLM, it may only rephrase retrieved chunks, must return the chunk IDs it used (unknown IDs are rejected),
  and every answer goes through a **post-generation check** that blocks doses, schedules, drug names, diagnostic
  claims ("you have/don't have HIV") and phone numbers not in the source. Blocked → the verbatim reviewed text.
* **Dose / diagnosis / off-topic** requests get the designed refusals (`cant_help.dose`, `extra.diagnosis`, `cant_help.offtopic`).
* **Prompt injection:** user text is never placed in the system prompt; it is delimited, `<`/`>` neutralised, and
  injection patterns get a polite refusal (question box: filtered, not stored).
* **Question box hygiene:** pranks/abuse filtered; names, phone numbers, emails, handles and links stripped before storage.
* **Production gate:** with `DEMO_MODE=false`, only chunks with `review_status: approved…` and services verified in
  the last 90 days are served.
* Rate limits on all public endpoints; staff endpoints are role-checked; there is **no endpoint that returns
  individual learner or student data**.

## Learner device safety
Quick exit in the chat header menu → a working calculator with no app branding and the chat cleared; press and hold "="
to return. Android `FLAG_SECURE` hides content in recent apps and blocks screenshots. Neutral app name, icon and
notification text ("Hi, it's NextStep. Just checking in."). No chat history is kept on the device.

## Red-team results
`tests/redteam.yaml` → **114/114 automated cases pass** (`docs/REDTEAM.md`, deterministic layers, `LLM_PROVIDER=none`):
crisis en/pcm (28), dose (11), diagnosis (8), injection (8), off-topic (4), under-15 (5), consent (3), keywords (4),
grounded control (4), question box (24: pranks, names/numbers, injection, classroom crisis), access control (15:
facilitator/clinic/org-admin attempts to reach individual data). App behaviour (quick exit, no stored chat text): 3 widget
tests in `app_flutter/test/privacy_test.dart`.

## Known limitations
* Knowledge base: only 2 draft chunks with text, citations TODO; no guideline PDFs ingested yet.
* Private-check scoring is a placeholder from the design handoff, not a validated tool.
* Keyword crisis detection misses indirect phrasing; the LLM layer is untested against real traffic. Hausa has no patterns yet.
* Pidgin copy and patterns need native-speaker review with young women 15–24.
* Name redaction is heuristic (capitalisation-based) and over-redacts; lower-case names can slip through.
* Voice: no speech server evaluated yet, so real voice notes get the "please type" reply. Demo builds can play
  the design's sample voice note (tap the mic), clearly a scripted demo.
* No PIN lock in this version (not in the design); quick exit has no PIN, so it hides content from a glance only.
* The chat needs a connection; there is no offline mode in this version.
* Red-team runs without an LLM; repeat with the chosen model before any pilot.
* No security audit or penetration test; in-memory rate limits reset on restart.
