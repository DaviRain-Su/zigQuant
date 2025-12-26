#!/usr/bin/env python3
"""
Convert Binance K-line CSV format to zigQuant format.

Binance format: open_time,open,high,low,close,volume,close_time,quote_volume,num_trades,taker_buy_base,taker_buy_quote,ignore
zigQuant format: timestamp,open,high,low,close,volume
"""

import os
import glob
import zipfile
import sys

def convert_binance_to_zigquant(input_dir, output_file):
    """Convert all Binance K-line CSV files in directory to single zigQuant CSV."""

    # Find all zip files
    zip_files = sorted(glob.glob(os.path.join(input_dir, "*.zip")))

    if not zip_files:
        print(f"No zip files found in {input_dir}")
        return False

    print(f"Found {len(zip_files)} zip files")

    all_lines = []

    # Process each zip file
    for zip_path in zip_files:
        print(f"Processing {os.path.basename(zip_path)}...")

        try:
            with zipfile.ZipFile(zip_path, 'r') as zf:
                # Get the CSV file name (should be only one file)
                csv_files = [f for f in zf.namelist() if f.endswith('.csv')]

                if not csv_files:
                    print(f"  Warning: No CSV file found in {zip_path}")
                    continue

                csv_file = csv_files[0]

                # Read CSV content
                with zf.open(csv_file) as f:
                    content = f.read().decode('utf-8')
                    lines = content.strip().split('\n')

                    # Convert each line (take only first 6 columns)
                    for line in lines:
                        if not line.strip():
                            continue

                        fields = line.split(',')
                        if len(fields) >= 6:
                            # timestamp,open,high,low,close,volume
                            converted = ','.join(fields[:6])
                            all_lines.append(converted)

                    print(f"  Extracted {len(lines)} lines")

        except Exception as e:
            print(f"  Error processing {zip_path}: {e}")
            continue

    if not all_lines:
        print("No data extracted!")
        return False

    # Sort by timestamp (first field)
    print(f"\nSorting {len(all_lines)} total lines by timestamp...")
    all_lines.sort(key=lambda x: int(x.split(',')[0]))

    # Write to output file
    print(f"Writing to {output_file}...")
    with open(output_file, 'w') as f:
        # Write header
        f.write("timestamp,open,high,low,close,volume\n")

        # Write all lines
        for line in all_lines:
            f.write(line + '\n')

    print(f"\nSuccess! Converted {len(all_lines)} candles to {output_file}")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 convert_binance_to_zigquant.py <input_dir> <output_file>")
        print("Example: python3 convert_binance_to_zigquant.py binance_raw/ BTCUSDT_1h_2024.csv")
        sys.exit(1)

    input_dir = sys.argv[1]
    output_file = sys.argv[2]

    if not os.path.exists(input_dir):
        print(f"Error: Directory not found: {input_dir}")
        sys.exit(1)

    success = convert_binance_to_zigquant(input_dir, output_file)
    sys.exit(0 if success else 1)
