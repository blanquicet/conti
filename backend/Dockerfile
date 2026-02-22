# Build stage
FROM golang:1.24-alpine AS builder

WORKDIR /app

# Install CA certificates for HTTPS
RUN apk add --no-cache ca-certificates

# Copy go mod files first for caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build arguments for version info
ARG VERSION=dev
ARG COMMIT=unknown
ARG BUILD_TIME=unknown

# Build the binary with version info
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-w -s -X github.com/blanquicet/gastos/backend/internal/httpserver.Version=${VERSION} -X github.com/blanquicet/gastos/backend/internal/httpserver.Commit=${COMMIT} -X github.com/blanquicet/gastos/backend/internal/httpserver.BuildTime=${BUILD_TIME}" \
    -o /api ./cmd/api

# Runtime stage
FROM alpine:3.19

# Install only ffmpeg (for STT audio conversion) and CA certs
RUN apk add --no-cache ca-certificates ffmpeg && rm -rf /var/cache/apk/*

# Copy binary
COPY --from=builder /api /api

# Expose port
EXPOSE 8080

# Run
ENTRYPOINT ["/api"]
