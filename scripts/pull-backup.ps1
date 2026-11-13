# SwarmChaser forum backup pull - runs on your backup machine (Windows PowerShell).
# Fetches the forum's /export.json and saves a timestamped copy PLUS a
# latest.json to BOTH drives, so one drive failing never loses the backup:
#   C:\ForumBackups\  (skipper's main drive)
#   D:\ForumBackups\  (skipper's USB drive)
# Best-effort per drive: if a drive is missing or the site is asleep/down,
# it just warns and exits 0 - it never breaks anything else.
#
# Two guards that keep a wipe from eating the backup:
#   1. latest.json is only overwritten when the new export is NOT smaller
#      than the saved one (a wiped site exports seed-only: 2 threads,
#      2 posts, 0 bounties). Timestamped copies are still saved as a record.
#   2. Auto-restore: if the live export looks seed-only but a saved backup
#      has more, the script POSTs that backup straight back to the site's
#      /restore endpoint. A redeploy wipe heals itself within one run
#      (15 minutes) with nobody having to do anything.
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

function Get-BackupCounts($path) {
    try {
        $d = Get-Content $path -Raw | ConvertFrom-Json
        return @{ t = @($d.threads).Count; p = @($d.posts).Count; b = @($d.bounties).Count }
    } catch {
        return $null
    }
}

try {
    # Render free tier sleeps after ~15 min idle; first request can take ~60s to wake it.
    Invoke-WebRequest -Uri $url -OutFile $tmp -TimeoutSec 120 -UseBasicParsing | Out-Null
    $size = (Get-Item $tmp).Length
    if ($size -lt 100) { Write-Warning "Export looked empty ($size bytes) - skipping this run."; exit 0 }
} catch {
    Write-Warning "Forum backup pull failed: $($_.Exception.Message) - skipping this run."
    exit 0
}

$live = Get-BackupCounts $tmp
if (-not $live) { Write-Warning "Could not parse the export - skipping this run."; exit 0 }
Write-Output "Live export: $($live.t) threads, $($live.p) posts, $($live.b) bounties."

foreach ($destDir in @("C:\ForumBackups", "D:\ForumBackups")) {
    try {
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        $dest = Join-Path $destDir "forum-$stamp.json"
        Copy-Item $tmp $dest -Force
        $latestPath = Join-Path $destDir "latest.json"
        $saved = $null
        if (Test-Path $latestPath) { $saved = Get-BackupCounts $latestPath }
        # Guard: only promote to latest.json if the new export is not smaller
        # than what we already saved. A wiped site exports seed-only, which
        # must never clobber a good latest.json (this bit us Nov 13 ~00:36).
        if ((-not $saved) -or (($live.t -ge $saved.t) -and ($live.p -ge $saved.p) -and ($live.b -ge $saved.b))) {
            Copy-Item $tmp $latestPath -Force
            Write-Output "Forum backup saved: $dest ($size bytes)"
        } else {
            Write-Warning "Export is smaller than saved latest ($($saved.t)/$($saved.p)/$($saved.b)) - kept timestamped copy only, latest.json untouched."
        }
    } catch {
        Write-Warning "Could not save to $destDir : $($_.Exception.Message) - other drive may still have it."
    }
}

# Auto-restore: the live site looks wiped (seed-only) but we hold a better
# backup. Push the best saved copy back to /restore so the site heals itself.
$seedOnly = ($live.t -le 2) -and ($live.p -le 2) -and ($live.b -eq 0)
if ($seedOnly) {
    $bestPath = $null
    $bestCounts = $null
    foreach ($destDir in @("C:\ForumBackups", "D:\ForumBackups")) {
        $candidates = @()
        $latestPath = Join-Path $destDir "latest.json"
        if (Test-Path $latestPath) { $candidates += $latestPath }
        $candidates += Get-ChildItem (Join-Path $destDir "forum-*.json") -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -ExpandProperty FullName
        foreach ($cand in $candidates) {
            $c = Get-BackupCounts $cand
            if ($c -and (($c.t -gt $live.t) -or ($c.p -gt $live.p) -or ($c.b -gt $live.b))) {
                if ((-not $bestCounts) -or (($c.t + $c.p + $c.b) -gt ($bestCounts.t + $bestCounts.p + $bestCounts.b))) {
                    $bestPath = $cand
                    $bestCounts = $c
                }
            }
        }
    }
    if ($bestPath) {
        try {
            $r = Invoke-RestMethod -Uri "$forumUrl/restore" -Method Post -ContentType "application/json" -InFile $bestPath -TimeoutSec 120
            Write-Output "Site looked wiped - auto-restored from $bestPath : threads $($r.threads), posts $($r.posts), bounties $($r.bounties)."
        } catch {
            Write-Warning "Auto-restore failed: $($_.Exception.Message) - will retry on the next run."
        }
    } else {
        Write-Warning "Site looked wiped but no better saved backup was found - nothing to restore from."
    }
}

Remove-Item $tmp -Force -ErrorAction SilentlyContinue
