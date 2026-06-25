#Requires -Version 5.1
<#
.SYNOPSIS
    Install and register a Forgejo Actions runner as a Windows service.

.DESCRIPTION
    The Windows counterpart to `forgejo-node runner` (a bash command that
    can register a Windows runner but cannot install a *native* Windows
    service, since there is no systemd/launchd there). This script:

      1. downloads the forgejo-runner.exe binary,
      2. registers the runner against a Forgejo instance with the label
         preset for the chosen platform,
      3. installs it as a service so it survives reboots, and
      4. starts it.

    Jobs run on the Windows host via the runner's 'host' backend
    (-Platform windows), or in containers via the 'docker' backend when
    Docker Desktop is present (-Platform docker). The label presets match
    those emitted by `forgejo-node runner platforms`.

    For the service, nssm (https://nssm.cc/) is used when available
    because forgejo-runner is a console application; otherwise the script
    falls back to a Scheduled Task that runs at startup.

.PARAMETER InstanceUrl
    Base URL of the Forgejo instance, e.g. https://git.example.org

.PARAMETER Token
    Runner registration token (Site / Org / Repo -> Settings -> Actions
    -> Runners -> Create new runner).

.PARAMETER Platform
    Label preset: 'windows' (host backend, default), 'docker'
    (containers, needs Docker Desktop), or 'host' (generic host backend).

.PARAMETER Labels
    Explicit label list (comma-separated), overriding -Platform. Example:
    "windows:host,windows-2022:host,self-hosted:host"

.PARAMETER Name
    Runner name shown in the instance UI. Defaults to the computer name.

.PARAMETER Version
    forgejo-runner version to download. Default: 6.3.1

.PARAMETER InstallDir
    Where to place forgejo-runner.exe. Default: %ProgramFiles%\forgejo-runner

.PARAMETER WorkDir
    Working directory holding the .runner credential and config.yaml.
    Default: %ProgramData%\forgejo-runner

.PARAMETER NoService
    Register and configure only; do not install/start a service.

.EXAMPLE
    .\Install-ForgejoRunner.ps1 -InstanceUrl https://git.example.org `
        -Token XXXX -Platform windows

.EXAMPLE
    # Docker backend, custom name, explicit labels
    .\Install-ForgejoRunner.ps1 -InstanceUrl https://git.example.org `
        -Token XXXX -Labels "docker:docker://node:20-bookworm" -Name win-ci-1

.NOTES
    Run from an elevated PowerShell prompt (Administrator). See the
    matching Unix command in forgejo-node-runner(1).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $InstanceUrl,
    [Parameter(Mandatory = $true)] [string] $Token,
    [ValidateSet('windows', 'docker', 'host')] [string] $Platform = 'windows',
    [string] $Labels = '',
    [string] $Name = $env:COMPUTERNAME,
    [string] $Version = '6.3.1',
    [string] $InstallDir = (Join-Path $env:ProgramFiles 'forgejo-runner'),
    [string] $WorkDir = (Join-Path $env:ProgramData 'forgejo-runner'),
    [switch] $NoService
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- helpers -----------------------------------------------------------------

function Write-Info  { param([string] $Msg) Write-Host "forgejo-runner: $Msg" -ForegroundColor Cyan }
function Write-Warn2 { param([string] $Msg) Write-Warning "forgejo-runner: $Msg" }

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must be run from an elevated (Administrator) PowerShell prompt.'
    }
}

function Get-RunnerArch {
    switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'amd64' }
        'ARM64' { 'arm64' }
        default { throw "Unsupported processor architecture: $($env:PROCESSOR_ARCHITECTURE)" }
    }
}

# Label presets — kept in lockstep with libexec/forgejo-node/runner
# (platform_labels) so a Windows runner advertises the same labels as the
# Unix command would.
function Get-PlatformLabels {
    param([string] $Plat)
    $image = if ($env:FORGEJO_RUNNER_IMAGE) { $env:FORGEJO_RUNNER_IMAGE } else { 'node:20-bookworm' }
    switch ($Plat) {
        'windows' { "windows:host,windows-latest:host,self-hosted:host" }
        'host'    { "host:host,self-hosted:host" }
        'docker'  { "docker:docker://$image,ubuntu-latest:docker://$image,ubuntu-22.04:docker://$image" }
        default   { throw "Unknown platform '$Plat' (use: windows, docker, host)" }
    }
}

