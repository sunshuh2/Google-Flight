"""Strict, dependency-free source validation and reproducible data-quality audit."""
import argparse
import csv
import hashlib
import json
import re
from collections import Counter, defaultdict
from datetime import date, time
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_HEADER = ['departure time', 'arrival time', 'date change',
    'departure airport', 'arrival airport', 'price', 'airline',
    'distinct airline count', 'stop airport', 'stop count', 'carry on bag',
    'checked bag', 'day', 'date', 'class', 'scrape_date']
OLD_FIELDS = ['departure airport', 'arrival airport', 'departure time',
    'arrival time', 'stop count', 'distinct airline count', 'date',
    'date change', 'class', 'scrape_date']
OFFER_FIELDS = [f for f in EXPECTED_HEADER if f not in
    ('price', 'scrape_date', 'day', 'distinct airline count')]


def validate_row(row, line_number):
    errors = []
    if None in row or any(v is None for v in row.values()):
        return [f'line {line_number}: expected exactly 16 fields']
    try:
        for field in ('departure time', 'arrival time'):
            if not re.fullmatch(r'[0-2][0-9]:[0-5][0-9]', row[field]):
                raise ValueError(f'invalid {field}')
            time.fromisoformat(row[field])
        departure = date.fromisoformat(row['date'])
        scraped = date.fromisoformat(row['scrape_date'])
        if scraped > departure:
            errors.append('scrape date is after departure')
        if departure.isoweekday() != int(row['day']):
            errors.append('weekday does not match departure date')
        for field, maximum in [('date change', 3), ('stop count', 5),
                               ('carry on bag', 5), ('checked bag', 5)]:
            if not 0 <= int(row[field]) <= maximum:
                errors.append(f'{field} outside 0..{maximum}')
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]{1,2})?', row['price']):
            errors.append('price must be a positive decimal with at most two decimal places')
        elif not Decimal('0') < Decimal(row['price']) < Decimal('100000000'):
            errors.append('price outside supported range')
        stops = [s.strip() for s in row['stop airport'].split(',')] if row['stop airport'] else []
        carriers = [s.strip() for s in row['airline'].split(',')]
        if len(stops) != int(row['stop count']):
            errors.append('stop count does not match ordered stop list')
        if len(set(carriers)) != int(row['distinct airline count']):
            errors.append('carrier count does not match carrier set')
        if any(not re.fullmatch(r'[A-Z]{3}', a) for a in
               [row['departure airport'], row['arrival airport']] + stops):
            errors.append('invalid airport code')
        if any(not re.fullmatch(r'[A-Za-z0-9() -]{1,20}', c) for c in carriers):
            errors.append('invalid or empty carrier label')
        if row['departure airport'] == row['arrival airport']:
            errors.append('departure and arrival airports are identical')
        if row['class'] not in ('Economy(Basic)', 'Economy', 'Economy(Premium)'):
            errors.append('unsupported cabin class')
    except (ValueError, TypeError) as exc:
        errors.append(str(exc))
    return [f'line {line_number}: {e}' for e in errors]


def audit(path):
    with Path(path).open(newline='', encoding='utf-8-sig') as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != EXPECTED_HEADER:
            raise ValueError(f'Unexpected CSV header: {reader.fieldnames}')
        rows, errors, headers = [], [], 0
        for row in reader:
            if list(row.values()) == EXPECTED_HEADER:
                headers += 1
                continue
            errors.extend(validate_row(row, reader.line_num))
            rows.append(row)
    if errors:
        raise ValueError('\n'.join(errors))
    unique = {tuple(row[f] for f in EXPECTED_HEADER) for row in rows}
    clean = [dict(zip(EXPECTED_HEADER, values)) for values in sorted(unique)]
    old, new = defaultdict(list), defaultdict(set)
    offers = set()
    for row in clean:
        old[tuple(row[f] for f in OLD_FIELDS)].append(row)
        # Carrier order is not known segment order; stop order is meaningful.
        row['airline'] = ','.join(sorted(set(s.strip() for s in row['airline'].split(','))))
        row['stop airport'] = ','.join(s.strip() for s in row['stop airport'].split(','))
        key = tuple(row[f] for f in OFFER_FIELDS)
        offers.add(key)
        new[key + (row['scrape_date'],)].add(Decimal(row['price']))
    collisions = [group for group in old.values() if len(group) > 1]
    report = {
        'source_sha256': hashlib.sha256(Path(path).read_bytes()).hexdigest(),
        'data_rows': len(rows), 'repeated_headers': headers,
        'extra_exact_duplicates': len(rows) - len(unique),
        'distinct_observations': len(unique), 'offers': len(offers),
        'original_key_collision_groups': len(collisions),
        'original_key_groups_with_multiple_prices': sum(len({r['price'] for r in g}) > 1 for g in collisions),
        'offer_date_groups_with_multiple_prices': sum(len(v) > 1 for v in new.values()),
        'collection_dates': sorted({r['scrape_date'] for r in clean}),
        'observations_by_class': dict(sorted(Counter(r['class'] for r in clean).items())),
    }
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('csv_path', type=Path, nargs='?', default=ROOT / 'data/flight_info.csv')
    parser.add_argument('--report', type=Path, help='Write the audit as JSON')
    args = parser.parse_args()
    try:
        report = audit(args.csv_path)
    except ValueError as exc:
        parser.exit(1, f'Validation failed:\n{exc}\n')
    output = json.dumps(report, indent=2)
    print(output)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
