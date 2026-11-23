"""Apply independently authored copy to an owner-only 150-recipe manifest.

This is an editorial build, not a copyright-clearance or plagiarism-score tool.
It preserves recipe identity, ingredients, portions, nutrition and meal roles.
Source documents and paid recipe bodies are never created in the public repo.
"""
import argparse
import collections
import copy
import hashlib
import json
import re
from pathlib import Path


LANGUAGES = ('ru', 'en', 'uk')
FACT_FIELDS = ('id', 'ingredients', 'estimatedServings', 'mealKinds', 'kcal', 'protein',
               'nutrients', 'nutrientPreparations', 'nutritionEdibleYield', 'allergens',
               'allergensVerified', 'courseRole', 'unquantifiedIngredients')
STRING_LINE = re.compile(r'\s*("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*");\s*')
RULE_TEXT = {
    'lunch-by-1530': ('Обед: ориентир до 14:00, крайнее время в этом меню — 15:30.',
                     'Lunch: aim for 14:00; this menu uses 15:30 as its latest time.',
                     'Обід: орієнтир до 14:00, крайній час у цьому меню — 15:30.'),
    'rare-lunch-starches': ('Для разнообразия картофель, макароны, кукуруза, кус-кус и белый рис в обед чередуются с другими крупами; ориентир — раз в неделю.',
                           'For variety, lunch rotates potatoes, pasta, corn, couscous and white rice with other grains; aim for once a week.',
                           'Для різноманітності картопля, макарони, кукурудза, кус-кус і білий рис в обід чергуються з іншими крупами; орієнтир — раз на тиждень.'),
    'meat-starch-pairing': ('В подборе обедов мясо и рыба сочетаются с овощами и выбранными крупами. Картофель, макароны и хлеб планируются отдельно; яйца — исключение.',
                          'Lunch planning pairs meat and fish with vegetables and selected grains. Potatoes, pasta and bread are planned separately; eggs are an exception.',
                          'У доборі обідів м’ясо й риба поєднуються з овочами та вибраними крупами. Картопля, макарони й хліб плануються окремо; яйця — виняток.'),
    'breakfast-and-snacks-are-advice': ('Если завтрака не хватило, включите перекус примерно за час до обеда. Он учитывается в порциях и покупках.',
                                     'If breakfast was not enough, enable a snack about an hour before lunch. It is included in portions and groceries.',
                                     'Якщо сніданку не вистачило, увімкніть перекус приблизно за годину до обіду. Він враховується в порціях і покупках.'),
    'summer-salads-lunch-only': ('Эта группа овощных дополнений закреплена за обедом. Для ужина выбирайте блюда из раздела ужинов.',
                               'This group of vegetable sides belongs to lunch. For dinner, choose from the dinner selection.',
                               'Ця група овочевих доповнень закріплена за обідом. Для вечері вибирайте страви з розділу вечерь.'),
    'summer-oily-salads-before-1400': ('Для отмеченных салатов с маслом ориентир обеда — до 14:00. Личное расписание можно настроить отдельно.',
                                    'For the marked oil-dressed salads, aim for lunch by 14:00. Personal meal times can be set separately.',
                                    'Для позначених салатів з олією орієнтир обіду — до 14:00. Особистий розклад можна налаштувати окремо.'),
    'breakfast-by-1100': ('Завтрак: желательно до 10:00, крайний ориентир — 11:00, примерно в течение часа после пробуждения.',
                        'Breakfast: preferably by 10:00, with 11:00 as the latest guide, about an hour after waking.',
                        'Сніданок: бажано до 10:00, крайній орієнтир — 11:00, приблизно протягом години після пробудження.'),
    'dinner-by-1900': ('Ужин: ориентир 18:00–19:00. Время в личном расписании остаётся под вашим управлением.',
                     'Dinner: aim for 18:00–19:00. You control the times in your personal schedule.',
                     'Вечеря: орієнтир 18:00–19:00. Час в особистому розкладі залишається під вашим керуванням.'),
}


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def facts(recipe):
    return {k: recipe[k] for k in FACT_FIELDS if k in recipe}


def read_strings(path):
    values = {}
    for line in path.read_text().splitlines():
        match = STRING_LINE.fullmatch(line)
        if match:
            values[json.loads(match[1])] = json.loads(match[2])
    return values


