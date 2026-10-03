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
  under `app/`, `skill/`, `requirements.txt`, `Dockerfile` or `.gcloudignore` (e.g. app-only or docs-only)
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

## Rolling back by hand

```bash
gcloud run revisions list --service yourcounselor-api --region asia-south1          # newest first
gcloud run services update-traffic yourcounselor-api --region asia-south1 \
  --to-revisions REVISION_NAME=100
```

Or Cloud Console → Cloud Run → yourcounselor-api → **Revisions** → select an older one → **Manage traffic**.

## Changing settings or secrets

Deploys keep the service's existing environment variables and Secret Manager mounts. To change them, run
this once in Cloud Shell:

```bash
gcloud run services update yourcounselor-api --region asia-south1 --update-env-vars NAME=value
gcloud run services update yourcounselor-api --region asia-south1 --update-secrets NAME=secret-name:latest
```

A new version of a secret in Secret Manager is picked up by the next deploy (`:latest`).
