#!/usr/bin/env bash
set -uo pipefail

# LifeOS Database Migration Runner
# Runs pending .up.sql migrations against the nexus database.
# Tracks applied migrations in ops.schema_migrations.
#
# Usage:
#   ./migrate.sh                  Run all pending migrations
#   ./migrate.sh status           Show migration status
#   ./migrate.sh baseline         Mark all existing migrations as applied (first-time setup)
#   ./migrate.sh run <file>       Run a specific migration file
#   ./migrate.sh pending          List pending migrations only

MIGRATIONS_DIR="$(cd "$(dirname "$0")/migrations" && pwd)"
DB_HOST="${NEXUS_DB_HOST:-nexus}"
DB_NAME="${NEXUS_DB_NAME:-nexus}"
DB_USER="${NEXUS_DB_USER:-nexus}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

run_sql() {
    ssh "$DB_HOST" "docker exec nexus-db psql -U $DB_USER -d $DB_NAME -qtAX -c \"$1\"" 2>/dev/null
}

run_sql_file() {
    ssh "$DB_HOST" "docker exec nexus-db psql -U $DB_USER -d $DB_NAME -f /tmp/_migration.sql" 2>&1
}

copy_to_container() {
    local local_file="$1"
    local container_path="${2:-/tmp/_migration.sql}"
    scp -q "$local_file" "$DB_HOST:/tmp/_mig_stage" 2>/dev/null
    ssh "$DB_HOST" "docker cp /tmp/_mig_stage nexus-db:$container_path && rm -f /tmp/_mig_stage" 2>/dev/null
}

ensure_table() {
    run_sql "CREATE TABLE IF NOT EXISTS ops.schema_migrations (
        filename TEXT PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        checksum TEXT,
        duration_ms INT
    );" >/dev/null 2>&1
}

is_applied() {
    local result
    result=$(run_sql "SELECT 1 FROM ops.schema_migrations WHERE filename = '$1';")
    [[ "$result" == "1" ]]
}

get_checksum() {
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
}

get_migrations() {
    find "$MIGRATIONS_DIR" -name '*.up.sql' -not -name 'verify_*' | sort
}

get_applied_count() {
    run_sql "SELECT COUNT(*) FROM ops.schema_migrations;"
}

get_total_count() {
    get_migrations | wc -l | tr -d ' '
}

get_applied_list() {
    # Fetch all applied filenames in one SSH call
    run_sql "SELECT filename FROM ops.schema_migrations ORDER BY filename;"
}

cmd_status() {
    ensure_table
    local total applied_count pending
    total=$(get_total_count)
    applied_count=$(get_applied_count)
    pending=$((total - applied_count))

    echo -e "${CYAN}Migration Status${NC}"
    echo "  Total:   $total"
    echo -e "  Applied: ${GREEN}$applied_count${NC}"
    if [[ $pending -gt 0 ]]; then
        echo -e "  Pending: ${YELLOW}$pending${NC}"
        echo ""
        echo "Pending migrations:"

        local applied_set
        applied_set=$(get_applied_list)
        while IFS= read -r file; do
            local fname
            fname=$(basename "$file")
            if ! echo "$applied_set" | grep -qxF "$fname"; then
                echo -e "  ${YELLOW}$fname${NC}"
            fi
        done < <(get_migrations)
    else
        echo -e "  Pending: ${GREEN}0${NC}"
        echo ""
        echo "All migrations applied."
    fi
}

cmd_pending() {
    ensure_table
    local count=0 applied_set
    applied_set=$(get_applied_list)
    while IFS= read -r file; do
        local fname
        fname=$(basename "$file")
        if ! echo "$applied_set" | grep -qxF "$fname"; then
            echo "$fname"
            count=$((count + 1))
        fi
    done < <(get_migrations)
    if [[ $count -eq 0 ]]; then
        echo "No pending migrations."
    fi
}

