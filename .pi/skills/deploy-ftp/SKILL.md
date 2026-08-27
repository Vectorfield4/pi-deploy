---
name: deploy-ftp
description: "Downloads the latest release zip from GitHub and uploads to the server via FTP."
---

# Deploy FTP

Downloads latest release artifact from GitHub Releases and uploads to production server via FTP.

## Instructions

### 1. Find latest release
- `gh release list --limit 1 --repo <repo>`
- If no releases → block: "No GitHub Releases found. Create a release first."

### 2. Download release zip
- `gh release view <tag> --json assets` → get `.zip` asset URL
- `curl -L -o /tmp/<project>-<tag>.zip "<asset_url>"`
- Verify: `file /tmp/<project>-<tag>.zip`

### 3. Extract
- `mkdir -p /tmp/<project>-deploy && unzip /tmp/<project>-<tag>.zip -d /tmp/<project>-deploy`

### 4. Upload to FTP
- `lftp -u $FTP_USER,$FTP_PASS $FTP_HOST -e "set cmd:parallel 5; mirror --reverse --delete --exclude '.git/' --exclude 'node_modules/' --exclude '.cache/' --exclude '*.map' /tmp/<project>-deploy/ ./public; quit"`

### 5. Cleanup
- `rm -rf /tmp/<project>-<tag>.zip /tmp/<project>-deploy || true`
- Cleanup is best-effort. A failed `rm` does not fail the deploy.

## Verification
- Latest release found
- Zip downloaded and extracted
- Files uploaded to FTP
- Temp files cleaned up
