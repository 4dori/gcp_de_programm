CREATE OR REPLACE EXTERNAL TABLE `{{PROJECT_ID}}.warehouse.airbnb_snapshot_listings`
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://{{PROJECT_ID}}-landing/derived/airbnb/snapshot/listings/*']
);

CREATE OR REPLACE EXTERNAL TABLE `{{PROJECT_ID}}.warehouse.airbnb_incremental_listings`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://{{PROJECT_ID}}-landing/derived/airbnb/incremental/listings/*'],
  hive_partition_uri_prefix = 'gs://{{PROJECT_ID}}-landing/derived/airbnb/incremental/listings',
  require_hive_partition_filter = FALSE
);

CREATE OR REPLACE EXTERNAL TABLE `{{PROJECT_ID}}.warehouse.airbnb_snapshot_calendar`
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://{{PROJECT_ID}}-landing/derived/airbnb/snapshot/calendar/*']
);

CREATE OR REPLACE EXTERNAL TABLE `{{PROJECT_ID}}.warehouse.airbnb_incremental_calendar`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://{{PROJECT_ID}}-landing/derived/airbnb/incremental/calendar/*'],
  hive_partition_uri_prefix = 'gs://{{PROJECT_ID}}-landing/derived/airbnb/incremental/calendar',
  require_hive_partition_filter = FALSE
);

CREATE OR REPLACE EXTERNAL TABLE `{{PROJECT_ID}}.warehouse.airbnb_snapshot_reviews`
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://{{PROJECT_ID}}-landing/derived/airbnb/snapshot/reviews/*']
);

CREATE OR REPLACE EXTERNAL TABLE `{{PROJECT_ID}}.warehouse.airbnb_incremental_reviews`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://{{PROJECT_ID}}-landing/derived/airbnb/incremental/reviews/*'],
  hive_partition_uri_prefix = 'gs://{{PROJECT_ID}}-landing/derived/airbnb/incremental/reviews',
  require_hive_partition_filter = FALSE
);

CREATE OR REPLACE TABLE `{{PROJECT_ID}}.warehouse.airbnb_trusted_listings` AS
WITH combined AS (
  SELECT id, name, host_id, neighbourhood, latitude, longitude, room_type, price,
         minimum_nights, number_of_reviews, last_review, reviews_per_month,
         calculated_host_listings_count, availability_365,
         DATE '1900-01-01' AS dt, 0 AS source_rank
  FROM `{{PROJECT_ID}}.warehouse.airbnb_snapshot_listings`
  UNION ALL
  SELECT id, name, host_id, neighbourhood, latitude, longitude, room_type, price,
         minimum_nights, number_of_reviews, last_review, reviews_per_month,
         calculated_host_listings_count, availability_365, dt, 1 AS source_rank
  FROM `{{PROJECT_ID}}.warehouse.airbnb_incremental_listings`
)
SELECT * EXCEPT (source_rank)
FROM combined
QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY source_rank DESC, dt DESC) = 1;

CREATE OR REPLACE TABLE `{{PROJECT_ID}}.warehouse.airbnb_trusted_calendar` AS
WITH combined AS (
  SELECT listing_id, date, available, price, DATE '1900-01-01' AS dt, 0 AS source_rank
  FROM `{{PROJECT_ID}}.warehouse.airbnb_snapshot_calendar`
  UNION ALL
  SELECT listing_id, date, available, price, dt, 1 AS source_rank
  FROM `{{PROJECT_ID}}.warehouse.airbnb_incremental_calendar`
)
SELECT * EXCEPT (source_rank)
FROM combined
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY listing_id, date ORDER BY source_rank DESC, dt DESC
) = 1;

CREATE OR REPLACE TABLE `{{PROJECT_ID}}.warehouse.airbnb_trusted_reviews` AS
WITH combined AS (
  SELECT listing_id, id, date, reviewer_id, reviewer_name, comments,
         DATE '1900-01-01' AS dt, 0 AS source_rank
  FROM `{{PROJECT_ID}}.warehouse.airbnb_snapshot_reviews`
  UNION ALL
  SELECT listing_id, id, date, reviewer_id, reviewer_name, comments,
         dt, 1 AS source_rank
  FROM `{{PROJECT_ID}}.warehouse.airbnb_incremental_reviews`
)
SELECT * EXCEPT (source_rank)
FROM combined
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY listing_id, id ORDER BY source_rank DESC, dt DESC
) = 1;
