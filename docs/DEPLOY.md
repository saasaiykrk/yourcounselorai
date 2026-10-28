# Deploying the backend (CI/CD)

```
pull request ──► ci (backend tests) ──► merge to main ──► ci on main
                                                                   │ green
                                                                   ▼
                                       deploy: Cloud Run revision ─► /health check ─► live
                                                                   │ check fails
                                                                   ▼
                                                     traffic goes back to the previous revision
```

- **ci** (`.github/workflows/ci.yml`) runs on every pull request and on `main`: backend tests, the API
  tests, skill integrity, the cleaner parity check and the safety-file label guard. The mobile app is
  **not** built or tested here; it is released separately by its owner (its jobs only run by hand).
- **Scope of CD:** the backend only, which is the API plus the `/admin` web page. A merge that changes nothing
  under `app/`, `skill/`, `shared/`, `requirements.txt`, `Dockerfile` or `.gcloudignore` (e.g. app-only or docs-only)
  does not redeploy.
- **deploy** (`.github/workflows/deploy.yml`) runs only after `ci` passes on `main`, or by hand
  (Actions → deploy → Run workflow). It builds the `Dockerfile` with Cloud Build, rolls out a new
  revision of `yourcounselor-api` in `asia-south1`, and checks `/health`:
  - `ok` is true,
  - `dev_mode` is false,
  - the WHO ICD keys are present.

  If the check fails, all traffic goes back to the revision that was serving before.
- **No keys in GitHub.** The job signs in with Workload Identity Federation: Google trusts a
  short-lived token that GitHub issues only for this repository's `main` branch. The Anthropic,
  WHO and database secrets stay in Secret Manager and are never seen by GitHub.
- **Not automated:** database migrations. Run any new `db/migrations/*.sql` in Supabase →
  SQL Editor **before** merging the pull request that needs it.

## One-time setup (about 10 minutes)

### 1. Google Cloud: create the deploy identity (Cloud Shell)

Paste this block into Cloud Shell as it is. It is safe to run again; "already exists" messages are fine.

```bash
PROJECT_ID=yourcounselor-beta
REPO=saasaiykrk/yourcounselorai
PN=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
SA=github-deployer@$PROJECT_ID.iam.gserviceaccount.com
gcloud config set project $PROJECT_ID

gcloud services enable iamcredentials.googleapis.com sts.googleapis.com cloudbuild.googleapis.com \
  run.googleapis.com artifactregistry.googleapis.com

# A service account that can only deploy Cloud Run from source.
gcloud iam service-accounts create github-deployer --display-name="GitHub Actions deployer"
for ROLE in roles/run.admin roles/cloudbuild.builds.editor roles/artifactregistry.writer \
            roles/storage.admin roles/serviceusage.serviceUsageConsumer roles/logging.viewer; do
  gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$SA --role=$ROLE --condition=None
done
# It runs the service and the build as the default compute account (as before).
gcloud iam service-accounts add-iam-policy-binding $PN-compute@developer.gserviceaccount.com \
  --member=serviceAccount:$SA --role=roles/iam.serviceAccountUser

# Trust GitHub's tokens, but only for this repository's main branch.
gcloud iam workload-identity-pools create github --location=global --display-name="GitHub Actions"
gcloud iam workload-identity-pools providers create-oidc github-repo --location=global \
  --workload-identity-pool=github --display-name="yourcounselorai main" \
  --issuer-uri=https://token.actions.githubusercontent.com \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository=='$REPO' && assertion.ref=='refs/heads/main'"
gcloud iam service-accounts add-iam-policy-binding $SA --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$PN/locations/global/workloadIdentityPools/github/attribute.repository/$REPO"

echo
echo "GCP_PROJECT_ID   = $PROJECT_ID"
echo "GCP_WIF_PROVIDER = projects/$PN/locations/global/workloadIdentityPools/github/providers/github-repo"
echo "GCP_DEPLOY_SA    = $SA"
```

### 2. GitHub: three repository variables (not secrets; none of these is a password)

GitHub → repository → **Settings → Secrets and variables → Actions → Variables tab → New repository variable**.
Add the three values printed at the end of step 1:

| Name | Example value |
|---|---|
| `GCP_PROJECT_ID` | `yourcounselor-beta` |
| `GCP_WIF_PROVIDER` | `projects/504294667459/locations/global/workloadIdentityPools/github/providers/github-repo` |
| `GCP_DEPLOY_SA` | `github-deployer@yourcounselor-beta.iam.gserviceaccount.com` |

Until these exist, the deploy workflow is skipped (it does not fail).

