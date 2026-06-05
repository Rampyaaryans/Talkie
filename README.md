# Talkie — OpenClaw WhatsApp Agent on OCI blast-arm

## 🦞 What is this?

Auto-reply WhatsApp agent running on Oracle Cloud (OCI) A1.Flex — **4 OCPU / 24GB RAM / FREE FOREVER**.

- **AI Brain**: Gemini 2.0 Flash (primary) + Groq LLaMA 3.3 70B (fallback)
- **Personality**: Hinglish, casual, human-like responses
- **Platform**: OpenClaw v2026.6.1 on OCI ARM VM

## 🏗️ Architecture

```
WhatsApp Message
      ↓
OCI VM blast-arm (129.146.108.100)
      ↓
OpenClaw Gateway (port 4000)
      ↓
┌─────────────────────┐
│  Gemini 2.0 Flash   │ ← Primary (quality)
│  (try first)        │
└─────────────────────┘
         ↓ (if quota exceeded)
┌─────────────────────┐
│  Groq LLaMA 3.3 70B │ ← Fallback (speed)
└─────────────────────┘
      ↓
Reply with human-like delay + typing simulation
```

## 🛡️ VM Keep-Alive System (5 layers)

| Layer | What | Interval |
|---|---|---|
| Anti-idle CPU pulse | Prevents OCI idle reclamation | Every 6 hours |
| PM2 health watchdog | Restarts crashed processes | Every 2 min |
| Memory guardian | Clears RAM leaks | Every 5 min |
| Network watchdog | Auto-recovers drops | Every 3 min |
| GitHub Actions | External cloud guardian | Every 30 min |

## 🚀 VM Details

- **IP**: `129.146.108.100`
- **Shape**: VM.Standard.A1.Flex (Ampere ARM)
- **RAM**: 24 GB
- **OCPUs**: 4
- **Disk**: 45 GB
- **Region**: Phoenix (PHX-AD-2)
- **Status**: Always Free tier, tagged `do-not-delete: true`

## ⚠️ Gemini Key Note

Current Gemini key has quota exhausted. Get a new one free from:
👉 https://aistudio.google.com/app/apikey

Then update: `nano ~/.openclaw/openclaw.json`

## 📋 Useful Commands (SSH into VM)

```bash
# SSH in
ssh -i ~/.oci/blast_vm_key ubuntu@129.146.108.100

# OpenClaw status
openclaw status

# PM2 status  
pm2 status

# View gateway logs
pm2 logs openclaw-gateway

# Restart gateway
pm2 restart openclaw-gateway

# Update API keys
openclaw onboard --non-interactive --accept-risk --gemini-api-key YOUR_NEW_KEY
```
