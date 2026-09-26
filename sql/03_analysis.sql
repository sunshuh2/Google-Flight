
CREATE OR REPLACE VIEW offer_observation AS
SELECT
    f.offer_id,
    f.departure_airport,
    f.arrival_airport,
    f.departure_at,
    f.arrival_at,
    f.cabin_class,
    f.stop_count,
    f.carrier_signature,
    f.stop_signature,
    f.carry_on_count,
    f.checked_bag_count,
    p.scrape_date,
    p.price,
    p.currency,
    f.departure_at::DATE - p.scrape_date AS days_in_advance,
    EXTRACT(ISODOW FROM f.departure_at)::SMALLINT AS departure_weekday
FROM flight_offer f
JOIN price_observation p USING (offer_id)
WHERE p.scrape_date <= f.departure_at::DATE;

-- One row per offer and scrape date. When Google showed multiple prices for
-- the same visible attributes, use the lowest as the best visible daily fare
-- but retain the range and count for auditing.
CREATE OR REPLACE VIEW offer_daily_price AS
SELECT
    offer_id,
    departure_airport,
    arrival_airport,
    departure_at,
    arrival_at,
    cabin_class,
    stop_count,
    carrier_signature,
    stop_signature,
    carry_on_count,
    checked_bag_count,
    scrape_date,
    MIN(price) AS daily_min_price,
    MAX(price) AS daily_max_price,
    COUNT(*) AS visible_price_count,
    days_in_advance,
    departure_weekday
FROM offer_observation
GROUP BY
    offer_id,
    departure_airport,
    arrival_airport,
    departure_at,
    arrival_at,
    cabin_class,
    stop_count,
    carrier_signature,
    stop_signature,
    carry_on_count,
    checked_bag_count,
    scrape_date,
    days_in_advance,
    departure_weekday;

-- 1. Collection coverage. Use this before interpreting price changes.
SELECT
    scrape_date,
    COUNT(*) AS offer_snapshots,
    COUNT(DISTINCT offer_id) AS distinct_offers,
    COUNT(DISTINCT (departure_airport, arrival_airport)) AS routes
FROM offer_daily_price
GROUP BY scrape_date
ORDER BY scrape_date;

-- 2. Price by booking window and class. Median is more robust than mean here.
WITH bucketed AS (
    SELECT *, CASE
        WHEN days_in_advance BETWEEN 0 AND 7 THEN '0-7'
        WHEN days_in_advance BETWEEN 8 AND 14 THEN '8-14'
        WHEN days_in_advance BETWEEN 15 AND 21 THEN '15-21'
        WHEN days_in_advance BETWEEN 22 AND 30 THEN '22-30'
        ELSE '31+'
    END AS booking_window
    FROM offer_daily_price
)
SELECT
    cabin_class,
    booking_window,
    COUNT(*) AS offer_snapshots,
    ROUND(AVG(daily_min_price), 2) AS average_price,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY daily_min_price) AS median_price,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY daily_min_price) AS p25,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY daily_min_price) AS p75
FROM bucketed
GROUP BY cabin_class, booking_window
ORDER BY cabin_class, MIN(days_in_advance);

-- 3. Match ONLY adjacent collection dates. LAG within each offer alone
-- would bridge missing runs and describe a different comparison.
CREATE OR REPLACE VIEW matched_fare_movement AS
WITH collection_dates AS (
    SELECT scrape_date, LAG(scrape_date) OVER (ORDER BY scrape_date) AS previous_date
    FROM (SELECT DISTINCT scrape_date FROM price_observation) d
)
SELECT current.offer_id, current.cabin_class, current.scrape_date,
       dates.previous_date, current.scrape_date - dates.previous_date AS elapsed_days,
       current.days_in_advance,
       CASE WHEN current.days_in_advance <= 7 THEN '0-7'
            WHEN current.days_in_advance <= 14 THEN '8-14'
            WHEN current.days_in_advance <= 21 THEN '15-21'
            WHEN current.days_in_advance <= 30 THEN '22-30'
            ELSE '31+' END AS booking_window,
       previous.daily_min_price AS previous_price,
       current.daily_min_price AS current_price,
       current.daily_min_price - previous.daily_min_price AS price_change,
       ROUND(100 * (current.daily_min_price - previous.daily_min_price)
             / previous.daily_min_price, 2) AS percent_change
FROM collection_dates dates
JOIN offer_daily_price current ON current.scrape_date = dates.scrape_date
JOIN offer_daily_price previous ON previous.scrape_date = dates.previous_date
                              AND previous.offer_id = current.offer_id;

SELECT cabin_class, booking_window, COUNT(*) AS matched_transitions,
       COUNT(DISTINCT offer_id) AS distinct_offers,
       COUNT(*) FILTER (WHERE price_change > 0) AS increases,
       COUNT(*) FILTER (WHERE price_change < 0) AS decreases,
       COUNT(*) FILTER (WHERE price_change = 0) AS unchanged,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_change) AS median_change,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY percent_change) AS median_percent_change
FROM matched_fare_movement
GROUP BY cabin_class, booking_window
ORDER BY cabin_class, MIN(days_in_advance);

-- 4. Booking lead time at each offer's lowest observed price.
-- Ties choose the earliest collection date (largest lead time).
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY offer_id
        ORDER BY daily_min_price, scrape_date
    ) AS price_rank
    FROM offer_daily_price
)
SELECT
    cabin_class,
    COUNT(*) AS offers,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_in_advance) AS median_days_in_advance,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY daily_min_price) AS median_lowest_price
FROM ranked
WHERE price_rank = 1
GROUP BY cabin_class
ORDER BY cabin_class;

-- 5. Carrier comparison within class and booking window. Carrier combinations
-- remain combined so one fare is not counted once for every carrier.
WITH bucketed AS (
    SELECT *, CASE
        WHEN days_in_advance <= 14 THEN '0-14'
        WHEN days_in_advance <= 30 THEN '15-30'
        ELSE '31+'
    END AS booking_window
    FROM offer_daily_price
)
SELECT
    cabin_class,
    booking_window,
    carrier_signature,
    COUNT(*) AS offer_snapshots,
    COUNT(DISTINCT offer_id) AS offers,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY daily_min_price) AS median_price
FROM bucketed
GROUP BY cabin_class, booking_window, carrier_signature
HAVING COUNT(DISTINCT offer_id) >= 3
ORDER BY cabin_class, booking_window, median_price;

-- 6. Descriptive direct/connecting comparison, stratified by class and lead time.
SELECT
    cabin_class,
    CASE WHEN stop_count = 0 THEN 'direct' ELSE 'connecting' END AS itinerary_type,
    CASE
        WHEN days_in_advance <= 14 THEN '0-14'
        WHEN days_in_advance <= 30 THEN '15-30'
        ELSE '31+'
    END AS booking_window,
    COUNT(*) AS offer_snapshots,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY daily_min_price) AS median_price
FROM offer_daily_price
GROUP BY cabin_class, itinerary_type, booking_window
ORDER BY cabin_class, itinerary_type, booking_window;

-- 7. Volatility of the same offer over time.
SELECT
    offer_id,
    cabin_class,
    carrier_signature,
    departure_at,
    COUNT(*) AS scrape_count,
    MIN(daily_min_price) AS lowest_price,
    MAX(daily_min_price) AS highest_price,
    MAX(daily_min_price) - MIN(daily_min_price) AS price_range
FROM offer_daily_price
GROUP BY offer_id, cabin_class, carrier_signature, departure_at
HAVING COUNT(*) >= 2
ORDER BY price_range DESC, scrape_count DESC
LIMIT 25;