### 3. Optional but recommended: approve each deploy

GitHub → **Settings → Environments → production** (created on the first run) → **Required reviewers** →
add yourself. Each deploy then waits for your click in the Actions tab before going live.

### 4. Try it

Actions → **deploy** → **Run workflow** (branch `main`). It takes about 4 to 6 minutes. The summary ends with
the skill version, model and prompt hash that are now live.

## Clinical evals (optional, manual)

Actions → **ci** → Run workflow builds the app. Tick **run_evals** only when you also want the clinical
test cases (`evals/evals.json`) run through the real model (it costs money; needed before changing the model, the skill or the
inspector). They need these extra settings in GitHub → Settings → Secrets and variables → Actions:

| Kind | Name | Value |
|---|---|---|
| Secret | `ANTHROPIC_API_KEY` | an Anthropic key (ideally a separate one, so its spend shows apart) |
| Secret | `WHO_ICD_CLIENT_ID`, `WHO_ICD_CLIENT_SECRET` | the WHO keys (optional; without them ICD lookups are offline) |
| Variable | `CLAUDE_MODEL` | `claude-opus-5-5` |
| Variable | `ICD_RELEASE` | `2025-01` |

The grading pack appears under *Artifacts* as **eval-grading-pack** for the clinician to grade.

## Before merging this release: run migration 004

`db/migrations/004_clinician_identity.sql` adds the clinician's name, gender and age (asked at registration).
Run it in Supabase → SQL Editor **before** the backend that needs it is deployed, or new registrations fail.

## Held-back replies in the web admin: run migration 005

`db/migrations/005_held_back_attempts.sql` keeps every reply the safety check held back, so **/admin → Reports →
a held-back report → Show held-back text** can show what the AI actually wrote. Run it in Supabase → SQL Editor
(safe to run again). The server works without it; until then only the last attempt is shown, and only for
replies logged after it runs will every attempt be kept. Each view is written to the audit log; the phone app
never shows this text.

## Guided consultation (off until you switch it on)

The guided consultation (case → a few questions → the fixed Consultation Report) ships switched off in
production. The app shows the Guided option only when the server has it on. To switch it on:

1. Supabase → SQL Editor: run `db/migrations/003_consultations.sql` once.
2. Cloud Shell:
   ```bash
   gcloud run services update yourcounselor-api --region asia-south1 --project yourcounselor-beta \
     --update-env-vars CONSULTATION_ENABLED=1
   ```
   Set it back to `0` to hide the option again; consultations already saved stay in the database.
3. Before real clients: run `python -m evals.run_consultation_evals` (real model; a few dollars) and have the
   psychologist grade the reports in `evals/out/consult-*` against
   `skill/clinical-assist/references/example-consult-report-ocd.md`.

## Pricing plans and payments (off until an admin switches pricing on)

Until pricing is switched on in **/admin → Pricing Plans**, every report stays free, exactly as before.

1. **Database (before deploying this release):** Supabase → SQL Editor → run `db/migrations/006_billing.sql`
   (safe to run again). Without it the server still starts and reports stay free, but the pricing pages fail.
2. **Razorpay keys (Secret Manager only; never in the app, in GitHub or in chat).** Razorpay Dashboard →
   *Account & Settings → API Keys* (use **Test mode** keys first). In Cloud Shell, paste each value when asked:
   ```bash
   for s in razorpay-key-id razorpay-key-secret razorpay-webhook-secret; do
     read -rsp "$s: " v; echo; printf '%s' "$v" | gcloud secrets create $s --data-file=- --project yourcounselor-beta
   done
   # The key that encrypts clinicians' own Anthropic keys (generated, never shown):
   openssl rand -base64 32 | tr -d '\n' | gcloud secrets create byok-encryption-key --data-file=- --project yourcounselor-beta
   gcloud run services update yourcounselor-api --region asia-south1 --project yourcounselor-beta --update-secrets \
     RAZORPAY_KEY_ID=razorpay-key-id:latest,RAZORPAY_KEY_SECRET=razorpay-key-secret:latest,RAZORPAY_WEBHOOK_SECRET=razorpay-webhook-secret:latest,BYOK_ENCRYPTION_KEY=byok-encryption-key:latest
   ```
   If the update says *permission denied on secret*, give the service's account **Secret Manager Secret
   Accessor** on the new secrets (IAM page), as was done for the Anthropic key.
3. **Razorpay webhook:** Razorpay Dashboard → *Webhooks → Add New Webhook*:
   - URL: `https://<your Cloud Run URL>/v1/payments/razorpay/webhook`
   - Secret: the same value you stored as `razorpay-webhook-secret`
   - Events: `payment.authorized`, `payment.captured`, `payment.failed`, `order.paid`, `refund.processed`,
     `refund.failed`
