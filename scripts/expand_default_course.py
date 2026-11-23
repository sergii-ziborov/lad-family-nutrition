"""Extend an owner-provided launch manifest without editing any existing recipe.

Recipe authoring input and the full paid manifest stay outside the app target.
The bundled free selection keeps exactly the same 50 recipe records and IDs.
"""
import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def expand(source, additions):
    result = copy.deepcopy(source)
    original = {r['id']: r for r in source['recipes']}
    assert len(original) == len(source['recipes'])
    added = {entry['recipe']['id']: entry for entry in additions}
    assert len(added) == len(additions) == 29
    assert not set(original).intersection(added)
    assert collections.Counter(e['recipe']['mealKinds'][0] for e in additions) == {0: 9, 1: 10, 2: 10}
    for entry in additions:
        recipe, base = entry['recipe'], original[entry['baseRecipeID']]
        assert recipe['mealKinds'] == base['mealKinds'], recipe['id']
        assert recipe['ingredients'] != base['ingredients'], recipe['id']
        assert all(i.get('amount', 0) > 0 for i in recipe['ingredients']), recipe['id']
        assert set(recipe['nutrientPreparations']) == {i['name'] for i in recipe['ingredients']}
        assert all(entry['translations'][lang].get(text) for lang in ['en', 'uk']
                   for text in [recipe['title'], *recipe['steps']])
        result['recipes'].append(copy.deepcopy(recipe))
    course = result['course']
    original_pairs = copy.deepcopy(course['suggestedPairs'])
    next_number = max(pair['number'] for pair in original_pairs) + 1
    paired = []
    for entry in additions:
        kind = entry['recipe']['mealKinds'][0]
        if kind == 0:
            continue
        key = 'lunchRecipeID' if kind == 1 else 'dinnerRecipeID'
        template = next((pair for pair in original_pairs if pair.get(key) == entry['baseRecipeID']), None)
        if template is None:
            raise ValueError(f"No source pairing for {entry['baseRecipeID']}")
        pair = copy.deepcopy(template)
        pair['number'] = next_number
        next_number += 1
        pair[key] = entry['recipe']['id']
        course['suggestedPairs'].append(pair)
        paired.append(entry['recipe']['id'])
    course['recipeIDs'].extend(added)
    course['breakfastRecipeIDs'].extend(e['recipe']['id'] for e in additions if e['recipe']['mealKinds'] == [0])
    course.update(totalRecipeCount=len(result['recipes']), titleRu='Меню на каждый день',
                  titleEn='Everyday menu', titleUk='Меню на щодень',
                  summaryRu='Завтраки, обеды и ужины с личными порциями. Перекус по желанию.',
                  summaryEn='Breakfasts, lunches and dinners with personal portions. An optional snack when needed.',
                  summaryUk='Сніданки, обіди та вечері з особистими порціями. Перекус за бажанням.')
    result['revision'] = source['revision'] + '-expanded-20261025'
    assert len(result['recipes']) == len(set(course['recipeIDs'])) == 150
    assert all(original[r['id']] == r for r in result['recipes'] if r['id'] in original)
    assert result['freeRecipeIDs'] == source['freeRecipeIDs']
    assert course['rules'] == source['course']['rules']
    assert course['suggestedPairs'][:len(original_pairs)] == original_pairs
    audit = dict(fullCount=150, addedCounts={'breakfast': 9, 'lunch': 10, 'dinner': 10},
                 mealCounts=dict(collections.Counter(r['mealKinds'][0] for r in result['recipes'])),
                 existingRecipesPreserved=len(original), freeSelectionPreserved=source['freeRecipeIDs'],
                 existingRecipeSHA256={rid: digest(r) for rid, r in original.items()},
                 originalRulesPreserved=True, originalPairingsPreserved=len(original_pairs),
                 derivedPairingsAdded=len(paired),
                 variantSources={rid: e['baseRecipeID'] for rid, e in added.items()},
                 newRecipeText='Original AI-assisted editorial text; not copied from websites.',
                 sourceCourseRights='Permission evidence has not been supplied; not legally cleared by this audit.')
    return result, audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--additions', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--app-root', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    source = json.loads(args.source.read_text())
    entries = json.loads(args.additions.read_text())
    full, audit = expand(source, entries)
    args.output.write_text(json.dumps(full, ensure_ascii=False, indent=2) + '\n')
    args.audit.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n')
    public_path = args.app_root / 'Lad/public-recipes.json'
    public = json.loads(public_path.read_text())
    assert [r['id'] for r in public['recipes']] == full['freeRecipeIDs']
    for key in ['titleRu', 'titleEn', 'titleUk', 'summaryRu', 'summaryEn', 'summaryUk', 'totalRecipeCount']:
        public['programs'][0][key] = full['course'][key]
    public_path.write_text(json.dumps(public, ensure_ascii=False, indent=2) + '\n')
    fixture = {'recipes': [entry['recipe'] for entry in entries],
               'baseRecipeIDs': {e['recipe']['id']: e['baseRecipeID'] for e in entries}}
    fixture_folder = args.app_root / 'LadTests/Fixtures'
    fixture_folder.mkdir(exist_ok=True)
    (fixture_folder / 'ExpandedCourseFixture.json').write_text(json.dumps(fixture, ensure_ascii=False, indent=2) + '\n')
    for lang in ['en', 'uk']:
        translations = {'На одну порцию.': 'One serving.' if lang == 'en' else 'На одну порцію.',
                        'Меню на каждый день': 'Everyday menu' if lang == 'en' else 'Меню на щодень'}
        for entry in entries:
            translations.update(entry['translations'][lang])
        strings = args.app_root / f'Lad/{lang}.lproj/Localizable.strings'
        existing = strings.read_text()
        lines = []
        for key, value in translations.items():
            serialized_key = json.dumps(key, ensure_ascii=False)
            if serialized_key + ' =' not in existing:
                lines.append(f'{serialized_key} = {json.dumps(value, ensure_ascii=False)};')
        if lines:
            strings.write_text(existing.rstrip() + '\n\n// Original default-course variants, October 2026.\n' + '\n'.join(lines) + '\n')
    print(json.dumps({k: audit[k] for k in ['fullCount', 'addedCounts', 'mealCounts',
                                         'existingRecipesPreserved', 'derivedPairingsAdded']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