def independent_pairs(recipes, old_pairs, free_ids):
    """New examples from ingredient variety, availability and strict meal roles.

    This deliberately does not reuse the photographed day order or old pairs.
    The runtime still checks personal allergies and course restrictions.
    """
    free = set(free_ids)
    old = {(p['lunchRecipeID'], p.get('dinnerRecipeID')) for p in old_pairs}
    lunches = sorted((r for r in recipes if r['mealKinds'] == [1] and r.get('courseRole') != 'side'),
                     key=lambda r: (r['title'].casefold(), r['id']))
    dinners = [r for r in recipes if r['mealKinds'] == [2]]
    sides = [r for r in recipes if r['mealKinds'] == [1] and r.get('courseRole') == 'side']
    foods = {r['id']: {i['name'] for i in r['ingredients']} for r in recipes}
    staples = {'Куриное филе', 'Куриный фарш', 'Говядина', 'Свиная вырезка', 'Мясной фарш',
               'Филе индейки', 'Минтай', 'Хек', 'Скумбрия', 'Творог', 'Гречка', 'Бурый рис'}
    used, side_used = collections.Counter(), collections.Counter()
    pairs = []
    for lunch in lunches:
        rid = lunch['id']
        candidates = [d for d in dinners if (rid, d['id']) not in old]
        assert candidates
        def score(dinner):
            did = dinner['id']
            return ((rid in free) != (did in free), used[did],
                    len(foods[rid] & foods[did] & staples),
                    digest(['Menudaro editorial examples 2026-10-26', rid, did]))
        dinner = min(candidates, key=score)
        did = dinner['id']
        used[did] += 1
        extras = []
        # Attach an independently chosen vegetable side to animal-protein lunches.
        # Sides never become standalone main meals or change their meal role.
        if foods[rid] & (staples - {'Творог', 'Гречка', 'Бурый рис'}):
            available = [s for s in sides if (s['id'] in free) == (rid in free)]
            if available:
                side = min(available, key=lambda s: (side_used[s['id']],
                           len(foods[s['id']] & foods[rid]), digest([rid, s['id']])))
                extras = [side['id']]
                side_used[side['id']] += 1
        pairs.append({'number': len(pairs) + 1, 'lunchRecipeID': rid, 'dinnerRecipeID': did,
                      'lunchExtraRecipeIDs': extras, 'dinnerExtraRecipeIDs': []})
    assert all((p['lunchRecipeID'], p['dinnerRecipeID']) not in old for p in pairs)
    return pairs


def subset_course(course, ids):
    result, selected = copy.deepcopy(course), set(ids)
    result['recipeIDs'] = list(ids)
    result['breakfastRecipeIDs'] = [x for x in course['breakfastRecipeIDs'] if x in selected]
    result['suggestedPairs'] = []
    for original in course['suggestedPairs']:
        if original['lunchRecipeID'] not in selected:
            continue
        pair = copy.deepcopy(original)
        if pair['dinnerRecipeID'] not in selected:
            pair['dinnerRecipeID'] = None
        for key in ('lunchExtraRecipeIDs', 'dinnerExtraRecipeIDs'):
            pair[key] = [x for x in pair[key] if x in selected]
        result['suggestedPairs'].append(pair)
    result['rules'] = []
    for original in course['rules']:
        rule = copy.deepcopy(original)
        if rule.get('recipeIDs'):
            rule['recipeIDs'] = [x for x in rule['recipeIDs'] if x in selected]
            if not rule['recipeIDs']:
                continue
        result['rules'].append(rule)
    return result


def atomic_json(path, value):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


