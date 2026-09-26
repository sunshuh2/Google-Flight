"""Regression tests for malformed input and the supplied dataset's audit."""
import csv
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from validate_csv import ROOT, EXPECTED_HEADER, audit, validate_row


class ValidationTests(unittest.TestCase):
    def setUp(self):
        with (ROOT / 'data/flight_info.csv').open(newline='', encoding='utf-8-sig') as f:
            self.row = next(csv.DictReader(f))

    def test_reference_counts(self):
        result = audit(ROOT / 'data/flight_info.csv')
        for key, expected in [('distinct_observations', 3543), ('offers', 585),
                              ('repeated_headers', 2), ('extra_exact_duplicates', 88),
                              ('original_key_collision_groups', 145),
                              ('offer_date_groups_with_multiple_prices', 108)]:
            self.assertEqual(result[key], expected)
        self.assertEqual(len(result['collection_dates']), 11)

    def test_bad_values(self):
        for field, value in [('price', '0'), ('price', 'NaN'), ('price', '1.234'),
                             ('airline', ''), ('stop count', '1'),
                             ('distinct airline count', '2'), ('day', '7'),
                             ('scrape_date', '2026-02-30'), ('class', 'Unknown'),
                             ('departure time', '24:00'), ('checked bag', '6')]:
            with self.subTest(field=field, value=value):
                self.assertTrue(validate_row(dict(self.row, **{field: value}), 2))

    def test_ragged_rows(self):
        self.assertTrue(validate_row(dict(self.row, price=None), 2))
        extra = dict(self.row)
        extra[None] = ['extra']
        self.assertTrue(validate_row(extra, 2))

    def test_partial_header_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'bad.csv'
            with path.open('w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(EXPECTED_HEADER)
                writer.writerow(['departure time'] + ['bad'] * 15)
            with self.assertRaises(ValueError):
                audit(path)


if __name__ == '__main__':
    unittest.main()
