# CareLoop dev-server + Cloudflare tunnel watchdog.
# Runs on a schedule (see register-watchdog.ps1); self-heals the backend and the public tunnel
# within a couple of minutes of either dying (machine sleep, network blip, tunnel edge drop) so a
# manual restart is no longer the only way back online.
#
# Known limitation this script does NOT solve: a free Cloudflare "quick tunnel" gets a brand-new
# random hostname every time it's restarted -- there is no way to keep the same URL without a real
# Cloudflare account + owned domain. So any already-built APK will still need rebuilding whenever
# the tunnel actually has to restart; this script only shrinks how long the backend stays dark and
# how often a human has to notice and intervene.

$repoRoot = "C:\Users\varad\CareLoop"
$scriptsDir = "$repoRoot\scripts"
$logFile = "$scriptsDir\watchdog.log"
$urlFile = "$scriptsDir\current_tunnel_url.txt"
$cloudflaredExe = "C:\devtools\cloudflared\cloudflared.exe"
$cloudflaredLog = "$scriptsDir\cloudflared_current.log"

function Write-Log($msg) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
  Add-Content -Path $logFile -Value $line
}

function Test-Url($url, $timeoutSec = 12) {
  try {
    $resp = Invoke-WebRequest -Uri $url -TimeoutSec $timeoutSec -UseBasicParsing
    return $resp.StatusCode -eq 200
  } catch {
    return $false
  }
}

# --- Backend ---
if (-not (Test-Url "http://localhost:4000/api/health")) {
  Write-Log "backend DOWN -- restarting npm run dev:server"
  Start-Process -FilePath "cmd.exe" `
    -ArgumentList "/c cd /d $repoRoot && npm run dev:server >> $scriptsDir\server.log 2>&1" `
    -WindowStyle Hidden
  Start-Sleep -Seconds 10
  if (Test-Url "http://localhost:4000/api/health") {
    Write-Log "backend back up"
  } else {
    Write-Log "backend still not responding after restart attempt"
  }
}

# --- Tunnel ---
$tunnelOk = $false
if (Test-Path $urlFile) {
  $savedUrl = (Get-Content $urlFile -Raw).Trim()
  if ($savedUrl -and (Test-Url "$savedUrl/api/health")) {
    $tunnelOk = $true
  }
}

if (-not $tunnelOk) {
  Write-Log "tunnel DOWN or URL unverified -- restarting cloudflared"
  Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  Remove-Item $cloudflaredLog -ErrorAction SilentlyContinue

  Start-Process -FilePath $cloudflaredExe `
    -ArgumentList "tunnel --protocol http2 --url http://localhost:4000" `
    -RedirectStandardError $cloudflaredLog `
    -WindowStyle Hidden

  $newUrl = $null
  for ($i = 0; $i -lt 8 -and -not $newUrl; $i++) {
    Start-Sleep -Seconds 2
    if (Test-Path $cloudflaredLog) {
      # Anchor to the boxed "Your quick Tunnel has been created" banner line specifically --
      # a loose match-anywhere-in-log regex can grab cloudflared's internal provisioning API
      # host (e.g. api.trycloudflare.com) if it gets logged before the real banner, which is
      # not a real per-tunnel hostname and will never resolve -- causing an immediate false
      # "tunnel down" on the next check and needless re-restart.
      $match = Select-String -Path $cloudflaredLog -Pattern "^\d.*\|\s+(https://(?!api\.)[a-z0-9-]+\.trycloudflare\.com)\s+\|" | Select-Object -Last 1
      if ($match) {
        $newUrl = $match.Matches[0].Groups[1].Value
      }
    }
  }

  if ($newUrl) {
    Set-Content -Path $urlFile -Value $newUrl
    Write-Log "tunnel restarted: $newUrl (rebuild any APK before installing -- old URL is dead)"
  } else {
    Write-Log "tunnel restart did not produce a URL within timeout -- check $cloudflaredLog"
  }
}
