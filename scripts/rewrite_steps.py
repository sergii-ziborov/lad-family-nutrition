"""Rewrite the cooking steps of the bundled course in plain kitchen language.

Usage:
  python3 scripts/rewrite_steps.py export DIR [--batches N]
  python3 scripts/rewrite_steps.py check DIR/batch-K.out.json [...]
  python3 scripts/rewrite_steps.py apply DIR

`export` writes DIR/batch-K.in.json with each recipe's ingredients and current
steps. A writer answers in DIR/batch-K.out.json:

  {"<recipe id>": {"steps": [{"ru": "...", "en": "...", "uk": "...", "minutes": 12}, ...],
                    "minutesTotal": 45,            # optional, only when the old total was wrong
                    "note": "..."}}                # optional remark for the editor

`check` validates an answer the same way `apply` does. `apply` writes the new
steps and per-step minutes into Lad/public-recipes.json and adds the English and
Ukrainian strings. Quantities stay out of the text: the app prints the scaled
amount of every ingredient beside the step that first names it.
"""
import json
import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RECIPES = ROOT / "Lad/public-recipes.json"
STRINGS = {lang: ROOT / f"Lad/{lang}.lproj/Localizable.strings" for lang in ("en", "uk")}

BANNED = ["по упаковк", "отмерен", "до готовност", "при необходимост", "указанн", "из списк", "в приложени",
          "по инструкци", "на эту готовку", "согласно рецепт"]
QUANTITY = re.compile(r"\d+(?:[.,]\d+)?\s*(?:г|гр|кг|мл|л)(?![а-яё])|(?:чайн|столов|десертн)\w*\s+лож|стакан", re.I)
HEAT = re.compile(r"вар[ия]|свари|обжар|жарь|запек|туши|тушите|кипят|до кипени|выпек|томит|духовк|прогрей|пассеру", re.I)
TIME = re.compile(r"мин|сек|\bчас", re.I)
CYRILLIC = re.compile("[А-Яа-яЁёІіЇїЄєҐґ]")
RUSSIAN_ONLY = re.compile("[ыэъёЫЭЪЁ]")
ALIASES = {"макароны": ["паст", "спагет", "лапш"], "картофель": ["картош"], "лук": ["луков"],
           "яйцо": ["яйц", "яиц"], "гречка": ["греч"]}
RAW_NOT_FOOD = {"сырого", "сырым", "сырая", "сырое", "сырые", "сырой", "сырую"}


def normalized(text):
    text = unicodedata.normalize("NFD", text.lower())
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    return " ".join(unicodedata.normalize("NFC", text).replace("ё", "е").split())


def tokens(text):
    return [t for t in re.split(r"[^\w]+|\d+|_", normalized(text)) if t]


def stems(word):
    word = normalized(word)
    if len(word) < 3:
        return []
    out = [word]
    if len(word) == 4:
        out.append(word[:3])
    if len(word) >= 5:
        out.append(word[:-1])
    if len(word) >= 6:
        out += [word[:-2], word[:4]]
    if len(word) >= 7:
        out.append(word[:5])
    return [s for s in out if len(s) >= 3]


def mentions(name, step):
    words = tokens(step)
    candidates = [s for t in tokens(name) for s in stems(t)] + ALIASES.get(normalized(name), [])
    for stem in candidates:
        allowance = 4 if len(stem) <= 3 else 5
        for word in words:
            if word in RAW_NOT_FOOD and stem.startswith("сыр"):
                continue
            if word == stem or (word.startswith(stem) and len(word) - len(stem) <= allowance):
                return True
    return False


def strings_table(path):
    table = {}
    for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', path.read_text(), re.M):
        table[m.group(1).replace('\\"', '"').replace("\\\\", "\\")] = m.group(2).replace('\\"', '"').replace("\\\\", "\\")
    return table


