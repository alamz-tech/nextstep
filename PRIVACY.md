# NextStep privacy notice (technical)

Prototype. The principle: **the server never learns who a learner or student is.** No names, no phone numbers,
no accounts for learners, no message text kept.

## Learners (app)

| Data | Where | How long | Notes |
|---|---|---|---|
| Random install ID (UUID) | device, encrypted | until "delete my data" or uninstall | Sent as `X-Install-ID`; the server stores only an HMAC of it, and only next to referral codes. |
| Preferences, PIN hash (salted SHA-256), language, age tier | device, encrypted | until deleted | Age tier is a band, never a date of birth. |
| Saved referral codes, reminder settings, outcomes | device, encrypted | until deleted | |
| Content bundle (copy, KB, services, kits) | device, encrypted | refreshed when online | Public content, encrypted anyway so the topic isn't visible on the device. |
| Questions asked and answers | device memory only | until you leave the Ask screen | Kept on the device only if you turn on "Keep my questions" (off by default). **Never stored on the server.** |
| Voice notes | memory/temp file only | seconds | Uploaded once for transcription, then deleted on device and server. TTS audio is held in server memory for 10 minutes under an unguessable URL. |
| Private-check answers | device memory only | until the result shows | Server receives answers to score when online, does not store them, logs only the result band. |
| Referral code | server: code, service id, state, age band, language, setting, HMAC(install ID) | 90 days (`REFERRAL_TTL_DAYS`) | Clinics see only "confirmed / not found / expired". |
| Usage counts | server `events` table | 365 days (`EVENTS_RETENTION_DAYS`) | Columns: day, event, category dimensions. No IDs, no text, no time finer than a day. |

**Delete my data:** wipes everything on the device, cancels reminders and calls `DELETE /v1/learner/data`, which removes
that install's referral codes. If offline, the device keeps only the old random ID until the server delete succeeds.
Aggregate counts already recorded cannot be traced to anyone and are not removed.

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
