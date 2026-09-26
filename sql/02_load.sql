-- Run from the project root with psql so data/flight_info.csv resolves.
-- Staging uses TEXT because the source contains repeated header rows. Typed
-- staging would fail before those rows could be filtered.

DROP VIEW IF EXISTS pg_temp.staged_offer;
DROP TABLE IF EXISTS pg_temp.clean_flight_csv;
DROP TABLE IF EXISTS pg_temp.raw_flight_csv;

CREATE TEMP TABLE raw_flight_csv (
    departure_time TEXT,
    arrival_time TEXT,
    date_change TEXT,
    departure_airport TEXT,
    arrival_airport TEXT,
    price TEXT,
    airline TEXT,
    distinct_airline_count TEXT,
    stop_airport TEXT,
    stop_count TEXT,
    carry_on_bag TEXT,
    checked_bag TEXT,
    weekday_number TEXT,
    departure_date TEXT,
    cabin_class TEXT,
    scrape_date TEXT
);

\copy raw_flight_csv FROM 'data/flight_info.csv' WITH (FORMAT csv, HEADER true)

-- Reject malformed rows instead of silently discarding them. Invalid casts also
-- abort the enclosing transaction. Only exact repeated header rows are ignored.
DO $$
DECLARE r raw_flight_csv%ROWTYPE;
BEGIN
  FOR r IN SELECT * FROM raw_flight_csv LOOP
    IF ROW(r.*) = ROW('departure time','arrival time','date change',
       'departure airport','arrival airport','price','airline','distinct airline count',
       'stop airport','stop count','carry on bag','checked bag','day','date','class','scrape_date') THEN
      CONTINUE;
    END IF;
    IF NOT COALESCE(
       r.departure_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       AND r.arrival_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       AND r.date_change ~ '^[0-3]$'
       AND r.departure_airport ~ '^[A-Z]{3}$'
       AND r.arrival_airport ~ '^[A-Z]{3}$'
       AND r.departure_airport <> r.arrival_airport
       AND r.price ~ '^[0-9]+([.][0-9]{1,2})?$'
       AND r.price::NUMERIC > 0
       AND r.distinct_airline_count ~ '^[1-9][0-9]*$'
       AND r.stop_count ~ '^[0-5]$'
       AND r.carry_on_bag ~ '^[0-5]$'
       AND r.checked_bag ~ '^[0-5]$'
       AND r.weekday_number ~ '^[1-7]$'
       AND r.departure_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
       AND r.scrape_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
       AND r.scrape_date::DATE <= r.departure_date::DATE
       AND r.weekday_number::INT = EXTRACT(ISODOW FROM r.departure_date::DATE)
       AND r.cabin_class IN ('Economy(Basic)','Economy','Economy(Premium)')
       AND r.airline IS NOT NULL AND BTRIM(r.airline) <> ''
       AND NOT EXISTS (SELECT 1 FROM regexp_split_to_table(r.airline, ',') x
                       WHERE BTRIM(x) !~ '^[A-Za-z0-9() -]{1,20}$')
       AND r.distinct_airline_count::INT = (SELECT COUNT(DISTINCT BTRIM(x))
                          FROM regexp_split_to_table(r.airline, ',') x)
       AND r.stop_count::INT = cardinality(string_to_array(COALESCE(r.stop_airport,''), ','))
       AND NOT EXISTS (SELECT 1 FROM unnest(string_to_array(COALESCE(r.stop_airport,''), ',')) x
                       WHERE BTRIM(x) !~ '^[A-Z]{3}$'), FALSE) THEN
      RAISE EXCEPTION 'Invalid source row: %', row_to_json(r);
    END IF;
  END LOOP;
END $$;

CREATE TEMP TABLE clean_flight_csv ON COMMIT DROP AS
WITH valid_text AS MATERIALIZED (
    SELECT *
    FROM raw_flight_csv
    WHERE departure_time <> 'departure time'
      AND departure_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      AND arrival_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      AND date_change ~ '^[0-3]$'
      AND departure_airport ~ '^[A-Za-z]{3}$'
      AND arrival_airport ~ '^[A-Za-z]{3}$'
      AND price ~ '^[0-9]+([.][0-9]{1,2})?$'
      AND stop_count ~ '^[0-5]$'
      AND carry_on_bag ~ '^[0-5]$'
      AND checked_bag ~ '^[0-5]$'
      AND weekday_number ~ '^[1-7]$'
      AND departure_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      AND scrape_date ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      AND BTRIM(cabin_class) IN (
          'Economy(Basic)', 'Economy', 'Economy(Premium)'
      )
),
typed AS (
    SELECT
        UPPER(BTRIM(departure_airport))::CHAR(3) AS departure_airport,
        UPPER(BTRIM(arrival_airport))::CHAR(3) AS arrival_airport,
        departure_date::DATE + departure_time::TIME AS departure_at,
        departure_date::DATE + date_change::INTEGER + arrival_time::TIME AS arrival_at,
        BTRIM(cabin_class) AS cabin_class,
        stop_count::SMALLINT AS stop_count,
        (SELECT string_agg(code, ',' ORDER BY code) FROM
            (SELECT DISTINCT BTRIM(x) AS code FROM regexp_split_to_table(airline, ',') x) codes) AS carrier_signature,
        COALESCE(
            regexp_replace(BTRIM(stop_airport), '[[:space:]]*,[[:space:]]*', ',', 'g'),
            ''
        ) AS stop_signature,
        carry_on_bag::SMALLINT AS carry_on_count,
        checked_bag::SMALLINT AS checked_bag_count,
        scrape_date::DATE AS scrape_date,
        price::NUMERIC(10, 2) AS price,
        weekday_number::SMALLINT AS source_weekday
    FROM valid_text
)
SELECT DISTINCT *
FROM typed
WHERE scrape_date <= departure_at::DATE
  AND source_weekday = EXTRACT(ISODOW FROM departure_at)::SMALLINT
  AND (
      (stop_count = 0 AND stop_signature = '')
      OR
      (stop_count > 0 AND stop_signature <> '')
  );

