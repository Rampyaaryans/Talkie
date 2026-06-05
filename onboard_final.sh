#!/bin/bash
export PATH="/home/ubuntu/.npm-global/bin:$PATH"

# Keys come from environment variables (never hardcode!)
# Set these as GitHub Secrets: GROQ_API_KEY, GEMINI_API_KEY
GROQ_KEY="${GROQ_API_KEY:-}"
GEMINI_KEY="${GEMINI_API_KEY:-}"

if [ -z "$GROQ_KEY" ] || [ -z "$GEMINI_KEY" ]; then
  echo "ERROR: Set GROQ_API_KEY and GEMINI_API_KEY env vars before running"
  exit 1
fi

echo "=== OpenClaw v$(openclaw --version | head -1) — Final Config ==="

# Onboard with both keys, accept-risk for non-interactive
openclaw onboard \
  --non-interactive \
  --accept-risk \
  --gemini-api-key "$GEMINI_KEY" \
  --mode local \
  --no-install-daemon \
  --skip-channels \
  --skip-search \
  2>&1

echo ""
echo "=== Adding Groq key separately ==="
openclaw onboard \
  --non-interactive \
  --accept-risk \
  --groq-api-key "$GROQ_KEY" \
  --mode local \
  --no-install-daemon \
  --skip-channels \
  --skip-search \
  2>&1 || true

echo ""
echo "=== OpenClaw status ==="
openclaw status 2>&1 || true

echo ""
echo "=== Starting gateway via PM2 (port 4000) ==="
pm2 delete openclaw-gateway 2>/dev/null || true

# Write a proper gateway start script
cat > /home/ubuntu/start_gateway.sh << 'GWEOF'
#!/bin/bash
export PATH="/home/ubuntu/.npm-global/bin:$PATH"
exec openclaw gateway --port 4000
GWEOF
chmod +x /home/ubuntu/start_gateway.sh

pm2 start /home/ubuntu/start_gateway.sh \
  --name openclaw-gateway \
  --restart-delay=8000 \
  --max-restarts=10

pm2 save

echo ""
echo "=== PM2 Status ==="
pm2 status

sleep 8
echo ""
echo "=== Gateway health ==="
curl -s http://localhost:4000/ 2>/dev/null | head -3 || echo "Gateway booting..."
