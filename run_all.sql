\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA IF NOT EXISTS flight_prices;
SET LOCAL search_path = flight_prices, public;
\ir sql/01_schema.sql
\ir sql/02_load.sql
\ir sql/03_analysis.sql
\ir sql/04_checks.sql
COMMIT;
