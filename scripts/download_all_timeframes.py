#!/usr/bin/env python3
"""
Download all BTC timeframes from Binance (2017-2024)
With retry mechanism for SSL errors
"""

import os
import sys
import time
import urllib.request
import ssl
from pathlib import Path

# Binance public data base URL
BASE_URL = "https://data.binance.vision/"

# All timeframes
TIMEFRAMES = [
    "1s",
    "1m",
    "3m",
    "5m",
    "15m",
    "30m",
    "1h",
    "2h",
    "4h",
    "6h",
    "8h",
    "12h",
    "1d",
]

# Years to download (BTCUSDT started Aug 2017)
YEARS = range(2017, 2026)  # 2017-2025
MONTHS = range(1, 13)

# Output directory
OUTPUT_DIR = "/home/davirain/dev/zigQuant/data/binance_raw"


def download_file(url, save_path, max_retries=3):
    """Download file with retry mechanism"""
    for attempt in range(max_retries):
        try:
            # Create SSL context that's more lenient
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE

            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            response = urllib.request.urlopen(req, context=ctx, timeout=30)

            # Get file size
            file_size = response.getheader("content-length")
            if file_size:
                file_size = int(file_size)

            # Download with progress
            with open(save_path, "wb") as f:
                downloaded = 0
                block_size = 8192
                while True:
                    buffer = response.read(block_size)
                    if not buffer:
                        break
                    downloaded += len(buffer)
                    f.write(buffer)

            return True

        except urllib.request.HTTPError as e:
            if e.code == 404:
                # File doesn't exist (expected for some months)
                return False
            print(f"  HTTP Error {e.code}: {e.reason}")

        except Exception as e:
            print(f"  Attempt {attempt + 1}/{max_retries} failed: {str(e)[:50]}")
            if attempt < max_retries - 1:
                time.sleep(2**attempt)  # Exponential backoff

    return False


def download_timeframe(timeframe, years=YEARS):
    """Download all data for a specific timeframe"""
    print(f"\n{'=' * 60}")
    print(f"Downloading BTCUSDT {timeframe} data")
    print(f"Years: {min(years)} - {max(years)}")
    print(f"{'=' * 60}")

    # Create output directory
    out_dir = (
        Path(OUTPUT_DIR)
        / "data"
        / "spot"
        / "monthly"
        / "klines"
        / "BTCUSDT"
        / timeframe
    )
    out_dir.mkdir(parents=True, exist_ok=True)

    downloaded = 0
    skipped = 0
    failed = 0

    for year in years:
        for month in MONTHS:
            filename = f"BTCUSDT-{timeframe}-{year}-{month:02d}.zip"
            save_path = out_dir / filename

            # Skip if already exists
            if save_path.exists():
                skipped += 1
                continue

            # Construct URL
            url = f"{BASE_URL}data/spot/monthly/klines/BTCUSDT/{timeframe}/{filename}"

            print(f"  Downloading {filename}...", end=" ", flush=True)

            if download_file(url, save_path):
                print("OK")
                downloaded += 1
            else:
                # Remove partial file if exists
                if save_path.exists():
                    save_path.unlink()
                print("Not found")
                failed += 1

    print(
        f"\n  Summary: {downloaded} downloaded, {skipped} skipped (exists), {failed} not found"
    )
    return downloaded, skipped, failed


def main():
    print("=" * 60)
    print("Binance BTC Data Downloader")
    print(f"Timeframes: {', '.join(TIMEFRAMES)}")
    print(f"Years: 2017-2025")
    print(f"Output: {OUTPUT_DIR}")
    print("=" * 60)

    # Check which timeframes to download
    if len(sys.argv) > 1:
        timeframes = sys.argv[1:]
        # Validate
        for tf in timeframes:
            if tf not in TIMEFRAMES:
                print(f"Invalid timeframe: {tf}")
                print(f"Valid options: {', '.join(TIMEFRAMES)}")
                sys.exit(1)
    else:
        timeframes = TIMEFRAMES

    total_downloaded = 0
    total_skipped = 0
    total_failed = 0

    for tf in timeframes:
        d, s, f = download_timeframe(tf)
        total_downloaded += d
        total_skipped += s
        total_failed += f

    print("\n" + "=" * 60)
    print("ALL DOWNLOADS COMPLETE")
    print(
        f"Total: {total_downloaded} downloaded, {total_skipped} skipped, {total_failed} not found"
    )
    print("=" * 60)


if __name__ == "__main__":
    main()
