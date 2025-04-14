# AutoNuke-Doxbin.ps1
# Fully automated Doxbin artifact remover — no user input needed
# Run as administrator

$ErrorActionPreference = "SilentlyContinue"
$domainsToPurge = @("doxbin.com", "doxbin.org", "doxbin.net")

# Ensure sqlite3 is available
$sqlitePath = "$env:TEMP\sqlite3.exe"
if (-not (Test-Path $sqlitePath)) {
    Write-Host "[*] Downloading sqlite3.exe..."
    Invoke-WebRequest -Uri "https://www.sqlite.org/2024/sqlite-tools-win32-x86-3450200.zip" -OutFile "$env:TEMP\sqlite.zip"
    Expand-Archive -Path "$env:TEMP\sqlite.zip" -DestinationPath "$env:TEMP\sqlite" -Force
    Copy-Item "$env:TEMP\sqlite\sqlite-tools-win32-x86-3450200\sqlite3.exe" -Destination $sqlitePath -Force
    Remove-Item "$env:TEMP\sqlite*" -Recurse -Force
}

function Remove-SQLiteEntries {
    param (
        [string]$dbPath,
        [string]$table,
        [string]$column,
        [string[]]$domains
    )
    if (-not (Test-Path $dbPath)) { return }

    foreach ($domain in $domains) {
        $query = "DELETE FROM $table WHERE $column LIKE '%$domain%';"
        Start-Process -FilePath $sqlitePath -ArgumentList "`"$dbPath`" `"$query`"" -Wait -WindowStyle Hidden
    }
}

function Nuke-ChromiumBased {
    $paths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
    )

    foreach ($browserPath in $paths) {
        if (-not (Test-Path $browserPath)) { continue }

        $procName = ($browserPath -split "\\")[2]
        Stop-Process -Name $procName -Force -ErrorAction SilentlyContinue

        $cookieDB = Join-Path $browserPath "Network\Cookies"
        $localStorage = Join-Path $browserPath "Local Storage\leveldb"
        $sessionStorage = Join-Path $browserPath "Session Storage\leveldb"
        $indexedDb = Join-Path $browserPath "IndexedDB"
        $serviceWorkers = Join-Path $browserPath "Service Worker"

        Remove-SQLiteEntries -dbPath $cookieDB -table "cookies" -column "host_key" -domains $domainsToPurge

        foreach ($domain in $domainsToPurge) {
            Get-ChildItem $localStorage, $sessionStorage -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$domain*" } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

            Get-ChildItem $indexedDb, $serviceWorkers -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like "*$domain*" } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

function Nuke-Firefox {
    $profiles = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory
    foreach ($profile in $profiles) {
        $cookies = Join-Path $profile.FullName "cookies.sqlite"
        $storage = Join-Path $profile.FullName "storage\default"
        Remove-SQLiteEntries -dbPath $cookies -table "moz_cookies" -column "host" -domains $domainsToPurge

        foreach ($domain in $domainsToPurge) {
            Get-ChildItem $storage -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like "*$domain*" } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    Stop-Process -Name "firefox" -Force -ErrorAction SilentlyContinue
}

Write-Host "`n[+] Starting full browser-level purge of all Doxbin artifacts..."
Nuke-ChromiumBased
Nuke-Firefox
Write-Host "`n✅ Cleanup complete. All browser data related to Doxbin domains has been purged."
