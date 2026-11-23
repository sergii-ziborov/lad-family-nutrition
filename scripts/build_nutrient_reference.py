"""Build the small, reviewed USDA reference bundled with Lad.

Inputs are the official FoodData Central SR Legacy CSV download (April 2018)
and USDA Table of Nutrient Retention Factors, Release 6 (2007). Keep FDC IDs
explicit: automatic text matching can silently select a cooked or fortified
food for a raw ingredient. This is a bulk data transform, not a source of
ingredient-weight or recipe-yield estimates.

Usage: python3 scripts/build_nutrient_reference.py SR_LEGACY.zip retn06.txt
Sources:
https://fdc.nal.usda.gov/download-datasets/
https://www.ars.usda.gov/ARSUserFiles/80400535/Data/retn/retn06.txt
"""

import csv
import io
import json
import sys
import zipfile
from pathlib import Path


# Ingredient spelling in the app -> reviewed USDA SR Legacy FDC ID.
# A few broad ingredient labels necessarily use an explicitly documented proxy.
FOOD_IDS = {
    "Лосось": 175167,
    "Картофель": 170026,
    "Брокколи": 170379,
    "Йогурт натуральный": 171284,
    "Лимон": 167746,
    "Творог": 172182,             # low-fat cottage cheese, 2%; brand/fat varies
    "Яйцо": 171287,
    "Мука": 169761,              # unenriched wheat flour
    "Ягоды": 167762,             # strawberries proxy for unspecified berries
    "Чечевица красная": 172420, # generic lentils, raw
    "Томаты": 170457,
    "Лук": 170000,
    "Морковь": 170393,
    "Овсяные хлопья": 169705,
    "Молоко": 172217,           # whole milk without A/D fortification
    "Банан": 173944,
    "Хлеб": 174924,             # white bread proxy for unspecified bread
    "Куриное филе": 171464,    # chicken light meat, meat only, raw
    "Гречка": 170685,          # roasted dry groats
    "Огурец": 168409,
    "Макароны": 168927,
    "Кабачок": 169291,
    "Цукини": 169291,
    "Сыр": 173414,             # cheddar proxy for unspecified cheese
    "Филе индейки": 171098,
    "Рис": 169756,             # unenriched white rice
    "Бурый рис": 169703,
    "Пропаренный рис": 169758,
    "Перец сладкий": 170108,
    "Сладкий перец": 170108,
    "Минтай": 173725,
    "Хек": 173713,             # whiting proxy for hake (no SR hake entry)
    "Сметана": 171257,
    "Цветная капуста": 169986,
    "Шампиньоны": 169251,
    "Рисовая мука": 169714,
    "Гречневая мука": 170687,
    "Ржаная мука": 168886,
    "Сельдерей": 169988,
    "Мясной фарш": 174036,    # 80/20 beef proxy; actual mince may differ
    "Растительное масло": 171025, # sunflower oil proxy
    "Капуста": 169975,
    "Капуста белокочанная": 169975,
    "Свёкла": 169145,
    "Яблоко": 171688,
    "Чеснок": 169230,
    "Чернослив": 168162,
    "Говядина": 170809,        # stew cut proxy for unspecified beef
    "Говяжья печень": 169451,
    "Утка": 172410,             # skinless duck meat proxy for unspecified cut
    "Скумбрия": 175119,
    "Вяленые томаты": 168567,
    "Лимонный сок": 167747,
    "Рисовая лапша": 169742,
    "Зелёный лук": 170005,
    "Укроп": 172233,
    "Зелень": 170416,          # parsley proxy for unspecified greens
    "Майонез": 171009,
    "Майоран": 170928,
    "Сушёный чеснок": 171325,
    "Чёрный перец": 170931,
    "Кориандр": 170922,
    "Паприка": 171329,
    "Душистый перец": 171315,
    "Лавровый лист": 170917,
    "Разрыхлитель": 172803,
    "Соль": 173468,
    "Кефир": 170904,             # plain low-fat commercial kefir proxy
    "Пекинская капуста": 169979,
    "Красное сухое вино": 173190, # generic red table wine proxy
    "Квашеная капуста": 169279,  # canned sauerkraut proxy
    "Горчица": 172234,
    "Имбирь": 169231,
    "Сливы": 169949,
    "Томатная паста": 170459,
    "Креветки": 175179,
    "Рис варёный": 169708,      # parboiled enriched rice, already cooked
    "Томатный сок": 170545,
    "Ржаные криспы": 172739,
    "Творожный сыр": 169079,   # low-fat cream cheese proxy
    "Свиная вырезка": 168249,
    "Баклажан": 169228,
    "Соевый соус": 174277,     # shoyu: contains wheat
    "Мандарин": 169105,
    "Пшено": 169702,
    "Нори": 167602,           # dried seaweed proxy; exact nori species is absent
    "Корица": 171320,
    "Тыква": 168448,
    "Мясной бульон": 172883,  # homemade beef stock proxy
    "Желатин": 169599,
    "Йогурт греческий": 170903, # plain low-fat; source allows up to 5% fat
    "Оливковое масло": 171413,
    "Куриный фарш": 171116,
    "Стручковая фасоль": 169961,
    "Солёные огурцы": 169379,
    "Говядина варёная": 169520, # cooked braised beef proxy
    "Гороховая крупа": 172428, # dry green split peas proxy for unspecified pea groats
    "Апельсин": 169097,
    "Киви": 168153,
    "Авокадо": 171705,
    "Редис": 169276,
    "Листья салата": 169249,  # green leaf lettuce proxy for mixed leaves
    "Моцарелла": 170845,    # whole-milk mozzarella
    "Фета": 173420,
    "Руккола": 169387,
    "Свинина": 167810,            # mixed pork cuts: cut not specified in source
    "Печень индейки": 171486,
    "Брынза": 173420,              # feta proxy: brined-cheese composition varies
    "Белое сухое вино": 174837,  # generic white table wine, not dry-specific
    "Куриный окорочок": 172378, # raw leg meat and skin; purchased bone excluded via yield
    "Свиные ножки": 167859,      # raw feet; edible broth/collagen yield estimated
    "Говядина на кости": 170809, # beef stew cut proxy; bone excluded via yield
    "Голень индейки": 171493,   # raw turkey leg meat and skin; bone excluded via yield
    "Гвоздика": 171321,
    "Нут": 173756,
    "Булгур": 170688,
    "Оливки": 169096,             # green pickled olives, edible portion
    "Грецкие орехи": 170187,
    "Шпинат": 168462,
    "Чечевица": 172420,
    "Томаты черри": 170457,      # raw tomato reference, cultivar varies
    "Петрушка": 170416,
    "Базилик": 172232,
    "Орегано": 171328,
    "Кунжутное масло": 171016,
    "Ореховое масло": 171030,
    "Сыр с белой плесенью": 172177, # brie reference, not every soft cheese
    "Винный уксус": 172240,
    "Яблочный уксус": 173469,
    "Вода": 174158,
}

