#!/bin/bash
# Update Gemini API key + model on the VM
export PATH="/home/ubuntu/.npm-global/bin:$PATH"

NEW_GEMINI_KEY="${1:-AIzaSyBH6QxIDYosr_Hkvb-AecA_nrmOJ6i2gbw}"
GROQ_KEY="${GROQ_API_KEY:-}"   # Set GROQ_API_KEY env var before running

echo "=== Updating OpenClaw with new Gemini 2.5 Flash key ==="
openclaw onboard \
  --non-interactive \
  --accept-risk \
  --gemini-api-key "$NEW_GEMINI_KEY" \
  --mode local \
  --no-install-daemon \
  --skip-channels \
  --skip-search \
  2>&1

echo ""
echo "=== Updating WhatsApp bot .env with new key ==="
cat > /home/ubuntu/openclaw/.env << ENVEOF
GROQ_API_KEY=${GROQ_KEY}
GEMINI_API_KEY=${NEW_GEMINI_KEY}
GEMINI_MODEL=gemini-2.5-flash
ENVEOF

echo "=== Patching index.js to use gemini-2.5-flash ==="
if [ -f /home/ubuntu/openclaw/index.js ]; then
  sed -i "s|gemini-2.0-flash|gemini-2.5-flash|g" /home/ubuntu/openclaw/index.js
  sed -i "s|gemini-1.5-flash|gemini-2.5-flash|g" /home/ubuntu/openclaw/index.js
  echo "index.js patched"
fi

echo ""
echo "=== Restarting PM2 processes ==="
pm2 restart all 2>&1 || true
pm2 save

echo ""
echo "=== Quick sanity test — calling Gemini 2.5 Flash ==="
curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$NEW_GEMINI_KEY" \
  -H "Content-Type: application/json" \
  -d '{"contents":[{"parts":[{"text":"say exactly: blast-arm gemini online"}]}],"generationConfig":{"maxOutputTokens":10}}' \
  2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('GEMINI RESPONSE:', d['candidates'][0]['content']['parts'][0]['text'].strip())" 2>/dev/null

echo ""
echo "=== Final PM2 Status ==="
pm2 status
