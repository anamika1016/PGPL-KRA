#!/usr/bin/env bash
set -euo pipefail

echo "Installing LibreOffice for PPT/DOCX preview..."

if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y libreoffice-core libreoffice-impress libreoffice-writer
else
  echo "ERROR: apt-get not found. Please install LibreOffice manually."
  exit 1
fi

echo "Verifying LibreOffice binary..."
if command -v libreoffice >/dev/null 2>&1; then
  echo "OK: libreoffice at $(command -v libreoffice)"
elif command -v soffice >/dev/null 2>&1; then
  echo "OK: soffice at $(command -v soffice)"
elif [[ -x /usr/bin/libreoffice ]]; then
  echo "OK: /usr/bin/libreoffice"
elif [[ -x /usr/bin/soffice ]]; then
  echo "OK: /usr/bin/soffice"
else
  echo "ERROR: LibreOffice not found after install."
  exit 1
fi

echo
echo "Done."
echo "Now restart your Rails app (example):"
echo "  sudo systemctl restart puma"
#!/bin/bash
# Server pe PPT/DOCX preview ke liye LibreOffice install karo.
# Run: sudo bash scripts/install_libreoffice_for_preview.sh

set -e
echo "Installing LibreOffice for training preview..."
apt-get update -qq
apt-get install -y libreoffice-core libreoffice-impress libreoffice-writer

if command -v libreoffice &>/dev/null; then
  echo "OK: libreoffice found at $(command -v libreoffice)"
elif command -v soffice &>/dev/null; then
  echo "OK: soffice found at $(command -v soffice)"
else
  echo "WARNING: libreoffice/soffice not in PATH. Trying /usr/bin..."
  test -x /usr/bin/libreoffice && echo "OK: /usr/bin/libreoffice" && exit 0
  test -x /usr/bin/soffice && echo "OK: /usr/bin/soffice" && exit 0
  echo "ERROR: LibreOffice still not found. Install manually: apt-get install -y libreoffice"
  exit 1
fi
echo "Done. Restart your Rails app (e.g. systemctl restart puma) and try PPT preview again."
