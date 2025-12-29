#!/bin/bash
# Download all BTC timeframes from Binance

cd /home/davirain/dev/zigQuant/data/binance-public-data/python
source .venv/bin/activate

OUTPUT_DIR="/home/davirain/dev/zigQuant/data/binance_raw"
YEARS="2020 2021 2022 2023 2024 2025"

# All timeframes to download
TIMEFRAMES="1s 1m 3m 5m 15m 30m 1h 2h 4h 6h 8h 12h 1d"

echo "=========================================="
echo "Downloading BTC data for all timeframes"
echo "Years: $YEARS"
echo "Timeframes: $TIMEFRAMES"
echo "Output: $OUTPUT_DIR"
echo "=========================================="

for tf in $TIMEFRAMES; do
    echo ""
    echo ">>> Downloading $tf timeframe..."
    echo "n" | python download-kline.py -s BTCUSDT -i $tf -y $YEARS -t spot -skip-daily 1 -folder "$OUTPUT_DIR"
    echo ">>> Completed $tf"
done

echo ""
echo "=========================================="
echo "All downloads completed!"
echo "=========================================="
