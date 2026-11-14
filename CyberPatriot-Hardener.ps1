# ==============================================================================
# CYBERPATRIOT MASTER WINDOWS SERVER HARDENING SCRIPT
# ==============================================================================
# ==============================================================================
# CYBERPATRIOT MASTER WINDOWS SERVER HARDENING SCRIPT
# ==============================================================================

# 0. ADMINISTRATOR PRIVILEGE CHECK
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "==========================================================" -ForegroundColor Red
    Write-Host "[ERROR] ACCESS DENIED: You are not running as Administrator!" -ForegroundColor Red
    Write-Host "Please close this window, right-click the script, and select 'Run as administrator'." -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Red
    Pause
    Exit
}

# 1. DEFINE HELPER FUNCTION (Must be placed before any Invoke-SafeStep calls)
function Invoke-SafeStep {
    param (
        [string]$StepName,
        [scriptblock]$Action
    )
    Write-Host "[+] $StepName..." -ForegroundColor Yellow
    try {
        $ErrorActionPreference = "Stop"
        & $Action
        Write-Host "    [OK] $StepName succeeded." -ForegroundColor Green
    }
    catch [System.UnauthorizedAccessException] {
        Write-Host "    [ACCESS DENIED] Insufficient permissions for: $StepName" -ForegroundColor Red
    }
    catch {
        Write-Host "    [WARNING] Could not complete $StepName - $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
    finally {
        $ErrorActionPreference = "Continue"
    }
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Starting Master CyberPatriot Hardening..." -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# --- YOUR HARDENING STEPS GO HERE ---
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Starting Master CyberPatriot Hardening..." -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. ACCOUNT POLICIES (Password & Lockout Settings)
# ------------------------------------------------------------------------------
Write-Host "[+] Configuring Account Policies..." -ForegroundColor Yellow
net accounts /minpwlen:10 /maxpwage:90 /minpwage:1 /uniquepw:5
net accounts /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30

# ------------------------------------------------------------------------------
# 2. FIREWALL CONFIGURATION
# ------------------------------------------------------------------------------
Write-Host "[+] Enabling Windows Firewall..." -ForegroundColor Yellow
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# ------------------------------------------------------------------------------
# 3. DISABLE INSECURE / UNWANTED SERVICES
# ------------------------------------------------------------------------------
Write-Host "[+] Disabling Insecure Services..." -ForegroundColor Yellow
$servicesToDisable = @("Telnet", "RemoteRegistry", "SNMP", "XboxGipSvc", "XblAuthManager")
foreach ($svc in $servicesToDisable) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled
        Write-Host "    Disabled service: $svc"
    }
}

# ------------------------------------------------------------------------------
# 4. SECURITY OPTIONS & REGISTRY TWEAKS
# ------------------------------------------------------------------------------
Write-Host "[+] Applying Registry & Security Options..." -ForegroundColor Yellow

# Disable Guest account
Disable-LocalUser -Name "Guest" -ErrorAction SilentlyContinue

# Limit local use of blank passwords to console only
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LimitBlankPasswordUse" -Value 1

# Disable autorun/autoplay
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 255

# Enable UAC (User Account Control) to highest level
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 2

# ------------------------------------------------------------------------------
# 5. FIX SERVER MANAGER & REMOTE MANAGEMENT ISSUES
# ------------------------------------------------------------------------------
Write-Host "[+] Repairing Server Manager and WinRM Services..." -ForegroundColor Yellow
if (Get-Service -Name "WinRM" -ErrorAction SilentlyContinue) {
    Set-Service -Name "WinRM" -StartupType Automatic
    Restart-Service -Name "WinRM" -Force -ErrorAction SilentlyContinue
    Write-Host "    WinRM service reset and configured."
}
winrm quickconfig -q 2>$null

Write-Host "[+] Verifying WMI Repository..." -ForegroundColor Yellow
winmgmt /salvagerepository 2>$null

Get-ScheduledTask -TaskName "*ServerManager*" -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue

