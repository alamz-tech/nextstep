# Deploying the demo to Google Cloud Run

Live demo (fake data): https://nextstep-826530220017.europe-west1.run.app/app/
Dashboard: https://nextstep-826530220017.europe-west1.run.app/dashboard

Region: `europe-west1` (Belgium). One instance at most (`--max-instances 1`), scales to zero when idle,
so the first request after a quiet period takes ~10 s. Cloud Run has no persistent disk: the SQLite
database resets on every restart or deploy, and `SEED_DEMO_ON_START=true` re-creates the CLEARLY FAKE
demo data each time. This is fine for a demo and **not** for a pilot (use Postgres, e.g. Cloud SQL).

Secrets and demo sign-ins are in `.env.cloudrun` on the deploying machine (git-ignored, never commit it).
For a real deployment move them to Secret Manager.

## Redeploy after a change

```bash
scripts/build_web.sh                       # if the Flutter app changed
gcloud run deploy nextstep --source . --region europe-west1 --quiet
```

Environment variables persist between revisions. First deployment used:

```bash
set -a; . ./.env.cloudrun; set +a
gcloud run deploy nextstep --source . --region europe-west1 --allow-unauthenticated \
  --max-instances 1 --min-instances 0 --memory 512Mi --cpu 1 --port 8080 \
  --set-env-vars "^@^DEMO_MODE=true@DEMO_STATE=Lagos@SEED_DEMO_ON_START=true@FORWARDED_ALLOW_IPS=*@PUBLIC_BASE_URL=https://nextstep-826530220017.europe-west1.run.app@LLM_PROVIDER=none@FEATURE_WHATSAPP=false@HMAC_SECRET=$HMAC_SECRET@TOKEN_SECRET=$TOKEN_SECRET@PLATFORM_ADMIN_USER=$PLATFORM_ADMIN_USER@PLATFORM_ADMIN_PASSWORD=$PLATFORM_ADMIN_PASSWORD@DEMO_PASSWORD=$DEMO_PASSWORD"
```

Health check: `/v1/health` (Cloud Run reserves `/healthz`).

## Android APK for the live server

Live downloads (debug-signed demo builds):
- https://nextstep-826530220017.europe-west1.run.app/download/nextstep.apk (64-bit phones, most since ~2019)
- https://nextstep-826530220017.europe-west1.run.app/download/nextstep-32bit.apk (older or low-end phones)

They are split per phone type because Cloud Run caps one response at 32 MB. To refresh them, build, copy
the `app-arm64-v8a` and `app-armeabi-v7a` APKs into `downloads/` as `nextstep.apk` and `nextstep-32bit.apk`,
then redeploy.


```bash
scripts/build_apk.sh https://nextstep-826530220017.europe-west1.run.app
```

## Before recording

Avoid the cold start by keeping one instance warm for the day, then switch back (an always-on
instance costs a little; scaled-to-zero costs nothing when idle):

```bash
gcloud run services update nextstep --region europe-west1 --min-instances 1
gcloud run services update nextstep --region europe-west1 --min-instances 0
```
