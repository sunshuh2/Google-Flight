import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
const root = fileURLToPath(new URL('../', import.meta.url));
const db = new PGlite();
const csv = fs.readFileSync(`${root}/data/flight_info.csv`);
async function run(data = csv) {
  await db.exec('BEGIN; CREATE SCHEMA IF NOT EXISTS flight_prices; SET LOCAL search_path = flight_prices, public;');
  try {
    await db.exec(fs.readFileSync(`${root}/sql/01_schema.sql`, 'utf8'));
    const load = fs.readFileSync(`${root}/sql/02_load.sql`, 'utf8');
    const [before, after] = load.split(/\\copy[^\r\n]+/);
    await db.exec(before);
    await db.exec("COPY raw_flight_csv FROM '/dev/blob' WITH (FORMAT csv, HEADER true)", {blob:new Blob([data])});
    await db.exec(after);
    const results = await db.exec(fs.readFileSync(`${root}/sql/03_analysis.sql`, 'utf8'));
    const checks = await db.exec(fs.readFileSync(`${root}/sql/04_checks.sql`, 'utf8'));
    if (data === csv) assert.equal(Number(checks.at(-1).rows[0].original_key_collision_groups), 145);
    await db.exec('COMMIT');
    return results;
  } catch(e) { await db.exec('ROLLBACK'); throw e; }
}
const analysisResults = await run();
await db.exec('SET search_path = flight_prices, public');
async function counts() { return (await db.query('SELECT (SELECT count(*)::int FROM flight_offer) offers, count(*)::int observations, count(DISTINCT scrape_date)::int dates FROM price_observation')).rows[0]; }
assert.deepEqual(await counts(), {offers:585, observations:3543, dates:11});
await run();
assert.deepEqual(await counts(), {offers:585, observations:3543, dates:11});
// A malformed row must roll back the entire load and leave the prior data intact.
await assert.rejects(run(Buffer.from(csv.toString().replace(',82,F8,', ',0,F8,'))));
assert.deepEqual(await counts(), {offers:585, observations:3543, dates:11});
const movements = (await db.query(`SELECT cabin_class, booking_window, count(*)::int transitions,
  count(*) FILTER (WHERE price_change>0)::int increases,
  count(*) FILTER (WHERE price_change<0)::int decreases,
  count(*) FILTER (WHERE price_change=0)::int unchanged,
  percentile_cont(0.5) WITHIN GROUP (ORDER BY price_change) median_change
  FROM matched_fare_movement GROUP BY cabin_class, booking_window
  ORDER BY cabin_class, min(days_in_advance)`)).rows;
const collision = (await db.query(`SELECT count(*)::int n FROM
 (SELECT offer_id,scrape_date FROM price_observation GROUP BY 1,2 HAVING count(*)>1) t`)).rows[0].n;
assert.equal(collision,108);
const gaps = (await db.query(`SELECT count(*)::int n FROM matched_fare_movement m
 WHERE EXISTS (SELECT 1 FROM price_observation p WHERE p.scrape_date>m.previous_date AND p.scrape_date<m.scrape_date)`)).rows[0].n;
assert.equal(gaps,0);
// Distinct visible attributes and multiple prices must survive ingestion.
const header = csv.toString().split(/\r?\n/)[0];
const base = '07:55,10:20,0,YYZ,YVR,82,F8,1,,0,0,0,1,2026-02-02,Economy(Basic),2025-12-29';
const variants = [base.replace(',82,F8,', ',83,F8,'),
  base.replace(',0,0,0,1,2026', ',0,1,0,1,2026'),
  base.replace(',F8,1,', ',TEST,1,'), base.replace(',1,,0,', ',1,YUL,1,')];
// Append synthetic variants only inside this disposable in-memory database.
const beforeVariants = await counts();
await run(Buffer.from(header+'\n'+variants.join('\n')+'\n'));
assert.deepEqual(await counts(), {offers:588, observations:3547, dates:11});
// Source-shape and date failures must reject without partial writes.
for (const invalid of [base.replace(',82,F8,', ',NaN,F8,'),
  base.replace(',1,,0,', ',1,,1,'), base.replace('2025-12-29', '2026-02-30'),
  base.replace(',F8,1,', ',F8,2,')]) {
  const before = await counts();
  await assert.rejects(run(Buffer.from(header+'\n'+invalid+'\n')));
  assert.deepEqual(await counts(), before);
}
const version = (await db.query('SELECT version()')).rows[0].version;
fs.writeFileSync(`${root}/analysis/verification.json`, JSON.stringify({runtime:version, counts:beforeVariants,
  passed:['all SQL files executed', 'repeat load unchanged', 'invalid load rolled back',
  'junction consistency', '108 multiple-price groups preserved', 'no collection gaps bridged', 'carrier, baggage, connection and price variants preserved', 'malformed counts/dates/prices rejected'], movements}, null, 2)+'\n');
console.log('PASS: SQL integration, idempotency, rollback, identity preservation and matched movements');
fs.writeFileSync(`${root}/analysis/query_results.json`, JSON.stringify(analysisResults.filter(r=>r.rows.length).map(r=>r.rows), null, 2)+'\n');
await db.close();
