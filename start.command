#!/bin/bash
set -e
cd "$(dirname "$0")"

if [ ! -d "venv" ]; then
  echo "Setting up (first run only)..."
  python3 -m venv venv
  ./venv/bin/pip install --quiet --upgrade pip
  ./venv/bin/pip install --quiet -r requirements.txt
fi

# Open the browser shortly after the server starts.
( sleep 1.5 && open "http://127.0.0.1:5058" ) &

echo "Starting Torrent Tube... (close this window to stop the server)"
./venv/bin/python app.py
