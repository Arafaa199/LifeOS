#!/usr/bin/env python3
"""Import USDA FoodData Central data into nutrition.foods.

Handles Foundation Foods, SR Legacy, and Branded Foods datasets.
Downloads are CSV files from USDA FDC bulk download.
"""

import csv
import os
import sys
from collections import defaultdict
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values

DB_HOST = os.environ.get("NEXUS_DB_HOST", "10.0.0.11")
DB_PORT = os.environ.get("NEXUS_DB_PORT", "5432")
DB_NAME = os.environ.get("NEXUS_DB_NAME", "nexus")
DB_USER = os.environ.get("NEXUS_DB_USER", "nexus")
DB_PASS = os.environ.get("NEXUS_DB_PASS", "")

DATA_DIR = Path(__file__).parent.parent.parent / "data" / "usda"

# USDA nutrient IDs we care about
NUTRIENT_MAP = {
    1008: "calories",    # Energy (kcal)
    1003: "protein",     # Protein
    1005: "carbs",       # Carbohydrate, by difference
    1004: "fat",         # Total lipid (fat)
    1079: "fiber",       # Fiber, total dietary
    2000: "sugar",       # Sugars, total including NLEA
    1093: "sodium",      # Sodium, Na (mg)
}

BATCH_SIZE = 5000
MAX_NUTRIENT_VALUE = 9999999.99  # NUMERIC(9,2) max


def clamp(val):
    """Clamp nutrient value to fit NUMERIC(9,2), discard absurd values."""
    if val is None:
        return None
    if abs(val) > MAX_NUTRIENT_VALUE:
        return None
    return val


def get_conn():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
        user=DB_USER, password=DB_PASS
    )


