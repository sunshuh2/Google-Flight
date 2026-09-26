-- PostgreSQL schema for Google Flights price observations.
-- A flight_offer is a listing visible in the search results, not a confirmed
-- airline flight. The source does not provide a flight number or fare ID.


CREATE TABLE IF NOT EXISTS airport (
    airport_code CHAR(3) PRIMARY KEY,
    CHECK (airport_code ~ '^[A-Z]{3}$')
);

CREATE TABLE IF NOT EXISTS carrier (
    carrier_code VARCHAR(20) PRIMARY KEY CHECK (BTRIM(carrier_code) <> '')
);

CREATE TABLE IF NOT EXISTS flight_offer (
    offer_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    departure_airport CHAR(3) NOT NULL REFERENCES airport(airport_code),
    arrival_airport CHAR(3) NOT NULL REFERENCES airport(airport_code),
    departure_at TIMESTAMP NOT NULL,
    arrival_at TIMESTAMP NOT NULL,
    cabin_class VARCHAR(30) NOT NULL CHECK (
        cabin_class IN ('Economy(Basic)', 'Economy', 'Economy(Premium)')
    ),
    stop_count SMALLINT NOT NULL CHECK (stop_count BETWEEN 0 AND 5),
    carrier_signature TEXT NOT NULL CHECK (BTRIM(carrier_signature) <> ''),
    stop_signature TEXT NOT NULL DEFAULT '',
    carry_on_count SMALLINT NOT NULL CHECK (carry_on_count BETWEEN 0 AND 5),
    checked_bag_count SMALLINT NOT NULL CHECK (checked_bag_count BETWEEN 0 AND 5),
    CHECK (departure_airport <> arrival_airport),
    UNIQUE (
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
);

-- Multiple prices can exist for listings whose visible attributes are the
-- same. Preserve them and choose a daily minimum/median explicitly in analysis.
CREATE TABLE IF NOT EXISTS price_observation (
    observation_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    offer_id BIGINT NOT NULL REFERENCES flight_offer(offer_id) ON DELETE CASCADE,
    scrape_date DATE NOT NULL,
    price NUMERIC(10, 2) NOT NULL CHECK (price > 0),
    currency CHAR(3) NOT NULL DEFAULT 'CAD' CHECK (currency = 'CAD'),
    UNIQUE (offer_id, scrape_date, price, currency)
);

CREATE TABLE IF NOT EXISTS transfer (
    offer_id BIGINT NOT NULL REFERENCES flight_offer(offer_id) ON DELETE CASCADE,
    stop_order SMALLINT NOT NULL CHECK (stop_order >= 1),
    airport_code CHAR(3) NOT NULL REFERENCES airport(airport_code),
    PRIMARY KEY (offer_id, stop_order)
);

CREATE TABLE IF NOT EXISTS operating_airline (
    offer_id BIGINT NOT NULL REFERENCES flight_offer(offer_id) ON DELETE CASCADE,
    carrier_code VARCHAR(20) NOT NULL REFERENCES carrier(carrier_code),
    PRIMARY KEY (offer_id, carrier_code)
);

CREATE INDEX IF NOT EXISTS idx_offer_route_departure
    ON flight_offer (departure_airport, arrival_airport, departure_at);

CREATE INDEX IF NOT EXISTS idx_offer_class
    ON flight_offer (cabin_class);

CREATE INDEX IF NOT EXISTS idx_observation_scrape_date
    ON price_observation (scrape_date);

-- The observation UNIQUE index already starts with (offer_id, scrape_date).
CREATE INDEX IF NOT EXISTS idx_carrier_offer ON operating_airline (carrier_code, offer_id);
CREATE INDEX IF NOT EXISTS idx_transfer_airport ON transfer (airport_code);

