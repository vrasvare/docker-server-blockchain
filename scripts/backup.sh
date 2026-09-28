#!/bin/bash
# ============================================================
# BTCPay AIO Backup Script
# ============================================================
# Backs up ONLY critical data from /config volume (NVMe)
# Does NOT backup /chaindata - that's expendable blockchain data
# ============================================================

set -e

# ============================================================
# Configuration
# ============================================================
BACKUP_DIR="${BACKUP_DIR:-/config/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="btcpay-backup-${TIMESTAMP}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# Functions
# ============================================================

show_help() {
    cat <<EOF
BTCPay AIO Backup Script

Usage: backup.sh [OPTIONS]

Options:
  -d, --dir DIR       Backup destination directory (default: /config/backups)
  -r, --retention N   Keep backups for N days (default: 30)
  -l, --list          List existing backups
  --verify            Verify latest backup integrity
  -h, --help          Show this help

What gets backed up (from /config - NVMe RAID):
  - PostgreSQL database (pg_dumpall)
  - MariaDB database (mysqldump) - for Mempool
  - BTCPay Server settings and data
  - BTCPay plugins
  - NBXplorer configuration
  - Bitcoin & Monero configs
  - Mempool configuration
  - Credentials file

What is NOT backed up (/chaindata - HDD):
  - Bitcoin blockchain (~700GB)
  - Monero blockchain (~200GB)
  - Mempool indexes
  These can be re-synced from the network.

Example:
  backup.sh                    # Run backup with defaults
  backup.sh -d /mnt/backup     # Backup to specific directory
  backup.sh -l                 # List existing backups
  backup.sh --verify           # Verify last backup

EOF
}

list_backups() {
    log_info "Existing backups in ${BACKUP_DIR}:"
    echo ""
    if [ -d "$BACKUP_DIR" ]; then
        ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "  No backups found"
    else
        echo "  Backup directory does not exist"
    fi
}

verify_backup() {
    local latest=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
    if [ -z "$latest" ]; then
        log_error "No backups found to verify"
        exit 1
    fi

    log_info "Verifying: $latest"

    # Check tar integrity
    if tar -tzf "$latest" > /dev/null 2>&1; then
        log_success "Archive integrity: OK"
    else
        log_error "Archive integrity: FAILED"
        exit 1
    fi

    # Check manifest
    if tar -xzf "$latest" -O "*/manifest.txt" 2>/dev/null | head -5; then
        log_success "Manifest: OK"
    else
        log_warn "No manifest found in backup"
    fi
}

