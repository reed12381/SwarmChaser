# SwarmChaser forum restore - pushes a backup file back to the site after
# a wipe, so the site can read it again. Uses the newest backup it can find:
#   C:\ForumBackups\latest.json, then D:\ForumBackups\latest.json
# Run it on skipper after a Render redeploy wipes the forum DB:
#   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\reedk\restore-backup.ps1"
# Set $env:FORUM_URL / $env:BACKUP_TOKEN the same way as pull-backup.ps1.

$ErrorActionPreference = 'Stop'

$forumUrl = $env:FORUM_URL
if (-not $forumUrl) { $forumUrl = "https://swarmchaser.onrender.com" }
$forumUrl = $forumUrl.TrimEnd('/')

$src = $null
foreach ($cand in @("C:\ForumBackups\latest.json", "D:\ForumBackups\latest.json")) {
    if (Test-Path $cand) { $src = $cand; break }
}
if (-not $src) { Write-Warning "No backup found in C:\ForumBackups or D:\ForumBackups."; exit 0 }

$url = "$forumUrl/restore"
if ($env:BACKUP_TOKEN) { $url += "?token=" + [uri]::EscapeDataString($env:BACKUP_TOKEN) }

try {
    $resp = Invoke-WebRequest -Uri $url -Method Post -ContentType 'application/json' -InFile $src -TimeoutSec 120 -UseBasicParsing
    Write-Output "Restore sent from $src : $($resp.Content)"
} catch {
    Write-Warning "Restore failed: $($_.Exception.Message)"
    exit 0
}
