#!/bin/bash
export PATH="/home/ubuntu/.npm-global/bin:$PATH"

# Keys from environment — set as GitHub Secrets: GROQ_API_KEY, GEMINI_API_KEY
GROQ_KEY="${GROQ_API_KEY:-}"
GEMINI_KEY="${GEMINI_API_KEY:-}"

echo "=== OpenClaw onboard with Groq + Gemini ==="
openclaw onboard \
  --non-interactive \
  --groq-api-key "$GROQ_KEY" \
  --gemini-api-key "$GEMINI_KEY" \
  --mode local \
  --skip-channels \
  --no-install-daemon \
  2>&1

echo "=== Config saved ==="
openclaw config list 2>&1 | head -40

echo "=== Starting OpenClaw gateway via PM2 ==="
pm2 delete openclaw-gateway 2>/dev/null || true
pm2 start "openclaw gateway --port 4000" \
  --name openclaw-gateway \
  --restart-delay=5000 \
  --max-restarts=20 \
  --interpreter bash
pm2 save

echo "=== All services ==="
pm2 status

echo "=== Health check ==="
sleep 5
curl -s http://localhost:4000/health 2>/dev/null || echo "Gateway starting..."

echo "DONE"