run_backup() {
    log_info "Starting backup: ${BACKUP_NAME}"
    log_info "Destination: ${BACKUP_DIR}"
    echo ""

    mkdir -p "$BACKUP_DIR"
    local WORK_DIR=$(mktemp -d)
    local BACKUP_WORK="${WORK_DIR}/${BACKUP_NAME}"
    mkdir -p "$BACKUP_WORK"

    # ============================================================
    # 1. PostgreSQL Database Dump
    # ============================================================
    log_info "Backing up PostgreSQL..."
    if gosu postgres pg_dumpall > "${BACKUP_WORK}/postgres-all.sql" 2>/dev/null; then
        log_success "PostgreSQL dump: $(du -h "${BACKUP_WORK}/postgres-all.sql" | cut -f1)"
    else
        log_warn "PostgreSQL dump failed (service may not be running)"
    fi

    # ============================================================
    # 1b. MariaDB Database Dump (for Mempool)
    # ============================================================
    log_info "Backing up MariaDB..."
    if mysqldump --all-databases --single-transaction > "${BACKUP_WORK}/mariadb-all.sql" 2>/dev/null; then
        log_success "MariaDB dump: $(du -h "${BACKUP_WORK}/mariadb-all.sql" | cut -f1)"
    else
        log_warn "MariaDB dump failed (service may not be running)"
    fi

    # ============================================================
    # 2. BTCPay Server Data
    # ============================================================
    log_info "Backing up BTCPay Server..."
    if [ -d "${CONFIG_DIR:-/config}/btcpay" ]; then
        tar -czf "${BACKUP_WORK}/btcpay-data.tar.gz" -C "${CONFIG_DIR:-/config}" btcpay 2>/dev/null
        log_success "BTCPay data: $(du -h "${BACKUP_WORK}/btcpay-data.tar.gz" | cut -f1)"
    fi

    # ============================================================
    # 3. BTCPay Plugins
    # ============================================================
    log_info "Backing up plugins..."
    if [ -d "${CONFIG_DIR:-/config}/btcpay-plugins" ]; then
        tar -czf "${BACKUP_WORK}/btcpay-plugins.tar.gz" -C "${CONFIG_DIR:-/config}" btcpay-plugins 2>/dev/null
        log_success "Plugins: $(du -h "${BACKUP_WORK}/btcpay-plugins.tar.gz" | cut -f1)"
    fi

    # ============================================================
    # 4. NBXplorer Configuration
    # ============================================================
    log_info "Backing up NBXplorer config..."
    if [ -d "${CONFIG_DIR:-/config}/nbxplorer" ]; then
        tar -czf "${BACKUP_WORK}/nbxplorer.tar.gz" -C "${CONFIG_DIR:-/config}" nbxplorer 2>/dev/null
        log_success "NBXplorer: $(du -h "${BACKUP_WORK}/nbxplorer.tar.gz" | cut -f1)"
    fi

    # ============================================================
    # 5. Service Configurations
    # ============================================================
    log_info "Backing up service configs..."
    tar -czf "${BACKUP_WORK}/configs.tar.gz" -C "${CONFIG_DIR:-/config}" \
        btc xmr mempool 2>/dev/null || true
    log_success "Configs: $(du -h "${BACKUP_WORK}/configs.tar.gz" 2>/dev/null | cut -f1 || echo "0")"

    # ============================================================
    # 6. Credentials
    # ============================================================
    log_info "Backing up credentials..."
    if [ -f "${CONFIG_DIR:-/config}/.credentials" ]; then
        cp "${CONFIG_DIR:-/config}/.credentials" "${BACKUP_WORK}/.credentials"
        chmod 600 "${BACKUP_WORK}/.credentials"
        log_success "Credentials: backed up"
    fi

    # ============================================================
    # 7. Create Manifest
    # ============================================================
    log_info "Creating manifest..."
    cat > "${BACKUP_WORK}/manifest.txt" <<EOF
# ============================================================
# BTCPay AIO Backup Manifest
# ============================================================
# Backup Name:    ${BACKUP_NAME}
# Created:        $(date -Iseconds)
# Hostname:       $(hostname)
# Domain:         ${DOMAIN:-unknown}
# Network:        ${BTCPAY_NETWORK:-mainnet}
# ============================================================

## Files Included:
$(ls -lh "${BACKUP_WORK}" 2>/dev/null)

## Checksums:
$(cd "${BACKUP_WORK}" && sha256sum * 2>/dev/null)

## Storage Note:
This backup contains only CRITICAL data from /config (NVMe).
Blockchain data (/chaindata on HDD) is NOT included.
To restore, re-sync blockchains from the network.

## Restore Instructions:
1. Stop BTCPay AIO container
2. Extract backup to /config volume
3. Restore PostgreSQL: psql -f postgres-all.sql
4. Extract data archives to appropriate directories
5. Start BTCPay AIO container
6. Wait for blockchain resync

EOF
    log_success "Manifest created"

    # ============================================================
    # 8. Create Final Archive
    # ============================================================
    log_info "Creating final archive..."
    tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" -C "$WORK_DIR" "$BACKUP_NAME"

    local SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)
    log_success "Backup complete: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz (${SIZE})"

    # Cleanup
    rm -rf "$WORK_DIR"

    # ============================================================
    # 9. Apply Retention Policy
    # ============================================================
    log_info "Applying retention policy (${RETENTION_DAYS} days)..."
    find "$BACKUP_DIR" -name "btcpay-backup-*.tar.gz" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true

    local COUNT=$(ls -1 "$BACKUP_DIR"/btcpay-backup-*.tar.gz 2>/dev/null | wc -l)
    log_success "Backups retained: ${COUNT}"

    echo ""
    log_success "Backup completed successfully!"
    echo ""
    echo "  Archive: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    echo "  Size:    ${SIZE}"
    echo ""
}

# ============================================================
# Main
# ============================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -r|--retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        -l|--list)
            list_backups
            exit 0
            ;;
        --verify)
            verify_backup
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

run_backup
