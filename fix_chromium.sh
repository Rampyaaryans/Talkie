#!/bin/bash
# Fix script — patches chromium path and restarts bot
JSFILE="/home/ubuntu/openclaw/index.js"

echo "Before fix:"
grep "executablePath" "$JSFILE"

# Simple string replacement
cat "$JSFILE" | tr '\n' '\001' | \
  sed 's|/usr/bin/chromium-browser|/usr/bin/chromium|g' | \
  tr '\001' '\n' > /tmp/index_fixed.js

mv /tmp/index_fixed.js "$JSFILE"

echo "After fix:"
grep "executablePath" "$JSFILE"

# Test chromium works
echo "Testing chromium..."
/usr/bin/chromium --version 2>&1 | head -1

# Restart
pm2 restart openclaw
echo "Waiting 10s..."
sleep 10

# Check logs
pm2 logs openclaw --lines 40 --nostream
