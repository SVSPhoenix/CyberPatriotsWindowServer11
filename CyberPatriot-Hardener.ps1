# ==============================================================================
# CYBERPATRIOT MASTER WINDOWS SERVER HARDENING SCRIPT
# ==============================================================================

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
# 7. SCAN FOR PROHIBITED MEDIA & UNAUTHORIZED FILES
# ------------------------------------------------------------------------------
Write-Host "[+] Scanning system for unauthorized media and prohibited files..." -ForegroundColor Yellow
$mediaExtensions = @("*.mp3", "*.mp4", "*.avi", "*.mkv", "*.mov", "*.wav", "*.flac", "*.wma", "*.png", "*.jpg", "*.jpeg", "*.gif", "*.bmp", "*.torrent")
$hackingTools = @("*wireshark*", "*cain*", "*john*", "*nmap*", "*ophcrack*", "*keylogger*", "*mimikatz*")

$logPath = "$env:USERPROFILE\Desktop\Prohibited_Files_Found.txt"
"--- CYBERPATRIOT PROHIBITED FILES AUDIT LOG ---`n" | Out-File -FilePath $logPath

$foundFiles = Get-ChildItem -Path "C:\" -Recurse -Include $mediaExtensions -ErrorAction SilentlyContinue | 
    Where-Object { $_.FullName -notmatch "C:\\Users\\.*\\Desktop" -and $_.FullName -notmatch "C:\\Windows\\System32" }

$foundTools = Get-ChildItem -Path "C:\Users", "C:\Program Files", "C:\Program Files (x86)" -Recurse -Include $hackingTools -ErrorAction SilentlyContinue

if ($foundFiles) {
    Write-Host "    Found $(($foundFiles).Count) prohibited media files!" -ForegroundColor Red
    $foundFiles | Select-Object FullName, Length | Out-File -FilePath $logPath -Append
} else {
    Write-Host "    No prohibited media files found outside Desktop." -ForegroundColor Green
}

if ($foundTools) {
    Write-Host "    Found suspicious security tools!" -ForegroundColor Red
    $foundTools | Select-Object FullName | Out-File -FilePath $logPath -Append
}

Write-Host "=========================================" -ForegroundColor Green
Write-Host "All Hardening Tasks Completed Successfully!" -ForegroundColor Green
Write-Host "Check Desktop for Prohibited_Files_Found.txt" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
