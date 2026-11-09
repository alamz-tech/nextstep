# Demo script (2–3 minute video)

Everything shown uses **clearly fake data**: "DEMO NGO (fake)", "DEMO Clinic (fake)", `[DEMO] Youth Health Service`
rows tagged "DEMO DATA – not a real service", and scripted test traffic. Say so on screen.

## Setup (once, before recording)

```bash
cp .env.example .env            # set HMAC_SECRET, TOKEN_SECRET; keep DEMO_MODE=true
scripts/build_web.sh
docker compose up --build -d
docker compose exec api python scripts/seed_demo.py     # prints demo sign-ins, a join code and an unconfirmed referral code
```

Windows to have open: (1) the learner app on an Android phone/emulator (APK from `scripts/build_apk.sh`) or a
narrow browser window at `http://localhost:8077/app/`; (2) a second browser window for the facilitator; (3) a phone
or narrow window for the student join page; (4) the dashboard.

Demo password: `demo-only-password` unless you set `DEMO_PASSWORD`.

## Journey 1: learner chat (≈60 s)

The app is one chat screen, as in the design's WhatsApp-style chat frame.

| Time | Do | Say |
|---|---|---|
| 0:00 | Open the app. The consent message appears. Tap **I agree** → **18–24**. | "Private by design: no name, no phone number. Consent comes first." |
| 0:08 | Tap **Choose** → **Ask a question**. Tap the mic once (demo voice note). | "Voice-first. The answer comes only from vetted content, marked draft until a clinician signs off." |
| 0:20 | Type "How many PrEP pills should I take?" | "It never gives doses or diagnoses." |
| 0:26 | **Choose** → **Private check** → **Start** → answer the six questions (Yes to Q1). | "One question at a time. The result is a next step, not a diagnosis." |
| 0:40 | **Find a service** → type "Yaba". Point at the DEMO tag and the referral code on the card. | "Demo data is always tagged. The code carries no personal details." |
| 0:48 | **Remind me** → **Skip 3 days (demo)** → **Yes, I went**. | "Reminders are on the phone and say only 'Hi, it's NextStep'." |
| 0:55 | Header menu (⋮) → **Quick exit**. Calculator appears. Press and hold **=** to come back. | "One tap hides everything." |

## Journey 2: facilitator with question box (≈60 s)

| Time | Do | Say |
|---|---|---|
| 1:00 | Facilitator window: `/app/#/staff` → sign in `demo_facilitator` → **New session** (School, 15–17, 40). | "Accounts are created by the organisation. No student data is collected." |
| 1:10 | Show the QR code and join code; tick the two school checklist items. | "Students scan, no install, no login." |
| 1:15 | Student window: open the join URL. Send "Can you get HIV from kissing?", "My name is Ada, what is PrEP?", "teacher is a bitch lol". | "Names are stripped before storage; pranks are filtered." |
| 1:30 | Send "my uncle forced me to have sex". The student sees the crisis screen. | "Crisis detection runs on every question. The student gets support immediately." |
| 1:38 | Facilitator: themes update, flagged count = 1 with the group reminder. Expand a theme to show the grounded answer + source. | "The facilitator never sees raw questions and cannot identify anyone." |
| 1:48 | **Projector**. Then **Report PDF**. | "Aggregate reach, questions and themes for donor reporting." |

## Journey 3: clinic confirms a referral (≈25 s)

| Time | Do | Say |
|---|---|---|
| 2:00 | `/app/#/staff` → sign in `demo_clinic` → enter the referral code from Journey 1 (or the one the seeder printed). | "The clinic enters the code: no names, no clinical details." |
| 2:10 | "Visit confirmed."  | |
| 2:15 | Dashboard (`/dashboard`, sign in `demo_platform`): funnel app opens → checks → referrals → **clinic-confirmed visits**; facilitator metrics; filter by age tier. | "Our key metric is visits confirmed by clinics, separate from self-reports. Counts under 5 are hidden." |

## Close (≈15 s)
"Built in 24 hours as a prototype; not piloted. Content is draft pending clinician review; helplines and services are
placeholders. UNICEF funding would pay for the clinic-partnered pilot in Lagos, clinician-reviewed content from the
national guidelines, and Pidgin and Hausa voice evaluated with young women."
