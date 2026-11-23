"""Grow the bundled default course from 163 to 200 dishes.

Usage: python3 scripts/expand_course_to_200.py [--images DIR]

Adds the dishes from course_200_dishes.py with English and Ukrainian strings,
turns plain staples (buckwheat, lentils, split peas, purée, plain eggs) into
sides of a composed main, and copies the dish photos into Assets.xcassets when
--images points at the generated PNGs. Running it twice changes nothing.
"""
import argparse
import collections
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from course_200_dishes import DISHES, NEW_PAIRS, PAIR_EDITS, SIDES  # noqa: E402

RECIPES = ROOT / "Lad/public-recipes.json"
NUTRIENTS = json.loads((ROOT / "Lad/nutrient-reference.json").read_text())["foods"]
STRINGS = {lang: ROOT / f"Lad/{lang}.lproj/Localizable.strings" for lang in ("en", "uk")}
ALLERGENS = {  # mirrors IngredientAllergens.groups in Models.swift
    "Молоко": {"Молоко", "Творог", "Сыр", "Творожный сыр", "Сметана", "Йогурт натуральный", "Йогурт греческий",
               "Кефир", "Ряженка", "Моцарелла", "Фета", "Брынза", "Сыр с белой плесенью"},
    "Яйцо": {"Яйцо", "Майонез"}, "Рыба": {"Лосось", "Минтай", "Хек", "Скумбрия"}, "Ракообразные": {"Креветки"},
    "Пшеница": {"Мука", "Хлеб", "Макароны", "Соевый соус", "Булгур"}, "Рожь": {"Ржаная мука", "Ржаные криспы"},
    "Овёс": {"Овсяные хлопья"}, "Соя": {"Соевый соус"}, "Горчица": {"Горчица"}, "Сельдерей": {"Сельдерей"},
    "Кунжут": {"Кунжутное масло"}, "Орехи": {"Ореховое масло", "Грецкие орехи"},
    "Диоксид серы и сульфиты": {"Красное сухое вино", "Белое сухое вино"},
}
NOT_IN_CAPTION = {"Соль", "Вода", "Оливковое масло", "Растительное масло", "Чёрный перец", "Лимонный сок", "Паприка",
                  "Корица", "Орегано", "Кориандр", "Лавровый лист", "Специи для плова", "Чеснок", "Базилик", "Укроп",
                  "Зелень", "Петрушка", "Зелёный лук", "Томатная паста"}
CATEGORY_OVERRIDE = {"Хек": "Рыба и мясо", "Яйцо": "Молочные продукты"}


def strings_table(path):
    table = {}
    for match in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', path.read_text(), re.M):
        table[match.group(1)] = match.group(2)
    return table


def quote(text):
    return text.replace("\\", "\\\\").replace('"', '\\"')


