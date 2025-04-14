# Block-Doxbin-Full.ps1
# Blocks Doxbin domains, resolves IPs, blocks IP ranges, creates scheduled task for persistence
# Must be run as Administrator

$ErrorActionPreference = "SilentlyContinue"

Write-Output "`n[+] Starting full-spectrum Doxbin infrastructure block..."

# Define domains
$domains = @(
    "doxbin.com", "www.doxbin.com",
    "doxbin.org", "www.doxbin.org",
    "doxbin.net", "www.doxbin.net"
)

# Block IP range from IPInfo
function Block-IPRange {
    param ($ip, $domain)

    try {
        $whois = Invoke-RestMethod -Uri "https://ipinfo.io/$ip/json"
        $range = $whois.cidr
        $asn = $whois.org

        if ($range) {
            $ruleName = "Block $domain [$range]"
            if (-not (Get-NetFirewallRule -DisplayName $ruleName)) {
                New-NetFirewallRule -DisplayName $ruleName `
                                    -Direction Outbound `
                                    -Action Block `
                                    -RemoteAddress $range `
                                    -Profile Any `
                                    -Enabled True
                Write-Output "[+] Blocked IP range $range for $domain ($asn)"
            } else {
                Write-Output "[=] Firewall rule already exists for $range"
            }
        }
    } catch {
        Write-Warning "[-] Could not retrieve IP info for $ip ($domain)"
    }
}

# Resolve domains and block
foreach ($domain in $domains) {
    try {
        $ips = (Resolve-DnsName $domain | Where-Object { $_.IPv4Address } | Select-Object -ExpandProperty IPv4Address) | Sort-Object -Unique
        foreach ($ip in $ips) {
            Block-IPRange -ip $ip -domain $domain
        }
    } catch {
        Write-Warning "[-] DNS resolution failed for $domain"
    }
}

# Add HOSTS file entries (extra DNS-layer hardening)
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$loopback = "127.0.0.1"

foreach ($domain in $domains) {
    $entry = "$loopback`t$domain"
    if (-not (Select-String -Path $hostsPath -Pattern "$domain" -Quiet)) {
        Add-Content -Path $hostsPath -Value $entry
        Write-Output "[+] HOSTS entry added for $domain"
    } else {
        Write-Output "[=] HOSTS entry already exists for $domain"
    }
}

# Create Scheduled Task to re-run this script every 12 hours
$taskName = "BlockDoxbinNetInfra"
$scriptFullPath = $MyInvocation.MyCommand.Path

try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptFullPath`""
    $trigger1 = New-ScheduledTaskTrigger -Daily -At 12:00AM
    $trigger2 = New-ScheduledTaskTrigger -Daily -At 12:00PM
    Register-ScheduledTask -Action $action -Trigger @($trigger1, $trigger2) -TaskName $taskName -Description "Reinforces Doxbin firewall/IP blocks" -User "SYSTEM" -RunLevel Highest

    Write-Output "[+] Scheduled Task '$taskName' created (12-hour refresh cycle)"
} catch {
    Write-Warning "[-] Failed to create Scheduled Task"
}

Write-Output "`n✅ Doxbin network block initialized and persistent. Recommend verifying firewall rules via Get-NetFirewallRule."
