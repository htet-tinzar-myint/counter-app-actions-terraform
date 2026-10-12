# counter-app-actions-terraform

[日本語](README.md) | English

A repository that runs CI/CD for two binaries, `counting-service` and `dashboard-service`, using **only GitHub Actions + Terraform**. **No cloud provider (GCP, AWS, etc.) is used at all.**

- The app is built and tested on GitHub Actions and published to GitHub Container Registry (ghcr.io)
- The GitHub repository's own settings (variables, approval rules, branch protection) are managed with Terraform
- The Terraform state is encrypted and stored on this repository's `tfstate` branch

## Architecture

```
  GitHub Actions
      │
      ├─ CI (on pull request)
      │    build → start both services → smoke test / terraform fmt・validate
      │
      ├─ CD (on push to main)
      │    build → smoke test → approval → push to ghcr.io
      │
      └─ GitHub Settings (when infra/github changes)
           Terraform plan (PR) / approval → Terraform apply (main)
                │
                ▼
           GitHub resources
             ├─ Actions variables
             ├─ production environment (reviewers, main only)
             └─ main ruleset (PR required, CI required)

  Terraform state ──encrypted (AES256)──▶ tfstate branch
```

| Service | Role |
| --- | --- |
| counting-service | Returns the count each time it is called (`{"count":1,...}`) |
| dashboard-service | Shows the value from counting-service on screen over WebSocket |

Both binaries choose their listening port from the `PORT` environment variable. dashboard-service gets the address to call from `COUNTING_SERVICE_URL`.

## Directory layout

```
.
├── docker-compose.yml   Starts both services together (dashboard :9002 → counting :9003)
├── services/
│   ├── counting-service/   Dockerfile, bin/counting-service
│   └── dashboard-service/  Dockerfile, bin/dashboard-service
├── infra/
│   └── github/      GitHub repository settings (Actions variables, production environment, main protection)
├── scripts/
│   ├── smoke_test.py   Connects to dashboard over WebSocket and checks that a count arrives
│   ├── capture.py      Records dashboard → counting working (screenshot, received counts)
│   └── tfstate.sh      Encrypts the Terraform state and saves/restores it on the tfstate branch
└── .github/workflows/
    ├── ci.yml       On PR: build → start both services → smoke test / terraform fmt・validate
    ├── cd.yml       On push to main: build → smoke test → approval → push to ghcr.io
    └── github.yml   When infra/github changes: plan on PR, approval → terraform apply on main
```

## Prerequisites

- A GitHub repository (push the contents of this folder to it) and admin access to it
- Terraform is **not** needed locally (everything runs on GitHub Actions)

## Setup

### 1. Create a PAT (personal access token)

Changing repository settings needs more permissions than the standard Actions `GITHUB_TOKEN` has, so a PAT is used.

In GitHub, go to **Settings → Developer settings → Fine-grained personal access tokens** and create a token scoped to this repository only.

| Repository permissions | Access |
| --- | --- |
| Administration | Read and write (ruleset) |
| Environments | Read and write |
| Variables | Read and write |
| Metadata | Read-only (added automatically) |

### 2. Add two secrets

Add them under the repository's **Settings → Secrets and variables → Actions → Secrets**.

| Secret | Value |
| --- | --- |
| `GH_ADMIN_TOKEN` | The PAT from step 1 |
| `TF_STATE_PASSPHRASE` | Passphrase used to encrypt the state (a long random string, e.g. `openssl rand -base64 32`) |

> If you lose `TF_STATE_PASSPHRASE`, the state can no longer be decrypted. Keep a copy somewhere safe, such as a password manager.

### 3. Fill in the settings

Edit `infra/github/settings.auto.tfvars`. CI/CD reads this file, so **commit it** (do not put secrets in it).

