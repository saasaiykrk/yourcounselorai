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

## Rolling back by hand

```bash
gcloud run revisions list --service yourcounselor-api --region asia-south1          # newest first
gcloud run services update-traffic yourcounselor-api --region asia-south1 \
  --to-revisions REVISION_NAME=100
```

Or Cloud Console → Cloud Run → yourcounselor-api → **Revisions** → select an older one → **Manage traffic**.

A rollback pins traffic to that revision. The next deploy from GitHub moves traffic back to the newest
revision by itself. To do it by hand:
`gcloud run services update-traffic yourcounselor-api --region asia-south1 --to-latest`

## Changing settings or secrets

Deploys keep the service's existing environment variables and Secret Manager mounts. To change them, run
this once in Cloud Shell:

```bash
gcloud run services update yourcounselor-api --region asia-south1 --update-env-vars NAME=value
gcloud run services update yourcounselor-api --region asia-south1 --update-secrets NAME=secret-name:latest
```

A new version of a secret in Secret Manager is picked up by the next deploy (`:latest`).
