#!/bin/bash
# ============================================================
# BUILD BOT — Gemini Primary + Groq Fallback + Racing Mode
# Run: bash ~/build_bot.sh GROQ_KEY GEMINI_KEY
# ============================================================

GROQ_KEY="${1:-PLACEHOLDER}"
GEMINI_KEY="${2:-PLACEHOLDER}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $1"; }
ok()  { echo -e "${GREEN}✅ $1${NC}"; }

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║  OpenClaw — Gemini Primary + Groq Fallback       ║"
echo "║     Dual-Brain Racing Architecture               ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

mkdir -p ~/openclaw && cd ~/openclaw

# ── package.json ──────────────────────────────────────────────
log "Writing package.json..."
cat > package.json << 'EOF'
{
  "name": "openclaw-bot",
  "version": "2.0.0",
  "description": "WhatsApp Agent — Gemini + Groq Dual Brain",
  "main": "index.js",
  "dependencies": {
    "whatsapp-web.js": "^1.23.0",
    "qrcode-terminal": "^0.12.0",
    "groq-sdk": "^0.9.0",
    "@google/generative-ai": "^0.21.0",
    "dotenv": "^16.4.5",
    "express": "^4.19.2"
  }
}
EOF
ok "package.json done"

# ── .env ──────────────────────────────────────────────────────
log "Writing .env..."
cat > .env << ENVEOF
GROQ_API_KEY=${GROQ_KEY}
GEMINI_API_KEY=${GEMINI_KEY}
ENVEOF

# ── SOUL.md ───────────────────────────────────────────────────
log "Writing SOUL.md..."
cat > SOUL.md << 'SOUL'
You are replying on behalf of Rampyaaryan. These are ABSOLUTE rules — never break them:

STYLE RULES:
- always lowercase. never capitalize anything
- no full stops/periods at end ever
- max 1 sentence, 3-8 words is ideal
- use naturally: u, ur, rn, ngl, bro, lol, fr, yaar, kya, bc, lmao, bhai, ik
- mix hindi and english (hinglish) naturally like a north indian 20-something guy
- never sound formal or robotic

BEHAVIOUR RULES:
- never say you're an AI, bot, or assistant. never. if asked, deflect casually
- if message is complex or deep: "bro ill get back to u" or "ask me later yaar"
- if someone says good morning: "gm yaar" or "gm bro"
- if complimenting: "haha thanks yaar" or "aww fr"
- match their energy completely

BANNED (never ever say):
- "Hello! How can I assist"
- "Certainly!" "Of course!" "Great!"
- "As an AI..." "I am an AI"
- multiple sentences
- formal English
SOUL
ok "SOUL.md done"

# ── main index.js ─────────────────────────────────────────────
log "Writing index.js (Gemini-primary + Groq-fallback dual-brain)..."
cat > index.js << 'BOTEOF'
require('dotenv').config();
const { Client, LocalAuth } = require('whatsapp-web.js');
const qrcode = require('qrcode-terminal');
const Groq = require('groq-sdk');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const express = require('express');
const fs = require('fs');

// ── Config ──────────────────────────────────────────────────
const CONFIG = {
  allowFrom: ['*'],              // '*' = everyone, or ['+919876543210']
  replyDelayMin: 3500,           // ms before replying
  replyDelayMax: 13000,
  typingDurationMin: 1500,
  typingDurationMax: 6000,
  sleep: {
    enabled: true,
    sleepHour: 1, sleepMin: 30,  // 1:30 AM IST
    wakeHour: 9,  wakeMin: 0,    // 9:00 AM IST
  },
  maxRepliesPerHour: 20,
  // AI architecture: 'gemini-first' | 'groq-first' | 'race'
  aiMode: 'gemini-first',
};

// ── AI Clients ───────────────────────────────────────────────
const GROQ_KEY   = process.env.GROQ_API_KEY;
const GEMINI_KEY = process.env.GEMINI_API_KEY;
const SOUL       = fs.readFileSync('./SOUL.md', 'utf8');

const groq  = GROQ_KEY   ? new Groq({ apiKey: GROQ_KEY })   : null;
const genAI = GEMINI_KEY ? new GoogleGenerativeAI(GEMINI_KEY) : null;

// ── Rate limit ───────────────────────────────────────────────
let repliesThisHour = 0;
const stats = { total: 0, groqUsed: 0, geminiUsed: 0, fallbacks: 0, errors: 0 };
setInterval(() => { repliesThisHour = 0; }, 3600000);