| Variable | Meaning |
| --- | --- |
| `github_repository` | This repository (`OWNER/REPO`) |
| `production_reviewers` | GitHub usernames allowed to approve deployments |
| `required_approvals` | Number of PR approvals needed to merge into main (`0` if you work alone) |
| `actions_variables` | Actions variables to create (`IMAGE_REGISTRY` is used by CD) |

### 4. Push and run the first apply

Pushing to main runs the **GitHub Settings** workflow, and `terraform apply` creates the following (you can also run it by hand from **Actions → GitHub Settings → Run workflow**):

- **Actions variables**: the contents of `actions_variables`
- **`production` environment**: requires approval from `production_reviewers`, deploys only from `main`
- **Ruleset `protect-main` on main**: blocks direct push, force push and deletion; requires a PR; requires CI (`Build & smoke test`, `Terraform fmt / validate`) to pass. Admins can bypass it

The first apply runs without approval because the `production` environment doesn't exist yet. From the second run on, it waits for approval.

> `cd.yml` also runs at the same time on this push. See [Workflow order](#workflow-order) for details.

After apply, the state is encrypted and committed to the `tfstate` branch automatically.

### 5. First deployment

Pushing to main (or **Actions → CD → Run workflow**) runs these steps in order:

1. Build both images, start them and run the smoke test
2. A reviewer approves under **Review deployments**
3. Push to `ghcr.io/<owner>/<repo>/counting-service` and `.../dashboard-service`, tagged with the commit SHA and `latest`

Published images appear under **Packages** on the right side of the repository page.

## Workflow order

Which workflow runs depends on the event that triggers it.

| File | When it runs | Order |
| --- | --- | --- |
| `github.yml` | Push to main (apply) / pull request (plan), only when `infra/github` changes | First during setup; after that, only when settings change |
| `ci.yml` | Every pull request | Before merging |
| `cd.yml` | Push or merge to main when `services/` or `docker-compose.yml` changes | After merging |

### First time (setup)

```
1. Add the secrets GH_ADMIN_TOKEN and TF_STATE_PASSPHRASE (by hand, before pushing)
2. Push to main
      ├─▶ github.yml  → terraform apply: creates the production environment, ruleset, variables
      └─▶ cd.yml      → build, test, publish to ghcr.io
   (ci.yml does not run here — it only runs on pull requests)
```

On a push to main, `github.yml` and `cd.yml` start **at the same time**, and there is no fixed order between them.

- If `cd.yml` reaches its publish step before `github.yml` finishes, GitHub automatically creates the `production` environment with no reviewers, so the first images are **published without approval**. Terraform then adds the reviewers.
- To require approval from the very first run, push in two steps:
  1. Push only `infra/github/`, `scripts/tfstate.sh` and `.github/workflows/github.yml`, then wait for `github.yml` to finish
  2. Push the remaining files

### After that (everyday flow)

```
1. Open a pull request
      ├─▶ ci.yml                build, smoke test, terraform fmt/validate
      └─▶ github.yml (plan)     only when infra/github changes

2. Merge the PR into main (the ruleset blocks merging until ci.yml passes)
      ├─▶ cd.yml                test → wait for approval → publish to ghcr.io
      └─▶ github.yml (apply)    only when infra/github changes → wait for approval → apply
```

After `github.yml` runs for the first time, only admins can push directly to main. Admins can still push directly, but make changes through pull requests so that `ci.yml` checks them first.

## Checking that it works (capture)

The `Capture dashboard → counting` step in CI and CD records whether dashboard can call counting-service. Even if you can't run it locally, you can check the result on GitHub.

| What to check | Where |
| --- | --- |
| Result (✅ OK / ❌ NG) and the table of received counts | **Actions → (run) → Summary** |
| Dashboard screenshot (`dashboard.png`), `counts.json`, container logs (`compose-logs.txt`) | Download **Artifacts → dashboard-capture** at the bottom of the same Summary page (kept for 14 days) |

If the count goes up, the dashboard → counting-service call is working. If the count is `-1` or the table is empty, the result is NG (dashboard can't reach counting-service).

## Everyday development

| Action | What runs |
| --- | --- |
| Open or update a PR | CI: build the images, start both services and run the smoke test, check Terraform format and syntax |
| PR that changes `infra/github` | In addition, GitHub Settings: `terraform plan` (`Plan: ...` in the Summary) |
| Merge the PR into main | CD: test → approval → push to ghcr.io / GitHub Settings: approval → `terraform apply` |
| Roll back | `git revert` the commit and merge it into main |

To replace a binary, swap the file in `services/*/bin/` and open a PR. To change GitHub settings (reviewers, required checks, etc.), edit `infra/github` and open a PR. If you change a setting directly in the GitHub UI, the next apply sets it back to what Terraform defines.

## Try it locally

`docker-compose.yml` starts both services together (CI and CD use the same file).

```
Browser ──:9002──▶ dashboard-service ──http://counting:9003──▶ counting-service
                    (published to host)                        (internal only)
```

```bash
docker compose up -d --build

pip install websocket-client
python scripts/smoke_test.py http://localhost:9002
# Open http://localhost:9002 in a browser

docker compose logs -f     # view logs
docker compose down        # stop and remove
```

To run the published images (ghcr.io):

```bash
COUNTING_IMAGE=ghcr.io/<owner>/<repo>/counting-service:latest \
DASHBOARD_IMAGE=ghcr.io/<owner>/<repo>/dashboard-service:latest \
docker compose up -d --no-build
```

To change a port, update each `Dockerfile`'s `ENV PORT` and `EXPOSE`, together with `PORT`, `ports` and `COUNTING_SERVICE_URL` in `docker-compose.yml`.

## Design notes

- **No cloud needed**: Workflows run on GitHub Actions, images live in ghcr.io, and the state lives on the repository's `tfstate` branch — everything stays inside GitHub.
- **Encrypted state**: The state contains your settings, so it is encrypted with AES256 before being committed. Its contents can't be read even in a public repository. The history of the `tfstate` branch doubles as a backup of the state.
- **No concurrent state updates**: Instead of Terraform's locking, the workflow's `concurrency` setting prevents applies from running at the same time.
- **GitHub settings as code**: Keeping Actions variables, approval rules and branch protection in `infra/github` leaves a PR record of who changed what and when.
- **Image tag = commit SHA**: You can trace which commit each image was built from.

## Caveats

- **Do not run `terraform apply` locally.** The state is restored and saved on GitHub Actions, so a local apply makes the state drift. Always make changes through PRs.
- For **private repositories**, environment reviewers (Required reviewers) and rulesets are not available on GitHub Free (Pro / Team or higher is required). Public repositories can use them on Free.
- **Ruleset check names must match the job names.** If you rename a job in `ci.yml`, update `required_status_checks` too, or PRs can't be merged.
- `GH_ADMIN_TOKEN` expires. When it does, `github.yml` fails — renew it and replace the secret.
- Do not delete the `tfstate` branch (Terraform would lose track of the existing settings and conflict with resources it already created).
- **The binaries are built for linux/amd64.** To run locally on an Apple Silicon Mac, use `docker build --platform linux/amd64`.
- **The count is kept in memory.** Restarting counting-service resets the count to 0.

## Cleanup

1. Delete `infra/github/main.tf` and `outputs.tf`, open a PR → merge → approve; this deletes the variables, environment and ruleset on GitHub
2. Delete the `tfstate` branch
3. Delete the ghcr.io images from **Packages**
4. Delete the secrets `GH_ADMIN_TOKEN` and `TF_STATE_PASSPHRASE`, and the PAT

## References

- [Terraform GitHub provider (integrations/github)](https://registry.terraform.io/providers/integrations/github/latest/docs)
- [hashicorp/setup-terraform](https://github.com/hashicorp/setup-terraform)
- [Working with the Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [GitHub Actions: Using environments for deployment](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
