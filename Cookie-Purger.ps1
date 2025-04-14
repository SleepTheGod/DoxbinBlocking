# Full Doxbin Domain Blocker + Cookie/Data Purger for Windows 10/11
# Run as Administrator

$ErrorActionPreference = "SilentlyContinue"
$domains = @("doxbin.com", "doxbin.org", "doxbin.net", "www.doxbin.com", "www.doxbin.org", "www.doxbin.net")
$shortDomains = @("doxbin.com", "doxbin.org", "doxbin.net")

# --- HOSTS File Blocking ---
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$loopback = "127.0.0.1"

foreach ($domain in $domains) {
    $entry = "$loopback`t$domain"
    if (-not (Select-String -Path $hostsPath -Pattern "$domain" -Quiet)) {
        Add-Content -Path $hostsPath -Value $entry
    }
}

# --- Firewall Blocking ---
foreach ($domain in $domains) {
    $ruleName = "Block $domain"
    try {
        $ips = (Resolve-DnsName $domain | Where-Object { $_.IPv4Address } | Select-Object -ExpandProperty IPv4Address) | Sort-Object -Unique
    } catch {
        continue
    }

    foreach ($ip in $ips) {
        $ipRuleName = "$ruleName [$ip]"
        if (-not (Get-NetFirewallRule -DisplayName $ipRuleName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $ipRuleName `
                                -Direction Outbound `
                                -Action Block `
                                -RemoteAddress $ip `
                                -Profile Any `
                                -Enabled True
        }
    }
}

# --- Download sqlite3 ---
$sqlitePath = "$env:TEMP\sqlite3.exe"
if (-not (Test-Path $sqlitePath)) {
    Invoke-WebRequest -Uri "https://www.sqlite.org/2024/sqlite-tools-win32-x86-3450200.zip" -OutFile "$env:TEMP\sqlite.zip"
    Expand-Archive -Path "$env:TEMP\sqlite.zip" -DestinationPath "$env:TEMP\sqlite" -Force
    Copy-Item "$env:TEMP\sqlite\sqlite-tools-win32-x86-3450200\sqlite3.exe" -Destination $sqlitePath -Force
    Remove-Item "$env:TEMP\sqlite*" -Recurse -Force
}

# --- Kill Browsers ---
Stop-Process -Name "chrome","msedge","brave","firefox" -Force -ErrorAction SilentlyContinue

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

function Clean-Chromium {
    $paths = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default"
    )

    foreach ($path in $paths) {
        if (-not (Test-Path $path)) { continue }

        $cookieDB = Join-Path $path "Network\Cookies"
        $localStorage = Join-Path $path "Local Storage\leveldb"
        $sessionStorage = Join-Path $path "Session Storage\leveldb"
        $indexedDb = Join-Path $path "IndexedDB"
        $serviceWorkers = Join-Path $path "Service Worker"
        $cache = Join-Path $path "Cache"

        Remove-SQLiteEntries -dbPath $cookieDB -table "cookies" -column "host_key" -domains $shortDomains

        foreach ($domain in $shortDomains) {
            Get-ChildItem $localStorage, $sessionStorage, $cache -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "*$domain*" } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

            Get-ChildItem $indexedDb, $serviceWorkers -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like "*$domain*" } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

function Clean-Firefox {
    $profiles = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory
    foreach ($profile in $profiles) {
        $cookies = Join-Path $profile.FullName "cookies.sqlite"
        $localStorage = Join-Path $profile.FullName "storage\default"
        $sessionStorage = Join-Path $profile.FullName "storage\default"
        $cache = Join-Path $profile.FullName "cache2"

        Remove-SQLiteEntries -dbPath $cookies -table "moz_cookies" -column "host" -domains $shortDomains

        foreach ($domain in $shortDomains) {
            Get-ChildItem $localStorage, $sessionStorage, $cache -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like "*$domain*" } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}

Clean-Chromium
Clean-Firefox

Write-Host "`n✅ Doxbin domains and all related artifacts (including session cookies, local storage, cache, and service workers) have been blocked and purged."
