# ============================================================
# OCI A1.Flex Auto-Grab Script — PowerShell
# Keeps retrying until it snags a free A1.Flex slot
# Run this on your Windows machine with OCI CLI configured
# ============================================================

$env:OCI_CLI_SUPPRESS_FILE_PERMISSIONS_WARNING = "True"
$env:SUPPRESS_LABEL_WARNING = "True"

# ─── CONFIG — Edit these ────────────────────────────────────
$TENANCY_ID   = "ocid1.tenancy.oc1..aaaaaaaa5frx4pqrno45woojq5rlrl7tyr4rkxy7csdrnbvvatqfaq7kyzha"
$SUBNET_ID    = "ocid1.subnet.oc1.phx.aaaaaaaa5jk7oqoh3e7ayjxk6kllbmx6rlvb5t4bvu455xhbhinfbh5c2aqq"
$IMAGE_ID     = "ocid1.image.oc1.phx.aaaaaaaavukymfigv3gbia4nglaotp2uqr5sc7dt5cbvjcjps4vgmrhxiv2q"  # Ubuntu 22.04 ARM
$SSH_KEY_FILE = "$env:USERPROFILE\.ssh\id_rsa.pub"   # Change if your key is elsewhere
$INSTANCE_NAME = "openclaw-arm"
$OCPUS        = 4
$MEMORY_GB    = 24
$RETRY_DELAY  = 30   # seconds between attempts
# Try all 3 ADs in rotation for best chance
$ADS = @("Aopq:PHX-AD-1", "Aopq:PHX-AD-2", "Aopq:PHX-AD-3")
# ─────────────────────────────────────────────────────────────

$SSH_KEY = Get-Content $SSH_KEY_FILE -Raw

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  OCI A1.Flex Auto-Grab — OpenClaw Deploy" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Target: $OCPUS OCPU / $MEMORY_GB GB RAM" -ForegroundColor Yellow
Write-Host "Retrying every $RETRY_DELAY seconds across all ADs..." -ForegroundColor Yellow
Write-Host ""

$attempt = 0
$adIndex = 0

while ($true) {
    $attempt++
    $AD = $ADS[$adIndex % $ADS.Length]
    $adIndex++

    Write-Host "[$( Get-Date -Format 'HH:mm:ss' )] Attempt #$attempt | AD: $AD" -NoNewline

    $result = oci compute instance launch `
        --compartment-id $TENANCY_ID `
        --availability-domain $AD `
        --shape "VM.Standard.A1.Flex" `
        --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}" `
        --subnet-id $SUBNET_ID `
        --image-id $IMAGE_ID `
        --display-name $INSTANCE_NAME `
        --assign-public-ip true `
        --ssh-authorized-keys-file $SSH_KEY_FILE `
        --wait-for-state RUNNING `
        --max-wait-seconds 300 `
        2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host " ✅ SUCCESS!" -ForegroundColor Green
        Write-Host ""
        Write-Host "🎉 VM Created! Getting IP..." -ForegroundColor Green
        $instanceData = $result | ConvertFrom-Json
        $instanceId = $instanceData.data.id
        Write-Host "Instance ID: $instanceId"

        # Get public IP
        Start-Sleep -Seconds 15
        $vnic = oci compute instance list-vnics --instance-id $instanceId 2>&1 | ConvertFrom-Json
        $publicIp = $vnic.data[0]."public-ip"
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
        Write-Host "  ✅ A1.Flex VM is UP!" -ForegroundColor Green
        Write-Host "  Public IP : $publicIp" -ForegroundColor Green
        Write-Host "  SSH cmd   : ssh -i ~/.ssh/id_rsa ubuntu@$publicIp" -ForegroundColor Green
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green

        # Windows toast notification
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "A1.Flex VM snagged!`nIP: $publicIp`nSSH: ubuntu@$publicIp",
            "OCI VM Ready! 🎉",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        break
    } else {
        $errText = $result -join " "
        if ($errText -match "Out of host capacity|InternalError|500|capacity") {
            Write-Host " ❌ No capacity, retrying in ${RETRY_DELAY}s..." -ForegroundColor Red
        } else {
            Write-Host " ⚠️  Error: $($errText.Substring(0, [Math]::Min(100,$errText.Length)))" -ForegroundColor Yellow
        }
        Start-Sleep -Seconds $RETRY_DELAY
    }
}
