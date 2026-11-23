"""Refresh public statistical food-price references, with source units and periods.

No retailer scraping, API keys, currency conversion or health/profile data.
The output is also the public /v3/prices payload; deployment is a separate step.
"""
import argparse
import concurrent.futures
from datetime import date
import hashlib
import io
import json
import math
from pathlib import Path
import re
import ssl
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
UA_URL = 'https://data.gov.ua/dataset/12f4fe34-0759-4271-b1f6-780995f0ec4a/resource/9d4280b1-20ce-4aae-a005-24e4b9b7e32c/download/df_price_change_consumer_goods_service_latest.json'
UA_LICENSE = 'https://creativecommons.org/licenses/by/4.0/'
IL_LICENSE = 'https://www.cbs.gov.il/he/cbsNewBrand/Pages/רישיון-שימוש.aspx'
BLS_LICENSE = 'https://www.bls.gov/opub/copyright-information.htm'

# Statistical reference categories, not quotations for a specific brand or shop.
IL_PRODUCTS = {
    '160015': 'Хлеб', '160050': 'Мука', '160070': 'Макароны', '160083': 'Рис',
    '161020': 'Чечевица', '160137': 'Говядина', '160190': 'Куриное филе',
    '160197': 'Куриный фарш', '160095': 'Оливковое масло', '160255': 'Молоко',
    '160260': 'Йогурт натуральный', '160270': 'Сметана', '160305': 'Творог',
    '160310': 'Сыр', '160243': 'Яйцо', '160330': 'Кофе', '161130': 'Сладкий перец',
    '160520': 'Морковь', '160550': 'Томаты', '160560': 'Томаты черри',
    '160570': 'Огурец', '160600': 'Капуста', '160610': 'Цветная капуста',
    '160620': 'Баклажан', '160630': 'Цукини', '160640': 'Картофель',
    '160650': 'Лук', '160680': 'Мандарин', '160710': 'Лимон', '160800': 'Яблоко',
    '160840': 'Сливы', '160870': 'Банан', '160880': 'Авокадо',
}
UA_PRODUCTS = {
    '01_1_1_1_1': 'Рис', '01_1_1_2_2': 'Хлеб', '01_1_1_3_9': 'Макароны',
    '01_1_1_5_18': 'Мука', '01_1_1_5_20': 'Гречка', '01_1_1_5_23': 'Пшено',
    '01_1_2_1_25': 'Говядина', '01_1_2_2_28': 'Свинина',
    '01_1_2_4_33': 'Куриное филе', '01_1_4_1_59': 'Молоко',
    '01_1_4_5_68': 'Творог', '01_1_4_6_70': 'Сметана', '01_1_4_7_73': 'Яйцо',
    '01_1_5_4_78': 'Растительное масло', '01_1_6_3_83': 'Яблоко',
    '01_1_7_2_90': 'Капуста', '01_1_7_4_96': 'Лук', '01_1_7_4_97': 'Свёкла',
    '01_1_7_4_98': 'Морковь', '01_1_7_7_103': 'Картофель',
}
# Units are BLS publication units. A pound is 453.59237 g and a US gallon
# is 3785.411784 ml. Dozens are kept as pieces, never treated as grams.
BLS_PRODUCTS = {
    'APU0000701111': ('Мука', 'Flour, white, all purpose, per lb.', 453.59237, 'г'),
    'APU0000702111': ('Хлеб', 'Bread, white, pan, per lb.', 453.59237, 'г'),
    'APU0000701312': ('Рис', 'Rice, white, long grain, uncooked, per lb.', 453.59237, 'г'),
    'APU0000FF1101': ('Куриное филе', 'Chicken breast, boneless, per lb.', 453.59237, 'г'),
    'APU0000708111': ('Яйцо', 'Eggs, grade A, large, per dozen', 12, 'шт.'),
    'APU0000709112': ('Молоко', 'Milk, fresh, whole, fortified, per US gallon', 3785.411784, 'мл'),
    'APU0000710212': ('Сыр', 'Cheddar cheese, natural, per lb.', 453.59237, 'г'),
    'APU0000711211': ('Банан', 'Bananas, per lb.', 453.59237, 'г'),
    'APU0000711311': ('Апельсин', 'Oranges, Navel, per lb.', 453.59237, 'г'),
    'APU0000712112': ('Картофель', 'Potatoes, white, per lb.', 453.59237, 'г'),
    'APU0000712211': ('Листья салата', 'Lettuce, iceberg, per lb.', 453.59237, 'г'),
    'APU0000712311': ('Томаты', 'Tomatoes, field grown, per lb.', 453.59237, 'г'),
    'APU0000717311': ('Кофе', 'Coffee, ground roast, per lb.', 453.59237, 'г'),
}