def author(source, editorial, translations):
    original = {r['id']: r for r in source['recipes']}
    assert len(original) == 150
    assert {rid for rid in original if rid.startswith('photo')}.issubset(editorial)
    assert set(editorial).issubset(original)
    result = copy.deepcopy(source)
    old_keys = set()
    added = {lang: {} for lang in ('en', 'uk')}
    timing_changes = {}
    for recipe in result['recipes']:
        rid = recipe['id']
        if rid in editorial:
            entry = editorial[rid]
            old_keys.update([recipe['caption'], *recipe['steps']])
            recipe['steps'] = [s['ru'] for s in entry['steps']]
            if 'title' in entry:
                old_keys.add(recipe['title'])
                recipe['title'] = entry['title']['ru']
                for lang in added:
                    added[lang][recipe['title']] = entry['title'][lang]
            for lang in added:
                added[lang].update({s['ru']: s[lang] for s in entry['steps']})
            if 'minutes' in entry:
                timing_changes[rid] = {'before': recipe['minutes'], 'after': entry['minutes']}
                recipe['minutes'] = entry['minutes']
            # A finished-dish illustration is accurate for the final step; old
            # page-specific process sequences are no longer used as step media.
            recipe['stepImageIDs'] = [None] * (len(recipe['steps']) - 1) + [recipe.get('imageId')]
            assert recipe['steps'] != original[rid]['steps'], rid
        old_keys.add(recipe['caption'])
        names = [i['name'] for i in recipe['ingredients'] if i['name'] not in
                 {'Вода', 'Соль', 'Чёрный перец', 'Специи', 'Лавровый лист'}][:3]
        assert names, rid
        recipe['caption'] = ' · '.join(names)
        for lang in added:
            missing = [n for n in names if n not in translations[lang]]
            assert not missing, (lang, rid, missing)
            added[lang][recipe['caption']] = ' · '.join(translations[lang][n] for n in names)
        assert facts(recipe) == facts(original[rid]), rid
    course = result['course']
    for rule in course['rules']:
        old_keys.update(rule[k] for k in ('titleRu', 'titleEn', 'titleUk') if k in rule)
        titles = RULE_TEXT[rule['id']]
        for field, value in zip(('titleRu', 'titleEn', 'titleUk'), titles):
            rule[field] = value
    without_text = lambda rule: {k: v for k, v in rule.items() if k not in ('titleRu', 'titleEn', 'titleUk')}
    assert [without_text(r) for r in course['rules']] == [without_text(r) for r in source['course']['rules']]
    old_pairs = course['suggestedPairs']
    course['suggestedPairs'] = independent_pairs(result['recipes'], old_pairs, result['freeRecipeIDs'])
    ordered = sorted(result['recipes'], key=lambda r: (r['mealKinds'][0], r.get('courseRole') == 'side',
                                                      r['title'].casefold(), r['id']))
    course['recipeIDs'] = [r['id'] for r in ordered]
    course['breakfastRecipeIDs'] = [r['id'] for r in ordered if r['mealKinds'] == [0]]
    result['revision'] = 'menudaro-editorial-20261026-' + digest([editorial, course])[:16]
    assert result['freeRecipeIDs'] == source['freeRecipeIDs']
    assert collections.Counter(r['mealKinds'][0] for r in result['recipes']) == {0: 27, 1: 71, 2: 52}
    assert set(course['recipeIDs']) == set(original)
    audit = {
        'date': '2026-10-26', 'brand': 'Menudaro', 'sourceRevision': source['revision'],
        'newRevision': result['revision'], 'fullCount': 150,
        'independentlyWrittenRecipeBodies': len(editorial), 'originalMainMealBodiesReplaced': 103,
        'retainedPreviouslyAuthoredBodies': 150 - len(editorial),
        'mealCounts': {'breakfast': 27, 'lunch': 71, 'dinner': 52},
        'unchangedFacts': list(FACT_FIELDS), 'factsPreservedForAllRecipes': True,
        'freeRecipeIDsPreserved': True, 'freeCount': 50,
        'oldMainRecipeBodiesRetained': 0, 'newPairCount': len(course['suggestedPairs']),
        'oldCompleteMainPairsReused': 0, 'oldDayOrderReused': False,
        'ruleParametersPreserved': True, 'ruleTextRewritten': len(course['rules']),
        'timeEstimatesCorrected': timing_changes,
        'inputFactsSHA256': {rid: digest(facts(r)) for rid, r in original.items()},
        'userRightsStatement': 'User supplies a mixed collection: personal material, internet, books and prior AI contributions. This is not evidence of licences for every third-party item.',
        'editorialMethod': 'New RU/EN/UK cooking instructions composed from ingredient/preparation facts; factual ingredient captions; separately generated illustrations; independently assembled pairing examples.',
        'globalUniquenessClaim': False, 'exclusiveCopyrightClaim': False,
        'sourceCollectionRightsCleared': False,
        'publicationStatus': 'Local candidate only; no server import, TestFlight upload or App Store submission.',
        'primarySources': ['https://www.copyright.gov/circs/circ33.pdf',
                           'https://developer.apple.com/app-store/review/guidelines/#intellectual-property',
                           'https://www.foodsafety.gov/food-safety-charts/safe-minimum-internal-temperatures',
                           'https://ask.fsis.usda.gov/article/To-what-temperature-should-I-cook-beef'],
    }
    return result, audit, old_keys, added


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--editorial', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--legacy-source', type=Path,
                        help='Optional immutable pre-edit legacy bundle for repeatable text cleanup')
    parser.add_argument('--app-root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    source, editorial = (json.loads(p.read_text()) for p in (args.source, args.editorial))
    translations = {lang: read_strings(args.app_root / f'Lad/{lang}.lproj/Localizable.strings')
                    for lang in ('en', 'uk')}
    full, audit, old_keys, additions = author(source, editorial, translations)
    if args.apply:
        atomic_json(args.output, full)
        by_id = {r['id']: r for r in full['recipes']}
        public = {'recipes': [by_id[rid] for rid in full['freeRecipeIDs']],
                  'programs': [subset_course(full['course'], full['freeRecipeIDs'])]}
        legacy_path = args.app_root / 'Lad/legacy-recipes.json'
        legacy = json.loads((args.legacy_source or legacy_path).read_text())
        updated_legacy = 0
        for r in legacy['recipes']:
            if r['id'] in by_id:
                current = by_id[r['id']]
                previous_facts = facts(r)
                old_keys.update([r['title'], r['caption'], *r['steps']])
                # Retain old access/image settings and facts of legacy records.
                for key in ('title', 'caption', 'steps', 'minutes'):
                    r[key] = current[key]
                r['stepImageIDs'] = [None] * (len(r['steps']) - 1) + [r.get('imageId')]
                assert facts(r) == previous_facts
                updated_legacy += 1
        atomic_json(args.app_root / 'Lad/public-recipes.json', public)
        atomic_json(legacy_path, legacy)
        # Drop superseded recipe-only translation keys from the app bundle.
        used = set()
        def strings(value):
            if isinstance(value, str): used.add(value)
            elif isinstance(value, dict):
                for item in value.values(): strings(item)
            elif isinstance(value, list):
                for item in value: strings(item)
        strings(full); strings(legacy)
        swift = '\n'.join(p.read_text() for p in (args.app_root / 'Lad').glob('*.swift'))
        removed = {}
        for lang, new in additions.items():
            path = args.app_root / f'Lad/{lang}.lproj/Localizable.strings'
            lines, count = [], 0
            for line in path.read_text().splitlines():
                match = STRING_LINE.fullmatch(line)
                key = json.loads(match[1]) if match else None
                if key and (key in new or (key in old_keys and key not in used and json.dumps(key, ensure_ascii=False) not in swift)):
                    count += 1
                else:
                    lines.append(line)
            lines += ['', '// Menudaro independent cooking copy, 26 October 2026.']
            lines += [f'{json.dumps(k, ensure_ascii=False)} = {json.dumps(v, ensure_ascii=False)};' for k, v in new.items()]
            path.write_text('\n'.join(lines).rstrip() + '\n')
            removed[lang] = count
        fixture = {'recipes': full['recipes'], 'baselineFacts': {r['id']: facts(r) for r in source['recipes']},
                   'course': full['course'], 'replacedBodyIDs': list(editorial),
                   'newPairs': full['course']['suggestedPairs'],
                   'previousMainPairs': [[p['lunchRecipeID'], p['dinnerRecipeID']]
                                         for p in source['course']['suggestedPairs'] if p.get('dinnerRecipeID')]}
        fixture_path = args.app_root / 'LadTests/Fixtures/EditorialCourseFixture.json'
        atomic_json(fixture_path, fixture)
        audit.update(legacyRecordsUpdated=updated_legacy, legacyFactsPreserved=True,
                     translationEntriesReplacedOrRemoved=removed)
        atomic_json(args.audit, audit)
    print(json.dumps({k: audit[k] for k in ('fullCount', 'independentlyWrittenRecipeBodies', 'newPairCount',
                                          'factsPreservedForAllRecipes', 'sourceCollectionRightsCleared')}, ensure_ascii=False))
    if not args.apply:
        print('Dry run; no application files written.')


if __name__ == '__main__':
    main()