INSERT INTO airport (airport_code)
SELECT departure_airport FROM clean_flight_csv
UNION
SELECT arrival_airport FROM clean_flight_csv
UNION
SELECT BTRIM(stop_code)::CHAR(3)
FROM clean_flight_csv
CROSS JOIN LATERAL regexp_split_to_table(stop_signature, ',') AS stop_code
WHERE stop_signature <> ''
ON CONFLICT DO NOTHING;

INSERT INTO carrier (carrier_code)
SELECT DISTINCT BTRIM(carrier_code)
FROM clean_flight_csv
CROSS JOIN LATERAL regexp_split_to_table(carrier_signature, ',') AS carrier_code
WHERE BTRIM(carrier_code) <> ''
ON CONFLICT DO NOTHING;

INSERT INTO flight_offer (
    departure_airport,
    arrival_airport,
    departure_at,
    arrival_at,
    cabin_class,
    stop_count,
    carrier_signature,
    stop_signature,
    carry_on_count,
    checked_bag_count
)
SELECT DISTINCT
    departure_airport,
    arrival_airport,
    departure_at,
    arrival_at,
    cabin_class,
    stop_count,
    carrier_signature,
    stop_signature,
    carry_on_count,
    checked_bag_count
FROM clean_flight_csv
ON CONFLICT DO NOTHING;

CREATE TEMP VIEW staged_offer AS
SELECT f.offer_id, s.*
FROM clean_flight_csv s
JOIN flight_offer f
  ON f.departure_airport = s.departure_airport
 AND f.arrival_airport = s.arrival_airport
 AND f.departure_at = s.departure_at
 AND f.arrival_at = s.arrival_at
 AND f.cabin_class = s.cabin_class
 AND f.stop_count = s.stop_count
 AND f.carrier_signature = s.carrier_signature
 AND f.stop_signature = s.stop_signature
 AND f.carry_on_count = s.carry_on_count
 AND f.checked_bag_count = s.checked_bag_count;

INSERT INTO price_observation (offer_id, scrape_date, price)
SELECT DISTINCT offer_id, scrape_date, price
FROM staged_offer
ON CONFLICT DO NOTHING;

INSERT INTO operating_airline (offer_id, carrier_code)
SELECT DISTINCT offer_id, BTRIM(carrier_code)
FROM staged_offer
CROSS JOIN LATERAL regexp_split_to_table(carrier_signature, ',') AS carrier_code
WHERE BTRIM(carrier_code) <> ''
ON CONFLICT DO NOTHING;

INSERT INTO transfer (offer_id, stop_order, airport_code)
SELECT DISTINCT
    offer_id,
    stop_order,
    BTRIM(airport_code)::CHAR(3)
FROM staged_offer
CROSS JOIN LATERAL regexp_split_to_table(stop_signature, ',')
    WITH ORDINALITY AS split_stop(airport_code, stop_order)
WHERE stop_signature <> ''
ON CONFLICT DO NOTHING;

ANALYZE flight_offer;
ANALYZE price_observation;

-- Expected for the supplied file: 3,633 staged rows, 2 repeated headers,
-- 3,543 distinct valid observations, 585 offers, and 108 offer/date groups
-- with more than one visible price.
SELECT
    (SELECT COUNT(*) FROM raw_flight_csv) AS staged_rows,
    (SELECT COUNT(*) FROM raw_flight_csv WHERE departure_time = 'departure time') AS repeated_headers,
    (SELECT COUNT(*) FROM clean_flight_csv) AS distinct_valid_observations,
    (SELECT COUNT(*) FROM flight_offer) AS offers,
    (SELECT COUNT(*) FROM price_observation) AS price_observations;

SELECT COUNT(*) AS offer_date_groups_with_multiple_prices
FROM (
    SELECT offer_id, scrape_date
    FROM price_observation
    GROUP BY offer_id, scrape_date
    HAVING COUNT(*) > 1
) conflicts;