def download(url, body=None, accept='*/*'):
    context = ssl.create_default_context()
    try:
        import certifi
        context = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        pass
    headers = {'User-Agent': 'MenudaroPriceReference/1.0', 'Accept': accept}
    if body is not None:
        headers['Content-Type'] = 'application/json'
    request = urllib.request.Request(url, data=body, headers=headers)
    with urllib.request.urlopen(request, context=context, timeout=40) as response:
        raw = response.read(16_000_001)
    if len(raw) > 16_000_000:
        raise ValueError('Source response exceeds 16 MB')
    return raw


def observation(name, price, quantity, unit, country, period, publisher, source, license_url, code, label):
    assert name and math.isfinite(price) and price > 0 and quantity > 0
    assert re.fullmatch(r'20\d{2}-(0[1-9]|1[0-2])', period)
    return dict(productName=name, packagePrice=price, packageQuantity=quantity, packageUnit=unit,
                currency={'IL': 'ILS', 'UA': 'UAH', 'US': 'USD'}[country],
                reference=dict(country=country, period=period, publisher=publisher,
                               sourceURL=source, licenseURL=license_url, seriesID=code,
                               sourceLabel=label, method='statistical-category-average'))


def xlsx_rows(raw):
    """Read cached cell values; never execute spreadsheet formulas or external links."""
    ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        if sum(i.file_size for i in archive.infolist()) > 25_000_000:
            raise ValueError('Workbook is too large')
        strings = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            shared = ET.fromstring(archive.read('xl/sharedStrings.xml'))
            strings = [''.join(node.itertext()) for node in shared.findall('s:si', ns)]
        sheet = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
        for row in sheet.findall('.//s:sheetData/s:row', ns):
            cells = [None] * 16
            for cell in row.findall('s:c', ns):
                letters = re.match(r'[A-Z]+', cell.attrib['r'])[0]
                index = 0
                for letter in letters:
                    index = index * 26 + ord(letter) - 64
                if index > 16:
                    continue
                value = cell.find('s:v', ns)
                text = value.text if value is not None else None
                if text is not None:
                    cells[index - 1] = strings[int(text)] if cell.get('t') == 's' else text
            yield cells


def hebrew_unit(text):
    text = re.sub(r'\s+', ' ', text or '').strip().replace('״', '"')
    for pattern, factor, unit in [(r'([\d.]+)\s*ק"?ג', 1000, 'г'),
                                  (r'([\d.]+)\s*גרם', 1, 'г'),
                                  (r'([\d.]+)\s*ליטר', 1000, 'мл'),
                                  (r'([\d.]+)\s*מ"?ל', 1, 'мл'),
                                  (r'([\d.]+)\s*יחידות', 1, 'шт.')]:
        match = re.search(pattern, text)
        if match:
            return float(match[1]) * factor, unit
    raise ValueError('Unknown CBS unit: ' + text)


