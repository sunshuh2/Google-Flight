-- Structural checks run inside the same transaction as ingestion.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM flight_offer f
        WHERE f.stop_count <> (SELECT COUNT(*) FROM transfer t WHERE t.offer_id = f.offer_id)
           OR f.stop_signature <> COALESCE((SELECT string_agg(t.airport_code::TEXT, ',' ORDER BY t.stop_order)
                                            FROM transfer t WHERE t.offer_id = f.offer_id), '')
           OR f.carrier_signature IS DISTINCT FROM
               (SELECT string_agg(a.carrier_code, ',' ORDER BY a.carrier_code)
                FROM operating_airline a WHERE a.offer_id = f.offer_id)
    ) THEN
        RAISE EXCEPTION 'Offer identity and junction tables disagree';
    END IF;
    IF EXISTS (SELECT 1 FROM price_observation p JOIN flight_offer f USING (offer_id)
               WHERE p.scrape_date > f.departure_at::DATE) THEN
        RAISE EXCEPTION 'Observation collected after departure date';
    END IF;
    IF (SELECT COUNT(*) FROM staged_offer) <> (SELECT COUNT(*) FROM clean_flight_csv) THEN
        RAISE EXCEPTION 'Not all staged observations matched an offer';
    END IF;
END $$;

-- Reproduce collisions in the ORIGINAL Flight natural key plus scrape date.
SELECT COUNT(*) AS original_key_collision_groups
FROM (
    SELECT departure_airport, arrival_airport, departure_at, arrival_at,
           stop_count, cardinality(string_to_array(carrier_signature, ',')),
           cabin_class, scrape_date
    FROM clean_flight_csv
    GROUP BY departure_airport, arrival_airport, departure_at, arrival_at,
             stop_count, cardinality(string_to_array(carrier_signature, ',')),
             cabin_class, scrape_date
    HAVING COUNT(*) > 1
) collisions;