# --- steps -------------------------------------------------------------------

function Install-Binary {
    param([string] $Dir, [string] $Ver)
    $arch = Get-RunnerArch
    $exe  = Join-Path $Dir 'forgejo-runner.exe'
    $url  = "https://code.forgejo.org/forgejo/runner/releases/download/v$Ver/forgejo-runner-$Ver-windows-$arch.exe"

    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Write-Info "downloading $url"
    # TLS 1.2 for older Windows PowerShell defaults.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $exe -UseBasicParsing
    Write-Info "installed $exe"
    return $exe
}

function Register-Runner {
    param([string] $Exe, [string] $Work, [string] $Instance, [string] $Tok, [string] $RunnerName, [string] $LabelList)
    New-Item -ItemType Directory -Force -Path $Work | Out-Null
    Write-Info "registering '$RunnerName' against $Instance"
    Write-Info "labels: $LabelList"
    Push-Location $Work
    try {
        & $Exe register --no-interactive `
            --instance $Instance `
            --token    $Tok `
            --name     $RunnerName `
            --labels   $LabelList
        if ($LASTEXITCODE -ne 0) { throw "forgejo-runner register failed (exit $LASTEXITCODE)" }
    }
    finally {
        Pop-Location
    }
    Write-Info "credential written to $(Join-Path $Work '.runner')"
}

function New-RunnerConfig {
    param([string] $Exe, [string] $Work)
    $config = Join-Path $Work 'config.yaml'
    if (-not (Test-Path $config)) {
        & $Exe generate-config | Out-File -FilePath $config -Encoding ascii
        Write-Info "wrote $config"
    }
    return $config
}

function Install-Service {
    param([string] $Exe, [string] $Work, [string] $Config)
    $svcName = 'forgejo-runner'
    $nssm = Get-Command nssm -ErrorAction SilentlyContinue

    if ($nssm) {
        Write-Info "installing service via nssm"
        if (Get-Service -Name $svcName -ErrorAction SilentlyContinue) {
            & $nssm.Source stop   $svcName | Out-Null
            & $nssm.Source remove $svcName confirm | Out-Null
        }
        & $nssm.Source install $svcName $Exe 'daemon' '--config' $Config
        & $nssm.Source set $svcName AppDirectory $Work
        & $nssm.Source set $svcName Start SERVICE_AUTO_START
        & $nssm.Source start $svcName
        Write-Info "service '$svcName' installed and started (nssm)"
    }
    else {
        Write-Warn2 "nssm not found — falling back to a Scheduled Task at startup."
        Write-Warn2 "Install nssm (https://nssm.cc/) and re-run for a real service."
        $taskName = 'forgejo-runner'
        $action   = New-ScheduledTaskAction -Execute $Exe `
                        -Argument "daemon --config `"$Config`"" -WorkingDirectory $Work
        $trigger  = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        Write-Info "scheduled task '$taskName' registered and started"
    }
}

# --- main --------------------------------------------------------------------

Assert-Admin

if ([string]::IsNullOrWhiteSpace($Labels)) {
    $Labels = Get-PlatformLabels -Plat $Platform
}

$exe    = Install-Binary  -Dir $InstallDir -Ver $Version
Register-Runner -Exe $exe -Work $WorkDir -Instance $InstanceUrl -Tok $Token -RunnerName $Name -LabelList $Labels
$config = New-RunnerConfig -Exe $exe -Work $WorkDir

if ($NoService) {
    Write-Info "registration complete (service install skipped: -NoService)"
    Write-Info "run manually with: `"$exe`" daemon --config `"$config`""
}
else {
    Install-Service -Exe $exe -Work $WorkDir -Config $config
}

Write-Info "done."