# App key -> (SR Legacy nutrient ID, USDA retention-table nutrient code, unit)
NUTRIENTS = {
    "energy": (1008, None, "ккал"),
    "protein": (1003, None, "г"),
    "fat": (1004, None, "г"),
    "carbohydrate": (1005, None, "г"),
    "fiber": (1079, None, "г"),
    "sodium": (1093, 307, "мг"),
    "vitamin_a": (1106, 392, "мкг"),
    "vitamin_c": (1162, 401, "мг"),
    "vitamin_d": (1114, None, "мкг"),
    "vitamin_e": (1109, None, "мг"),
    "vitamin_k": (1185, None, "мкг"),
    "vitamin_b1": (1165, 404, "мг"),
    "vitamin_b2": (1166, 405, "мг"),
    "vitamin_b3": (1167, 406, "мг"),
    "vitamin_b6": (1175, 415, "мг"),
    "vitamin_b12": (1178, 418, "мкг"),
    "folate": (1187, 432, "мкг"),
    "choline": (1180, 421, "мг"),
    "calcium": (1087, 301, "мг"),
    "iron": (1089, 303, "мг"),
    "magnesium": (1090, 304, "мг"),
    "phosphorus": (1091, 305, "мг"),
    "potassium": (1092, 306, "мг"),
    "zinc": (1095, 309, "мг"),
    "selenium": (1103, None, "мкг"),
}


def zip_rows(archive, filename):
    name = next(name for name in archive.namelist() if name.endswith("/" + filename))
    with archive.open(name) as raw:
        yield from csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig"))


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    selected = set(FOOD_IDS.values())
    nutrient_ids = {value[0]: key for key, value in NUTRIENTS.items()}
    descriptions = {}
    values = {fdc_id: {} for fdc_id in selected}
    with zipfile.ZipFile(sys.argv[1]) as archive:
        for row in zip_rows(archive, "food.csv"):
            fdc_id = int(row["fdc_id"])
            if fdc_id in selected:
                descriptions[fdc_id] = row["description"]
        for row in zip_rows(archive, "food_nutrient.csv"):
            fdc_id = int(row["fdc_id"])
            if fdc_id in selected:
                key = nutrient_ids.get(int(row["nutrient_id"]))
                if key and row["amount"]:
                    values[fdc_id][key] = round(float(row["amount"]), 5)
    missing = selected - descriptions.keys()
    if missing:
        raise ValueError(f"Unknown FDC IDs: {sorted(missing)}")

    retention_ids = {code: key for key, (_, code, _) in NUTRIENTS.items() if code}
    retention = {}
    if sys.argv[2] == "--keep-retention":
        existing = Path(__file__).resolve().parents[1] / "Lad" / "nutrient-reference.json"
        retention = json.loads(existing.read_text(encoding="utf-8"))["retention"]
        lines = []
    else:
        lines = Path(sys.argv[2]).read_text(encoding="utf-8-sig").splitlines()
    for line in lines:
        parts = [part.strip("~ \r\n") for part in line.split("^")]
        if len(parts) < 6:
            continue
        key = retention_ids.get(int(parts[3]))
        if key and parts[5]:
            retention.setdefault(str(int(parts[0])), {})[key] = float(parts[5]) / 100
    output = {
        "source": "USDA FoodData Central SR Legacy 2018; USDA Nutrient Retention Factors R6",
        "units": {key: unit for key, (_, _, unit) in NUTRIENTS.items()},
        "foods": {name: {"fdc_id": fdc_id, "description": descriptions[fdc_id],
                         "per_100g": values[fdc_id]}
                  for name, fdc_id in sorted(FOOD_IDS.items())},
        "retention": retention,
    }
    output_path = Path(__file__).resolve().parents[1] / "Lad" / "nutrient-reference.json"
    output_path.write_text(json.dumps(output, ensure_ascii=False, sort_keys=True,
                                      separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{len(output['foods'])} ingredient names, {len(retention)} retention methods; {output_path}")


if __name__ == "__main__":
    main()
