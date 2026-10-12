# Guideline: first run and commit

A step-by-step checklist to set up this project on GitHub and run it.
Steps 1–3 are done on the GitHub website, and steps 4–7 on your PC.

- Repository: `htet-tinzar-myint/counter-app-actions-terraform`
- Local folder: `C:\Users\MyintHT\GCP_CICD_GitHubActions\counter-app-actions-terraform`

> For how the project works, see [README-en.md](README-en.md) (English) or [README.md](README.md) (Japanese).

---

## Step 1: Create an empty repository on GitHub

- [ ] Open https://github.com/new
- [ ] **Owner:** `htet-tinzar-myint`. **Name:** `counter-app-actions-terraform`. It must match `github_repository` in `infra/github/settings.auto.tfvars`.
- [ ] **Visibility: Public** is recommended. On a private repo with the free plan, the approval rule and the branch protection rule don't work, and `github.yml` fails.
- [ ] **Don't** tick "Add a README", ".gitignore" or "license". The repo must be completely empty.
- [ ] Click **Create repository**

## Step 2: Create the personal access token (PAT)

- [ ] Open https://github.com/settings/personal-access-tokens/new
- [ ] **Name:** `counter-app-terraform`. **Expiration:** for example 90 days.
- [ ] **Repository access:** Only select repositories → `counter-app-actions-terraform`
- [ ] **Repository permissions:**

  | Permission | Access |
  | --- | --- |
  | Administration | Read and write |
  | Environments | Read and write |
  | Variables | Read and write |
  | Metadata | Read-only (added automatically) |

- [ ] Click **Generate token** and copy it. GitHub shows it only once.

## Step 3: Add the 2 secrets

In the repo, open **Settings → Secrets and variables → Actions → New repository secret**.

| Name | Value |
| --- | --- |
| `GH_ADMIN_TOKEN` | The token from step 2 |
| `TF_STATE_PASSPHRASE` | A long random string. Make one in Git Bash with `openssl rand -base64 32` |

- [ ] `GH_ADMIN_TOKEN` added
- [ ] `TF_STATE_PASSPHRASE` added
- [ ] Passphrase also saved somewhere safe, such as a password manager

> ⚠️ If the passphrase is lost, the stored Terraform state (on the `tfstate` branch) can't be decrypted.

## Step 4: Commit on your PC

Run in PowerShell:

```powershell
cd C:\Users\MyintHT\GCP_CICD_GitHubActions\counter-app-actions-terraform

git init -b main
git config user.name  "htet-tinzar-myint"
git config user.email "<the email on your GitHub account>"

git add .
git status
```

> The global git email on this PC is `MyintHT@fpt.com`. If your GitHub account uses a different email, set it with the `git config user.email` line above (it applies to this repo only). Otherwise the commits won't be linked to your GitHub profile.

In the `git status` output, check:

- [ ] `infra/github/settings.auto.tfvars` **is** in the list
- [ ] There's no `terraform.tfstate` and no `.terraform/` folder

Then commit:

```powershell
git commit -m "Initial commit: GitHub Actions + Terraform CI/CD"
```

## Step 5: Push

```powershell
git remote add origin https://github.com/htet-tinzar-myint/counter-app-actions-terraform.git
git push -u origin main
```

- [ ] If a browser window opens asking you to sign in to GitHub, sign in (Git Credential Manager)

## Step 6: Watch it run

Open the repo's **Actions** tab. Two workflows start:

| Workflow | What to expect |
| --- | --- |
| **GitHub Settings** → `GitHub settings apply` | Runs without approval the first time. It should finish green. |
| **CD** → `Build & test`, then `Publish` | `Publish` may wait for approval. Click **Review deployments → Approve and deploy**. |

When both are green, check:

- [ ] **Settings → Environments:** `production` exists, with you as the required reviewer
- [ ] **Settings → Rules → Rulesets:** `protect-main` exists
- [ ] **Settings → Secrets and variables → Actions → Variables:** `IMAGE_REGISTRY` exists
- [ ] **Branches:** a `tfstate` branch exists and contains `github.tfstate.gpg`
- [ ] **Packages** (right side of the repo page): `counting-service` and `dashboard-service`

Check that dashboard → counting-service works (from the **CD** run):

- [ ] **Actions → CD → (run) → Summary** shows **Result: ✅ OK** and a table of counts going up
- [ ] At the bottom of the same page, download **Artifacts → dashboard-capture** and open:
  - `dashboard.png`: screenshot of the dashboard page
  - `counts.json`: counts received from counting-service
  - `compose-logs.txt`: logs of both containers

## Step 7: Try the normal flow (ci.yml)

```powershell
git checkout -b test-ci
# make any small change, e.g. edit README.md
git add .
git commit -m "Test CI"
git push -u origin test-ci
```

- [ ] On GitHub, click **Compare & pull request**
- [ ] `ci.yml` runs (`Build & smoke test`, `Terraform fmt / validate`)
- [ ] In the CI run's **Summary**, the capture shows **Result: ✅ OK** (same as step 6)
- [ ] **Merge** becomes possible only after both checks pass
- [ ] Merge the PR

After you merge, `cd.yml` runs only if the change touched `services/` or `docker-compose.yml`. A README-only change won't start it.

Return to main afterwards:

```powershell
git checkout main
git pull
```

---

## If something fails

| Error | Fix |
| --- | --- |
| `シークレット GH_ADMIN_TOKEN が未登録です` ("secret GH_ADMIN_TOKEN is not registered") | Check step 3. The secret name must be spelled exactly as shown. |
| `シークレット TF_STATE_PASSPHRASE が未登録です` ("secret TF_STATE_PASSPHRASE is not registered") | Same as above, for `TF_STATE_PASSPHRASE` |
| `403 Resource not accessible by personal access token` | The token is missing a permission from step 2 |
| `Upgrade to GitHub Pro or make this repository public` | The repo is private. Make it public. |
| `GET .../users/htet-tinzar-myint: 404` | Fix the username in `production_reviewers` (`infra/github/settings.auto.tfvars`) |
| Smoke test fails in CI | Open the failed job and read the `Show logs on failure` step |
| Capture shows **❌ NG** | Download **dashboard-capture** and check `compose-logs.txt` for errors from counting-service or dashboard |
| `github.yml` fails after a few months | The token expired. Create a new one (step 2) and update `GH_ADMIN_TOKEN` (step 3). |

After fixing a failure, rerun it from **Actions → (failed run) → Re-run jobs**.

---

## Next time (after the first setup)

Steps 1–5 are only needed once. From then on:

| I want to... | Do this |
| --- | --- |
| Change the app (binaries, Dockerfile, compose) | New branch → change → PR → `ci.yml` passes → merge → approve in `cd.yml` |
| Change GitHub settings (reviewers, variables, required checks) | Edit `infra/github/` → PR → check the plan in `github.yml` → merge → approve the apply |
| Run CD or GitHub Settings by hand | **Actions → (workflow) → Run workflow** |
| Renew the token | Step 2 → update the `GH_ADMIN_TOKEN` secret (step 3) |
| Run it on my PC | `docker compose up -d --build` → open http://localhost:9002 → `docker compose down` |

Rules to remember:

- Don't run `terraform apply` on your PC. The state lives only on the `tfstate` branch.
- Don't delete the `tfstate` branch.
- Make changes through pull requests, so `ci.yml` checks them first.
