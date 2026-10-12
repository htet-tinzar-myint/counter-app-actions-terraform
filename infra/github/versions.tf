# GitHub リポジトリ自体の設定（Actions 変数・production 環境・main の保護ルール）を管理するスタック
#   GitHub Actions（github.yml）が PR で plan、main 反映で apply する
#   クラウドは使わない：state はローカルファイル（terraform.tfstate）として扱い、
#   ワークフローが暗号化して tfstate ブランチに保存する（scripts/tfstate.sh）
#   GitHub への認証は環境変数 GITHUB_TOKEN（リポジトリ管理権限を持つ PAT）を使う
terraform {
  required_version = ">= 1.6"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "github" {
  owner = split("/", var.github_repository)[0]
}
