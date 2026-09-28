#!/bin/bash
# ============================================================
# BTCPay AIO Health Check Script
# ============================================================
# Checks if core services are RUNNING (not synced).
# Blockchain sync takes hours/days - we just need processes up.
# ============================================================

# Check if supervisor is running and services are up
check_supervisor_service() {
    local service=$1
    local status=$(supervisorctl status "$service" 2>/dev/null | awk '{print $2}')
    [ "$status" = "RUNNING" ]
}

# Core database - must be running
if ! check_supervisor_service "postgres"; then
    echo "PostgreSQL not running"
    exit 1
fi

# BTCPay Server - the main service we care about
if ! check_supervisor_service "btcpayserver"; then
    echo "BTCPay Server not running"
    exit 1
fi

# NBXplorer - required for BTCPay
if ! check_supervisor_service "nbxplorer"; then
    echo "NBXplorer not running"
    exit 1
fi

# Bitcoin daemon - must be running (but NOT necessarily synced)
if ! check_supervisor_service "bitcoind"; then
    echo "Bitcoin Core not running"
    exit 1
fi

# Optional: Quick check if BTCPay web interface responds
# Use timeout to avoid hanging
if command -v curl &>/dev/null; then
    curl -sf --max-time 5 http://127.0.0.1:49392/ > /dev/null 2>&1 || {
        echo "BTCPay Server not responding yet (may still be starting)"
        # Don't fail - process is running, just not ready yet
    }
fi

echo "All core services running"
exit 0
