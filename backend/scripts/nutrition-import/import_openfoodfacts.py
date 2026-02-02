#!/usr/bin/env python3
"""Import Open Food Facts data into nutrition.foods.

Streams the large CSV and filters for relevant products:
- UAE/Gulf region products
- Global brands commonly found in UAE supermarkets
- Products with complete nutritional data
"""

import csv
import os
import sys
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values

DB_HOST = os.environ.get("NEXUS_DB_HOST", "10.0.0.11")
DB_PORT = os.environ.get("NEXUS_DB_PORT", "5432")
DB_NAME = os.environ.get("NEXUS_DB_NAME", "nexus")
DB_USER = os.environ.get("NEXUS_DB_USER", "nexus")
DB_PASS = os.environ.get("NEXUS_DB_PASS", "")

DATA_DIR = Path(__file__).parent.parent.parent / "data" / "off"

# Countries to include (UAE + Gulf + major export countries)
INCLUDE_COUNTRIES = {
    "united arab emirates", "uae", "en:united-arab-emirates",
    "saudi arabia", "en:saudi-arabia",
    "oman", "en:oman",
    "qatar", "en:qatar",
    "bahrain", "en:bahrain",
    "kuwait", "en:kuwait",
    "egypt", "en:egypt",
    "lebanon", "en:lebanon",
    "jordan", "en:jordan",
    "united kingdom", "en:united-kingdom",
    "united states", "en:united-states",
    "france", "en:france",
    "germany", "en:germany",
    "australia", "en:australia",
}

BATCH_SIZE = 5000
MAX_NUTRIENT_VALUE = 9999999.99


def get_conn():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
        user=DB_USER, password=DB_PASS
    )


def safe_float(val):
    if not val or val.strip() == "":
        return None
    try:
        v = float(val)
        if v < 0 or abs(v) > MAX_NUTRIENT_VALUE:
            return None
        return v
    except (ValueError, TypeError):
        return None


def should_include(row: dict) -> bool:
    """Filter: must have name, calories, and be from a relevant country."""
    name = row.get("product_name", "").strip()
    if not name:
        return False

    calories = safe_float(row.get("energy-kcal_100g"))
    if calories is None:
        return False

    countries = row.get("countries_tags", "").lower()
    if not countries:
        return False

    for country in countries.split(","):
        if country.strip() in INCLUDE_COUNTRIES:
            return True

    return False


def stream_and_import(conn):
    """Stream OFF CSV, filter, and bulk insert."""
    off_csv = DATA_DIR / "en.openfoodfacts.org.products.csv"
    if not off_csv.exists():
        print(f"ERROR: {off_csv} not found")
        sys.exit(1)

    cur = conn.cursor()
    batch = []
    total_read = 0
    total_inserted = 0
    total_skipped = 0

    csv.field_size_limit(sys.maxsize)

    with open(off_csv, "r", encoding="utf-8", errors="replace") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            total_read += 1

            if total_read % 100000 == 0:
                print(f"  ... read {total_read} rows, inserted {total_inserted}, skipped {total_skipped}")

            if not should_include(row):
                total_skipped += 1
                continue

            barcode = row.get("code", "").strip() or None
            name = row.get("product_name", "").strip()[:500]
            brand = row.get("brands", "").strip()[:200] or None
            category = row.get("main_category_en", "").strip()[:200] or None

            calories = safe_float(row.get("energy-kcal_100g"))
            protein = safe_float(row.get("proteins_100g"))
            carbs = safe_float(row.get("carbohydrates_100g"))
            fat = safe_float(row.get("fat_100g"))
            fiber = safe_float(row.get("fiber_100g"))
            sugar = safe_float(row.get("sugars_100g"))
            sodium = safe_float(row.get("sodium_100g"))
            if sodium is not None:
                sodium = sodium * 1000  # g -> mg
                if sodium > MAX_NUTRIENT_VALUE:
                    sodium = None

            serving_size = safe_float(row.get("serving_quantity"))
            if serving_size is not None and serving_size > MAX_NUTRIENT_VALUE:
                serving_size = None

            batch.append((
                None,       # fdc_id
                barcode,
                name,
                brand,
                "off",
                calories,
                protein,
                carbs,
                fat,
                fiber,
                sugar,
                sodium,
                serving_size,
                row.get("serving_size", "").strip()[:100] or None,
                category,
                False,
                3,
            ))

            if len(batch) >= BATCH_SIZE:
                inserted = _bulk_insert(cur, conn, batch)
                total_inserted += inserted
                batch = []

    if batch:
        inserted = _bulk_insert(cur, conn, batch)
        total_inserted += inserted

    cur.close()
    print(f"\nDone. Read {total_read}, inserted {total_inserted}, skipped {total_skipped}")
    return total_inserted


def _bulk_insert(cur, conn, rows: list) -> int:
    sql = """
        INSERT INTO nutrition.foods (
            fdc_id, barcode, name, brand, source,
            calories_per_100g, protein_per_100g, carbs_per_100g,
            fat_per_100g, fiber_per_100g, sugar_per_100g, sodium_mg_per_100g,
            serving_size_g, serving_description, category, is_whole_food, data_quality
        ) VALUES %s
        ON CONFLICT (barcode, source) WHERE barcode IS NOT NULL DO NOTHING
    """
    execute_values(cur, sql, rows, page_size=BATCH_SIZE)
    count = cur.rowcount
    conn.commit()
    return count


def main():
    if not DATA_DIR.exists():
        print(f"ERROR: Data directory not found: {DATA_DIR}")
        print("Run run_import.sh to download OFF data first.")
        sys.exit(1)

    conn = get_conn()
    try:
        print("Streaming Open Food Facts CSV...")
        stream_and_import(conn)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
