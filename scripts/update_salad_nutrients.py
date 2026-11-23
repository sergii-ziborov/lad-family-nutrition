"""Append six reviewed USDA FDC SR Legacy salad-food profiles from its CSV zip.

Usage: python3 scripts/update_salad_nutrients.py /path/to/FoodData_Central_sr_legacy_food_csv_2018-04.zip
"""

import json
import sys
import zipfile
from pathlib import Path

from build_nutrient_reference import FOOD_IDS, NUTRIENTS, zip_rows

NAMES = ("Авокадо", "Редис", "Листья салата", "Моцарелла", "Фета", "Руккола")
OUTPUT = Path(__file__).resolve().parents[1] / "Lad" / "nutrient-reference.json"


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    archive_path = Path(sys.argv[1])
    reference = json.loads(OUTPUT.read_text(encoding="utf-8"))
    identifiers = {FOOD_IDS[name]: name for name in NAMES}
    descriptions: dict[int, str] = {}
    values: dict[int, dict[str, float]] = {identifier: {} for identifier in identifiers}
    nutrient_keys = {nutrient_id: key for key, (nutrient_id, _, _) in NUTRIENTS.items()}
    with zipfile.ZipFile(archive_path) as archive:
        for row in zip_rows(archive, "food.csv"):
            identifier = int(row["fdc_id"])
            if identifier in identifiers:
                descriptions[identifier] = row["description"]
        for row in zip_rows(archive, "food_nutrient.csv"):
            identifier = int(row["fdc_id"])
            if identifier in identifiers and row["amount"]:
                key = nutrient_keys.get(int(row["nutrient_id"]))
                if key:
                    values[identifier][key] = round(float(row["amount"]), 5)
    for fdc_id, name in identifiers.items():
        per_100g = values[fdc_id]
        if len(per_100g) < 12:
            raise ValueError(f"incomplete nutrient profile for {name}: {len(per_100g)}")
        reference["foods"][name] = {
            "fdc_id": fdc_id,
            "description": descriptions[fdc_id],
            "per_100g": per_100g,
        }
        print(f"{name}: {fdc_id}, {len(per_100g)} nutrients")
    OUTPUT.write_text(json.dumps(reference, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