def parse_cbs(raw, source_url, as_of):
    latest, code, label = {}, None, None
    for row in xlsx_rows(raw):
        if row[15] and re.fullmatch(r'\d{6}', row[15]):
            code, label = row[15], row[14]
        if code not in IL_PRODUCTS or not row[12] or not re.fullmatch(r'20\d{2}', row[12]):
            continue
        quantity, unit = hebrew_unit(row[13])
        for column, value in enumerate(row[:12]):
            period = f'{row[12]}-{12-column:02d}'
            if period > as_of[:7] or not value:
                continue
            try:
                price = float(value)
            except ValueError:
                continue
            if price > 0 and (code not in latest or period > latest[code]['reference']['period']):
                latest[code] = observation(IL_PRODUCTS[code], price, quantity, unit, 'IL', period,
                                           'Israel Central Bureau of Statistics', source_url, IL_LICENSE, code,
                                           re.sub(r'\s+', ' ', label).strip())
    if len(latest) < 20:
        raise ValueError('CBS food table is missing expected rows')
    return list(latest.values())


def parse_ukraine(raw, metadata_raw, as_of, source_url=UA_URL):
    data = json.loads(raw)['data']
    structure = data['structures'][0]
    metadata = json.loads(metadata_raw)['data']
    codelists = {cl['id']: {c['id']: c.get('names', {}).get('en', c.get('name', c['id']))
                           for c in cl['codes']} for cl in metadata['codelists']}
    labels = codelists['CL_PRICE_CHANGE_CONSUMER_GOODS_SERVICE_TYPE']
    units = codelists['CL_UNITS_OF_MEASURE']
    dimensions = structure['dimensions']['series']
    times = structure['dimensions']['observation'][0]['values']
    unit_values = structure['attributes']['series'][0]['values']
    unit_map = {'Kilogram': (1000, 'г'), '1000 g': (1000, 'г'), 'Liter': (1000, 'мл'),
                '10 pcs': (10, 'шт.'), '200 g': (200, 'г'), '500 g': (500, 'г')}
    result = []
    for key, series in data['dataSets'][0]['series'].items():
        ids = {d['id']: d['values'][int(i)]['id'] for d, i in zip(dimensions, key.split(':'))}
        code = ids['GOODS_SERVICES_TYPE']
        if ids['INDICATOR'] != 'AVG_CONS_PRCS' or ids['REGION'] != 'UA00000000000000000' or ids['FREQ'] != 'M' or code not in UA_PRODUCTS:
            continue
        unit = units[unit_values[series['attributes'][0]]['id']]
        if unit not in unit_map:
            raise ValueError('Unknown Ukrainian price unit: ' + unit)
        candidates = []
        for index, values in series.get('observations', {}).items():
            period = times[int(index)]['value'].replace('-M', '-')
            if period <= as_of[:7] and values and values[0] is not None:
                try:
                    number = float(values[0])
                    if math.isfinite(number) and number > 0:
                        candidates.append((period, number))
                except (ValueError, TypeError):
                    pass
        if candidates:
            period, price = max(candidates)
            quantity, pack_unit = unit_map[unit]
            result.append(observation(UA_PRODUCTS[code], price, quantity, pack_unit, 'UA', period,
                                      'State Statistics Service of Ukraine', source_url, UA_LICENSE, code, labels[code]))
    if len(result) < 15:
        raise ValueError('Ukrainian average-price data is missing expected rows')
    return result


