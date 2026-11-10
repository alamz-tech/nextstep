# NextStep privacy notice (technical)

Prototype. The principle: **the server never learns who a learner or student is.** No names, no phone numbers,
no accounts for learners, no message text kept.

## Learners (app)

| Data | Where | How long | Notes |
|---|---|---|---|
| Random install ID (UUID) | device, encrypted | until STOP/DELETE or uninstall | Sent as `X-Install-ID`; the server stores only an HMAC of it. |
| Language, next check-in date | device, encrypted | until STOP/DELETE | |
| Chat messages | device memory only | until the app closes or quick exit | Never written to device storage. **Never stored on the server.** |
| Conversation state (step, language, age band, private-check running score) | server, keyed by HMAC(install ID) | 24 hours (`SESSION_TTL_HOURS`) | No message text. Check answers are not kept; only the running score until the result shows. |
| Voice notes | memory/temp file only | seconds | Uploaded once for transcription, then deleted. |
| Referral code | server: code, service id, state, age band, language, HMAC(install ID) | 90 days (`REFERRAL_TTL_DAYS`) | Shown on the service card. Clinics see only "confirmed / not found / expired". |
| Usage counts | server `events` table | 365 days (`EVENTS_RETENTION_DAYS`) | Day, event, category dimensions. No IDs, no text. |

**Delete my data** (Settings) and **STOP / DELETE** (typed in the chat) erase the server conversation state and the install's
referral codes, cancel reminders and wipe the device storage. Aggregate counts already recorded cannot be traced
to anyone and are not removed.

**Notifications** are scheduled on the device. Text: "Hi, it's NextStep. Just checking in." Hidden on the lock screen.

## Students (question box)
No install, no login, no name. Submissions are checked for crisis first (crisis text is never stored), pranks are
dropped, then names, numbers, emails, handles and links are stripped. The redacted text is stored only to group
questions into themes, and is **deleted when the facilitator closes the session or after 48 hours**. Facilitators,
admins and reports see theme labels and counts only, never question text.

## Facilitators, clinic staff, admins
Username, scrypt password hash, role, organisation. Signed tokens expire after 12 hours. Session records hold setting,
date, age band, approximate audience size and counts. Reports (CSV/PDF) contain aggregates only.

## Dashboard
Aggregate counts with small-cell suppression (any count under 5 shows as "<5"). Org admins see facilitator metrics for
their own organisation only.

## Server logs
Our own server's access logs are off (`--no-access-log`) and application logs pass through a scrubber that removes
phone-number-like digit runs and message fields. Request bodies are never logged. Rate-limit keys are hashes held in
memory only.

**Google Cloud Run platform logs:** the hosting platform itself records, for every request, the visitor's **IP address,
browser (user agent) and the URL path**, and keeps these logs for **30 days**. These logs do **not** contain message text,
questions, answers or check answers, because those travel in the request body. NextStep cannot delete them early on a
user's request.

## AI provider: Groq
The demo uses **Groq** (GroqCloud, model `openai/gpt-oss-120b`) for three jobs:
1. **Crisis check:** each chat message is also checked by the AI for signs of violence or self-harm (the keyword check always runs too).
2. **Rephrasing answers:** the AI may reword an answer, but only from the reviewed knowledge-base text that was retrieved for the question. Every AI answer then goes through the same safety check as before (no doses, no diagnosis, no phone numbers); if it fails, the reviewed text is shown unchanged.
3. **Grouping question-box questions** for facilitators, for questions the keyword search can't place. Keyword grouping is the fallback.

**What is sent to Groq:** the learner's message or the student's question, **after** names, phone numbers, emails and handles are
stripped out, plus the reviewed answer text. No install ID, IP address, age band or referral code is sent.

**Groq's terms** (from Groq's "Your Data" page, checked 2026-11-11, https://console.groq.com/docs/your-data):
- By default Groq does not keep prompts or outputs from inference requests.
- Groq may temporarily log inputs and outputs to troubleshoot reliability problems or investigate abuse, for **up to 30 days**,
  unless the law requires longer. **Zero Data Retention** (an account setting) turns this logging off.
- Groq always records usage metadata (it says this contains no inputs or outputs).
- Groq stores customer data in Google Cloud in the **United States**.
- Groq's page does not say whether customer data is used to train models.

**Status:** Zero Data Retention must be switched on by the account owner in the Groq console (Settings → Data Controls). Until
it is confirmed on, assume Groq may keep redacted messages for up to 30 days.

The Groq API key is held in Google Secret Manager (`groq-api-key`) and given to Cloud Run as an environment variable. It is not
in the code repository. To turn the AI off, set `LLM_PROVIDER=none`: NextStep then uses keyword checks and reviewed text only.

## Hosting (demo)
The public demo runs on Google Cloud Run in `europe-west1` (Belgium) with fake data only. Its database is wiped on every restart. A pilot needs a hosting decision on data location (Nigeria Data Protection Act 2023).

## Not yet done
Data protection impact assessment against the Nigeria Data Protection Act 2023; hosting decision (data location);
retention periods confirmed with a DPO; consent rules for HIV testing of under-18s confirmed with the national
programme; security review.
