# dashboard-service: counting-service の値を取得し、WebSocket で画面に表示するサービス
# ビルド済みの静的バイナリ（Go, linux/amd64）をそのまま載せる
# distroless/static には CA 証明書が入っているため、https の counting-service URL を呼べる
FROM gcr.io/distroless/static-debian12:nonroot

COPY --chmod=755 bin/dashboard-service /app/dashboard-service

# PORT: 待ち受けポート（既定 9002）
# COUNTING_SERVICE_URL: 呼び出し先（docker run -e で渡す）
ENV PORT=9002
EXPOSE 9002

USER nonroot:nonroot
ENTRYPOINT ["/app/dashboard-service"]