// ── Sleep check (IST = UTC+5:30) ─────────────────────────────
function isSleeping() {
  if (!CONFIG.sleep.enabled) return false;
  const ist = new Date(Date.now() + 5.5 * 3600000);
  const h = ist.getUTCHours(), m = ist.getUTCMinutes();
  const now = h * 60 + m;
  const sleep = CONFIG.sleep.sleepHour * 60 + CONFIG.sleep.sleepMin;
  const wake  = CONFIG.sleep.wakeHour  * 60 + CONFIG.sleep.wakeMin;
  return now >= sleep || now < wake;
}

function isAllowed(num) {
  if (CONFIG.allowFrom.includes('*')) return true;
  return CONFIG.allowFrom.some(n => num.includes(n.replace('+', '')));
}

// ── Gemini reply ─────────────────────────────────────────────
async function askGemini(userMsg, name) {
  if (!genAI) throw new Error('Gemini not configured');
  const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
  const prompt = `${SOUL}\n\n${name} says: "${userMsg}"\nReply (1 sentence, follow ALL rules above):`;
  const result = await model.generateContent({
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: { maxOutputTokens: 80, temperature: 1.0 },
  });
  return result.response.text().trim();
}

// ── Groq reply ───────────────────────────────────────────────
async function askGroq(userMsg, name) {
  if (!groq) throw new Error('Groq not configured');
  const res = await groq.chat.completions.create({
    model: 'llama-3.3-70b-versatile',
    messages: [
      { role: 'system', content: SOUL },
      { role: 'user',   content: `${name} says: "${userMsg}"\nReply (follow ALL personality rules):` },
    ],
    max_tokens: 80,
    temperature: 0.95,
  });
  return res.choices[0].message.content.trim();
}

// ── DUAL BRAIN — Race mode (fastest wins) ────────────────────
async function askRace(userMsg, name) {
  return Promise.any([
    askGemini(userMsg, name),
    askGroq(userMsg, name),
  ]);
}

// ── Master AI router ─────────────────────────────────────────
async function getReply(userMsg, name) {
  // ARCHITECTURE: Gemini primary → Groq fallback
  if (CONFIG.aiMode === 'gemini-first') {
    try {
      const r = await askGemini(userMsg, name);
      stats.geminiUsed++;
      console.log('   🧠 [Gemini]');
      return r;
    } catch (e) {
      console.log(`   ⚠️  Gemini failed (${e.message.substring(0,50)}) → falling back to Groq`);
      try {
        const r = await askGroq(userMsg, name);
        stats.groqUsed++;
        console.log('   ⚡ [Groq fallback]');
        return r;
      } catch (e2) {
        console.log(`   ❌ Groq also failed: ${e2.message.substring(0,50)}`);
      }
    }
  }

  // ARCHITECTURE: Groq primary → Gemini fallback
  if (CONFIG.aiMode === 'groq-first') {
    try {
      const r = await askGroq(userMsg, name);
      stats.groqUsed++;
      return r;
    } catch (e) {
      console.log(`   ⚠️  Groq failed → Gemini fallback`);
      try { return await askGemini(userMsg, name); } catch {}
    }
  }

  // ARCHITECTURE: Race — both fire simultaneously, fastest wins
  if (CONFIG.aiMode === 'race') {
    try {
      return await askRace(userMsg, name);
    } catch (e) {
      console.log('   ❌ Both AI failed in race mode');
    }
  }

  // Emergency fallbacks (if all AI fails)
  stats.fallbacks++;
  const fallbacks = [
    'bro kya hua', 'fr yaar', 'haha same', 'rn busy yaar',
    'bhai baad mein baat karte', 'ik bro', 'lmao kya', 'chill yaar'
  ];
  return fallbacks[Math.floor(Math.random() * fallbacks.length)];
}

function randomMs(min, max) {
  return new Promise(r => setTimeout(r, min + Math.random() * (max - min)));
}

// ── WhatsApp Client ──────────────────────────────────────────
const client = new Client({
  authStrategy: new LocalAuth({ clientId: 'openclaw' }),
  puppeteer: {
    headless: true,
    executablePath: '/usr/bin/chromium-browser',
    args: [
      '--no-sandbox', '--disable-setuid-sandbox',
      '--disable-dev-shm-usage', '--disable-gpu',
      '--no-first-run', '--no-zygote', '--single-process',
    ],
  },
});

client.on('qr', qr => {
  console.log('\n\n🔐 SCAN THIS QR WITH WHATSAPP:\n');
  qrcode.generate(qr, { small: true });
  console.log('\nWhatsApp → Linked Devices → Link a Device → Scan\n');
});

