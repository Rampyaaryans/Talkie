# ============================================================
# OCI VM SENTINEL — PowerShell (runs on your Windows PC)
# Monitors blast-arm from outside — alerts + auto-heals
# Set up as a Windows Scheduled Task to run every 5 minutes
# ============================================================

$env:OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING = "True"
$env:SUPPRESS_LABEL_WARNING = "True"

# ─── CONFIG ─────────────────────────────────────────────────
$INSTANCE_ID  = "ocid1.instance.oc1.phx.anyhqljr4x4qntycxa6y7uqcsjuafte7j5s7phdphkd4thjyhak6ggod3juq"
$TENANCY_ID   = "ocid1.tenancy.oc1..aaaaaaaa5frx4pqrno45woojq5rlrl7tyr4rkxy7csdrnbvvatqfaq7kyzha"
$VM_PUBLIC_IP = "129.146.108.100"
$VM_NAME      = "blast-arm"
$LOG_FILE     = "$PSScriptRoot\sentinel.log"
$SSH_KEY      = "$env:USERPROFILE\.oci\blast_vm_key"
# ─────────────────────────────────────────────────────────────

function Write-Log {
    param($msg, $color = "White")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg"
    Add-Content -Path $LOG_FILE -Value $line
    Write-Host $line -ForegroundColor $color
}

function Show-Toast {
    param($title, $msg)
    Add-Type -AssemblyName System.Windows.Forms
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Warning
    $notify.Visible = $true
    $notify.ShowBalloonTip(8000, $title, $msg, [System.Windows.Forms.ToolTipIcon]::Warning)
    Start-Sleep -Seconds 2
    $notify.Dispose()
}

function Get-VMState {
    $raw = oci compute instance get --instance-id $INSTANCE_ID 2>&1
    $json = $raw | Where-Object { $_ -notmatch "^oci :|Warning|FutureWarning|warnings\." } | ConvertFrom-Json
    return $json.data."lifecycle-state"
}

function Start-VM {
    Write-Log "🔄 Starting VM $VM_NAME..." "Yellow"
    oci compute instance action --instance-id $INSTANCE_ID --action START 2>&1 | Out-Null
    Write-Log "⏳ Waiting for RUNNING state..." "Yellow"
    oci compute instance get --instance-id $INSTANCE_ID --wait-for-state RUNNING --max-wait-seconds 180 2>&1 | Out-Null
    Write-Log "✅ VM is RUNNING" "Green"
}

function Test-VMPing {
    return (Test-Connection -ComputerName $VM_PUBLIC_IP -Count 2 -Quiet -ErrorAction SilentlyContinue)
}

function Test-SSHAlive {
    $result = ssh -i $SSH_KEY -o ConnectTimeout=10 -o StrictHostKeyChecking=no `
        -o BatchMode=yes ubuntu@$VM_PUBLIC_IP "pm2 jlist" 2>&1
    return ($LASTEXITCODE -eq 0)
}

# ── MAIN CHECK LOOP ─────────────────────────────────────────
Write-Log "===== Sentinel Check =====" "Cyan"

# 1. Check OCI VM lifecycle state
$state = Get-VMState
Write-Log "OCI State: $state"

if ($state -eq "RUNNING") {
    Write-Log "✅ VM is RUNNING in OCI" "Green"

    # 2. Check network reachability (ping)
    if (Test-VMPing) {
        Write-Log "✅ VM is reachable (ping OK)" "Green"

        # 3. Check PM2 + openclaw via SSH
        if (Test-SSHAlive) {
            Write-Log "✅ OpenClaw is alive via SSH" "Green"
        } else {
            Write-Log "⚠️  SSH/PM2 unreachable — attempting SSH restart of PM2" "Yellow"
            ssh -i $SSH_KEY -o ConnectTimeout=15 -o StrictHostKeyChecking=no `
                ubuntu@$VM_PUBLIC_IP `
                "pm2 resurrect || (cd ~/openclaw && pm2 start index.js --name openclaw && pm2 save)" 2>&1 | Out-Null
            Write-Log "🔄 PM2 restart attempted via SSH" "Yellow"
            Show-Toast "⚠️ blast-arm" "PM2 was dead — auto-restarted via SSH"
        }
    } else {
        Write-Log "❌ VM not responding to ping! May be network issue." "Red"
        Show-Toast "❌ blast-arm UNREACHABLE" "VM at $VM_PUBLIC_IP not responding to ping!"
    }

} elseif ($state -eq "STOPPED") {
    Write-Log "🔴 VM is STOPPED — auto-starting!" "Red"
    Show-Toast "🔴 blast-arm STOPPED" "Auto-starting your OCI VM now!"
    Start-VM
    Show-Toast "✅ blast-arm Restarted" "VM is back online at $VM_PUBLIC_IP"

} elseif ($state -eq "STOPPING" -or $state -eq "STARTING") {
    Write-Log "⏳ VM is in transition state: $state — waiting..." "Yellow"

} else {
    Write-Log "🚨 CRITICAL: VM state is '$state' — needs manual attention!" "Red"
    Show-Toast "🚨 blast-arm CRITICAL" "VM state: $state — Check OCI console NOW!"
}

Write-Log "===== Check Done =====" "Cyan"
