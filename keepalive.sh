#!/bin/bash
# ============================================================
# KEEPALIVE MASTER — Runs ON the OCI VM (blast-arm)
# Protects against:
#   1. OCI idle reclamation (needs >10% CPU every 7 days)
#   2. PM2 process crashes
#   3. Memory leaks
#   4. Network drops
#
# Install: paste this into VM then run:
#   chmod +x keepalive.sh && sudo bash keepalive.sh
# ============================================================

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════╗"
echo "║     blast-arm Keep-Alive System Installer        ║"
echo "║         4 OCPU | 24GB | Never Dies              ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# ── 1. ANTI-IDLE SCRIPT (defeats OCI's idle reclamation) ────
# Oracle reclaims free VMs with <10% CPU for 7 days
# This runs a lightweight CPU pulse every 6 hours
log "Creating anti-idle CPU pulse script..."
cat > /usr/local/bin/oci-anti-idle.sh << 'ANTI_IDLE'
#!/bin/bash
# Light CPU pulse — uses ~15% CPU for 60 seconds every 6 hours
# This keeps Oracle's idle detector from flagging our VM
LOG="/var/log/oci-keepalive.log"
echo "[$(date)] Anti-idle pulse started" >> $LOG

# Run a harmless compute task for 60 seconds
timeout 60 bash -c '
  while true; do
    # Fibonacci calculation — pure CPU, no I/O
    python3 -c "
a,b=0,1
for _ in range(500000):
    a,b=b,a+b
