variable "github_repository" {
  description = "管理対象の GitHub リポジトリ（OWNER/REPO 形式）"
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "github_repository は OWNER/REPO 形式で指定してください。"
  }
}

variable "actions_variables" {
  description = "Actions 変数（Settings → Secrets and variables → Actions → Variables）。秘密情報は入れない"
  type        = map(string)
  default     = {}
}

variable "production_reviewers" {
  description = "production 環境のデプロイを承認できる GitHub ユーザー名"
  type        = list(string)
  default     = []
}

variable "required_approvals" {
  description = "main へのマージに必要な PR 承認数（1人で開発している場合は 0）"
  type        = number
  default     = 0
}

variable "required_status_checks" {
  description = "main へのマージ前に成功が必要なチェック（ci.yml のジョブ名）"
  type        = list(string)
  default = [
    "Build & smoke test",
    "Terraform fmt / validate",
  ]
}