client.on('authenticated', () => console.log('✅ WhatsApp authenticated!'));
client.on('auth_failure', msg => console.error('❌ Auth failure:', msg));

client.on('ready', () => {
  console.log('\n╔═══════════════════════════════════════════════╗');
  console.log('║   ✅ OpenClaw Live on blast-arm (24GB RAM)     ║');
  console.log(`║   Gemini: ${genAI?'✅':'❌ (quota?)'}  Groq: ${groq?'✅':'❌'}  Mode: ${CONFIG.aiMode}  ║`);
  console.log(`║   Sleep: 01:30–09:00 IST | Max: ${CONFIG.maxRepliesPerHour}/hr          ║`);
  console.log('╚═══════════════════════════════════════════════╝\n');
});

client.on('message', async msg => {
  if (msg.isGroupMsg || msg.from === 'status@broadcast') return;
  if (msg.type !== 'chat' || !msg.body?.trim()) return;

  const sender = msg.from;
  const body   = msg.body.trim();

  if (!isAllowed(sender))           return;
  if (isSleeping())                 { console.log(`[SLEEP] Skipping: ${sender}`); return; }
  if (repliesThisHour >= CONFIG.maxRepliesPerHour) { console.log('[RATE] Limit hit'); return; }

  const contact = await msg.getContact();
  const name    = contact.pushname || contact.name || 'bro';
  console.log(`\n📨 ${name}: ${body}`);

  try {
    // 1. Mark seen (blue ticks)
    await client.sendSeen(sender);

    // 2. Human delay before typing starts
    await randomMs(CONFIG.replyDelayMin / 2, CONFIG.replyDelayMax / 2);

    // 3. Start typing indicator
    const chat = await msg.getChat();
    await chat.sendStateTyping();

    // 4. Get AI reply (Gemini → Groq)
    const reply = await getReply(body, name);

    // 5. Typing time proportional to reply length
    const typingTime = Math.min(CONFIG.typingDurationMax,
      Math.max(CONFIG.typingDurationMin, reply.length * 90));
    await randomMs(typingTime * 0.8, typingTime * 1.2);

    // 6. Send
    await chat.clearState();
    await msg.reply(reply);
    repliesThisHour++;
    stats.total++;

    console.log(`   💬 Sent: "${reply}" (${repliesThisHour}/${CONFIG.maxRepliesPerHour}hr | G:${stats.geminiUsed} Q:${stats.groqUsed} F:${stats.fallbacks})`);

  } catch (err) {
    stats.errors++;
    console.error('   ❌ Error:', err.message);
  }
});

client.on('disconnected', reason => {
  console.log('⚠️  Disconnected:', reason, '— restarting in 15s...');
  setTimeout(() => client.initialize(), 15000);
});

// ── Health check HTTP server (for external monitoring) ───────
const app = express();
app.get('/health', (req, res) => {
  res.json({
    status: 'alive',
    vm: 'blast-arm',
    ram: '24GB',
    uptime: Math.floor(process.uptime()),
    stats,
    sleeping: isSleeping(),
    repliesThisHour,
    timestamp: new Date().toISOString(),
  });
});
app.listen(8080, '0.0.0.0', () => {
  console.log('🏥 Health server: http://129.146.108.100:8080/health');
});

// ── Start bot ────────────────────────────────────────────────
console.log('🚀 Starting OpenClaw on blast-arm...');
client.initialize();

process.on('uncaughtException',  e => console.error('Uncaught:', e.message));
process.on('unhandledRejection', e => console.error('Unhandled:', e?.message || e));
BOTEOF
ok "index.js written"

# ── Install packages ─────────────────────────────────────────
log "npm install (1-2 min)..."
npm install 2>&1 | tail -5
ok "npm install done"

# ── Start PM2 ────────────────────────────────────────────────
log "Starting with PM2..."
pm2 delete openclaw 2>/dev/null || true
pm2 start index.js --name openclaw \
  --restart-delay=8000 \
  --max-restarts=20 \
  --exp-backoff-restart-delay=100
pm2 save
ok "PM2 started"

# ── Open firewall port 8080 for health endpoint ──────────────
sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
sudo netfilter-persistent save 2>/dev/null || sudo apt-get install -y iptables-persistent -qq 2>/dev/null

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           ✅ OpenClaw Bot LIVE!                   ║${NC}"
echo -e "${GREEN}║                                                  ║${NC}"
echo -e "${GREEN}║  Architecture: Gemini Primary → Groq Fallback    ║${NC}"
echo -e "${GREEN}║  Health URL:   http://129.146.108.100:8080/health ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}⚠️  SCAN QR: pm2 logs openclaw${NC}"
