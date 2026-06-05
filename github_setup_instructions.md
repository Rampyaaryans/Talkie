# Setting up GitHub Actions Guardian for blast-arm

## What you need to do (one-time setup)

### 1. Push this repo to Talkie

The `.github/workflows/vm-guardian.yml` file needs to be in your Talkie repo.

Run on your PC:
```powershell
cd d:\dfgr\openclaw-deploy
git init
git remote add origin https://github.com/Rampyaaryans/Talkie.git
git add .
git commit -m "Initial OpenClaw + VM Guardian setup"
git push -u origin main
```

### 2. Add OCI credentials as GitHub Secrets

Go to: https://github.com/Rampyaaryans/Talkie/settings/secrets/actions

Add these secrets:

**Secret: OCI_CONFIG**
```
[DEFAULT]
user=ocid1.user.oc1..aaaaaaaa6tbdlgy2vcmh7tbos6hvvt5r4phsogby6oxbkrfoe4o7qld536ea
fingerprint=<your-fingerprint-from-~/.oci/config>
tenancy=ocid1.tenancy.oc1..aaaaaaaa5frx4pqrno45woojq5rlrl7tyr4rkxy7csdrnbvvatqfaq7kyzha
region=us-phoenix-1
key_file=~/.oci/oci_signing_key.pem
```

**Secret: OCI_SIGNING_KEY**
= Contents of your `C:\Users\rampy\.oci\oci_signing_key.pem` file

### 3. Enable GitHub Actions

Go to: https://github.com/Rampyaaryans/Talkie/actions
Click "I understand my workflows, go ahead and enable them"

### That's it!
The guardian will run every 30 minutes automatically from GitHub's cloud servers.
Even when your PC is completely off.
