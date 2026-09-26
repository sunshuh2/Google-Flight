"""Validate the CSV, then run the transactional, repeatable PostgreSQL pipeline."""
import argparse
import json
import subprocess
from validate_csv import ROOT, audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', default='flight_prices', help='Existing PostgreSQL database name')
    parser.add_argument('--psql', default='psql', help='Path to psql if not on PATH')
    args = parser.parse_args()
    report = audit(ROOT / 'data/flight_info.csv')
    (ROOT / 'analysis/audit.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2), flush=True)
    # PGHOST, PGPORT, PGUSER and .pgpass handle connection details; no stored passwords.
    subprocess.run([args.psql, '-X', '--dbname', args.database,
                    '--file', 'run_all.sql'], cwd=ROOT, check=True)


if __name__ == '__main__':
    main()