4. **Check:** `https://<your Cloud Run URL>/healthz` shows `"payments_configured": true` and
   `"byok_configured": true`. Then /admin → Pricing Plans → set prices → switch pricing on.
5. **Test before going live:** with Test-mode keys, buy each plan from the app using Razorpay's test cards/UPI,
   check the credits, then refund one from /admin → Payments. Then replace the three Razorpay secrets with
   the Live-mode values (`gcloud secrets versions add razorpay-key-id --data-file=-`, and so on) and redeploy.

How it is protected:
- Prices come only from the server's saved configuration; the app never sends an amount.
- A payment counts only when Razorpay's signature is valid **and** Razorpay itself reports the payment as
  captured for that order and amount. Webhooks are signed, and each event is applied once.
- A report holds one credit while it is written. The credit is spent only if the report is delivered; a
  held-back or failed report gives it back. A retried request is never charged twice.
- Clinicians' own Anthropic keys are checked with Anthropic, encrypted (AES-256-GCM), never returned (only
  the last 4 characters), never logged, and never replaced by the platform key when they fail.
- **Never change or lose `byok-encryption-key`:** saved own keys can't be read without it. To rotate, store the
  old value as `BYOK_ENCRYPTION_KEY_PREVIOUS`, the new one as `BYOK_ENCRYPTION_KEY`, and raise
  `BYOK_KEY_VERSION` by 1. Each saved key is re-encrypted with the new value the next time it is used.

## Plans: Learn, Practice, BYOK Scale, Scale (run migration 012)

1. **Database (before deploying this release):** Supabase → SQL Editor → run `db/migrations/012_plan_tiers.sql`
   (safe to run again). Without it, buying a plan and the free months fail.
2. **What each plan unlocks** (fixed in `app/billing.py` → `FEATURES`; the admin edits names, prices and periods):
   | | Learn | Practice | BYOK Scale | Scale |
   |---|---|---|---|---|
   | Full practice library (Knowledge) | ✓ | ✓ | ✓ | ✓ |
   | PDF downloads with your name (handouts, reports) | | ✓ | ✓ | ✓ |
   | Booking page with your name and number | | ✓ | ✓ | ✓ |
   | Appointments in the app (Calendar) | | ✓ | ✓ | ✓ |
   | AI-Guided Case Taking | | | unlimited, own AI key | 10 a month, extra ₹129 each |
   - Prices (launch defaults): Learn ₹599/month or ₹4,999/year; Practice ₹999 or ₹5,999 (was ₹9,999);
     BYOK Scale ₹1,999 or ₹14,999 (was ₹19,999); Scale ₹2,999 or ₹19,999 (was ₹29,999).
   - **Learn's free months** (90 days by default) start by themselves the first time a verified clinician opens
     the app, once per account.
   - Plans are **prepaid** for a month (30 days) or a year (365 days); the app reminds them before the end.
     Paying again early adds the new period after the current one. Scale's yearly plan gets 10 AI-Guided
     reports every month; unused ones don't carry over.
   - A **quick consult** is always bought per report. **Pay per report** and **Single print** are unchanged.
   - The old 30- and 50-report plans and the own-key fee are retired; their past payments stay in Payments.
3. **Only while charging is on.** With charging off in /admin → Pricing Plans, everything is unlocked and free.
   When you switch it on, existing clinicians get Learn's free months at their next visit, so the calendar,
   PDF downloads and AI-Guided Case Taking lock until they choose Practice or above.
4. **Admins and the Google Play reviewer:** give them a plan in /admin → Subscriptions & Users → the person →
   **Give a plan…** → Scale (or BYOK Scale), with the days you want (e.g. 90).

## Plans bought outside the app (funnels): run migrations 015 and 016

A funnel, landing page or automation tool (GoHighLevel, Systeme.io, Zapier, Make, Pabbly…) can tell the server
about a sale. The plan starts at once if an account already uses that email; otherwise it waits and starts when
that person signs up with the same email. Every sale shows in **/admin → Payments → From funnels**, and applied
ones also appear in Transactions (marked "Funnel") and in the totals.