# ------------------------------------------------------------------------------
# 6. ENFORCE PASSWORD COMPLEXITY & DISABLE REVERSIBLE ENCRYPTION
# ------------------------------------------------------------------------------
Write-Host "[+] Configuring Password Complexity and Security Policy..." -ForegroundColor Yellow
$secPolFile = "$env:TEMP\secpol.cfg"
secedit /export /cfg $secPolFile

# Modify local security template values
(Get-Content $secPolFile) -replace 'PasswordComplexity = 0', 'PasswordComplexity = 1' | Set-Content $secPolFile
(Get-Content $secPolFile) -replace 'ClearTextPassword = 1', 'ClearTextPassword = 0' | Set-Content $secPolFile

# Re-apply the policy
secedit /configure /db "$env:windir\security\local.sdb" /cfg $secPolFile /areas SECURITYPOLICY
Remove-Item $secPolFile -ErrorAction SilentlyContinue
Write-Host "    Password complexity enabled and reversible encryption disabled."

# ------------------------------------------------------------------------------
# 7. SCAN FOR PROHIBITED MEDIA & UNAUTHORIZED FILES (FULL PATHS)
# ------------------------------------------------------------------------------
Write-Host "[+] Scanning user profiles for unauthorized media..." -ForegroundColor Yellow
$mediaExtensions = @("*.mp3", "*.mp4", "*.avi", "*.mkv", "*.mov", "*.wav", "*.flac", "*.wma", "*.png", "*.jpg", "*.jpeg", "*.gif", "*.bmp", "*.torrent")
$hackingTools = @("*wireshark*", "*cain*", "*john*", "*nmap*", "*ophcrack*", "*keylogger*", "*mimikatz*")

$logPath = "$env:USERPROFILE\Desktop\Prohibited_Files_Found.txt"
"--- CYBERPATRIOT PROHIBITED FILES AUDIT LOG ---`n" | Out-File -FilePath $logPath -Encoding UTF8

# Restrict search to C:\Users (excluding AppData and Desktop)
$foundFiles = Get-ChildItem -Path "C:\Users" -Recurse -Include $mediaExtensions -ErrorAction SilentlyContinue | 
    Where-Object { 
        $_.FullName -notmatch "\\AppData\\" -and 
        $_.FullName -notmatch "\\Desktop\\" 
    }

$foundTools = Get-ChildItem -Path "C:\Users", "C:\Program Files", "C:\Program Files (x86)" -Recurse -Include $hackingTools -ErrorAction SilentlyContinue

if ($foundFiles) {
    Write-Host "    [FOUND] $(($foundFiles).Count) prohibited media files:" -ForegroundColor Red
    "=== PROHIBITED MEDIA FILES ===" | Out-File -FilePath $logPath -Append -Encoding UTF8
    foreach ($file in $foundFiles) {
        $sizeKB = [math]::Round($file.Length / 1KB, 1)
        $entry = "$($file.FullName)  [$sizeKB KB]"
        Write-Host "      -> $entry" -ForegroundColor Gray
        $entry | Out-File -FilePath $logPath -Append -Encoding UTF8
    }
} else {
    Write-Host "    [OK] No prohibited user media found." -ForegroundColor Green
}

if ($foundTools) {
    Write-Host "    [FOUND] $(($foundTools).Count) suspicious security tools:" -ForegroundColor Red
    "`n=== SUSPICIOUS TOOLS ===" | Out-File -FilePath $logPath -Append -Encoding UTF8
    foreach ($tool in $foundTools) {
        Write-Host "      -> $($tool.FullName)" -ForegroundColor Gray
        $tool.FullName | Out-File -FilePath $logPath -Append -Encoding UTF8
    }
}
# ------------------------------------------------------------------------------
# 8. ADVANCED AUDIT POLICIES
# ------------------------------------------------------------------------------
Invoke-SafeStep -StepName "Configuring Advanced Audit Policies" -Action {
    auditpol /set /subcategory:"Computer Account Management" /success:enable /failure:enable | Out-Null
    auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable | Out-Null
    auditpol /set /subcategory:"Certification Services" /success:enable /failure:enable | Out-Null
}

# ------------------------------------------------------------------------------
# 9. RDP & REMOTE DESKTOP HARDENING
# ------------------------------------------------------------------------------
Invoke-SafeStep -StepName "Securing RDP (NLA & TLS)" -Action {
    # Require Network Level Authentication (NLA)
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
    
    # Require specific security layer (TLS / SSL)
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "SecurityLayer" -Value 2
}

