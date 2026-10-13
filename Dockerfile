# pitboard self-hosting image (M2; first live test pending on fnOS NAS)
FROM racket/racket:9.3

RUN raco pkg install --auto --no-docs http-easy

WORKDIR /app
COPY . .
RUN raco pkg install --auto --no-docs --link /app

EXPOSE 8090
VOLUME /data
CMD ["raco", "pitboard", "serve", "--port", "8090", "--data", "/data", "--assets", "/app/assets"]
