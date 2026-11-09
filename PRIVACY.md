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

**STOP / DELETE** (typed at any time, as in the design) erase the server conversation state and the install's
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
Access logs are off in Docker (`--no-access-log`); application logs pass through a scrubber that removes phone-number-like
digit runs and message fields. Request bodies are never logged. Rate-limit keys are hashes held in memory only.

## Not yet done
Data protection impact assessment against the Nigeria Data Protection Act 2023; hosting decision (data location);
retention periods confirmed with a DPO; consent rules for HIV testing of under-18s confirmed with the national
programme; security review.
