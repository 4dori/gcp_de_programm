"""Write sampled Airbnb snapshots and date-partitioned incremental data to GCS."""

import argparse
import os
from datetime import datetime, timezone

import google.auth
from pyspark.sql import SparkSession

TABLES = {
    "listings": [
        "id", "name", "host_id", "neighbourhood", "latitude", "longitude",
        "room_type", "price", "minimum_nights", "number_of_reviews",
        "last_review", "reviews_per_month", "calculated_host_listings_count",
        "availability_365",
    ],
    "calendar": ["listing_id", "date", "available", "price"],
    "reviews": [
        "listing_id", "id", "date", "reviewer_id", "reviewer_name", "comments",
    ],
}


def parse_args():
    _, default_project = google.auth.default()
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project",
        default=os.getenv("GOOGLE_CLOUD_PROJECT") or os.getenv("GCP_PROJECT") or default_project,
        help="GCP project ID (defaults to the Dataproc project environment)",
    )
    parser.add_argument("--mode", choices=("snapshot", "incremental", "both"), required=True)
    parser.add_argument(
        "--date",
        default=datetime.now(timezone.utc).date().isoformat(),
        help="Incremental partition date in YYYY-MM-DD format (UTC by default)",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    if not args.project:
        raise ValueError("GCP project ID is required via --project or GOOGLE_CLOUD_PROJECT")
    try:
        partition_date = datetime.strptime(args.date, "%Y-%m-%d").date()
    except ValueError as exc:
        raise ValueError("--date must use YYYY-MM-DD format") from exc

    source_root = f"gs://{args.project}-landing/raw/airbnb"
    output_root = f"gs://{args.project}-landing/derived/airbnb"
    spark = SparkSession.builder.appName(f"airbnb_{args.mode}").getOrCreate()
    modes = ("snapshot", "incremental") if args.mode == "both" else (args.mode,)

    try:
        for table, expected_columns in TABLES.items():
            source = f"{source_root}/{table}.csv"
            dataframe = (
                spark.read.option("header", "true")
                .option("multiLine", "true")
                .option("escape", '"')
                .csv(source)
            )
            missing = set(expected_columns) - set(dataframe.columns)
            if missing:
                raise ValueError(f"{source} is missing columns: {sorted(missing)}")

            for mode in modes:
                fraction = 0.8 if mode == "snapshot" else 0.05
                seed = 2026 if mode == "snapshot" else int(partition_date.strftime("%Y%m%d"))
                sampled = dataframe.sample(withReplacement=False, fraction=fraction, seed=seed)
                if mode == "snapshot":
                    destination = f"{output_root}/snapshot/{table}"
                else:
                    destination = (
                        f"{output_root}/incremental/{table}/dt={partition_date.isoformat()}"
                    )

                sampled.write.mode("overwrite").parquet(destination)
                print(f"Wrote {table} {mode} sample to {destination}")
    finally:
        spark.stop()


if __name__ == "__main__":
    main()
