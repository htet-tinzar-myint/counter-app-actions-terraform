# counter-app-actions-terraform

日本語 | [English](README-en.md)

`counting-service` と `dashboard-service` の2つのバイナリを、**GitHub Actions ＋ Terraform だけ**で CI/CD するリポジトリです。**クラウド（GCP・AWS など）は一切使いません。**

- アプリは GitHub Actions 上でビルド・テストし、GitHub Container Registry（ghcr.io）に公開
- GitHub リポジトリ自体の設定（変数・承認ルール・ブランチ保護）は Terraform で管理
- Terraform の state は暗号化して、このリポジトリの `tfstate` ブランチに保存

## 構成

```
  GitHub Actions
      │
      ├─ CI（PR 時）
      │    ビルド → 2サービス起動 → スモークテスト／terraform fmt・validate
      │
      ├─ CD（main 反映時）
      │    ビルド → スモークテスト → 承認 → ghcr.io へ push
      │
      └─ GitHub Settings（infra/github 変更時）
           Terraform plan（PR）／承認 → Terraform apply（main）
                │
                ▼
           GitHub のリソース
             ├─ Actions 変数
             ├─ production 環境（承認者・main 限定）
             └─ main のルールセット（PR 必須・CI 必須）

  Terraform state ──暗号化（AES256）──▶ tfstate ブランチ
```

| サービス | 役割 |
| --- | --- |
| counting-service | 呼ばれるたびにカウントを返す（`{"count":1,...}`） |
| dashboard-service | counting-service の値を WebSocket で画面に表示 |

どちらのバイナリも環境変数 `PORT` で待ち受けポートを決めます。dashboard-service は `COUNTING_SERVICE_URL` で呼び出し先を受け取ります。

## ディレクトリ

```
.
├── docker-compose.yml   2サービスをまとめて起動（dashboard :9002 → counting :9003）
├── services/
│   ├── counting-service/   Dockerfile, bin/counting-service
│   └── dashboard-service/  Dockerfile, bin/dashboard-service
├── infra/
│   └── github/      GitHub リポジトリの設定（Actions 変数・production 環境・main の保護）
├── scripts/
│   ├── smoke_test.py   dashboard に WebSocket で接続し、count が届くか確認
│   └── tfstate.sh      Terraform state を暗号化して tfstate ブランチに保存・復元
└── .github/workflows/
    ├── ci.yml       PR 時：ビルド → 2サービス起動 → スモークテスト／terraform fmt・validate
    ├── cd.yml       main 反映時：ビルド → スモークテスト → 承認 → ghcr.io へ push
    └── github.yml   infra/github 変更時：PR で plan、main 反映で承認 → terraform apply
```

## 前提

- GitHub リポジトリ（このフォルダの中身を push する）と、その管理者権限
- ローカルに Terraform は**不要**です（すべて GitHub Actions 上で動きます）

## セットアップ手順

### 1. PAT（個人アクセストークン）を作る

リポジトリの設定を変更するには、Actions 標準の `GITHUB_TOKEN` では権限が足りないため PAT を使います。

GitHub の **Settings → Developer settings → Fine-grained personal access tokens** で、このリポジトリだけを対象にしたトークンを作ります。

| Repository permissions | 権限 |
| --- | --- |
| Administration | Read and write（ルールセット） |
| Environments | Read and write |
| Variables | Read and write |
| Metadata | Read-only（自動で付く） |

### 2. シークレットを2つ登録する

リポジトリの **Settings → Secrets and variables → Actions → Secrets** に登録します。

| シークレット | 内容 |
| --- | --- |
| `GH_ADMIN_TOKEN` | 手順1の PAT |
| `TF_STATE_PASSPHRASE` | state 暗号化用のパスフレーズ（長いランダム文字列。例：`openssl rand -base64 32`） |

> `TF_STATE_PASSPHRASE` をなくすと state を復号できなくなります。パスワードマネージャーなどにも保管してください。

### 3. 設定値を書く

`infra/github/settings.auto.tfvars` を書き換えます。このファイルは CI/CD が読むので**コミットします**（秘密情報は書かないこと）。