def parse_bls(raw, as_of):
    data = json.loads(raw)
    if data.get('status') != 'REQUEST_SUCCEEDED':
        raise ValueError('BLS request failed: ' + str(data.get('message')))
    result = []
    for series in data['Results']['series']:
        code = series['seriesID']
        if code not in BLS_PRODUCTS:
            continue
        candidates = []
        for point in series.get('data', []):
            if not re.fullmatch(r'M(0[1-9]|1[0-2])', point['period']):
                continue
            period = point['year'] + '-' + point['period'][1:]
            try:
                price = float(point['value'])
            except ValueError:
                continue
            if period <= as_of[:7] and math.isfinite(price) and price > 0:
                candidates.append((period, price))
        if candidates:
            period, price = max(candidates)
            name, label, quantity, unit = BLS_PRODUCTS[code]
            result.append(observation(name, price, quantity, unit, 'US', period,
                                      'U.S. Bureau of Labor Statistics',
                                      'https://api.bls.gov/publicAPI/v2/timeseries/data/' + code,
                                      BLS_LICENSE, code, label))
    if len(result) < 8:
        raise ValueError('BLS is missing expected food series')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'Lad/reference-prices.json')
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--offline', action='store_true')
    parser.add_argument('--as-of', default=date.today().isoformat())
    args = parser.parse_args()
    as_of = date.fromisoformat(args.as_of)
    args.cache.mkdir(parents=True, exist_ok=True)
    if not args.offline:
        # All downloads must succeed before replacing any app data.
        meta_url = 'https://stat.gov.ua/sdmx/workspaces/default:integration/registry/sdmx/3.0/structure/dataflow/SSSU/DF_PRICE_CHANGE_CONSUMER_GOODS_SERVICE/~?references=all'
        ua_meta = download(meta_url)
        flow = next(f for f in json.loads(ua_meta)['data']['dataflows'] if f['id'] == 'DF_PRICE_CHANGE_CONSUMER_GOODS_SERVICE')
        if not re.fullmatch(r'[0-9.]+', flow['version']):
            raise ValueError('Unexpected Ukrainian dataflow version')
        ua_url = 'https://stat.gov.ua/sdmx/workspaces/default:integration/registry/sdmx/3.0/data/dataflow/SSSU/DF_PRICE_CHANGE_CONSUMER_GOODS_SERVICE/' + flow['version'] + '/AVG_CONS_PRCS'
        ua_raw = download(ua_url, accept='application/vnd.sdmx.data+json;version=2.0.0')
        bls_raw = download('https://api.bls.gov/publicAPI/v2/timeseries/data/',
                           json.dumps(dict(seriesid=list(BLS_PRODUCTS), startyear=str(as_of.year-1),
                                           endyear=str(as_of.year))).encode())
        cbs_raw = None
        cbs_url = None
        for offset in range(3):
            month_index = as_of.year * 12 + as_of.month - 1 - offset
            year, month0 = divmod(month_index, 12)
            url = f'https://www.cbs.gov.il/he/publications/Madad/DocLib/{year}/price{month0+1:02d}a/a5_6_h.xlsx'
            try:
                raw = download(url)
                if raw.startswith(b'PK'):
                    cbs_raw, cbs_url = raw, url
                    break
            except (OSError, ValueError):
                continue
        if cbs_raw is None:
            raise ValueError('No recent CBS workbook is available')
        for name, raw in [('ua-prices-json.data', ua_raw), ('ua-sdmx-flows.data', ua_meta),
                          ('bls-batch.data', bls_raw), ('cbs-xlsx.data', cbs_raw)]:
            (args.cache / name).write_bytes(raw)
        (args.cache / 'cbs-source-url.txt').write_text(cbs_url)
        (args.cache / 'ua-source-url.txt').write_text(ua_url)
    cbs_url = (args.cache / 'cbs-source-url.txt').read_text().strip()
    records = parse_cbs((args.cache / 'cbs-xlsx.data').read_bytes(), cbs_url, args.as_of)
    records += parse_ukraine((args.cache / 'ua-prices-json.data').read_bytes(),
                             (args.cache / 'ua-sdmx-flows.data').read_bytes(), args.as_of,
                             (args.cache / 'ua-source-url.txt').read_text().strip())
    records += parse_bls((args.cache / 'bls-batch.data').read_bytes(), args.as_of)
    keys = [(r['reference']['country'], r['productName']) for r in records]
    assert len(keys) == len(set(keys))
    payload = dict(schemaVersion=1, retrievedAt=args.as_of, prices=records,
                   coverage='Selected statistical food categories; missing items are not estimated.',
                   interpretation='Reference averages, not store quotations. Brand, variety and fat content may differ. No currency conversion.')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix('.json.new')
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(args.output)
    for country in ['IL', 'UA', 'US']:
        selected = [r for r in records if r['reference']['country'] == country]
        print(country, len(selected), 'categories;', min(r['reference']['period'] for r in selected),
              'through', max(r['reference']['period'] for r in selected))


if __name__ == '__main__':
    main()
