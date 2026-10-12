# Stage 1: Build stage
FROM debian:bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libcurl4-openssl-dev \
    nlohmann-json3-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY utility.cpp .

RUN g++ -O2 -std=c++17 utility.cpp -o telemetry_agent -lcurl

# Stage 2: Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/telemetry_agent /app/telemetry_agent

ENTRYPOINT ["/app/telemetry_agent"]