| 変数 | 内容 |
| --- | --- |
| `github_repository` | このリポジトリ（`OWNER/REPO`） |
| `production_reviewers` | デプロイを承認できる GitHub ユーザー名 |
| `required_approvals` | main へのマージに必要な PR 承認数（1人開発なら `0`） |
| `actions_variables` | 登録する Actions 変数（`IMAGE_REGISTRY` は CD が使う） |

### 4. push して初回 apply

main に push すると **GitHub Settings** ワークフローが動き、`terraform apply` で次のものを作ります（**Actions → GitHub Settings → Run workflow** で手動実行も可）。

- **Actions 変数**：`actions_variables` の内容
- **`production` 環境**：`production_reviewers` の承認が必要、デプロイは `main` のみ
- **main のルールセット `protect-main`**：直接 push・強制 push・削除を禁止、PR 必須、CI（`Build & smoke test`・`Terraform fmt / validate`）の成功が必須。管理者は迂回可能

初回だけは `production` 環境がまだ無いので承認なしで apply されます。2回目以降は承認待ちになります。

> この push では `cd.yml` も同時に動きます。詳しくは[ワークフローの実行順](#ワークフローの実行順)を参照してください。

apply 後の state は暗号化され、`tfstate` ブランチに自動でコミットされます。

### 5. 初回デプロイ

main に push する（または **Actions → CD → Run workflow**）と、次の順に動きます。

1. 2つのイメージをビルドし、起動してスモークテスト
2. 承認者が **Review deployments** で承認
3. `ghcr.io/<owner>/<repo>/counting-service` と `.../dashboard-service` に、コミット SHA と `latest` のタグで push

公開されたイメージはリポジトリの右側 **Packages** に表示されます。

## ワークフローの実行順

3つのワークフローは、きっかけ（イベント）によって動くものが決まります。

| ファイル | 動くタイミング | 順番 |
| --- | --- | --- |
| `github.yml` | main への push（apply）／PR（plan）。`infra/github` が変わったときだけ | セットアップ時に最初。以後は設定を変えたときだけ |
| `ci.yml` | すべての PR | マージの前 |
| `cd.yml` | main への push・マージ。`services/`・`docker-compose.yml` が変わったとき | マージの後 |

### 初回（セットアップ）

```
1. シークレット GH_ADMIN_TOKEN・TF_STATE_PASSPHRASE を登録（push より前に手作業で）
2. main に push
      ├─▶ github.yml  → terraform apply：production 環境・ルールセット・変数を作成
      └─▶ cd.yml      → ビルド・テスト・ghcr.io へ公開
   （ci.yml は PR のときだけ動くので、ここでは動かない）
```

main への push では、`github.yml` と `cd.yml` が**同時に**始まり、どちらが先かは決まっていません。

- `github.yml` より先に `cd.yml` が公開ステップに着くと、GitHub が承認者なしの `production` 環境を自動で作るため、初回のイメージは**承認なしで公開**されます（その後 Terraform が承認者を設定します）。
- 初回から承認を通したい場合は、2回に分けて push します。
  1. `infra/github/`・`scripts/tfstate.sh`・`.github/workflows/github.yml` だけを push し、`github.yml` の完了を待つ
  2. 残りのファイルを push する

### 2回目以降（普段の流れ）

```
1. PR を作る
      ├─▶ ci.yml                  ビルド・スモークテスト・terraform fmt/validate
      └─▶ github.yml（plan）      infra/github が変わったときだけ

2. PR を main にマージ（ルールセットにより ci.yml が成功しないとマージできない）
      ├─▶ cd.yml                  テスト → 承認待ち → ghcr.io へ公開
      └─▶ github.yml（apply）     infra/github が変わったときだけ → 承認待ち → apply
```

初回の `github.yml` の実行後は、main への直接 push は管理者以外できなくなります。管理者は直接 push もできますが、`ci.yml` のチェックを通すために PR 経由で変更してください。

## 普段の開発の流れ

| 操作 | 動くもの |
| --- | --- |
| PR を作る・更新する | CI：イメージのビルド、2サービスを起動してのスモークテスト、Terraform の書式・構文チェック |
| `infra/github` を変える PR | 上に加えて GitHub Settings：`terraform plan`（Summary に `Plan: ...`） |
| PR を main にマージ | CD：テスト → 承認 → ghcr.io へ push／GitHub Settings：承認 → `terraform apply` |
| 元に戻したい | 該当コミットを `git revert` して main にマージ |

バイナリを差し替えるときは、`services/*/bin/` のファイルを置き換えて PR を出します。GitHub の設定（承認者・必須チェックなど）を変えるときは `infra/github` を書き換えて PR を出します。画面から直接変更した場合、次回の apply で Terraform の内容に戻ります。

## ローカルで試す

`docker-compose.yml` で2つのサービスをまとめて起動します（CI・CD も同じファイルを使います）。

```
ブラウザ ──:9002──▶ dashboard-service ──http://counting:9003──▶ counting-service
                     （ホストに公開）                            （内部のみ）
```

```bash
docker compose up -d --build

pip install websocket-client
python scripts/smoke_test.py http://localhost:9002
# ブラウザで http://localhost:9002 を開く

docker compose logs -f     # ログを見る
docker compose down        # 停止・削除
```

公開済みのイメージ（ghcr.io）で動かす場合：

```bash
COUNTING_IMAGE=ghcr.io/<owner>/<repo>/counting-service:latest \
DASHBOARD_IMAGE=ghcr.io/<owner>/<repo>/dashboard-service:latest \
docker compose up -d --no-build
```

ポートを変えるときは、各 `Dockerfile` の `ENV PORT`・`EXPOSE` と、`docker-compose.yml` の `PORT`・`ports`・`COUNTING_SERVICE_URL` を合わせて変えます。

## 設計上のポイント

- **クラウド不要**：実行環境は GitHub Actions、イメージ置き場は ghcr.io、state 置き場はリポジトリの `tfstate` ブランチと、すべて GitHub の中で完結します。
- **state の暗号化**：state には設定内容が含まれるため、AES256 で暗号化してからコミットします。公開リポジトリでも中身は読めません。`tfstate` ブランチの履歴がそのまま state のバックアップになります。
- **state の同時更新を防ぐ**：Terraform のロック機能の代わりに、ワークフローの `concurrency` で apply が同時に走らないようにしています。
- **GitHub の設定もコードで管理**：Actions 変数・承認ルール・ブランチ保護を `infra/github` に置くことで、誰がいつ何を変えたかが PR に残ります。
- **イメージのタグ = コミット SHA**：どのコミットのイメージかを追跡できます。

## 注意点

- **ローカルで `terraform apply` しないでください。** state は GitHub Actions 上で復元・保存されるため、ローカルで apply すると state がずれます。変更は必ず PR 経由で行います。
- **プライベートリポジトリ**の場合、環境の承認者（Required reviewers）とルールセットは GitHub Free では使えません（Pro / Team 以上が必要）。公開リポジトリなら Free でも使えます。
- **ルールセットのチェック名はジョブ名と一致させます。** `ci.yml` のジョブ名を変えたら `required_status_checks` も変えないと、PR がマージできなくなります。
- `GH_ADMIN_TOKEN` には有効期限があります。期限が切れると `github.yml` が失敗するので、更新してシークレットを差し替えてください。
- `tfstate` ブランチは削除しないでください（削除すると Terraform は既存の設定を把握できなくなり、作成済みのリソースと衝突します）。
- **バイナリは linux/amd64 用**です。Apple Silicon の Mac でローカル実行する場合は `docker build --platform linux/amd64` を使います。
- **カウントはメモリ上に保存されます。** counting-service を再起動するとカウントは0に戻ります。

## 後片付け

1. `infra/github/main.tf` と `outputs.tf` を削除して PR → マージ → 承認すると、GitHub 上の変数・環境・ルールセットが削除されます
2. `tfstate` ブランチを削除
3. **Packages** から ghcr.io のイメージを削除
4. シークレット `GH_ADMIN_TOKEN`・`TF_STATE_PASSPHRASE` と PAT を削除

## 参考

- [Terraform GitHub provider（integrations/github）](https://registry.terraform.io/providers/integrations/github/latest/docs)
- [hashicorp/setup-terraform](https://github.com/hashicorp/setup-terraform)
- [GitHub Container Registry の利用](https://docs.github.com/ja/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [GitHub Actions：環境（Environments）](https://docs.github.com/ja/actions/deployment/targeting-different-environments/using-environments-for-deployment)
