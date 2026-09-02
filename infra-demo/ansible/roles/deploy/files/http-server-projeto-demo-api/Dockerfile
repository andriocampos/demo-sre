FROM golang:1.21-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux go build -o http-server-projeto-demo-api .

FROM alpine:3.19

RUN adduser -D -u 1000 appuser

WORKDIR /app

COPY --from=builder /app/http-server-projeto-demo-api .

USER appuser

EXPOSE 8080

ENTRYPOINT ["./http-server-projeto-demo-api"]
