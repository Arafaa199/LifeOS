#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$(cd "$SCRIPT_DIR/../../data" && pwd)"
USDA_DIR="$DATA_DIR/usda"
OFF_DIR="$DATA_DIR/off"

# USDA FoodData Central bulk download URLs
USDA_FULL_URL="https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_csv_2025-12-18.zip"

# Open Food Facts CSV (tab-separated)
OFF_URL="https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz"

echo "=== Nutrition Data Import ==="
echo "Data directory: $DATA_DIR"
echo ""

# --- Load DB password from .env ---
ENV_FILE="$SCRIPT_DIR/../../.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    export NEXUS_DB_PASS="${NEXUS_DB_PASS:-${DB_PASSWORD:-}}"
fi

# --- Setup Python venv ---
VENV_DIR="$SCRIPT_DIR/.venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating Python venv..."
    python3 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install -q psycopg2-binary

# --- Download USDA data ---
echo "--- USDA FoodData Central ---"
mkdir -p "$USDA_DIR"

if [ ! -f "$USDA_DIR/food.csv" ]; then
    USDA_ZIP="$USDA_DIR/fdc_csv.zip"
    if [ ! -f "$USDA_ZIP" ]; then
        echo "Downloading USDA FDC data..."
        curl -L -o "$USDA_ZIP" "$USDA_FULL_URL"
    fi
    echo "Extracting USDA data..."
    unzip -oj "$USDA_ZIP" -d "$USDA_DIR" "*/food.csv" "*/food_nutrient.csv" "*/branded_food.csv"
    echo "Extracted."
else
    echo "USDA data already present, skipping download."
fi

# --- Download Open Food Facts ---
echo ""
echo "--- Open Food Facts ---"
mkdir -p "$OFF_DIR"

if [ ! -f "$OFF_DIR/en.openfoodfacts.org.products.csv" ]; then
    OFF_GZ="$OFF_DIR/products.csv.gz"
    if [ ! -f "$OFF_GZ" ]; then
        echo "Downloading Open Food Facts data (~9GB compressed)..."
        echo "This will take a while..."
        curl -L -o "$OFF_GZ" "$OFF_URL"
    fi
    echo "Decompressing..."
    gunzip -k "$OFF_GZ"
    mv "$OFF_DIR/products.csv" "$OFF_DIR/en.openfoodfacts.org.products.csv" 2>/dev/null || true
    echo "Decompressed."
else
    echo "OFF data already present, skipping download."
fi

# --- Run imports ---
echo ""
echo "=== Running USDA import ==="
python3 "$SCRIPT_DIR/import_usda.py"

echo ""
echo "=== Running Open Food Facts import ==="
python3 "$SCRIPT_DIR/import_openfoodfacts.py"

# --- Verify ---
echo ""
echo "=== Verification ==="
ssh nexus "docker exec nexus-db psql -U nexus -d nexus -c \"
SELECT source, COUNT(*) as rows, COUNT(calories_per_100g) as has_cal
FROM nutrition.foods GROUP BY source ORDER BY source;\""

echo ""
ssh nexus "docker exec nexus-db psql -U nexus -d nexus -c \"
SELECT pg_size_pretty(pg_total_relation_size('nutrition.foods')) as table_size;\""

echo ""
echo "=== Import complete ==="
