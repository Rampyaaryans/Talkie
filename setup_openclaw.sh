#!/bin/bash
# ============================================================
# OpenClaw Full Setup Script — Ubuntu 22.04 ARM (A1.Flex)
# Run this once after SSHing into your fresh OCI VM
# Usage: bash setup_openclaw.sh YOUR_GROQ_KEY YOUR_GEMINI_KEY
# ============================================================

GROQ_API_KEY="${1:-REPLACE_WITH_GROQ_KEY}"
GEMINI_API_KEY="${2:-REPLACE_WITH_GEMINI_KEY}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}✅ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠️  $1${NC}"; }

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║     OpenClaw OCI Fresh Setup Script      ║"
echo "║         4 OCPU / 24GB RAM / ARM          ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── 1. SYSTEM UPDATE ────────────────────────────────────────
log "Updating system packages..."
sudo apt update -qq && sudo apt upgrade -y -qq
ok "System updated"

# ── 2. INSTALL NODE.JS 20 ───────────────────────────────────
log "Installing Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - > /dev/null 2>&1
sudo apt install -y nodejs > /dev/null 2>&1
NODE_VER=$(node --version)
ok "Node.js installed: $NODE_VER"

# ── 3. CHROMIUM DEPENDENCIES (for whatsapp-web.js) ──────────
log "Installing Chromium + Puppeteer dependencies..."
sudo apt install -y \
  chromium-browser \
  libgbm-dev libxkbcommon-x11-0 libglib2.0-0 libnss3 \
  libatk-bridge2.0-0 libgtk-3-0 libx11-xcb1 libxcomposite1 \
  libxdamage1 libxrandr2 libasound2 libpangocairo-1.0-0 \
  libxss1 libxtst6 fonts-liberation libappindicator3-1 \
  lsb-release xdg-utils wget curl git jq > /dev/null 2>&1
ok "Chromium deps installed"

# ── 4. PM2 ──────────────────────────────────────────────────
log "Installing PM2..."
sudo npm install -g pm2 > /dev/null 2>&1
ok "PM2 installed"

# ── 5. CLONE OPENCLAW ───────────────────────────────────────
log "Cloning OpenClaw..."
cd ~
if [ -d "openclaw" ]; then
  warn "openclaw dir exists, removing and re-cloning..."
  rm -rf openclaw
fi
git clone https://github.com/Clawdbot/openclaw.git
cd openclaw
npm install > /dev/null 2>&1
ok "OpenClaw cloned and deps installed"

# ── 6. CREATE config.json ───────────────────────────────────
log "Writing config.json (stealth + whitelist mode)..."
cat > ~/openclaw/config.json << EOF
{
  "allowFrom": ["*"],

  "autoReply": {
    "enabled": true,
    "platform": ["whatsapp"],
    "model": "groq",
    "fallbackModel": "gemini",

    "stealth": {
      "simulateTyping": true,
      "sendSeen": true,
      "typingDelayMs": { "min": 1800, "max": 5000 },
      "replyDelayMs":  { "min": 4000, "max": 14000 },
      "sleepSchedule": {
        "enabled": true,
        "timezone": "Asia/Kolkata",
        "sleepAt": "01:30",
        "wakeAt": "09:00"
      },
      "rateLimits": {
        "maxRepliesPerHour": 18,
        "maxRepliesPerDay": 90
      }
    }
  },

  "groq": {
    "apiKey": "${GROQ_API_KEY}",
    "model": "llama3-70b-8192"
  },

  "gemini": {
    "apiKey": "${GEMINI_API_KEY}",
    "model": "gemini-1.5-flash"
  }
}
EOF
ok "config.json written"

# ── 7. CREATE SOUL.md (personality) ─────────────────────────
log "Writing SOUL.md personality file..."
cat > ~/openclaw/SOUL.md << 'EOF'
# Agent Personality — Virtual Rampyaaryan

## STRICT RULES — NEVER BREAK THESE
- always write in lowercase, no exceptions
- no periods at end of sentences ever
- max 1 sentence, usually 3-8 words is perfect
- use short forms naturally: u, ur, rn, ngl, bro, lol, fr, yaar, kya, bc
- never say you are an AI, bot, or assistant — ever
- if someone asks "are you real" say something like "haha why u asking lol"
- if asked something complex, deflect: "bro ill get back to u" or "ask me later yaar"
- match their energy completely — excited = hyped, chill = chill, sad = soft

## Language Style
- mix hindi and english naturally (hinglish)
- casual, like texting a close friend
- never formal, never full sentences

## Example Conversations
User: bhai kya kar raha hai
You: soya tha abhi utha lol

User: you free tonight?
You: maybe kyun kya hua

User: meeting ka kya bana
You: kal baat karte bro

User: bro i need help
You: bol kya hua

User: what do you think about life
You: bhai bahut bada sawal hai subah subah

User: miss you yaar
You: haha same bc

User: good morning
You: gm yaar tu bhi uth gaya

## NEVER SAY
- "Hello! How can I assist you today?"
- "Certainly!" / "Of course!" / "Great question!"
- "As an AI language model..."
- Any formal or corporate language
- More than one sentence
EOF
ok "SOUL.md written"

# ── 8. CREATE AGENTS.md ─────────────────────────────────────
log "Writing AGENTS.md..."
cat > ~/openclaw/AGENTS.md << 'EOF'
# OpenClaw Agent Config

## Primary Agent: WhatsApp Auto-Reply
- Read SOUL.md for personality
- Check config.json for allowed numbers and stealth settings
- Use Groq llama3-70b as primary (fastest)
- Fall back to Gemini Flash if Groq fails
- Never reply during sleep hours (01:30 - 09:00 IST)
- Simulate typing and seen receipts on every message
EOF
ok "AGENTS.md written"

# ── 9. SETUP PM2 AUTOSTART ──────────────────────────────────
log "Configuring PM2 autostart..."
cd ~/openclaw
pm2 delete openclaw 2>/dev/null || true
pm2 start index.js --name openclaw
pm2 save
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u $USER --hp $HOME | tail -1 | bash
ok "PM2 configured for autostart"

# ── 10. SETUP OS FIREWALL ───────────────────────────────────
log "Configuring firewall..."
sudo ufw allow OpenSSH
sudo ufw --force enable
ok "Firewall configured"

# ─── DONE ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          OpenClaw is LIVE! 🎉             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Scan WhatsApp QR:${NC}  pm2 logs openclaw"
echo -e "  ${CYAN}Status:${NC}            pm2 status"
echo -e "  ${CYAN}Edit whitelist:${NC}    nano ~/openclaw/config.json"
echo -e "  ${CYAN}Edit personality:${NC}  nano ~/openclaw/SOUL.md"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Run 'pm2 logs openclaw' and scan the QR code with WhatsApp!${NC}"
