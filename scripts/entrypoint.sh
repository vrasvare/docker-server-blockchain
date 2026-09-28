#!/bin/sh
# ============================================================
# Docker Server Blockchain - Entrypoint Script
# ============================================================
# Initialization script for custom deployments
# ============================================================

set -e

echo "==================================="
echo "Docker Server Blockchain"
echo "==================================="
echo "Network: ${BTCPAY_NETWORK:-mainnet}"
echo "==================================="

# Wait for dependencies if needed
wait_for_service() {
    local host=$1
    local port=$2
    local max_attempts=${3:-30}
    local attempt=0

    echo "Waiting for $host:$port..."
    while ! nc -z "$host" "$port" 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "Failed to connect to $host:$port after $max_attempts attempts"
            return 1
        fi
        sleep 2
    done
    echo "$host:$port is available"
}

# Execute the main command
exec "$@"
