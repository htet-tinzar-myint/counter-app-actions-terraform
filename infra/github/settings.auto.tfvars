# GitHub 側の設定値（CI/CD が読むのでリポジトリにコミットする。秘密情報は書かない）
# 値を変えて PR を出す → plan を確認 → main にマージ → 承認後に apply
github_repository = "htet-tinzar-myint/counter-app-actions-terraform"

production_reviewers = ["htet-tinzar-myint"]
required_approvals   = 0

actions_variables = {
  IMAGE_REGISTRY = "ghcr.io"
}
