# SwarmChaser forum backup pull — runs on your backup machine (Windows PowerShell).
# Fetches the forum's /export.json and saves a timestamped copy to the
# USB drive (D:\ForumBackups\). Best-effort:
# if the drive is unplugged or the site is asleep/down, it just warns
# and exits 0 — it never breaks anything else.
#
# Set these two before first use (or pass them in):
#   $env:FORUM_URL    = "https://<your-service>.onrender.com"   # no trailing slash
#   $env:BACKUP_TOKEN  = "<value>"   # only if BACKUP_TOKEN is set on Render; otherwise leave unset
#
# Schedule it with Task Scheduler, e.g. daily at 04:30, as:
#   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\pull-backup.ps1"

$ErrorActionPreference = 'Stop'

$forumUrl = $env:FORUM_URL
if (-not $forumUrl) { Write-Warning "FORUM_URL not set — set `$env:FORUM_URL to the Render URL and re-run."; exit 0 }
$forumUrl = $forumUrl.TrimEnd('/')

$destDir = "D:\ForumBackups"
if (-not (Test-Path $destDir)) {
    Write-Warning "Backup drive not available ($destDir missing) — skipping this run."
    exit 0
}

$url = "$forumUrl/export.json"
if ($env:BACKUP_TOKEN) { $url += "?token=" + [uri]::EscapeDataString($env:BACKUP_TOKEN) }

$stamp = (Get-Date).ToString("yyyy-MM-dd-HHmm")
$dest = Join-Path $destDir "forum-$stamp.json"

try {
    # Render free tier sleeps after ~15 min idle; first request can take ~60s to wake it.
    Invoke-WebRequest -Uri $url -OutFile $dest -TimeoutSec 120 -UseBasicParsing | Out-Null
    $size = (Get-Item $dest).Length
    Write-Output "Forum backup saved: $dest ($size bytes)"
} catch {
    Write-Warning "Forum backup pull failed: $($_.Exception.Message) — skipping this run."
    if (Test-Path $dest) { Remove-Item $dest -Force }
    exit 0
}
