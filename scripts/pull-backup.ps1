# SwarmChaser forum backup pull - runs on your backup machine (Windows PowerShell).
# Fetches the forum's /export.json and saves a timestamped copy PLUS a
# latest.json to BOTH drives, so one drive failing never loses the backup:
#   C:\ForumBackups\  (skipper's main drive)
#   D:\ForumBackups\  (skipper's USB drive)
# Best-effort per drive: if a drive is missing or the site is asleep/down,
# it just warns and exits 0 - it never breaks anything else.
#
# Set these before first use (or pass them in):
#   $env:FORUM_URL    = "https://swarmchaser.onrender.com"   # no trailing slash
#   $env:BACKUP_TOKEN  = "<value>"   # only if BACKUP_TOKEN is set on Render; otherwise leave unset
#
# Schedule it with Task Scheduler, e.g. every 15 minutes, as:
#   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\reedk\pull-backup.ps1"

$ErrorActionPreference = 'Stop'

$forumUrl = $env:FORUM_URL
if (-not $forumUrl) { $forumUrl = "https://swarmchaser.onrender.com" }
$forumUrl = $forumUrl.TrimEnd('/')

$url = "$forumUrl/export.json"
if ($env:BACKUP_TOKEN) { $url += "?token=" + [uri]::EscapeDataString($env:BACKUP_TOKEN) }

$stamp = (Get-Date).ToString("yyyy-MM-dd-HHmm")
$tmp = Join-Path $env:TEMP "forum-backup-$stamp.json"

try {
    # Render free tier sleeps after ~15 min idle; first request can take ~60s to wake it.
    Invoke-WebRequest -Uri $url -OutFile $tmp -TimeoutSec 120 -UseBasicParsing | Out-Null
    $size = (Get-Item $tmp).Length
    if ($size -lt 100) { Write-Warning "Export looked empty ($size bytes) - skipping this run."; exit 0 }
} catch {
    Write-Warning "Forum backup pull failed: $($_.Exception.Message) - skipping this run."
    exit 0
}

foreach ($destDir in @("C:\ForumBackups", "D:\ForumBackups")) {
    try {
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        $dest = Join-Path $destDir "forum-$stamp.json"
        Copy-Item $tmp $dest -Force
        Copy-Item $tmp (Join-Path $destDir "latest.json") -Force
        Write-Output "Forum backup saved: $dest ($size bytes)"
    } catch {
        Write-Warning "Could not save to $destDir : $($_.Exception.Message) - other drive may still have it."
    }
}
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
