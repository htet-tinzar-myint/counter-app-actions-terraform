#!/usr/bin/env bash
# Terraform の state を、クラウドを使わずにこのリポジトリの tfstate ブランチへ保存する
#   - state は AES256 で暗号化してからコミットする（公開リポジトリでも中身は読めない）
#   - パスフレーズは環境変数 TF_STATE_PASSPHRASE（GitHub シークレット）で渡す
#   - tfstate ブランチのコミット履歴が、そのまま state の履歴（バックアップ）になる
#
# 使い方（GitHub Actions 上で、リポジトリのルートから実行）:
#   scripts/tfstate.sh pull infra/github   # tfstate ブランチ → <dir>/terraform.tfstate
#   scripts/tfstate.sh push infra/github   # <dir>/terraform.tfstate → tfstate ブランチ（変更時のみ）
set -euo pipefail

cmd="${1:?usage: tfstate.sh pull|push <terraform dir>}"
dir="${2:?usage: tfstate.sh pull|push <terraform dir>}"

branch="tfstate"
state="$dir/terraform.tfstate"
encrypted="$(basename "$dir").tfstate.gpg" # tfstate ブランチ内のファイル名
checksum="$dir/.tfstate.sha256"            # pull 時点の state のハッシュ（変更検知用）

: "${TF_STATE_PASSPHRASE:?シークレット TF_STATE_PASSPHRASE が未登録です（README 参照）}"

gpg_run() {
  gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 0 "$@" <<<"$TF_STATE_PASSPHRASE"
}

remote_has_branch() {
  git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1
}

case "$cmd" in
  pull)
    rm -f "$state" "$checksum"
    if remote_has_branch; then
      git fetch --quiet --depth=1 origin "$branch"
      if git cat-file -e "FETCH_HEAD:$encrypted" 2>/dev/null; then
        tmp="$(mktemp)"
        git show "FETCH_HEAD:$encrypted" >"$tmp"
        gpg_run --decrypt --output "$state" "$tmp"
        rm -f "$tmp"
        sha256sum "$state" | cut -d' ' -f1 >"$checksum"
        echo "state を復元しました（$branch:$encrypted）"
        exit 0
      fi
    fi
    echo "保存済みの state がありません。新規に作成します"
    ;;

  push)
    if [ ! -f "$state" ]; then
      echo "state がないため保存しません"
      exit 0
    fi
    if [ -f "$checksum" ] && [ "$(sha256sum "$state" | cut -d' ' -f1)" = "$(cat "$checksum")" ]; then
      echo "state に変更はありません"
      exit 0
    fi

    worktree="$(mktemp -d)"
    if remote_has_branch; then
      git fetch --quiet --depth=1 origin "$branch"
      git worktree add --quiet --detach "$worktree" FETCH_HEAD
    else
      # 初回：履歴を持たない tfstate ブランチを作る
      git worktree add --quiet --detach "$worktree"
      git -C "$worktree" checkout --quiet --orphan "$branch"
      git -C "$worktree" rm -rfq .
    fi

    gpg_run --symmetric --cipher-algo AES256 --output "$worktree/$encrypted" "$state"

    git -C "$worktree" add "$encrypted"
    git -C "$worktree" \
      -c user.name="github-actions[bot]" \
      -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
      commit --quiet -m "Update $encrypted (${GITHUB_SHA:-local})"
    git -C "$worktree" push --quiet origin "HEAD:refs/heads/$branch"
    git worktree remove --force "$worktree"
    echo "state を保存しました（$branch:$encrypted）"
    ;;

  *)
    echo "usage: tfstate.sh pull|push <terraform dir>" >&2
    exit 2
    ;;
esac
