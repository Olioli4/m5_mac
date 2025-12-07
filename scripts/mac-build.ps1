# Mac Remote Build Script for m5_mac
# Usage: .\scripts\mac-build.ps1

$MAC_HOST = "mac-build"
$REMOTE_DIR = "~/Code/m5_mac"
$FLUTTER = "/Users/oli/developp/flutter/bin/flutter"
$LOCAL_DIR = $PSScriptRoot | Split-Path -Parent

Write-Host "=== M5 MAC - Remote macOS Build ===" -ForegroundColor Cyan

# Step 1: Clone/pull from git on Mac
Write-Host "`n[1/4] Syncing code via git..." -ForegroundColor Yellow

# First, commit and push any local changes
Write-Host "  Pushing local changes..." -ForegroundColor Gray
Push-Location $LOCAL_DIR
git add -A
git commit -m "Build sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 2>$null
git push 2>&1 | Out-Null
Pop-Location

# Clone or pull on Mac
ssh $MAC_HOST "if [ -d ~/Code/m5_mac/.git ]; then cd ~/Code/m5_mac && git pull; else mkdir -p ~/Code && cd ~/Code && git clone https://github.com/Olioli4/m5_mac.git; fi"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to sync files" -ForegroundColor Red
    exit 1
}

# Step 2: Run flutter pub get
Write-Host "`n[2/4] Installing dependencies..." -ForegroundColor Yellow
ssh $MAC_HOST "export PATH=/usr/local/bin:`$PATH && cd $REMOTE_DIR && $FLUTTER pub get"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to get dependencies" -ForegroundColor Red
    exit 1
}

# Step 3: Build macOS app
Write-Host "`n[3/4] Building macOS app..." -ForegroundColor Yellow
ssh $MAC_HOST "export PATH=/usr/local/bin:`$PATH && cd $REMOTE_DIR && $FLUTTER build macos --release"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Build failed" -ForegroundColor Red
    exit 1
}

# Step 4: Copy DMG back (optional - create DMG first)
Write-Host "`n[4/4] Creating DMG and downloading..." -ForegroundColor Yellow
# Step 4: Copy DMG back (optional - create DMG first)
Write-Host "`n[4/4] Creating DMG and downloading..." -ForegroundColor Yellow
ssh $MAC_HOST "cd ~/Code/m5_mac/build/macos/Build/Products/Release && rm -rf dmg_contents m5_mac.dmg 2>/dev/null && mkdir -p dmg_contents && cp -R m5_mac.app dmg_contents/ && hdiutil create -volname 'M5 MAC' -srcfolder dmg_contents -ov -format UDZO m5_mac.dmg"

# Create local output directory
$outputDir = "$LOCAL_DIR\build\macos-remote"
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

# Download DMG
scp "mac-build:~/Code/m5_mac/build/macos/Build/Products/Release/m5_mac.dmg" "$outputDir\"

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n=== Build Complete! ===" -ForegroundColor Green
    Write-Host "DMG location: $outputDir\m5_mac.dmg" -ForegroundColor Cyan
    explorer $outputDir
} else {
    Write-Host "`nBuild complete on Mac. DMG download failed." -ForegroundColor Yellow
    Write-Host "You can manually copy from: mac-build:~/Code/m5_mac/build/macos/Build/Products/Release/m5_mac.dmg"
}
