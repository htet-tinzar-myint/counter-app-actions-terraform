"""dashboard → counting-service の動作を記録（キャプチャ）する。

1. WebSocket（socket.io）で dashboard に接続し、counting-service から取得した count を数回分記録
2. ブラウザ（ヘッドレス Chromium）で dashboard を開き、画面のスクリーンショットを撮る
3. 結果の表を capture/summary.md に書き出す（GitHub Actions では Summary ページにも表示）

出力（capture/ 以下。GitHub Actions ではアーティファクト dashboard-capture としてダウンロードできる）:
    dashboard.png   dashboard の画面
    counts.json     受け取った count の記録
    summary.md      結果の表

使い方:
    pip install websocket-client playwright
    python -m playwright install --with-deps chromium
    python scripts/capture.py http://localhost:9002
"""

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import websocket

from smoke_test import wait_for_health

OUT = Path("capture")


def collect_counts(base_url: str, samples: int = 5, timeout_sec: int = 60) -> list[dict]:
    """dashboard が counting-service から取得して送ってくる count を samples 回分記録する"""
    ws_url = base_url.replace("https://", "wss://").replace("http://", "ws://")
    ws_url += "/socket.io/?EIO=3&transport=websocket"
    ws = websocket.create_connection(ws_url, timeout=10)
    records = []
    try:
        deadline = time.time() + timeout_sec
        while len(records) < samples and time.time() < deadline:
            try:
                msg = ws.recv()
            except websocket.WebSocketTimeoutException:
                continue
            # socket.io のイベントは 42<ack id>["message", {...}] の形式で届く
            if not msg.startswith("42") or "[" not in msg:
                continue
            event, payload = json.loads(msg[msg.index("["):])
            if event != "message" or "count" not in payload:
                continue
            record = {"time": datetime.now(timezone.utc).strftime("%H:%M:%S"), **payload}
            records.append(record)
            print(f"... received {payload}")
    finally:
        ws.close()
    return records


def take_screenshot(base_url: str, path: Path) -> str | None:
    """dashboard をブラウザで開いてスクリーンショットを撮る。失敗したらエラー内容を返す"""
    try:
        from playwright.sync_api import sync_playwright

        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={"width": 1280, "height": 800})
            page.goto(base_url, wait_until="load", timeout=30_000)
            page.wait_for_timeout(5_000)  # 画面上の count が何回か更新されるのを待つ
            page.screenshot(path=str(path), full_page=True)
            browser.close()
        print(f"OK  screenshot saved: {path}")
        return None
    except Exception as e:  # スクリーンショットは補助的な記録なので、失敗しても結果は count で判定する
        print(f"WARN screenshot failed: {e}")
        return str(e)


def build_summary(base_url: str, records: list[dict], screenshot_error: str | None) -> tuple[bool, str]:
    counts = [r["count"] for r in records]
    ok = bool(records) and all(c >= 0 for c in counts)
    increasing = len(counts) > 1 and all(b > a for a, b in zip(counts, counts[1:]))

    lines = ["### Dashboard → counting-service capture", ""]
    if ok:
        trend = "increasing ✅" if increasing else "not strictly increasing"
        lines.append(
            f"**Result: ✅ OK** — dashboard (`{base_url}`) received {len(counts)} counts "
            f"from counting-service ({counts[0]} → {counts[-1]}, {trend})"
        )
    elif not records:
        lines.append("**Result: ❌ NG** — no count received (dashboard cannot reach counting-service?)")
    else:
        lines.append("**Result: ❌ NG** — dashboard cannot reach counting-service (count = -1)")
    lines += ["", "| # | time (UTC) | count | hostname | message |", "| --- | --- | --- | --- | --- |"]
    for i, r in enumerate(records, 1):
        lines.append(f"| {i} | {r['time']} | {r['count']} | {r.get('hostname', '-')} | {r.get('message', '-')} |")

    lines.append("")
    if screenshot_error:
        lines.append(f"Screenshot: failed (`{screenshot_error[:200]}`)")
    else:
        lines.append("Screenshot: `dashboard.png`")
    lines.append(
        "Screenshot, counts and container logs: download the **dashboard-capture** artifact "
        "at the bottom of this run's Summary page."
    )
    return ok, "\n".join(lines) + "\n"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: capture.py <dashboard base URL>")
    base = sys.argv[1].rstrip("/")
    OUT.mkdir(exist_ok=True)

    wait_for_health(base)
    records = collect_counts(base)
    screenshot_error = take_screenshot(base, OUT / "dashboard.png")

    ok, summary = build_summary(base, records, screenshot_error)
    (OUT / "counts.json").write_text(json.dumps(records, indent=2, ensure_ascii=False), encoding="utf-8")
    (OUT / "summary.md").write_text(summary, encoding="utf-8")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as f:
            f.write(summary)
    print(summary)

    if not ok:
        raise SystemExit(1)