1. **Database:** Supabase → SQL Editor → run `db/migrations/015_external_purchases.sql` (safe to run again).
2. **The secret** (Cloud Shell; the tool sends it with every sale; never put it in the app or in chat):
   ```bash
   openssl rand -hex 24      # copy the value; you paste it here and in the funnel tool
   read -rsp "funnel secret: " v; echo; printf '%s' "$v" | gcloud secrets create funnel-webhook-secret \
     --data-file=- --project yourcounselor-beta
   gcloud run services update yourcounselor-api --region asia-south1 --project yourcounselor-beta \
     --update-secrets FUNNEL_WEBHOOK_SECRET=funnel-webhook-secret:latest
   ```
   Until it is set, the webhook answers 404 (switched off).
3. **In the funnel tool**, add a webhook that runs after a successful payment:
   - **URL:** `https://app.yourcounselor.in/v1/webhooks/purchase` · **Method:** POST · **Body:** JSON
   - **Header:** `X-Webhook-Secret: <the secret>` (or `Authorization: Bearer <the secret>`)
   - **Body** (map the tool's fields to these names; other fields are ignored):
     ```json
     {"event_id": "<the tool's order or transaction id>", "email": "<buyer's email>",
      "plan": "scale", "period": "year", "amount": 19999, "source": "Launch funnel", "payment_id": "<optional>"}
     ```
     | plan | also send | gives |
     |---|---|---|
     | `learn`, `practice`, `byok_scale`, `scale` | `period`: `month` or `year` | that plan for a month (30 days) or a year (365 days) |
     | `per_report` | `report_type`: `guided` or `direct` | one report credit |
     `amount` is in rupees as paid (for the records; it does not change what is granted). `event_id` must be unique
     per sale: the same `event_id` sent again is ignored, so the tool's retries never grant twice.
4. **Test it** (Cloud Shell, with a test email):
   ```bash
   curl -sS -X POST https://app.yourcounselor.in/v1/webhooks/purchase -H "Content-Type: application/json" \
     -H "X-Webhook-Secret: $v" -d '{"event_id":"test-1","email":"you@example.com","plan":"practice","period":"month","amount":999}'
   ```
   The answer says `"applied"` (account found) or `"pending"` (starts at sign-up). A wrong secret gets 401.
5. **Refunds** are handled where the money was taken (the funnel's own gateway). Then, in /admin: a sale still
   waiting → Payments → From funnels → **Cancel…**; a plan already active → Subscriptions & Users → the person →
   **Deactivate…**.

## Sign-up without a confirmation email: run migration 016 first

New clinicians get one email, the 6-digit code, and are signed in; there is no separate "confirm your email"
message. Because Supabase then also accepts a password sign-up or an email change without any code, an account's
address alone proves nothing. The server therefore notes the address only when someone opens the app with a code
sent to it (`clinicians.proven_email`), and funnel plans go only to that address.

1. **Database:** Supabase → SQL Editor → run `db/migrations/016_proven_email.sql` (safe to run again). Then
   deploy the backend.
2. **Supabase → Authentication → Sign In / Providers → Email:** turn **Confirm email** off. Save.
3. **Supabase → Authentication → Emails → Templates → Magic Link:** this is now the only email new and
   returning clinicians get. It must show `{{ .Token }}` (the code), not a link.
4. **Supabase → Authentication → URL Configuration → Site URL:** `https://app.yourcounselor.in` (not localhost).

Existing accounts are proven the next time they open the app. The reviewer's password account is never proven,
so give it plans from /admin, not through a funnel.

## Mobile number at registration: run migration 017 first

The app asks every new clinician for their mobile number (existing clinicians add it in Account → Edit profile).
The Data Processing Agreement says it is also used for offers and updates, and how to stop them (reply STOP or
email). Admins see it on each registration card in /admin.

1. **Database:** Supabase → SQL Editor → run `db/migrations/017_clinician_mobile.sql` (safe to run again), before
   deploying the backend.
2. People who ask to stop offers: stop sending them from your messaging tool. Account and safety messages continue.

## Skip verification (admin switch): run migration 018 first

/admin → Registrations has a **Skip verification** switch, off by default. While it is on, a new registration is
approved at once with the level of the role the clinician chose (counsellor/trainee L1, psychologist L2,
psychiatrist L3): nobody checks the register. Turning it on also approves everyone already waiting (not anyone an
admin rejected). Each automatic approval and each switch change is in the audit log; an admin can still change a
level or reject someone.

1. **Database:** Supabase → SQL Editor → run `db/migrations/018_auto_approve.sql` (safe to run again), before
   deploying the backend.

## Create account (details before the email code): run migration 019 first

The app's welcome screen has **Create account**: the clinician fills in their details (with email and mobile),
then gets the 6-digit code. The details are saved the moment they press Send code (`POST /v1/signup/start`, no
sign-in; at most 10 an hour per network address and 500 an hour in total), so /admin → Registrations →
**Not finished** lists people who never entered the code. When a code sent to that email is verified, the server
makes the details their registration (then the usual verification, or the Skip verification switch).
Unfinished sign-ups are deleted after 90 days; the DPA says so. **Sign in** is unchanged for existing accounts.

1. **Database:** Supabase → SQL Editor → run `db/migrations/019_signup_leads.sql` (safe to run again), before
   deploying the backend.

## Dollar prices outside India

Clinicians whose registered mobile number is not +91 see and pay every price in US dollars. /admin → Pricing Plans
→ **Outside India: ₹ per $1** sets the rate (0, the default, keeps everyone on ₹); each ₹ price is converted and
rounded up to the next $x.99 (₹999 at 85 → $11.99). Orders, Razorpay checkout and refunds use the order's own
currency, and /admin → Payments shows ₹ and $ totals separately. No migration.

1. **Razorpay:** Dashboard → Account & Settings → **International payments** → enable (Razorpay reviews the
   request). Until it is approved, a dollar checkout fails, so leave the rate at 0.
2. /admin → Pricing Plans → set the rate (e.g. 85) → Save.

## Calendar and online booking (each consultant switches it on for themselves)

Consultants get a **Calendar** tab in the app: working hours (with breaks), time off, appointment length,
buffer, notice, how far ahead clients can book, and whether requests need their approval. They share a link
`https://app.yourcounselor.in/<link name>` (older `/book/<link name>` links still work) where clients pick a free time and give **only a first name
and an email**, and may pick one tag: **First Session**, **Follow-up** or **Online**. The consultant sees the
tag on the calendar and can set, change or clear it (Calendar → the appointment → Type of session, or when adding
one). The tag shows in the booking emails and on the client's own link. It is one tag or none, stored plainly
(it names the kind of session, not the client).

Consultants can also add their **address, mobile number, up to 5 web links and a photo** in Calendar → Booking
settings. These show on their booking page only (the photo is a small JPEG, PNG or WebP, at most 400 KB, checked by
its own bytes). **This needs `db/migrations/014_booking_profile.sql`** (Supabase → SQL Editor, safe to run again)
before the release that adds it is deployed; without it, saving booking settings fails.

**Tags need `db/migrations/013_appointment_tags.sql`** (Supabase → SQL Editor, safe to run again) before the
release that adds them is deployed; without it, every new booking fails.

1. **Database (before deploying this release):** Supabase → SQL Editor → run `db/migrations/007_booking.sql`
   (safe to run again). Without it the server still starts but the Calendar tab shows an error.
2. **Encryption key for client details (required for online booking):** in Cloud Shell
   ```bash
   openssl rand -base64 32 | tr -d '\n' | gcloud secrets create booking-encryption-key --data-file=- --project yourcounselor-beta
   gcloud run services update yourcounselor-api --region asia-south1 --project yourcounselor-beta \
     --update-secrets BOOKING_ENCRYPTION_KEY=booking-encryption-key:latest
   ```
   Give the service's account **Secret Manager Secret Accessor** on it if asked. `/healthz` then shows
   `"booking_configured": true`. Without it, consultants can still use their calendar, but can't switch
   booking on. **Never change or lose this key:** stored client names and emails can't be read without it.
3. **Emails (optional).** Without SMTP everything works and no email is sent (the client keeps their own
   link to see or cancel). To send confirmations, cancellations and 24-hour reminders, use any SMTP provider
   (for example the one that sends your sign-in codes):
   ```bash
   read -rsp "SMTP password: " v; echo; printf '%s' "$v" | gcloud secrets create smtp-password --data-file=- --project yourcounselor-beta
   gcloud run services update yourcounselor-api --region asia-south1 --project yourcounselor-beta \
     --update-env-vars SMTP_HOST=smtp.example.com,SMTP_PORT=587,SMTP_USERNAME=apikey,SMTP_FROM="YourCounselor <bookings@yourdomain>" \
     --update-secrets SMTP_PASSWORD=smtp-password:latest
   ```
4. **Reminders (only with email):** a Cloud Scheduler job calls the server every 15 minutes. It also deletes
   appointments (and their client details) 90 days after they ended.
   ```bash
   openssl rand -hex 24 | tr -d '\n' | gcloud secrets create cron-token --data-file=- --project yourcounselor-beta
   gcloud run services update yourcounselor-api --region asia-south1 --project yourcounselor-beta \
     --update-secrets CRON_TOKEN=cron-token:latest
   gcloud scheduler jobs create http booking-deliver --location asia-south1 --project yourcounselor-beta \
     --schedule "*/15 * * * *" --http-method POST \
     --uri "https://<your Cloud Run URL>/v1/internal/booking/deliver" \
     --headers "X-Cron-Token=$(gcloud secrets versions access latest --secret cron-token --project yourcounselor-beta)"
   ```
   Even without this job, emails for each booking are sent straight away; only reminders and the 90-day
   clean-up need it.
5. **Privacy text:** the booking page tells clients what is stored and for how long. The app's privacy pages
   and `mobile/store/play/privacy-policy.md` cover client booking details (first name, email, appointment time;
   encrypted; 90 days). Ask the data-protection lawyer to review them before inviting the public.

How it is protected:
- One time can never be booked twice: each change takes a per-consultant lock, re-checks the time inside it,
  and the database refuses overlapping pending/confirmed appointments (an exclusion constraint) as a last line.
- A request waiting for approval holds its time for up to 24 hours, then expires and frees it.
- Client details are encrypted (AES-256-GCM, bound to the appointment) and never logged or shown publicly.
  The client's cancel link is stored only as a hash. One email can hold at most two upcoming bookings
  with a consultant; the public form is rate-limited and has a hidden spam trap.
- Only verified consultants have a booking page; each sees and changes only their own calendar.
- Times are stored in UTC and shown in the consultant's timezone, so daylight-saving changes are handled.

## Comparing with Google Gemini (optional; Claude stays in use)

The server can use Gemini instead of Claude to write replies. The same knowledge base, tools, identifier
cleaner and safety inspector apply to both. **Gemini is off by default**, and switching the live app to it is a
model change (CLAUDE.md rule 3): run the evals with both, have the clinician grade both packs without knowing
which is which, add a CHANGELOG entry, and only then switch.

1. **Get a key:** Google AI Studio (aistudio.google.com) → *Get API key*. Note the exact model name you want
   to test.
2. **Store it in GitHub (for evals), never in chat:** repo → *Settings → Secrets and variables → Actions*:
   - *Secrets* tab → **New repository secret** → name `GEMINI_API_KEY`, paste the key.
   - *Variables* tab → **New repository variable** → name `GEMINI_MODEL`, value: the model name.
3. **Run the comparison:** *Actions → ci → Run workflow*, tick **run_evals**, choose **eval_provider: gemini**.
   Run it again with **anthropic**. Each run uploads a grading pack named after the provider. Both cost money.
4. **Only if the clinician approves Gemini** (and after the privacy policy names Google as a processor),
   switch the live server in Cloud Shell:
   ```bash
   read -rsp "Gemini key: " v; echo; printf '%s' "$v" | gcloud secrets create gemini-api-key --data-file=- --project yourcounselor-beta
   gcloud run services update yourcounselor-api --region asia-south1 --project yourcounselor-beta \
     --update-env-vars MODEL_PROVIDER=gemini,GEMINI_MODEL=<model name> --update-secrets GEMINI_API_KEY=gemini-api-key:latest
   ```
   To go back: `--update-env-vars MODEL_PROVIDER=anthropic`. `/healthz` shows `"model_provider"` and the model.
   Clinicians' own keys ("use my own key") stay Anthropic keys either way.

## AI model and keys from the web admin (AI Model page)

Admins can switch between the **approved** models in `app/ai_models.py` and add or replace the Anthropic
and Gemini API keys, from **/admin → AI Model**. Nothing changes until an admin does something there:
until then the server uses its own model and keys, as before.

1. **Database (before deploying this release):** Supabase → SQL Editor → run `db/migrations/008_ai_settings.sql`
   in the **yourcounselor-beta** project (safe to run again).
2. **Encryption key:** keys added on the page are encrypted with `BYOK_ENCRYPTION_KEY`, the same secret that
   protects clinicians' own keys. If `/healthz` shows `"byok_configured": false`, set it up first (see
   *Pricing plans and payments*, step 2). **Never change or lose it:** saved keys can't be read without it.
3. **Use it:** /admin → **AI Model** → *Add key* (the key is checked with the provider first, at no cost) →
   *Switch to this* on the model you want → type its name to confirm. Every server picks it up within 30 s.
   The change history on the page (and `admin_audit`) records who did what; keys show only their last 4.

Rules that still apply:
- Only models in `app/ai_models.py` can be chosen. Adding one needs the evals, the clinician grading pack,
  a CHANGELOG entry and the `clinician-reviewed` label (CI enforces the label for that file).
- The privacy texts must name every AI provider that can be chosen. They name Anthropic and Google (in the app:
  Account → How we protect client data and Data Processing Agreement; for the store:
  `mobile/store/play/privacy-policy.md`). Adding a provider means updating them, and the consent version in
  `mobile/lib/core/config.dart`, first.
- The key that is in use by the active model can't be removed unless the server has its own key for it.



```bash
gcloud run revisions list --service yourcounselor-api --region asia-south1          # newest first
gcloud run services update-traffic yourcounselor-api --region asia-south1 \
  --to-revisions REVISION_NAME=100
```

Or Cloud Console → Cloud Run → yourcounselor-api → **Revisions** → select an older one → **Manage traffic**.

A rollback pins traffic to that revision. The next deploy from GitHub moves traffic back to the newest
revision by itself. To do it by hand:
`gcloud run services update-traffic yourcounselor-api --region asia-south1 --to-latest`

## Education (free teaching pages)

1. **Database (before deploying this release):** Supabase → SQL Editor → run `db/migrations/010_print_pass.sql`
   once (safe to run again). Orders now record their page, so **every purchase fails until this has run**.

The pages in `app/education_web/` (the owner's handover, unchanged) appear in the app's **Education** tab for
every signed-in user, one card per page titled with the page's own title. They ship with the server.

- A card opens the page inside the app, full screen under the app's own bar, through a signed link that works
  for 12 hours (the page view can't send the app's sign-in). Without a valid link the page says "This link has
  expired". Links to other education pages stay in the app; phone numbers, email and outside websites open on
  the phone. The PDF handout opens in the app's PDF viewer.
- Reading is free. There is no page-wide print button, and whole pages don't print. Printing and saving as PDF
  happen only through each module's own **Print or save as PDF** buttons, on its client handouts and counsellor
  sheets (the reference pages have none). Who can use them:
  - **Charging off** (/admin → Pricing Plans): everyone. Nothing is charged, so printing is free too.
  - **Practice, BYOK Scale or Scale** (running, paid or given by an admin): every module. Learn and a single
    report purchase don't include printing. With no plan at all (Learn's free months over), the library itself
    locks until they choose a plan.
  - **A single print**: one module's handouts and sheets, printed or saved as often as needed for 24 hours, ₹49
    by default. Set the price, the hours or switch it off in /admin → Pricing Plans → **Single print (education
    page)**. It is paid through Razorpay like the plans and appears in Payments as "Single print".
- Unlocked, inside the app a button hands the app the handout exactly as the module would print it, and the app
  opens the phone's print / save-as-PDF dialog. In a browser outside the app, the module's own print window opens.
- Locked, inside the app a button opens a sheet: **Buy for ₹49** (this module) or **See plans**. After the
  payment is confirmed the page reloads unlocked and the card shows "Print until …". In a browser outside the app,
  the note appears under the button. If the check fails, printing stays off.
- The Case History PDF has no buttons of its own: its viewer in the app has the Print / Save as PDF button, under
  the same rules.
- The app shows these pages in the **Knowledge** tab, under the tabs All · Basics · Therapies · Practice ·
  Others · Handouts. Which page sits in which tab is `SECTION_OF` in `app/education.py` (by the page's slug); a
  page not listed there shows under Others, and a PDF under Handouts. Moving a page needs no app update.
- **To add or replace a page:** put the `.html` file in `app/education_web/` and merge. Its `<title>` becomes
  the card title. The reader modules read their live settings (viewer, published module list) from the app,
  as described in that folder's README.

## Custom domain: app.yourcounselor.in (API and admin panel)

One address for everything the server serves: the app's API, the admin panel (`/admin`), the booking pages
(`/book/...`) and the Knowledge pages (`/learn/...`). The server needs no code change: it builds its links from
the address a request arrives on, or from `PUBLIC_BASE_URL`.

Cloud Run's simple "domain mapping" isn't offered in Mumbai (asia-south1), so the domain goes through a Google
Cloud **external HTTPS load balancer** in front of the same Cloud Run service. It keeps the server and data in
Mumbai, gives a free Google-managed certificate, and allows long consults (Cloud Run's own 300-second limit
applies). Cost: about US$18 a month for the load balancer, plus a little per GB. The old `*.run.app` address
keeps working, so apps already installed are not affected. The deploy workflow's smoke test checks
`https://app.yourcounselor.in/health` (`PUBLIC_URL` in `deploy.yml`), so the `*.run.app` address can later be
closed with `--ingress internal-and-cloud-load-balancing` without breaking deploys.

1. **Load balancer** (Cloud Shell, once):
   ```bash
   PROJECT=yourcounselor-beta; REGION=asia-south1; SERVICE=yourcounselor-api; DOMAIN=app.yourcounselor.in
   gcloud config set project $PROJECT
   gcloud services enable compute.googleapis.com
   gcloud compute addresses create yc-ip --global --ip-version=IPV4 --network-tier=PREMIUM
   gcloud compute network-endpoint-groups create yc-neg --region=$REGION \
     --network-endpoint-type=serverless --cloud-run-service=$SERVICE
   gcloud compute backend-services create yc-backend --global --load-balancing-scheme=EXTERNAL_MANAGED
   gcloud compute backend-services add-backend yc-backend --global \
     --network-endpoint-group=yc-neg --network-endpoint-group-region=$REGION
   gcloud compute url-maps create yc-urlmap --default-service=yc-backend
   gcloud compute ssl-certificates create yc-cert --global --domains=$DOMAIN
   gcloud compute target-https-proxies create yc-https-proxy --url-map=yc-urlmap --ssl-certificates=yc-cert
   gcloud compute forwarding-rules create yc-https --global --load-balancing-scheme=EXTERNAL_MANAGED \
     --network-tier=PREMIUM --address=yc-ip --target-https-proxy=yc-https-proxy --ports=443
   # http:// → https://
   printf 'name: yc-http-redirect\ndefaultUrlRedirect:\n  redirectResponseCode: MOVED_PERMANENTLY_DEFAULT\n  httpsRedirect: true\n' \
     | gcloud compute url-maps import yc-http-redirect --global --source=/dev/stdin --quiet
   gcloud compute target-http-proxies create yc-http-proxy --url-map=yc-http-redirect
   gcloud compute forwarding-rules create yc-http --global --load-balancing-scheme=EXTERNAL_MANAGED \
     --network-tier=PREMIUM --address=yc-ip --target-http-proxy=yc-http-proxy --ports=80
   gcloud compute addresses describe yc-ip --global --format='value(address)'   # the IP for step 2
   ```
2. **DNS** (where you bought yourcounselor.in): add an **A** record, name `app`, value: the IP from step 1.
   If the domain uses Cloudflare, set the record to **DNS only** (grey cloud), not proxied.
3. **Wait for the certificate** (15–60 minutes after DNS is live). Check with:
   ```bash
   gcloud compute ssl-certificates describe yc-cert --global --format='value(managed.status)'
   ```
   When it says `ACTIVE`, open https://app.yourcounselor.in/health and https://app.yourcounselor.in/admin.
   `/health` in a browser is a status page (server, database, AI model, knowledge base, WHO ICD-11, payments,
   email, live mode); scripts still get JSON from the same address, or use `/health?format=json`.
4. **Links in emails and the app** use the new address:
   ```bash
   gcloud run services update yourcounselor-api --region asia-south1 --project yourcounselor-beta \
     --update-env-vars PUBLIC_BASE_URL=https://app.yourcounselor.in
   ```
5. **The app:** `mobile/config/live.json` → `BACKEND_URL` becomes `https://app.yourcounselor.in`, then rebuild the
   APK. Change this only after step 3 works, or new builds can't reach the server.

Sign-in needs no change: the app and the admin panel sign in with a 6-digit code (no email links), and the admin
panel calls the server on its own address.

## Account deletion (Account → Delete account): run migration 011

1. **Database (before deploying this release):** Supabase → SQL Editor → run
   `db/migrations/011_account_deletion.sql` (safe to run again). Without it, deleting an account fails.
2. **What deleting does:** the sign-in and email (Supabase Auth user), name, gender, age, registration number,
   level, the clinician's own AI key, and their booking page, hours, time off and appointments are deleted.
   Consults leave the history; the de-identified copy stays for the 12-month safety-review period. Payment
   records stay (tax law). Running plans are cancelled. The registration shows as **deleted** in /admin.
3. **Admins can't delete themselves** from the app: another admin removes admin access first.
4. **Web link for Google Play:** `https://<server>/delete-account` (for example
   `https://app.yourcounselor.in/delete-account`) explains the steps and gives the email for anyone who can't
   open the app. For an emailed request, ask the person to use the app if they still can. If they can't, delete
   the user in Supabase → Authentication → Users (this removes the sign-in and email); the rest of their details
   then need clearing by hand in the SQL Editor, the same steps `delete_account` in `app/db.py` runs.

## Changing settings or secrets

Deploys keep the service's existing environment variables and Secret Manager mounts. To change them, run
this once in Cloud Shell:

```bash
gcloud run services update yourcounselor-api --region asia-south1 --update-env-vars NAME=value
gcloud run services update yourcounselor-api --region asia-south1 --update-secrets NAME=secret-name:latest
```

A new version of a secret in Secret Manager is picked up by the next deploy (`:latest`).