cmd_baseline() {
    ensure_table
    echo -e "${CYAN}Baselining all migrations as applied...${NC}"

    # Build a single SQL file with all INSERT statements to avoid 115 SSH round-trips
    local sql_file
    sql_file=$(mktemp)
    local count=0

    while IFS= read -r file; do
        local fname checksum
        fname=$(basename "$file")
        checksum=$(get_checksum "$file")
        echo "INSERT INTO ops.schema_migrations (filename, checksum, duration_ms) VALUES ('$fname', '$checksum', 0) ON CONFLICT DO NOTHING;" >> "$sql_file"
        count=$((count + 1))
    done < <(get_migrations)

    copy_to_container "$sql_file" "/tmp/_baseline.sql"
    ssh "$DB_HOST" "docker exec nexus-db psql -U $DB_USER -d $DB_NAME -f /tmp/_baseline.sql" >/dev/null 2>&1
    rm -f "$sql_file"

    local applied
    applied=$(get_applied_count)
    echo -e "${GREEN}Baselined $applied migrations.${NC}"
}

run_one() {
    local file="$1"
    local fname checksum start_ms end_ms duration output exit_code
    fname=$(basename "$file")
    checksum=$(get_checksum "$file")

    if is_applied "$fname"; then
        echo -e "  ${GREEN}SKIP${NC}  $fname (already applied)"
        return 0
    fi

    printf "  %-50s " "$fname"

    copy_to_container "$file"

    start_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
    output=$(run_sql_file "$file" 2>&1)
    exit_code=$?
    end_ms=$(python3 -c 'import time; print(int(time.time()*1000))')
    duration=$((end_ms - start_ms))

    if [[ $exit_code -ne 0 ]] || echo "$output" | grep -qi "^ERROR:"; then
        echo -e "${RED}FAIL${NC} (${duration}ms)"
        echo "$output" | grep -i "error" | head -5
        return 1
    fi

    run_sql "INSERT INTO ops.schema_migrations (filename, checksum, duration_ms) VALUES ('$fname', '$checksum', $duration);" >/dev/null
    echo -e "${GREEN}OK${NC} (${duration}ms)"
    return 0
}

cmd_run_specific() {
    local target="$1"
    ensure_table

    if [[ -f "$MIGRATIONS_DIR/$target" ]]; then
        run_one "$MIGRATIONS_DIR/$target"
    elif [[ -f "$target" ]]; then
        run_one "$target"
    else
        echo -e "${RED}File not found: $target${NC}"
        return 1
    fi
}

cmd_migrate() {
    ensure_table
    local pending=0 applied=0 failed=0
    local applied_set
    applied_set=$(get_applied_list)

    echo -e "${CYAN}Running pending migrations...${NC}"
    echo ""

    while IFS= read -r file; do
        local fname
        fname=$(basename "$file")
        if ! echo "$applied_set" | grep -qxF "$fname"; then
            pending=$((pending + 1))
            if run_one "$file"; then
                applied=$((applied + 1))
            else
                failed=$((failed + 1))
                echo -e "\n${RED}Migration failed. Stopping.${NC}"
                break
            fi
        fi
    done < <(get_migrations)

    echo ""
    if [[ $pending -eq 0 ]]; then
        echo -e "${GREEN}No pending migrations.${NC}"
    else
        echo -e "Applied: ${GREEN}$applied${NC}  Failed: ${RED}$failed${NC}  Remaining: $((pending - applied - failed))"
    fi

    ssh "$DB_HOST" "rm -f /tmp/_migration.sql" 2>/dev/null
    [[ $failed -eq 0 ]]
}

case "${1:-}" in
    status)   cmd_status ;;
    baseline) cmd_baseline ;;
    pending)  cmd_pending ;;
    run)
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 run <filename>"
            exit 1
        fi
        cmd_run_specific "$2"
        ;;
    help|-h|--help)
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (none)     Run all pending migrations"
        echo "  status     Show migration status (applied/pending)"
        echo "  pending    List pending migration files"
        echo "  baseline   Mark all existing migrations as applied"
        echo "  run <file> Run a specific migration file"
        echo "  help       Show this help"
        ;;
    *)        cmd_migrate ;;
esac
