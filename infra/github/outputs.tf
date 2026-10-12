output "actions_variables" {
  description = "登録した Actions 変数"
  value       = var.actions_variables
}

output "production_environment" {
  description = "承認付きのデプロイ環境"
  value       = github_repository_environment.production.environment
}

output "ruleset" {
  description = "main ブランチの保護ルールセット"
  value       = github_repository_ruleset.main.name
}
