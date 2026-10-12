"""dashboard-service のスモークテスト。

1. /health が 200 を返すこと
2. WebSocket（socket.io）で接続し、counting-service から取得した "count" が届くこと
   → dashboard → counting の通信まで含めて動いていることを確認できる

使い方:
    pip install websocket-client
    python scripts/smoke_test.py http://localhost:9002
    python scripts/smoke_test.py https://dashboard-service-xxxx.a.run.app
"""

import json
import sys
import time
import urllib.request

import websocket


def wait_for_health(base_url: str, timeout_sec: int = 60) -> None:
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"{base_url}/health", timeout=5) as res:
                if res.status == 200:
                    print("OK  /health -> 200")
                    return
        except Exception as e:  # 起動待ちの間はエラーを無視して再試行
            print(f"... waiting for /health ({e})")
        time.sleep(2)
    raise SystemExit("NG  /health did not return 200")


def wait_for_count(base_url: str, timeout_sec: int = 30) -> dict:
    ws_url = base_url.replace("https://", "wss://").replace("http://", "ws://")
    ws_url += "/socket.io/?EIO=3&transport=websocket"
    ws = websocket.create_connection(ws_url, timeout=10)
    try:
        deadline = time.time() + timeout_sec
        while time.time() < deadline:
            msg = ws.recv()
            # socket.io のイベントは 42<ack id>["message", {...}] の形式で届く
            if not msg.startswith("42") or "[" not in msg:
                continue
            event, payload = json.loads(msg[msg.index("["):])
            if event != "message" or "count" not in payload:
                continue
            # counting-service に届かないと count = -1、hostname = "[Unreachable]" になる
            if payload["count"] < 0:
                raise SystemExit(f"NG  dashboard cannot reach counting-service: {payload.get('message')}")
            print(f"OK  received count over WebSocket: {payload}")
            return payload
    finally:
        ws.close()
    raise SystemExit("NG  no count received (dashboard cannot reach counting-service?)")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: smoke_test.py <dashboard base URL>")
    base = sys.argv[1].rstrip("/")
    wait_for_health(base)
    wait_for_count(base)
    print("Smoke test passed")
