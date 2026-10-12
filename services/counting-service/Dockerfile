# counting-service: 呼ばれるたびにカウントを1増やしてJSONで返すサービス
# ビルド済みの静的バイナリ（Go, linux/amd64）をそのまま載せる
FROM gcr.io/distroless/static-debian12:nonroot

COPY --chmod=755 bin/counting-service /app/counting-service

# 環境変数 PORT（既定 9003）で待ち受けポートを決める
ENV PORT=9003
EXPOSE 9003

USER nonroot:nonroot
ENTRYPOINT ["/app/counting-service"]