def build(data):
    existing = {r["id"]: r for r in data["recipes"]}
    categories = collections.defaultdict(collections.Counter)
    for recipe in data["recipes"]:
        for item in recipe["ingredients"]:
            categories[item["name"]][item["category"]] += 1
    tables = {lang: strings_table(path) for lang, path in STRINGS.items()}
    new_strings = {lang: {} for lang in STRINGS}
    report = []
    for dish in DISHES:
        names = [row[0] for row in dish["ingredients"]]
        assert len(set(names)) == len(names), dish["id"]
        ingredients, preparations, protein, energy = [], {}, 0.0, 0.0
        for name, amount, unit, preparation in dish["ingredients"]:
            assert name in categories, f"{dish['id']}: {name} is not an existing course ingredient"
            assert unit in ("г", "мл") and amount > 0, (dish["id"], name)
            category = CATEGORY_OVERRIDE.get(name) or categories[name].most_common(1)[0][0]
            ingredients.append({"name": name, "amount": amount, "unit": unit, "category": category})
            preparations[name] = preparation
            per100 = NUTRIENTS.get(name, {}).get("per_100g", {})
            protein += amount * per100.get("protein", 0) / 100
            energy += amount * per100.get("energy", 0) / 100
        caption_names = [n for n in names if n not in NOT_IN_CAPTION][:3]
        title_ru, title_en, title_uk = dish["title"]
        recipe = {
            "id": dish["id"], "title": title_ru, "caption": " · ".join(caption_names),
            "cuisine": dish["cuisine"], "minutes": dish["minutes"], "difficulty": dish["difficulty"],
            "allergens": sorted(group for group, foods in ALLERGENS.items() if foods & set(names)),
            "allergensVerified": True, "mealKinds": [dish["kind"]], "estimatedServings": 1,
            "imageId": f"Menu200-{dish['id']}", "imageSource": "bundled",
            "ingredients": ingredients, "steps": [step[0] for step in dish["steps"]],
            "nutrientPreparations": preparations, "nutrients": {}, "protein": round(protein),
            "editorialTitles": {"en": title_en, "uk": title_uk}, "visibility": "public",
        }
        assert len(recipe["steps"]) == 3
        texts = {"en": [title_en] + [s[1] for s in dish["steps"]], "uk": [title_uk] + [s[2] for s in dish["steps"]]}
        for lang in STRINGS:
            captions = [tables[lang].get(n) for n in caption_names]
            assert all(captions), (lang, dish["id"], caption_names)
            pairs = [(recipe["caption"], " · ".join(captions))] + list(zip([title_ru] + recipe["steps"], texts[lang]))
            for source, target in pairs:
                if lang == "en":
                    assert not re.search("[А-Яа-яЁёІіЇїЄєҐґ]", target), (dish["id"], target)
                if tables[lang].get(source, target) != target:
                    raise SystemExit(f"{lang}: {source!r} already means {tables[lang][source]!r}")
                if source not in tables[lang]:
                    new_strings[lang][source] = target
        report.append((dish["id"], dish["kind"], round(energy), round(protein)))
        if dish["id"] in existing:
            assert existing[dish["id"]] == recipe, f"{dish['id']} differs from the stored recipe"
        else:
            data["recipes"].append(recipe)
    for recipe_id in SIDES:
        existing[recipe_id]["courseRole"] = "side"

    course = data["programs"][0]
    by_number = {pair["number"]: pair for pair in course["suggestedPairs"]}
    for number, change in PAIR_EDITS.items():
        by_number[number].update(change)
    known = {(p["lunchRecipeID"], p.get("dinnerRecipeID")) for p in course["suggestedPairs"]}
    for lunch, extras, dinner in NEW_PAIRS:
        if (lunch, dinner) in known:
            continue
        course["suggestedPairs"].append({"number": max(by_number) + 1, "lunchRecipeID": lunch, "dinnerRecipeID": dinner,
                                         "lunchExtraRecipeIDs": extras, "dinnerExtraRecipeIDs": []})
        by_number[max(by_number) + 1] = course["suggestedPairs"][-1]
    for dish in DISHES:
        if dish["id"] not in course["recipeIDs"]:
            course["recipeIDs"].append(dish["id"])
        if dish["kind"] == 0 and dish["id"] not in course["breakfastRecipeIDs"]:
            course["breakfastRecipeIDs"].append(dish["id"])
    course["totalRecipeCount"] = len(course["recipeIDs"])
    ids = {r["id"]: r for r in data["recipes"]}
    assert len(ids) == len(data["recipes"]) == len(course["recipeIDs"]) == 200
    assert set(course["recipeIDs"]) == set(ids)
    for pair in course["suggestedPairs"]:
        assert ids[pair["lunchRecipeID"]]["mealKinds"] == [1] and ids[pair["lunchRecipeID"]].get("courseRole") != "side"
        assert ids[pair["dinnerRecipeID"]]["mealKinds"] == [2] and ids[pair["dinnerRecipeID"]].get("courseRole") != "side"
        for extra in pair.get("lunchExtraRecipeIDs") or []:
            assert 1 in ids[extra]["mealKinds"], (pair["number"], extra)
        for extra in pair.get("dinnerExtraRecipeIDs") or []:
            assert 2 in ids[extra]["mealKinds"], (pair["number"], extra)
    assert len(course["suggestedPairs"]) <= 100
    return new_strings, report


def write_strings(new_strings):
    for lang, entries in new_strings.items():
        if not entries:
            continue
        text = STRINGS[lang].read_text().rstrip("\n") + "\n\n/* Default course grown to 200 dishes, 23 November 2026 */\n"
        text += "".join(f'"{quote(k)}" = "{quote(v)}";\n' for k, v in entries.items())
        STRINGS[lang].write_text(text)


def copy_images(folder):
    from PIL import Image
    for dish in DISHES:
        source = Path(folder) / f"{dish['id']}.png"
        target = ROOT / f"Assets.xcassets/Menu200-{dish['id']}.imageset"
        if (target / "photo.jpg").exists():
            continue
        if not source.exists():
            print("missing image", source)
            continue
        target.mkdir(parents=True, exist_ok=True)
        image = Image.open(source).convert("RGB")
        if max(image.size) > 1254:
            image.thumbnail((1254, 1254), Image.LANCZOS)
        image.save(target / "photo.jpg", "JPEG", quality=86, optimize=True, progressive=True)
        (target / "Contents.json").write_text(json.dumps(
            {"images": [{"filename": "photo.jpg", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}},
            indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--images")
    args = parser.parse_args()
    data = json.loads(RECIPES.read_text())
    new_strings, report = build(data)
    RECIPES.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    write_strings(new_strings)
    if args.images:
        copy_images(args.images)
    for row in report:
        print("%-42s kind %d  ~%4d kcal  %3d g protein" % row)
    print("strings added:", {k: len(v) for k, v in new_strings.items()})


if __name__ == "__main__":
    main()
