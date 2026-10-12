data "github_repository" "this" {
  full_name = var.github_repository
}

# ---------------------------------------------------------------------------
# Actions 変数（Settings → Secrets and variables → Actions → Variables）
# ---------------------------------------------------------------------------
resource "github_actions_variable" "this" {
  for_each = var.actions_variables

  repository    = data.github_repository.this.name
  variable_name = each.key
  value         = each.value
}

# ---------------------------------------------------------------------------
# production 環境（CD のイメージ公開・github.yml の apply 前の承認）
#   - production_reviewers の誰かが承認するまで apply は待機する
#   - デプロイできるのは main ブランチだけ
# ---------------------------------------------------------------------------
data "github_user" "reviewers" {
  for_each = toset(var.production_reviewers)

  username = each.value
}

resource "github_repository_environment" "production" {
  repository          = data.github_repository.this.name
  environment         = "production"
  prevent_self_review = false

  dynamic "reviewers" {
    for_each = length(var.production_reviewers) > 0 ? [1] : []
    content {
      users = [for u in data.github_user.reviewers : tonumber(u.id)]
    }
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "main" {
  repository     = data.github_repository.this.name
  environment    = github_repository_environment.production.environment
  branch_pattern = "main"
}

# ---------------------------------------------------------------------------
# main ブランチの保護（ルールセット）
#   - 直接 push・強制 push・削除を禁止し、PR 経由でのみ変更する
#   - CI のチェックが通らないとマージできない
#   - リポジトリ管理者はルールを迂回できる（緊急時用）
# ---------------------------------------------------------------------------
resource "github_repository_ruleset" "main" {
  name        = "protect-main"
  repository  = data.github_repository.this.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  bypass_actors {
    actor_id    = 5 # リポジトリロール「Admin」
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      required_approving_review_count = var.required_approvals
      dismiss_stale_reviews_on_push   = true
    }

    required_status_checks {
      strict_required_status_checks_policy = true

      dynamic "required_check" {
        for_each = var.required_status_checks
        content {
          context = required_check.value
        }
      }
    }
  }
}