print(\"pulse ok\")
" > /dev/null 2>&1
  done
'

echo "[$(date)] Anti-idle pulse done. CPU back to idle." >> $LOG
ANTI_IDLE
chmod +x /usr/local/bin/oci-anti-idle.sh

# ── 2. PM2 HEALTH WATCHDOG ──────────────────────────────────
log "Creating PM2 health watchdog..."
cat > /usr/local/bin/pm2-watchdog.sh << 'PM2_WATCH'
#!/bin/bash
LOG="/var/log/pm2-watchdog.log"

check_and_restart() {
  local app=$1
  STATUS=$(pm2 jlist 2>/dev/null | python3 -c "
import sys,json
data=json.load(sys.stdin)
for p in data:
    if p['name']=='$app':
        print(p['pm2_env']['status'])
        break
" 2>/dev/null)

  if [ "$STATUS" != "online" ]; then
    echo "[$(date)] $app is $STATUS — restarting..." >> $LOG
    pm2 restart $app >> $LOG 2>&1
    sleep 5
    # If still not online, delete and re-start
    STATUS2=$(pm2 jlist 2>/dev/null | python3 -c "
import sys,json
data=json.load(sys.stdin)
for p in data:
    if p['name']=='$app':
        print(p['pm2_env']['status'])
" 2>/dev/null)
    if [ "$STATUS2" != "online" ]; then
      echo "[$(date)] $app still dead — doing hard restart" >> $LOG
      pm2 delete $app >> $LOG 2>&1
      sleep 2
      cd ~/openclaw && pm2 start index.js --name $app >> $LOG 2>&1
      pm2 save >> $LOG 2>&1
    fi
  fi
}

check_and_restart "openclaw"
PM2_WATCH
chmod +x /usr/local/bin/pm2-watchdog.sh

# ── 3. MEMORY LEAK GUARDIAN ─────────────────────────────────
log "Creating memory leak guardian..."
cat > /usr/local/bin/memory-guardian.sh << 'MEM_GUARD'
#!/bin/bash
LOG="/var/log/memory-guardian.log"
THRESHOLD=85  # Restart PM2 if RAM usage > 85%

USED_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')

if [ "$USED_PCT" -gt "$THRESHOLD" ]; then
  echo "[$(date)] RAM at ${USED_PCT}% — clearing cache & restarting openclaw" >> $LOG
  # Clear Linux page cache (safe, no data loss)
  sync && echo 3 > /proc/sys/vm/drop_caches
  pm2 restart openclaw >> $LOG 2>&1
  echo "[$(date)] Done. RAM now $(free | awk '/Mem:/ {printf "%.0f", $3/$2*100}')%" >> $LOG
fi
MEM_GUARD
chmod +x /usr/local/bin/memory-guardian.sh

# ── 4. INTERNET CONNECTIVITY CHECKER ────────────────────────
log "Creating network connectivity watchdog..."
cat > /usr/local/bin/net-watchdog.sh << 'NET_WATCH'
#!/bin/bash
LOG="/var/log/net-watchdog.log"

# Check connectivity
if ! ping -c 3 -W 5 8.8.8.8 > /dev/null 2>&1; then
  echo "[$(date)] Network DOWN — trying to recover..." >> $LOG
  # Restart networking
  sudo systemctl restart networking 2>/dev/null || true
  sudo dhclient -r && sudo dhclient 2>/dev/null || true
  sleep 10
  if ping -c 3 8.8.8.8 > /dev/null 2>&1; then
    echo "[$(date)] Network RECOVERED" >> $LOG
    pm2 restart openclaw >> $LOG 2>&1
  else
    echo "[$(date)] Network still DOWN — rebooting in 60s" >> $LOG
    # Last resort: reboot (PM2 will auto-restart openclaw after boot)
    sudo shutdown -r +1 >> $LOG 2>&1
  fi
fi
NET_WATCH
chmod +x /usr/local/bin/net-watchdog.sh

# ── 5. DISK CLEANUP (prevent full disk killing processes) ────
log "Creating disk cleanup script..."
cat > /usr/local/bin/disk-cleanup.sh << 'DISK_CLEAN'
#!/bin/bash
LOG="/var/log/disk-cleanup.log"
THRESHOLD=80

USED_PCT=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$USED_PCT" -gt "$THRESHOLD" ]; then
  echo "[$(date)] Disk ${USED_PCT}% full — cleaning..." >> $LOG
  # Clean PM2 logs
  pm2 flush >> $LOG 2>&1
  # Clean apt cache
  sudo apt-get clean -qq
  # Clean old logs
  sudo journalctl --vacuum-size=100M >> $LOG 2>&1
  sudo find /var/log -name "*.gz" -delete
  echo "[$(date)] Disk now $(df / | awk 'NR==2 {print $5}') used" >> $LOG
fi
DISK_CLEAN
chmod +x /usr/local/bin/disk-cleanup.sh

# ── 6. INSTALL ALL CRON JOBS ─────────────────────────────────
log "Installing cron jobs..."
# Write crontab for ubuntu user
(crontab -l 2>/dev/null | grep -v "keepalive\|anti-idle\|pm2-watch\|memory-guard\|net-watch\|disk-clean"; cat << 'CRON'
# OCI Anti-Idle Pulse — every 6 hours (keeps Oracle from reclaiming VM)
0 */6 * * * /usr/local/bin/oci-anti-idle.sh >> /var/log/oci-keepalive.log 2>&1

# PM2 Health Check — every 2 minutes
*/2 * * * * /usr/local/bin/pm2-watchdog.sh

# Memory Guardian — every 5 minutes
*/5 * * * * /usr/local/bin/memory-guardian.sh

# Network Watchdog — every 3 minutes
*/3 * * * * /usr/local/bin/net-watchdog.sh

# Disk Cleanup — every day at 3 AM
0 3 * * * /usr/local/bin/disk-cleanup.sh

# PM2 save — every 30 min (persist process list across reboots)
*/30 * * * * pm2 save --silent >> /dev/null 2>&1
CRON
) | crontab -

# ── 7. MAKE LOG FILES WRITABLE ──────────────────────────────
sudo touch /var/log/oci-keepalive.log /var/log/pm2-watchdog.log \
           /var/log/memory-guardian.log /var/log/net-watchdog.log \
           /var/log/disk-cleanup.log
sudo chmod 666 /var/log/oci-keepalive.log /var/log/pm2-watchdog.log \
               /var/log/memory-guardian.log /var/log/net-watchdog.log \
               /var/log/disk-cleanup.log

# ── 8. SYSTEMD FAILSAFE (in case cron itself dies) ──────────
log "Creating systemd failsafe service..."
sudo tee /etc/systemd/system/openclaw-guardian.service > /dev/null << 'SYSTEMD'
[Unit]
Description=OpenClaw Guardian — Ensures PM2 and openclaw survive reboots
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=ubuntu
ExecStart=/bin/bash -c 'pm2 resurrect || (cd /home/ubuntu/openclaw && pm2 start index.js --name openclaw && pm2 save)'
ExecStop=/bin/bash -c 'pm2 save'

[Install]
WantedBy=multi-user.target
SYSTEMD

sudo systemctl daemon-reload
sudo systemctl enable openclaw-guardian.service
sudo systemctl start openclaw-guardian.service

# ── 9. HOSTNAME KEEPALIVE ───────────────────────────────────
# OCI instance metadata ping — keeps OCI's internal health check happy
log "Starting IMDS keepalive..."
(crontab -l 2>/dev/null; echo "*/10 * * * * curl -s http://169.254.169.254/opc/v1/instance/ > /dev/null 2>&1") | crontab -

# ── DONE ────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         ✅ Keep-Alive System ACTIVE!              ║${NC}"
echo -e "${GREEN}║                                                  ║${NC}"
echo -e "${GREEN}║  Anti-idle pulse:    every 6 hours               ║${NC}"
echo -e "${GREEN}║  PM2 health check:   every 2 minutes             ║${NC}"
echo -e "${GREEN}║  Memory guardian:    every 5 minutes             ║${NC}"
echo -e "${GREEN}║  Network watchdog:   every 3 minutes             ║${NC}"
echo -e "${GREEN}║  Disk cleanup:       daily 3 AM                  ║${NC}"
echo -e "${GREEN}║  OCI IMDS ping:      every 10 minutes            ║${NC}"
echo -e "${GREEN}║  Systemd failsafe:   on every boot               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Verify crons: crontab -l${NC}"
echo -e "${YELLOW}Watch logs:   tail -f /var/log/oci-keepalive.log${NC}"