# ------------------------------------------------------------------------------
# 10. SMB PROTOCOL & NETWORK SECURITY HARDENING
# ------------------------------------------------------------------------------
Invoke-SafeStep -StepName "Hardening SMB & Authentication Rate Limiting" -Action {
    # Ensure registry paths exist before setting values
    $lanmanServerPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanServer"
    $lanmanWorkstationPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation"
    
    if (-not (Test-Path $lanmanServerPolicy)) { New-Item -Path $lanmanServerPolicy -Force | Out-Null }
    if (-not (Test-Path $lanmanWorkstationPolicy)) { New-Item -Path $lanmanWorkstationPolicy -Force | Out-Null }

    # SMB over QUIC
    Set-ItemProperty -Path $lanmanServerPolicy -Name "EnableSMBQUIC" -Value 1
    Set-ItemProperty -Path $lanmanWorkstationPolicy -Name "EnableSMBQUIC" -Value 1

    # Block NTLM
    Set-ItemProperty -Path $lanmanWorkstationPolicy -Name "BlockNTLM" -Value 1

    # Minimum SMB Version 3.0.0+
    Set-ItemProperty -Path $lanmanServerPolicy -Name "MinSmb2Dialect" -Value 300

    # Authentication Rate Limiter & 2-second delay
    Set-ItemProperty -Path $lanmanServerPolicy -Name "EnableAuthRateLimiter" -Value 1
    Set-ItemProperty -Path $lanmanServerPolicy -Name "InvalidAuthenticationDelayTimeInMs" -Value 2000
}

# ------------------------------------------------------------------------------
# 11. DEFENDER ASR RULES & VIRTUALIZATION-BASED SECURITY (VBS)
# ------------------------------------------------------------------------------
Invoke-SafeStep -StepName "Enabling Defender ASR Rules & VBS" -Action {
    # Block Webshell creation for Servers ASR rule
    Add-MpPreference -AttackSurfaceReductionRules_Ids "a8f5898e-1dc8-49a9-9878-85004b8a61e6" -AttackSurfaceReductionRules_Actions Enabled -ErrorAction SilentlyContinue

    # VBS Mandatory Mode
    $deviceGuardPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
    if (-not (Test-Path $deviceGuardPath)) { New-Item -Path $deviceGuardPath -Force | Out-Null }
    Set-ItemProperty -Path $deviceGuardPath -Name "Mandatory" -Value 1

    # Machine Identity Isolation
    $policyDeviceGuard = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"
    if (-not (Test-Path $policyDeviceGuard)) { New-Item -Path $policyDeviceGuard -Force | Out-Null }
    Set-ItemProperty -Path $policyDeviceGuard -Name "MachineIdentityIsolation" -Value 2
}

# ------------------------------------------------------------------------------
# 12. DISABLE POWERSHELL 2.0
# ------------------------------------------------------------------------------
Invoke-SafeStep -StepName "Removing PowerShell 2.0 Optional Feature" -Action {
    Disable-WindowsOptionalFeature -Online -FeatureName "MicrosoftWindowsPowerShellV2" -Remove -ErrorAction SilentlyContinue | Out-Null
}

# ------------------------------------------------------------------------------
# 13. TARGETED CLEANUP OF KNOWN MALICIOUS ARTIFACTS
# ------------------------------------------------------------------------------
Invoke-SafeStep -StepName "Cleaning Known Malicious Startup & Password Files" -Action {
    # Remove bad startup scripts if present
    $badStartupScript = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\uwu.ps1"
    if (Test-Path $badStartupScript) {
        Remove-Item -Path $badStartupScript -Force -ErrorAction SilentlyContinue
        Write-Host "    [REMOVED] Malicious startup script uwu.ps1" -ForegroundColor Green
    }

    # Search and remove plaintext password files in user folders
    Get-ChildItem -Path "C:\Users" -Filter "passwords.txt" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "    [REMOVED] Plaintext password file: $($_.FullName)" -ForegroundColor Green
    }
}