def load_nutrients(food_nutrient_csv: Path) -> dict:
    """Build {fdc_id: {nutrient_name: amount}} from food_nutrient.csv."""
    nutrients = defaultdict(dict)
    with open(food_nutrient_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            nutrient_id = int(row["nutrient_id"])
            if nutrient_id not in NUTRIENT_MAP:
                continue
            fdc_id = int(row["fdc_id"])
            try:
                amount = float(row["amount"])
            except (ValueError, TypeError):
                continue
            nutrients[fdc_id][NUTRIENT_MAP[nutrient_id]] = amount
    return nutrients


def load_foods_csv(food_csv: Path) -> list:
    """Read food.csv and return list of dicts."""
    foods = []
    with open(food_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            foods.append(row)
    return foods


def import_foundation_and_sr(conn, nutrients: dict):
    """Import Foundation Foods and SR Legacy from food.csv."""
    food_csv = DATA_DIR / "food.csv"
    if not food_csv.exists():
        print(f"  Skipping: {food_csv} not found")
        return 0

    foods = load_foods_csv(food_csv)
    source_map = {
        "foundation_food": ("usda_foundation", 1, True),
        "sr_legacy_food": ("usda_sr_legacy", 2, True),
    }

    rows = []
    for food in foods:
        data_type = food.get("data_type", "").lower()
        if data_type not in source_map:
            continue

        source, quality, is_whole = source_map[data_type]
        fdc_id = int(food["fdc_id"])
        n = nutrients.get(fdc_id, {})

        if not n.get("calories"):
            continue

        rows.append((
            fdc_id,
            None,  # barcode
            food.get("description", "").strip(),
            None,  # brand
            source,
            clamp(n.get("calories")),
            clamp(n.get("protein")),
            clamp(n.get("carbs")),
            clamp(n.get("fat")),
            clamp(n.get("fiber")),
            clamp(n.get("sugar")),
            clamp(n.get("sodium")),
            None,  # serving_size_g
            None,  # serving_description
            food.get("food_category_id"),
            is_whole,
            quality,
        ))

    if not rows:
        print("  No Foundation/SR Legacy rows to insert")
        return 0

    inserted = _bulk_insert(conn, rows)
    print(f"  Foundation + SR Legacy: {inserted} rows inserted")
    return inserted


def import_branded(conn, nutrients: dict):
    """Import Branded Foods from branded_food.csv + food.csv."""
    branded_csv = DATA_DIR / "branded_food.csv"
    food_csv = DATA_DIR / "food.csv"

    if not branded_csv.exists():
        print(f"  Skipping branded: {branded_csv} not found")
        return 0

    # Build fdc_id -> food description from food.csv
    food_names = {}
    with open(food_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get("data_type", "").lower() == "branded_food":
                food_names[int(row["fdc_id"])] = row.get("description", "").strip()

    rows = []
    with open(branded_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            fdc_id = int(row["fdc_id"])
            n = nutrients.get(fdc_id, {})

            if not n.get("calories"):
                continue

            name = food_names.get(fdc_id, row.get("short_description", "")).strip()
            if not name:
                continue

            barcode = row.get("gtin_upc", "").strip() or None
            brand = row.get("brand_owner", "").strip() or row.get("brand_name", "").strip() or None

            serving_size = None
            try:
                serving_size = float(row.get("serving_size", ""))
            except (ValueError, TypeError):
                pass

            rows.append((
                fdc_id,
                barcode,
                name,
                brand,
                "usda_branded",
                clamp(n.get("calories")),
                clamp(n.get("protein")),
                clamp(n.get("carbs")),
                clamp(n.get("fat")),
                clamp(n.get("fiber")),
                clamp(n.get("sugar")),
                clamp(n.get("sodium")),
                clamp(serving_size),
                row.get("serving_size_unit", "").strip() or None,
                row.get("branded_food_category", "").strip() or None,
                False,
                3,
            ))

    if not rows:
        print("  No branded rows to insert")
        return 0

    # Deduplicate by barcode — keep first occurrence (by fdc_id order)
    seen_barcodes = set()
    deduped = []
    for row in rows:
        barcode = row[1]  # index 1 = barcode
        if barcode and barcode in seen_barcodes:
            continue
        if barcode:
            seen_barcodes.add(barcode)
        deduped.append(row)

    print(f"  {len(rows)} raw, {len(deduped)} after barcode dedup")
    inserted = _bulk_insert(conn, deduped)
    print(f"  Branded Foods: {inserted} rows inserted")
    return inserted


def _bulk_insert(conn, rows: list) -> int:
    """Bulk insert rows into nutrition.foods, skip conflicts on fdc_id."""
    sql = """
        INSERT INTO nutrition.foods (
            fdc_id, barcode, name, brand, source,
            calories_per_100g, protein_per_100g, carbs_per_100g,
            fat_per_100g, fiber_per_100g, sugar_per_100g, sodium_mg_per_100g,
            serving_size_g, serving_description, category, is_whole_food, data_quality
        ) VALUES %s
        ON CONFLICT (fdc_id) WHERE fdc_id IS NOT NULL DO NOTHING
    """
    total = 0
    cur = conn.cursor()
    for i in range(0, len(rows), BATCH_SIZE):
        batch = rows[i:i + BATCH_SIZE]
        execute_values(cur, sql, batch, page_size=BATCH_SIZE)
        total += cur.rowcount
        conn.commit()
        if (i // BATCH_SIZE) % 20 == 0:
            print(f"    ... {i + len(batch)}/{len(rows)} processed")
    cur.close()
    return total


def main():
    if not DATA_DIR.exists():
        print(f"ERROR: Data directory not found: {DATA_DIR}")
        print("Run run_import.sh to download USDA data first.")
        sys.exit(1)

    nutrient_csv = DATA_DIR / "food_nutrient.csv"
    if not nutrient_csv.exists():
        print(f"ERROR: {nutrient_csv} not found")
        sys.exit(1)

    print("Loading nutrient data...")
    nutrients = load_nutrients(nutrient_csv)
    print(f"  Loaded nutrients for {len(nutrients)} foods")

    conn = get_conn()
    try:
        total = 0
        print("\nImporting Foundation Foods + SR Legacy...")
        total += import_foundation_and_sr(conn, nutrients)

        print("\nImporting Branded Foods...")
        total += import_branded(conn, nutrients)

        print(f"\nDone. Total USDA rows inserted: {total}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