def quote(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def load():
    return json.loads(RECIPES.read_text())


def export(folder, batches=5):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    recipes = load()["recipes"]
    size = -(-len(recipes) // batches)
    for k in range(batches):
        chunk = recipes[k * size:(k + 1) * size]
        rows = [{
            "id": r["id"], "title": r["title"], "mealKinds": r.get("mealKinds"), "minutes": r["minutes"],
            "servingsTheAmountsAreFor": r.get("estimatedServings", 1), "courseRole": r.get("courseRole"),
            "ingredients": [f'{i["name"]}: {i.get("amount")} {i.get("unit")}' for i in r["ingredients"]],
            "preparationHints": r.get("nutrientPreparations", {}),
            "currentSteps": r["steps"], "stepPhotos": r.get("stepImageIDs"),
        } for r in chunk]
        (folder / f"batch-{k + 1}.in.json").write_text(json.dumps(rows, ensure_ascii=False, indent=1) + "\n")
        print(folder / f"batch-{k + 1}.in.json", len(rows))


def problems(answer, recipes, tables, seen):
    """Every complaint about one answer file; empty when it can be applied."""
    issues = []
    by_id = {r["id"]: r for r in recipes}
    for rid, entry in answer.items():
        recipe = by_id.get(rid)
        if recipe is None:
            issues.append(f"{rid}: unknown recipe id")
            continue
        steps = entry.get("steps") or []
        if len(steps) != len(recipe["steps"]):
            issues.append(f"{rid}: {len(steps)} steps, the recipe has {len(recipe['steps'])} (each step has its own photo)")
        total = entry.get("minutesTotal", recipe["minutes"])
        minutes = [s.get("minutes") for s in steps]
        if not all(isinstance(m, int) and m >= 1 for m in minutes):
            issues.append(f"{rid}: every step needs integer minutes >= 1")
        elif sum(minutes) != total:
            issues.append(f"{rid}: step minutes add up to {sum(minutes)}, total is {total}")
        for n, step in enumerate(steps, 1):
            ru, en, uk = step.get("ru", ""), step.get("en", ""), step.get("uk", "")
            where = f"{rid} step {n}"
            if not (60 <= len(ru) <= 380):
                issues.append(f"{where}: Russian text is {len(ru)} characters, keep it 60–380")
            low = normalized(ru)
            for phrase in BANNED:
                if phrase in low:
                    issues.append(f"{where}: drop the vague phrase «{phrase}»")
            hit = QUANTITY.search(ru)
            if hit:
                issues.append(f"{where}: quantity «{hit.group(0)}» in the text; the app prints scaled amounts itself")
            if HEAT.search(ru) and not TIME.search(ru):
                issues.append(f"{where}: a cooking step needs its time in minutes")
            if len(re.findall(r"[.!?](?:\s|$)", ru)) > 5:
                issues.append(f"{where}: more than five sentences")
            if not en or CYRILLIC.search(en):
                issues.append(f"{where}: English text missing or contains Cyrillic")
            if not uk or RUSSIAN_ONLY.search(uk) or not CYRILLIC.search(uk):
                issues.append(f"{where}: Ukrainian text missing or has Russian-only letters (ы э ъ ё)")
            for lang, text in (("en", en), ("uk", uk)):
                known = tables[lang].get(ru)
                if known is not None and known != text:
                    issues.append(f"{where}: this Russian sentence already translates to {lang} as «{known}»")
                other = seen[lang].get(ru)
                if other is not None and other != text:
                    issues.append(f"{where}: the same Russian sentence is translated differently elsewhere")
                seen[lang][ru] = text
        joined = " ".join(s.get("ru", "") for s in steps)
        for ingredient in recipe["ingredients"]:
            if not mentions(ingredient["name"], joined):
                issues.append(f"{rid}: no step names «{ingredient['name']}», so its amount has nowhere to show")
    return issues


def check(paths):
    data = load()
    tables = {lang: strings_table(p) for lang, p in STRINGS.items()}
    seen = {lang: {} for lang in STRINGS}
    total = 0
    for path in paths:
        issues = problems(json.loads(Path(path).read_text()), data["recipes"], tables, seen)
        total += len(issues)
        for issue in issues:
            print(f"{Path(path).name}: {issue}")
    print("OK" if total == 0 else f"{total} problems")
    return total == 0


def apply(folder):
    folder = Path(folder)
    paths = sorted(folder.glob("batch-*.out.json"))
    if not check(paths):
        raise SystemExit("fix the answers first")
    data = load()
    by_id = {r["id"]: r for r in data["recipes"]}
    tables = {lang: strings_table(p) for lang, p in STRINGS.items()}
    added = {lang: {} for lang in STRINGS}
    for path in paths:
        for rid, entry in json.loads(path.read_text()).items():
            recipe = by_id[rid]
            recipe["steps"] = [s["ru"] for s in entry["steps"]]
            recipe["stepMinutes"] = [s["minutes"] for s in entry["steps"]]
            recipe["minutes"] = sum(recipe["stepMinutes"])
            for step in entry["steps"]:
                for lang in STRINGS:
                    if step["ru"] not in tables[lang]:
                        added[lang][step["ru"]] = step[lang]
    RECIPES.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    for lang, entries in added.items():
        if entries:
            text = STRINGS[lang].read_text().rstrip("\n") + "\n\n/* Cooking steps rewritten in plain kitchen language, 24 November 2026 */\n"
            text += "".join(f'"{quote(k)}" = "{quote(v)}";\n' for k, v in entries.items())
            STRINGS[lang].write_text(text)
    missing = [r["id"] for r in data["recipes"] if "stepMinutes" not in r]
    print("applied;", {k: len(v) for k, v in added.items()}, "strings; recipes not rewritten:", missing)


if __name__ == "__main__":
    command, *rest = sys.argv[1:]
    if command == "export":
        export(rest[0], int(rest[2]) if len(rest) > 2 and rest[1] == "--batches" else 5)
    elif command == "check":
        sys.exit(0 if check(rest) else 1)
    elif command == "apply":
        apply(rest[0])
    else:
        raise SystemExit(__doc__)
