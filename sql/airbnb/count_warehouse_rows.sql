SELECT 'airbnb_snapshot_listings' AS table_name, COUNT(*) AS row_count
FROM `{{PROJECT_ID}}.warehouse.airbnb_snapshot_listings`
UNION ALL
SELECT 'airbnb_incremental_listings', COUNT(*)
FROM `{{PROJECT_ID}}.warehouse.airbnb_incremental_listings`
UNION ALL
SELECT 'airbnb_trusted_listings', COUNT(*)
FROM `{{PROJECT_ID}}.warehouse.airbnb_trusted_listings`
UNION ALL
SELECT 'airbnb_snapshot_calendar', COUNT(*)
FROM `{{PROJECT_ID}}.warehouse.airbnb_snapshot_calendar`
UNION ALL
SELECT 'airbnb_incremental_calendar', COUNT(*)
FROM `{{PROJECT_ID}}.warehouse.airbnb_incremental_calendar`
UNION ALL
SELECT 'airbnb_trusted_calendar', COUNT(*)
FROM `{{PROJECT_ID}}.warehouse.airbnb_trusted_calendar`
UNION ALL
SELECT 'airbnb_snapshot_reviews', COUNT(*)
FROM `{{PROJECT_ID}}.warehouse.airbnb_snapshot_reviews`
UNION ALL
SELECT 'airbnb_incremental_reviews', COUNT(*)
FROM `{{PROJECT_ID}}.warehouse.airbnb_incremental_reviews`
UNION ALL
SELECT 'airbnb_trusted_reviews', COUNT(*)
FROM `{{PROJECT_ID}}.warehouse.airbnb_trusted_reviews`
ORDER BY table_name;
