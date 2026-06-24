Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------
# Tools directory — where downloaded CLI binaries (kubectl, helm, ...) are cached.
# -------------------------
$script:ToolsDir = $null

<#
.SYNOPSIS
    Sets the directory downloaded CLI tools (kubectl, helm, eksctl, ...) are
    cached in, creating it if needed and prepending it to $env:PATH.
.DESCRIPTION
    Defaults to "$env:LOCALAPPDATA\PowerShellClusterBootstrap\tools" on first
    use so the module works out of the box for any project. Call this once,
    before any Install-* function, if you want tools cached somewhere else —
    e.g. a project that already has its own `.tools` directory at a fixed
    location can point this there instead of using the default.
.PARAMETER Path
    Directory to use. Created automatically if it doesn't exist.
.EXAMPLE
    PS> Set-ClusterBootstrapToolsDir -Path "$PSScriptRoot\.tools"
#>
function Set-ClusterBootstrapToolsDir {
    param([Parameter(Mandatory)][string]$Path)
    $script:ToolsDir = $Path
    if (-not (Test-Path $script:ToolsDir)) { New-Item -ItemType Directory -Path $script:ToolsDir -Force | Out-Null }
    if ($env:PATH -notlike "*$script:ToolsDir*") { $env:PATH = "$script:ToolsDir;$env:PATH" }
}

Set-ClusterBootstrapToolsDir -Path (Join-Path $env:LOCALAPPDATA "PowerShellClusterBootstrap\tools")

<#
.SYNOPSIS
    Checks whether a command (CLI executable, function, alias, ...) is available.
.PARAMETER Command
    The command name to look up, e.g. "az" or "kubectl".
.EXAMPLE
    PS> Test-CommandExists "az"
    True
.OUTPUTS
    System.Boolean
#>
function Test-CommandExists {
    param([string]$Command)
    return $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

<#
.SYNOPSIS
    Returns this machine's OS and CPU architecture in the naming scheme most
    CLI tool release archives use (e.g. "windows"/"amd64", "linux"/"arm64").
.EXAMPLE
    PS> $os, $arch = Get-Os
.OUTPUTS
    Two strings: OS name, then architecture.
#>
function Get-Os {
    $os = "windows"
    $arch = "amd64"
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        if ($IsMacOS)   { $os = "darwin" }
        elseif ($IsLinux) { $os = "linux" }
        if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { $arch = "arm64" }
    }
    return $os, $arch
}

<#
.SYNOPSIS
    Downloads kubectl into the tools directory if not already present, and
    reports its version.
.DESCRIPTION
    No-op if kubectl.exe already exists in the tools directory — safe to call
    on every run. Pinned to a fixed version for reproducibility rather than
    always fetching "latest".
.EXAMPLE
    PS> Install-Kubectl
#>
function Install-Kubectl {
    $path = Join-Path $script:ToolsDir "kubectl.exe"
    [Console]::Write("`r  | kubectl: Checking...")

    if (-not (Test-Path $path)) {
        $version = "v1.29.0"
        $os, $arch = Get-Os
        $ext = if ($os -eq "windows") { ".exe" } else { "" }
        $url = "https://dl.k8s.io/release/$version/bin/$os/$arch/kubectl$ext"

        try {
            Invoke-ScriptBlockWithSpinner -Message "kubectl: Downloading $version..." -ScriptBlock {
                param($Url, $OutFile, $Os)
                Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
                if ($Os -ne "windows") { chmod +x $OutFile }
            } -ArgumentList @($url, $path, $os) | Out-Null
        } catch {
            Write-Error "Failed to download kubectl: $_"
            exit 1
        }
    }

    $v = & $path version --client 2>&1 | Select-String "Client Version|GitVersion" | Select-Object -First 1
    [Console]::Write("`r" + (" " * 80) + "`r")
    Write-Host "  ✓ kubectl: $($v.ToString().Trim())" -ForegroundColor Green
}

<#
.SYNOPSIS
    Downloads Helm into the tools directory if not already present, and
    reports its version.
.DESCRIPTION
    No-op if helm.exe already exists in the tools directory — safe to call
    on every run. Pinned to a fixed version for reproducibility.
.EXAMPLE
    PS> Install-Helm
#>
function Install-Helm {
    $path = Join-Path $script:ToolsDir "helm.exe"
    [Console]::Write("`r  | helm: Checking...")

    if (-not (Test-Path $path)) {
        $version = "v3.13.3"
        $zip = Join-Path $script:ToolsDir "helm.zip"
        $url = "https://get.helm.sh/helm-$version-windows-amd64.zip"
        $tmp = Join-Path $script:ToolsDir "helm-tmp"

        try {
            Invoke-ScriptBlockWithSpinner -Message "helm: Downloading $version..." -ScriptBlock {
                param($Url, $Zip, $Tmp, $Path)
                Invoke-WebRequest -Uri $Url -OutFile $Zip -UseBasicParsing
                Expand-Archive -Path $Zip -DestinationPath $Tmp -Force
                $exe = Get-ChildItem -Path $Tmp -Recurse -Filter "helm.exe" | Select-Object -First 1
                if (-not $exe) { throw "helm.exe not found in archive" }
                Copy-Item -Path $exe.FullName -Destination $Path -Force
            } -ArgumentList @($url, $zip, $tmp, $path) | Out-Null
        } catch {
            Write-Error "Failed to download helm: $_"
            exit 1
        } finally {
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $v = & $path version --short 2>&1
    [Console]::Write("`r" + (" " * 80) + "`r")
    Write-Host "  ✓ helm: $($v.ToString().Trim())" -ForegroundColor Green
}

<#
.SYNOPSIS
    Downloads the Rancher CLI into the tools directory if not already
    present, and reports its version.
.DESCRIPTION
    No-op if rancher.exe already exists in the tools directory — safe to
    call on every run. Pinned to a fixed version for reproducibility.
.EXAMPLE
    PS> Install-RancherCli
#>
function Install-RancherCli {
    $path = Join-Path $script:ToolsDir "rancher.exe"
    [Console]::Write("`r  | rancher: Checking...")

    if (-not (Test-Path $path)) {
        $version = "v2.14.2"
        $zip = Join-Path $script:ToolsDir "rancher-cli.zip"
        $url = "https://github.com/rancher/cli/releases/download/$version/rancher-windows-amd64-$version.zip"
        $tmp = Join-Path $script:ToolsDir "rancher-cli-tmp"

        try {
            Invoke-ScriptBlockWithSpinner -Message "rancher: Downloading $version..." -ScriptBlock {
                param($Url, $Zip, $Tmp, $Path)
                Invoke-WebRequest -Uri $Url -OutFile $Zip -UseBasicParsing
                Expand-Archive -Path $Zip -DestinationPath $Tmp -Force
                $exe = Get-ChildItem -Path $Tmp -Recurse -Filter "rancher.exe" | Select-Object -First 1
                if (-not $exe) { throw "rancher.exe not found in archive" }
                Copy-Item -Path $exe.FullName -Destination $Path -Force
            } -ArgumentList @($url, $zip, $tmp, $path) | Out-Null
        } catch {
            Write-Error "Failed to download rancher CLI: $_"
            exit 1
        } finally {
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $v = & $path --version 2>&1
    [Console]::Write("`r" + (" " * 80) + "`r")
    Write-Host "  ✓ rancher: $($v.ToString().Trim())" -ForegroundColor Green
}

<#
.SYNOPSIS
    Installs the CLI tooling specific to one cloud/cluster platform.
.DESCRIPTION
    "Azure AKS" installs the Azure CLI (az); "AWS EKS" installs the AWS CLI
    and eksctl; "Google GKE" installs the Google Cloud SDK (gcloud) and its
    gke-gcloud-auth-plugin; "Kind (Local)" installs kind into the tools
    directory; "RKE2 (On-Premise)" downloads plink.exe (PuTTY) for
    password-based SSH kubeconfig retrieval. No-op for any other value.
    Skips downloading anything already on $env:PATH or in a known install
    location for that platform's CLI.
.PARAMETER Platform
    One of: "Azure AKS", "AWS EKS", "Google GKE", "RKE2 (On-Premise)",
    "Kind (Local)".
.EXAMPLE
    PS> Install-PlatformTools -Platform "Azure AKS"
#>
function Install-PlatformTools {
    param([string]$Platform)

    switch ($Platform) {
        "Azure AKS" {
            # Add known install paths to session PATH before checking — CLI may already
            # be installed but missing from this session's PATH if installed previously
            foreach ($p in @("C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin", "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin")) {
                if ((Test-Path $p) -and $env:Path -notlike "*$p*") { $env:Path = "$p;$env:Path" }
            }

            [Console]::Write("`r  | az: Checking...")
            if (-not (Test-CommandExists "az")) {
                $msi = Join-Path $env:TEMP "AzureCLI.msi"
                $log = Join-Path $env:TEMP "AzureCLI_Install.log"
                try {
                    Invoke-ScriptBlockWithSpinner -Message "az: Downloading Azure CLI..." -ScriptBlock {
                        param($Url, $OutFile)
                        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
                    } -ArgumentList @("https://aka.ms/installazurecliwindows", $msi) | Out-Null
                } catch {
                    Write-Error "Failed to download Azure CLI: $_"; exit 1
                }
                [Console]::Write("`r  | az: Installing (UAC prompt may appear)...")
                $proc = Start-Process msiexec.exe -Wait -PassThru -Verb RunAs -ArgumentList "/i `"$msi`" /qn /L*v `"$log`""
                Remove-Item $msi -Force -ErrorAction SilentlyContinue
                if ($proc.ExitCode -ne 0) { Write-Error "Azure CLI install failed (code $($proc.ExitCode)). Log: $log"; exit 1 }
                foreach ($p in @("C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin", "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin")) {
                    if ((Test-Path $p) -and $env:Path -notlike "*$p*") { $env:Path = "$p;$env:Path"; break }
                }
            }
            $v = & az version 2>&1 | ConvertFrom-Json
            [Console]::Write("`r" + (" " * 80) + "`r")
            Write-Host "  ✓ az: $($v.'azure-cli')" -ForegroundColor Green
        }

        "AWS EKS" {
            foreach ($p in @("C:\Program Files\Amazon\AWSCLIV2", "C:\Program Files (x86)\Amazon\AWSCLIV2")) {
                if ((Test-Path $p) -and $env:Path -notlike "*$p*") { $env:Path = "$p;$env:Path" }
            }

            [Console]::Write("`r  | aws: Checking...")
            if (-not (Test-CommandExists "aws")) {
                $msi = Join-Path $env:TEMP "AWSCLIV2.msi"
                $log = Join-Path $env:TEMP "AWSCLI_Install.log"
                try {
                    Invoke-ScriptBlockWithSpinner -Message "aws: Downloading AWS CLI..." -ScriptBlock {
                        param($Url, $OutFile)
                        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
                    } -ArgumentList @("https://awscli.amazonaws.com/AWSCLIV2.msi", $msi) | Out-Null
                } catch {
                    Write-Error "Failed to download AWS CLI: $_"; exit 1
                }
                [Console]::Write("`r  | aws: Installing (UAC prompt may appear)...")
                $proc = Start-Process msiexec.exe -Wait -PassThru -Verb RunAs -ArgumentList "/i `"$msi`" /qn /L*v `"$log`""
                Remove-Item $msi -Force -ErrorAction SilentlyContinue
                if ($proc.ExitCode -ne 0) { Write-Error "AWS CLI install failed (code $($proc.ExitCode)). Log: $log"; exit 1 }
                foreach ($p in @("C:\Program Files\Amazon\AWSCLIV2", "C:\Program Files (x86)\Amazon\AWSCLIV2")) {
                    if ((Test-Path $p) -and $env:Path -notlike "*$p*") { $env:Path = "$p;$env:Path"; break }
                }
            }
            $v = & aws --version 2>&1
            [Console]::Write("`r" + (" " * 80) + "`r")
            Write-Host "  ✓ aws: $($v.ToString().Trim())" -ForegroundColor Green

            $eksctlPath = Join-Path $script:ToolsDir "eksctl.exe"
            [Console]::Write("`r  | eksctl: Checking...")
            if (-not (Test-Path $eksctlPath)) {
                $zip = Join-Path $env:TEMP "eksctl.zip"
                $tmp = Join-Path $env:TEMP "eksctl-tmp"
                try {
                    Invoke-ScriptBlockWithSpinner -Message "eksctl: Downloading..." -ScriptBlock {
                        param($Url, $Zip, $Tmp, $Path)
                        Invoke-WebRequest -Uri $Url -OutFile $Zip -UseBasicParsing
                        Expand-Archive -Path $Zip -DestinationPath $Tmp -Force
                        $exe = Get-ChildItem -Path $Tmp -Recurse -Filter "eksctl.exe" | Select-Object -First 1
                        if (-not $exe) { throw "eksctl.exe not found in archive" }
                        Copy-Item -Path $exe.FullName -Destination $Path -Force
                    } -ArgumentList @("https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Windows_amd64.zip", $zip, $tmp, $eksctlPath) | Out-Null
                } catch {
                    Write-Error "Failed to download eksctl: $_"; exit 1
                } finally {
                    Remove-Item $zip -Force -ErrorAction SilentlyContinue
                    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $v = & $eksctlPath version 2>&1
            [Console]::Write("`r" + (" " * 80) + "`r")
            Write-Host "  ✓ eksctl: $($v.ToString().Trim())" -ForegroundColor Green
        }

        "Google GKE" {
            [Console]::Write("`r  | gcloud: Checking...")
            if (-not (Test-CommandExists "gcloud")) {
                $exe = Join-Path $env:TEMP "gcloud-installer.exe"
                try {
                    Invoke-ScriptBlockWithSpinner -Message "gcloud: Downloading Google Cloud SDK..." -ScriptBlock {
                        param($Url, $OutFile)
                        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
                    } -ArgumentList @("https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe", $exe) | Out-Null
                } catch {
                    Write-Error "Failed to download Google Cloud SDK: $_"; exit 1
                }
                [Console]::Write("`r  | gcloud: Installing...")
                $proc = Start-Process -FilePath $exe -Wait -PassThru -ArgumentList "/S" -NoNewWindow
                Remove-Item $exe -Force -ErrorAction SilentlyContinue
                if ($proc.ExitCode -ne 0) { Write-Error "Google Cloud SDK install failed (code $($proc.ExitCode))"; exit 1 }
                foreach ($p in @("C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin", "C:\Program Files\Google\Cloud SDK\google-cloud-sdk\bin", "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin")) {
                    if ((Test-Path $p) -and $env:Path -notlike "*$p*") { $env:Path = "$p;$env:Path"; break }
                }
            }
            $v = & gcloud version 2>&1 | Select-String "Google Cloud SDK" | Select-Object -First 1
            [Console]::Write("`r" + (" " * 80) + "`r")
            Write-Host "  ✓ gcloud: $($v.ToString().Trim())" -ForegroundColor Green

            # Check PATH first, then the gcloud bin directory directly
            [Console]::Write("`r  | gke-gcloud-auth-plugin: Checking...")
            $pluginCmd = Get-Command "gke-gcloud-auth-plugin" -ErrorAction SilentlyContinue
            if (-not $pluginCmd) {
                $gcloudExe = (Get-Command "gcloud" -ErrorAction SilentlyContinue).Source
                $gcloudBin = if ($gcloudExe) { Split-Path $gcloudExe -Parent } else { $null }
                $pluginExe = if ($gcloudBin) { Join-Path $gcloudBin "gke-gcloud-auth-plugin.exe" } else { $null }
                if ($pluginExe -and (Test-Path $pluginExe)) {
                    if ($env:PATH -notlike "*$gcloudBin*") { $env:PATH = "$gcloudBin;$env:PATH" }
                    [Console]::Write("`r" + (" " * 80) + "`r")
                    Write-Host "  ✓ gke-gcloud-auth-plugin: found in gcloud bin" -ForegroundColor Green
                } else {
                    # gcloud blocks bundled Python in non-interactive mode (Start-Job counts as non-interactive).
                    # Fix: copy-bundled-python returns a standalone Python path we can pass as CLOUDSDK_PYTHON
                    # into the Start-Job via Invoke-WithSpinner's EnvVars parameter.
                    # NOTE: Invoke-WithSpinner comes from the powershell-menu-ui module — make sure that's
                    # imported too before calling Install-PlatformTools -Platform "Google GKE".
                    $extraEnv = @{}
                    $copiedPython = & gcloud components copy-bundled-python 2>&1 |
                        Where-Object { "$_".Trim() -ne "" -and "$_" -notmatch "^(WARNING|ERROR|System\.)" } |
                        Select-Object -Last 1
                    if ($copiedPython -and (Test-Path "$copiedPython")) {
                        $extraEnv["CLOUDSDK_PYTHON"] = "$copiedPython"
                    }
                    $exitCode = Invoke-WithSpinner -Message "gke-gcloud-auth-plugin: Installing..." `
                        -Executable "gcloud" -Arguments @("components", "install", "gke-gcloud-auth-plugin", "--quiet") `
                        -EnvVars $extraEnv
                    [Console]::Write("`r" + (" " * 80) + "`r")
                    if ($exitCode -eq 0) {
                        if ($gcloudBin -and $env:PATH -notlike "*$gcloudBin*") { $env:PATH = "$gcloudBin;$env:PATH" }
                        Write-Host "  ✓ gke-gcloud-auth-plugin: installed" -ForegroundColor Green
                    } else {
                        Write-Host "  ⚠ gke-gcloud-auth-plugin: could not auto-install" -ForegroundColor Yellow
                        Write-Host "    Run manually: gcloud components install gke-gcloud-auth-plugin" -ForegroundColor Yellow
                    }
                }
            } else {
                [Console]::Write("`r" + (" " * 80) + "`r")
                Write-Host "  ✓ gke-gcloud-auth-plugin: available" -ForegroundColor Green
            }
        }

        "Kind (Local)" {
            $path = Join-Path $script:ToolsDir "kind.exe"
            [Console]::Write("`r  | kind: Checking...")
            if (-not (Test-Path $path)) {
                $url = "https://github.com/kubernetes-sigs/kind/releases/download/v0.20.0/kind-windows-amd64"
                try {
                    Invoke-ScriptBlockWithSpinner -Message "kind: Downloading..." -ScriptBlock {
                        param($Url, $OutFile)
                        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
                    } -ArgumentList @($url, $path) | Out-Null
                } catch {
                    Write-Error "Failed to download kind: $_"
                    exit 1
                }
            }
            $v = & $path version 2>&1
            [Console]::Write("`r" + (" " * 80) + "`r")
            Write-Host "  ✓ kind: $($v.ToString().Trim())" -ForegroundColor Green
        }

        "RKE2 (On-Premise)" {
            $plinkPath = Join-Path $script:ToolsDir "plink.exe"
            [Console]::Write("`r  | plink: Checking...")
            if (-not (Test-Path $plinkPath) -and -not (Get-Command "plink.exe" -ErrorAction SilentlyContinue)) {
                try {
                    Invoke-ScriptBlockWithSpinner -Message "plink: Downloading (PuTTY)..." -ScriptBlock {
                        param($Url, $OutFile)
                        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
                    } -ArgumentList @("https://the.earth.li/~sgtatham/putty/latest/w64/plink.exe", $plinkPath) | Out-Null
                    [Console]::Write("`r" + (" " * 80) + "`r")
                    Write-Host "  ✓ plink: downloaded" -ForegroundColor Green
                } catch {
                    [Console]::Write("`r" + (" " * 80) + "`r")
                    Write-Warning "  ⚠ Could not download plink.exe — password SSH will not be available"
                }
            } else {
                [Console]::Write("`r" + (" " * 80) + "`r")
                Write-Host "  ✓ plink: available" -ForegroundColor Green
            }
            if ((Test-Path $plinkPath) -and $env:PATH -notlike "*$script:ToolsDir*") {
                $env:PATH = "$script:ToolsDir;$env:PATH"
            }
        }
    }
}

<#
.SYNOPSIS
    Adds or updates hostname entries in the local hosts file, in a single UAC
    elevation for all of them at once.
.DESCRIPTION
    Used by local/Kind setups where DNS isn't otherwise available — points a
    set of hostnames at a given IP (typically 127.0.0.1 or a MetalLB IP). Only
    triggers the elevated write if something actually needs to change.
.PARAMETER Hostnames
    The hostnames to add/update.
.PARAMETER IpAddress
    The IP every hostname should resolve to. Defaults to 127.0.0.1.
.EXAMPLE
    PS> Update-HostsFile -Hostnames @("grafana.kubernetes.local", "argocd.kubernetes.local")
#>
function Update-HostsFile {
    param(
        [string[]]$Hostnames,
        [string]$IpAddress = "127.0.0.1"
    )

    $hostsFile = "C:\Windows\System32\drivers\etc\hosts"
    $lines     = if (Test-Path $hostsFile) { Get-Content $hostsFile -Encoding UTF8 } else { @() }

    $toAdd    = [System.Collections.Generic.List[string]]::new()
    $toUpdate = [System.Collections.Generic.List[string]]::new()

    foreach ($h in ($Hostnames | Where-Object { $_ })) {
        $existingLine = $lines | Where-Object { $_ -match "\s+$([regex]::Escape($h))(\s|$)" } | Select-Object -First 1
        if (-not $existingLine) {
            $toAdd.Add($h)
        } elseif ($existingLine -notmatch "^$([regex]::Escape($IpAddress))\s") {
            $toUpdate.Add($h)
        }
    }

    if ($toAdd.Count -eq 0 -and $toUpdate.Count -eq 0) {
        Write-Host "  ✓ All hostnames already in hosts file with correct IP" -ForegroundColor Green
        return
    }

    # Build new hosts file content: replace outdated lines, append new ones
    $updatedLines = $lines | ForEach-Object {
        $line = $_
        $matched = $toUpdate | Where-Object { $line -match "\s+$([regex]::Escape($_))(\s|$)" } | Select-Object -First 1
        if ($matched) { "$IpAddress`t$matched" } else { $line }
    }
    foreach ($h in $toAdd) { $updatedLines += "$IpAddress`t$h" }

    $newContent = ($updatedLines -join "`r`n") + "`r`n"
    $tempEntry  = Join-Path $env:TEMP "hosts-update.txt"
    Set-Content -Path $tempEntry -Value $newContent -Encoding UTF8 -NoNewline

    $tempScript = Join-Path $env:TEMP "hosts-elevated.ps1"
    $scriptContent = @(
        "`$ErrorActionPreference = 'Stop'"
        "try {"
        "  Set-Content -Path '$hostsFile' -Value (Get-Content -Path '$tempEntry' -Raw -Encoding UTF8) -Encoding UTF8 -NoNewline"
        "  exit 0"
        "} catch { Write-Error `$_; exit 1 }"
    ) -join "`n"
    Set-Content -Path $tempScript -Value $scriptContent -Encoding UTF8

    $proc = Start-Process pwsh -Verb RunAs `
        -ArgumentList "-NonInteractive", "-File", "`"$tempScript`"" `
        -Wait -PassThru
    Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    Remove-Item $tempEntry  -Force -ErrorAction SilentlyContinue

    if ($proc.ExitCode -ne 0) { Write-Error "Failed to update hosts file"; exit 1 }

    foreach ($h in $toUpdate) { Write-Host "  ✓ Updated: $IpAddress`t$h" -ForegroundColor Green }
    foreach ($h in $toAdd)    { Write-Host "  ✓ Added:   $IpAddress`t$h" -ForegroundColor Green }
}

<#
.SYNOPSIS
    Recovers a Helm release stuck in pending-install/pending-upgrade/
    pending-rollback/failed state, typically caused by an aborted deploy.
.DESCRIPTION
    Rolls back to the previous revision if one exists; for a release with no
    prior revision (or one stuck in "failed", where rollback can't succeed),
    uninstalls it with --no-hooks so the next `helm upgrade --install` starts
    clean. No-op if the release doesn't exist or isn't in a stuck state.
.PARAMETER ReleaseName
    The Helm release name.
.PARAMETER Namespace
    The namespace the release lives in.
.EXAMPLE
    PS> Reset-StuckHelmRelease -ReleaseName "grafana" -Namespace "monitoring"
.OUTPUTS
    $true if it had to uninstall a failed release, $false if uninstall
    itself failed, or nothing if no recovery was needed.
#>
function Reset-StuckHelmRelease {
    param(
        [string]$ReleaseName,
        [string]$Namespace
    )
    $statusOutput = & helm status $ReleaseName --namespace $Namespace --output json 2>&1
    if ($LASTEXITCODE -ne 0) { return }  # release does not exist, nothing to do

    try {
        $releaseStatus = ($statusOutput | ConvertFrom-Json).info.status
        if ($releaseStatus -notin @("pending-install", "pending-upgrade", "pending-rollback", "failed")) { return }

        Write-Host "  ⚠ Release '$ReleaseName' in state '$releaseStatus' — resetting..." -ForegroundColor Yellow

        # failed releases cannot be rolled back — uninstall directly so next run is a clean install
        if ($releaseStatus -ne "failed") {
            & helm rollback $ReleaseName --namespace $Namespace 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Release reset via rollback" -ForegroundColor Green
                return
            }
        }

        # Use --no-hooks to bypass pre-delete hooks that may also be broken
        & helm uninstall $ReleaseName --namespace $Namespace --no-hooks 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ✗ helm uninstall failed — cannot reset release '$ReleaseName'" -ForegroundColor Red
            return $false
        }

        Write-Host "  ✓ Failed release uninstalled — will do fresh install" -ForegroundColor Green
        return $true
    } catch { }
}

<#
.SYNOPSIS
    Verifies kubectl's current context matches what's expected, switching to
    it if a get-credentials call left a different context active.
.PARAMETER ExpectedContext
    The kubectl context name that should be active.
.EXAMPLE
    PS> Confirm-KubectlContext -ExpectedContext "my-aks-cluster"
#>
function Confirm-KubectlContext {
    param([string]$ExpectedContext)

    $current = & kubectl config current-context 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($current)) {
        Write-Error "kubectl has no active context after get-credentials — kubeconfig may not have been updated"
        exit 1
    }

    if ($current.Trim() -ne $ExpectedContext) {
        Write-Warning "  ⚠ kubectl context is '$($current.Trim())' but expected '$ExpectedContext'"
        Write-Warning "    Run: kubectl config use-context $ExpectedContext"
        & kubectl config use-context $ExpectedContext 2>&1 | Out-Null
        $current = & kubectl config current-context 2>&1
        if ($current.Trim() -ne $ExpectedContext) {
            Write-Error "Failed to switch kubectl context to '$ExpectedContext'"
            exit 1
        }
    }

    Write-Host "  ✓ kubectl context: $($current.Trim())" -ForegroundColor Green
}

<#
.SYNOPSIS
    Polls an AKS-style Service until it has a LoadBalancer IP, returning it.
.PARAMETER Namespace
    Namespace the Service lives in. Defaults to "ingress-nginx".
.PARAMETER ServiceName
    Service name to poll. Defaults to "ingress-nginx-controller".
.PARAMETER TimeoutSeconds
    Give up and return $null after this many seconds. Defaults to 300.
.EXAMPLE
    PS> Get-AksIngressIp -Namespace "ingress-nginx"
.OUTPUTS
    System.String IP address, or $null on timeout.
#>
function Get-AksIngressIp {
    param(
        [string]$Namespace   = "ingress-nginx",
        [string]$ServiceName = "ingress-nginx-controller",
        [int]$TimeoutSeconds = 300
    )

    Write-Host "  Waiting for ingress LoadBalancer IP..." -ForegroundColor Cyan
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $ip = & kubectl get svc $ServiceName -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
        if ($ip -and $ip -match '^\d+\.\d+\.\d+\.\d+$') {
            Write-Host "  ✓ External IP: $ip" -ForegroundColor Green
            return $ip
        }
        Start-Sleep -Seconds 10
        $elapsed += 10
        Write-Host "    Still waiting... (${elapsed}s / ${TimeoutSeconds}s)" -ForegroundColor DarkGray
    }
    Write-Warning "  ⚠ Could not determine external IP within $TimeoutSeconds seconds"
    return $null
}

<#
.SYNOPSIS
    Polls an EKS-style Service until it has a LoadBalancer hostname, then
    resolves that hostname to an IP address.
.DESCRIPTION
    EKS LoadBalancer Services expose a hostname (not a raw IP) — this waits
    for it to appear, then does a DNS lookup to return a usable IP, e.g. for
    writing into a local hosts file.
.PARAMETER Namespace
    Namespace the Service lives in. Defaults to "ingress-nginx".
.PARAMETER ServiceName
    Service name to poll. Defaults to "ingress-nginx-controller".
.PARAMETER TimeoutSeconds
    Give up and return $null after this many seconds. Defaults to 300.
.EXAMPLE
    PS> Get-EksIngressIp -Namespace "ingress-nginx"
.OUTPUTS
    System.String IP address, or $null on timeout/resolution failure.
#>
function Get-EksIngressIp {
    param(
        [string]$Namespace   = "ingress-nginx",
        [string]$ServiceName = "ingress-nginx-controller",
        [int]$TimeoutSeconds = 300
    )

    Write-Host "  Waiting for ingress LoadBalancer hostname..." -ForegroundColor Cyan
    $elapsed  = 0
    $hostname = $null
    while ($elapsed -lt $TimeoutSeconds) {
        $hostname = & kubectl get svc $ServiceName -n $Namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
        if (-not [string]::IsNullOrWhiteSpace($hostname)) {
            Write-Host "  ✓ LoadBalancer hostname: $hostname" -ForegroundColor Green
            break
        }
        Start-Sleep -Seconds 10
        $elapsed += 10
        Write-Host "    Still waiting... (${elapsed}s / ${TimeoutSeconds}s)" -ForegroundColor DarkGray
    }

    if ([string]::IsNullOrWhiteSpace($hostname)) {
        Write-Warning "  ⚠ Could not determine LoadBalancer hostname within $TimeoutSeconds seconds"
        return $null
    }

    try {
        $ip = [System.Net.Dns]::GetHostAddresses($hostname) |
              Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
              Select-Object -First 1
        if ($ip) {
            Write-Host "  ✓ Resolved IP: $($ip.IPAddressToString)" -ForegroundColor Green
            return $ip.IPAddressToString
        }
    } catch { }
    Write-Warning "  ⚠ Could not resolve '$hostname' to an IP address"
    return $null
}

<#
.SYNOPSIS
    Returns the cluster's active IngressClass name.
.DESCRIPTION
    Prefers the IngressClass annotated as the cluster default; falls back to
    the first IngressClass found; falls back to the literal string "nginx"
    as a last resort if the cluster has none registered yet.
.EXAMPLE
    PS> Get-IngressClass
    nginx
.OUTPUTS
    System.String
#>
function Get-IngressClass {
    $default = & kubectl get ingressclass `
        -o jsonpath='{.items[?(@.metadata.annotations.ingressclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' `
        2>$null
    if ($default) { return $default.Trim() }

    $first = & kubectl get ingressclass -o jsonpath='{.items[0].metadata.name}' 2>$null
    if ($first) { return $first.Trim() }

    return "nginx"  # last-resort fallback
}

<#
.SYNOPSIS
    Creates or connects to an Azure AKS cluster and writes its kubeconfig.
.DESCRIPTION
    Logs into Azure via device code if not already authenticated, creates
    the resource group if needed, creates the AKS cluster if it doesn't
    already exist (skips creation if it does), then fetches credentials and
    confirms the kubectl context matches. -UseExisting skips straight to
    fetching credentials for an already-provisioned cluster.
.PARAMETER UseExisting
    Skip creation entirely and just fetch credentials for ResourceGroup/ClusterName.
.PARAMETER ReplaceCluster
    Delete the resource group first (and everything in it) before creating.
.EXAMPLE
    PS> Initialize-AksCluster -SubscriptionId $sub -ResourceGroup "my-rg" `
            -Location "westeurope" -ClusterName "my-cluster" -NodeCount 2
#>
function Initialize-AksCluster {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$Location,
        [string]$ClusterName,
        [int]$NodeCount        = 1,
        [string]$VmSize        = "Standard_D2s_v3",
        [bool]$ReplaceCluster  = $false,
        [bool]$UseExisting     = $false
    )

    & az account show 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  Azure login required. Open the following URL in your browser:" -ForegroundColor Cyan
        Write-Host "    https://microsoft.com/devicelogin" -ForegroundColor Yellow
        Write-Host "  Then enter the code shown below." -ForegroundColor Cyan
        Write-Host ""
        & az login --use-device-code
        if ($LASTEXITCODE -ne 0) { Write-Error "Azure login failed"; exit 1 }
    }

    $exitCode = Invoke-WithSpinner -Message "Setting subscription '$SubscriptionId'..." -Executable "az" `
        -Arguments @("account", "set", "--subscription", $SubscriptionId)
    if ($exitCode -ne 0) { Write-Error "Failed to set subscription '$SubscriptionId'"; exit 1 }
    Write-Host "  ✓ Subscription set" -ForegroundColor Green

    $kubefile = Join-Path $env:USERPROFILE ".kube\aks-$ClusterName.yaml"
    $env:KUBECONFIG = $kubefile

    if ($UseExisting) {
        $exitCode = Invoke-WithSpinner -Message "Fetching credentials for '$ClusterName'..." -Executable "az" `
            -Arguments @("aks", "get-credentials", "--resource-group", $ResourceGroup, "--name", $ClusterName, "--overwrite-existing", "--file", $kubefile)
        if ($exitCode -ne 0) { Write-Error "Failed to get credentials for '$ClusterName'"; exit 1 }
        Confirm-KubectlContext -ExpectedContext $ClusterName
        return
    }

    if ($ReplaceCluster) {
        $rgExists = & az group exists --name $ResourceGroup 2>$null
        if ($rgExists -eq "true") {
            $exitCode = Invoke-WithSpinner -Message "Deleting resource group '$ResourceGroup' (this may take several minutes)..." `
                -Executable "az" -Arguments @("group", "delete", "--name", $ResourceGroup, "--yes")
            if ($exitCode -ne 0) { Write-Warning "  ⚠ Resource group delete returned non-zero — continuing" }
            else { Write-Host "  ✓ Resource group deleted" -ForegroundColor Green }
        } else {
            Write-Host "  ✓ Resource group '$ResourceGroup' does not exist — skipping delete" -ForegroundColor Green
        }
    }

    $exitCode = Invoke-WithSpinner -Message "Creating resource group '$ResourceGroup' in $Location..." -Executable "az" `
        -Arguments @("group", "create", "--name", $ResourceGroup, "--location", $Location)
    if ($exitCode -ne 0) { Write-Error "Failed to create resource group '$ResourceGroup'"; exit 1 }
    Write-Host "  ✓ Resource group ready" -ForegroundColor Green

    & az aks show --resource-group $ResourceGroup --name $ClusterName 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $exitCode = Invoke-WithSpinner -Message "Registering Microsoft.ContainerService provider (once per subscription)..." -Executable "az" `
            -Arguments @("provider", "register", "--namespace", "Microsoft.ContainerService", "--wait")
        if ($exitCode -ne 0) { Write-Error "Failed to register Microsoft.ContainerService provider"; exit 1 }
        Write-Host "  ✓ Provider registered" -ForegroundColor Green

        $exitCode = Invoke-WithSpinner -Message "Creating AKS cluster '$ClusterName' ($NodeCount x $VmSize) — this takes 5-10 minutes..." `
            -Executable "az" -Arguments @(
                "aks", "create",
                "--resource-group", $ResourceGroup,
                "--name", $ClusterName,
                "--node-count", "$NodeCount",
                "--node-vm-size", $VmSize,
                "--location", $Location,
                "--generate-ssh-keys",
                "--network-plugin", "azure"
            )
        if ($exitCode -ne 0) { Write-Error "Failed to create AKS cluster '$ClusterName'"; exit 1 }
        Write-Host "  ✓ AKS cluster '$ClusterName' created" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Cluster '$ClusterName' already exists — skipping creation" -ForegroundColor Yellow
    }

    $exitCode = Invoke-WithSpinner -Message "Fetching kubectl credentials..." -Executable "az" `
        -Arguments @("aks", "get-credentials", "--resource-group", $ResourceGroup, "--name", $ClusterName, "--overwrite-existing", "--file", $kubefile)
    if ($exitCode -ne 0) { Write-Error "Failed to get credentials for '$ClusterName'"; exit 1 }
    Confirm-KubectlContext -ExpectedContext $ClusterName
}

<#
.SYNOPSIS
    Creates or connects to an AWS EKS cluster and writes its kubeconfig.
.DESCRIPTION
    Authenticates with AWS (using AccessKeyId/SecretAccessKey if not already
    configured), creates the cluster via eksctl if it doesn't already exist,
    then fetches credentials, retrying for a minute to absorb AWS API
    propagation delay. -UseExisting skips straight to fetching credentials.
.PARAMETER UseExisting
    Skip creation entirely and just fetch credentials for ClusterName.
.PARAMETER ReplaceCluster
    Delete the cluster first before creating it again.
.EXAMPLE
    PS> Initialize-EksCluster -Region "eu-west-1" -ClusterName "my-cluster" -NodeCount 2
#>
function Initialize-EksCluster {
    param(
        [string]$AccessKeyId,
        [string]$SecretAccessKey,
        [string]$Region,
        [string]$ClusterName,
        [int]$NodeCount       = 1,
        [string]$NodeType     = "t3.large",
        [bool]$ReplaceCluster = $false,
        [bool]$UseExisting    = $false
    )

    & aws configure set default.region $Region 2>&1 | Out-Null
    & aws sts get-caller-identity 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if (-not $AccessKeyId -or -not $SecretAccessKey) {
            Write-Error "AWS authentication failed — credentials not configured."
            exit 1
        }
        Write-Host "  Configuring AWS credentials..." -ForegroundColor Cyan
        & aws configure set aws_access_key_id $AccessKeyId 2>&1 | Out-Null
        & aws configure set aws_secret_access_key $SecretAccessKey 2>&1 | Out-Null
        & aws sts get-caller-identity 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Error "AWS authentication failed — check Access Key ID and Secret"; exit 1 }
    }
    Write-Host "  ✓ AWS authenticated" -ForegroundColor Green

    $kubefile = Join-Path $env:USERPROFILE ".kube\eks-$ClusterName.yaml"
    $env:KUBECONFIG = $kubefile

    if ($UseExisting) {
        $exitCode = Invoke-WithSpinner -Message "Fetching credentials for '$ClusterName'..." -Executable "aws" `
            -Arguments @("eks", "update-kubeconfig", "--region", $Region, "--name", $ClusterName, "--kubeconfig", $kubefile)
        if ($exitCode -ne 0) { Write-Error "Failed to get credentials for '$ClusterName'"; exit 1 }
        $ctx = (& kubectl config current-context 2>&1).Trim()
        Write-Host "  ✓ kubectl context: $ctx" -ForegroundColor Green
        return
    }

    $eksctlPath = Join-Path $script:ToolsDir "eksctl.exe"

    if ($ReplaceCluster) {
        $exitCode = Invoke-WithSpinner -Message "Deleting EKS cluster '$ClusterName' (this may take several minutes)..." `
            -Executable $eksctlPath -Arguments @("delete", "cluster", "--name", $ClusterName, "--region", $Region)
        if ($exitCode -ne 0) { Write-Warning "  ⚠ Cluster delete returned exit code $exitCode" }
        else { Write-Host "  ✓ Cluster deleted" -ForegroundColor Green }
    }

    & aws eks describe-cluster --region $Region --name $ClusterName 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $exitCode = Invoke-WithSpinner `
            -Message "Creating EKS cluster '$ClusterName' ($NodeCount x $NodeType) — this takes 20-40 minutes..." `
            -Executable $eksctlPath `
            -Arguments @("create", "cluster", "--name", $ClusterName, "--region", $Region,
                "--node-type", $NodeType, "--nodes", "$NodeCount", "--timeout", "45m")
        if ($exitCode -ne 0) {
            Write-Host ""
            Write-Host "  ✗ EKS cluster creation failed." -ForegroundColor Red
            Write-Host "  Check the CloudFormation console for details:" -ForegroundColor Yellow
            Write-Host "    https://console.aws.amazon.com/cloudformation/home?region=$Region" -ForegroundColor Yellow
            Write-Host "  Clean up: eksctl delete cluster --region=$Region --name=$ClusterName" -ForegroundColor Yellow
            Write-Error "Failed to create EKS cluster '$ClusterName'"
            exit 1
        }
        Write-Host "  ✓ EKS cluster '$ClusterName' created" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Cluster '$ClusterName' already exists — skipping creation" -ForegroundColor Yellow
    }

    $attempt = 0
    do {
        $exitCode = Invoke-WithSpinner -Message "Fetching kubectl credentials..." -Executable "aws" `
            -Arguments @("eks", "update-kubeconfig", "--region", $Region, "--name", $ClusterName, "--kubeconfig", $kubefile)
        if ($exitCode -ne 0 -and $attempt -lt 3) {
            $attempt++
            Write-Host "  Waiting 30s for API propagation (attempt $attempt/3)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
    } while ($exitCode -ne 0 -and $attempt -lt 3)
    if ($exitCode -ne 0) { Write-Error "Failed to get credentials for '$ClusterName'"; exit 1 }
    $ctx = (& kubectl config current-context 2>&1).Trim()
    Write-Host "  ✓ kubectl context: $ctx" -ForegroundColor Green
}

<#
.SYNOPSIS
    Creates or connects to a Google GKE cluster and writes its kubeconfig.
.DESCRIPTION
    Logs into Google Cloud if not already authenticated, sets the active
    project, enables the GKE API on first use, creates the cluster if it
    doesn't already exist, then fetches credentials with retry for API
    propagation delay. -UseExisting skips straight to fetching credentials.
.PARAMETER UseExisting
    Skip creation entirely and just fetch credentials for ClusterName.
.PARAMETER ReplaceCluster
    Delete the cluster first before creating it again.
.EXAMPLE
    PS> Initialize-GkeCluster -ProjectId $proj -Zone "europe-west6-a" -ClusterName "my-cluster"
#>
function Initialize-GkeCluster {
    param(
        [string]$ProjectId,
        [string]$Zone,
        [string]$ClusterName,
        [int]$NodeCount       = 1,
        [string]$MachineType  = "e2-standard-4",
        [bool]$ReplaceCluster = $false,
        [bool]$UseExisting    = $false
    )

    $accountRaw = & gcloud config get-value account 2>&1
    $account = if ($accountRaw -is [System.Management.Automation.ErrorRecord]) { "" } else { "$accountRaw".Trim() }
    if ($account -eq "(unset)" -or [string]::IsNullOrWhiteSpace($account)) {
        Write-Host ""
        Write-Host "  Google Cloud login required." -ForegroundColor Cyan
        Write-Host "  Open the URL that appears below in your browser." -ForegroundColor Cyan
        Write-Host ""
        & gcloud auth login --no-launch-browser
        if ($LASTEXITCODE -ne 0) { Write-Error "Google Cloud login failed"; exit 1 }
    }
    Write-Host "  ✓ Google Cloud authenticated" -ForegroundColor Green

    & gcloud config set project $ProjectId 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Error "Failed to set project '$ProjectId'"; exit 1 }
    Write-Host "  ✓ Project set: $ProjectId" -ForegroundColor Green

    $kubefile = Join-Path $env:USERPROFILE ".kube\gke-$ClusterName.yaml"
    $env:KUBECONFIG = $kubefile

    if ($UseExisting) {
        $exitCode = Invoke-WithSpinner -Message "Fetching credentials for '$ClusterName'..." -Executable "gcloud" `
            -Arguments @("container", "clusters", "get-credentials", $ClusterName, "--zone", $Zone, "--project", $ProjectId)
        if ($exitCode -ne 0) { Write-Error "Failed to get credentials for '$ClusterName'"; exit 1 }
        $ctx = (& kubectl config current-context 2>&1).Trim()
        Write-Host "  ✓ kubectl context: $ctx" -ForegroundColor Green
        return
    }

    if ($ReplaceCluster) {
        $exitCode = Invoke-WithSpinner -Message "Deleting GKE cluster '$ClusterName' (this may take several minutes)..." `
            -Executable "gcloud" -Arguments @("container", "clusters", "delete", $ClusterName, "--zone", $Zone, "--project", $ProjectId, "--quiet")
        if ($exitCode -ne 0) { Write-Warning "  ⚠ Cluster delete returned exit code $exitCode" }
        else { Write-Host "  ✓ Cluster deleted" -ForegroundColor Green }
    }

    & gcloud container clusters describe $ClusterName --zone $Zone --project $ProjectId 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $exitCode = Invoke-WithSpinner -Message "Enabling GKE API (once per project)..." -Executable "gcloud" `
            -Arguments @("services", "enable", "container.googleapis.com", "--project", $ProjectId)
        if ($exitCode -ne 0) { Write-Error "Failed to enable GKE API"; exit 1 }
        Write-Host "  ✓ GKE API enabled — waiting 30s for propagation..." -ForegroundColor Green
        Start-Sleep -Seconds 30

        $exitCode = Invoke-WithSpinner `
            -Message "Creating GKE cluster '$ClusterName' ($NodeCount x $MachineType) — this takes 5-10 minutes..." `
            -Executable "gcloud" `
            -Arguments @("container", "clusters", "create", $ClusterName,
                "--zone", $Zone, "--project", $ProjectId,
                "--num-nodes", "$NodeCount", "--machine-type", $MachineType,
                "--disk-type", "pd-standard", "--disk-size", "50",
                "--no-enable-autoupgrade")
        if ($exitCode -ne 0) { Write-Error "Failed to create GKE cluster '$ClusterName'"; exit 1 }
        Write-Host "  ✓ GKE cluster '$ClusterName' created" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Cluster '$ClusterName' already exists — skipping creation" -ForegroundColor Yellow
    }

    $attempt = 0
    do {
        $exitCode = Invoke-WithSpinner -Message "Fetching kubectl credentials..." -Executable "gcloud" `
            -Arguments @("container", "clusters", "get-credentials", $ClusterName, "--zone", $Zone, "--project", $ProjectId)
        if ($exitCode -ne 0 -and $attempt -lt 3) {  # gcloud respects $env:KUBECONFIG set above
            $attempt++
            Write-Host "  Waiting 30s for API propagation (attempt $attempt/3)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
    } while ($exitCode -ne 0 -and $attempt -lt 3)
    if ($exitCode -ne 0) { Write-Error "Failed to get credentials for '$ClusterName'"; exit 1 }

    $ctx = (& kubectl config current-context 2>&1).Trim()
    Write-Host "  ✓ kubectl context: $ctx" -ForegroundColor Green
}

<#
.SYNOPSIS
    Creates or replaces a local Kind cluster with ports 80/443 mapped to the
    host, and writes its kubeconfig.
.PARAMETER ClusterName
    Kind cluster name. Defaults to "my-kind-cluster".
.PARAMETER ReplaceCluster
    Delete the existing cluster of this name first, if any, before creating.
.EXAMPLE
    PS> Initialize-KindCluster -ClusterName "my-kind-cluster"
#>
function Initialize-KindCluster {
    param(
        [string]$ClusterName   = "my-kind-cluster",
        [bool]$ReplaceCluster  = $false
    )

    $kindExe    = Join-Path $script:ToolsDir "kind.exe"
    $existing   = & $kindExe get clusters 2>&1
    $kindConfig = Join-Path $env:TEMP "kind-cluster-config.yaml"

    Set-Content -Path $kindConfig -Value @"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  image: kindest/node:v1.32.0
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
"@ -Encoding UTF8

    if ($existing -contains $ClusterName) {
        if ($ReplaceCluster) {
            $exitCode = Invoke-WithSpinner -Message "Deleting Kind cluster '$ClusterName'..." `
                -Executable $kindExe -Arguments @("delete", "cluster", "--name", $ClusterName)
            if ($exitCode -ne 0) { Write-Error "Failed to delete Kind cluster '$ClusterName'"; exit 1 }
            Write-Host "  ✓ Cluster deleted" -ForegroundColor Green

            $exitCode = Invoke-WithSpinner -Message "Creating Kind cluster '$ClusterName'..." `
                -Executable $kindExe -Arguments @("create", "cluster", "--name", $ClusterName, "--config", $kindConfig)
            if ($exitCode -ne 0) { Write-Error "Failed to create Kind cluster '$ClusterName'"; exit 1 }
            Write-Host "  ✓ Kind cluster '$ClusterName' created" -ForegroundColor Green
        } else {
            Write-Host "  ✓ Kind cluster '$ClusterName' already exists" -ForegroundColor Green
        }
    } else {
        $exitCode = Invoke-WithSpinner -Message "Creating Kind cluster '$ClusterName'..." `
            -Executable $kindExe -Arguments @("create", "cluster", "--name", $ClusterName, "--config", $kindConfig)
        if ($exitCode -ne 0) { Write-Error "Failed to create Kind cluster '$ClusterName'"; exit 1 }
        Write-Host "  ✓ Kind cluster '$ClusterName' created" -ForegroundColor Green
    }
    Remove-Item $kindConfig -Force -ErrorAction SilentlyContinue

    $kubefile = Join-Path $env:USERPROFILE ".kube\kind-$ClusterName.yaml"
    & $kindExe export kubeconfig --name $ClusterName --kubeconfig $kubefile 2>&1 | Out-Null
    $env:KUBECONFIG = $kubefile
    Write-Host "  ✓ kubectl context set to kind-$ClusterName" -ForegroundColor Green
}

<#
.SYNOPSIS
    Connects to an RKE2 cluster, fetching its kubeconfig via SSH if a server
    is given, and verifies connectivity.
.DESCRIPTION
    If -SshServer is given, fetches `/etc/rancher/rke2/rke2.yaml` from that
    node (password auth via plink.exe if -SshPassword is set, otherwise
    ssh.exe with an optional -SshKeyPath), patches the embedded
    https://127.0.0.1:6443 endpoint to point at the real server address, and
    saves it to -KubeconfigPath. If no server is given, uses the kubeconfig
    already at -KubeconfigPath as-is. Either way, finishes by running
    `kubectl get nodes` to confirm the cluster is actually reachable.
.PARAMETER KubeconfigPath
    Where to read/write the kubeconfig. Defaults to
    "~/.kube/rke2-<server-or-'rke2'>.yaml" if not given.
.EXAMPLE
    PS> Initialize-Rke2Cluster -SshServer "10.0.0.10" -SshUser "root" -SshKeyPath "~/.ssh/id_rsa"
#>
function Initialize-Rke2Cluster {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'SshPassword',
        Justification = 'Password is passed as CLI argument to plink.exe — SecureString provides no benefit here')]
    param(
        [string]$KubeconfigPath = "",
        [string]$SshServer      = "",
        [string]$SshUser        = "root",
        [string]$SshKeyPath     = "",
        [string]$SshPassword    = ""
    )

    if ([string]::IsNullOrWhiteSpace($KubeconfigPath)) {
        $safeName = if ($SshServer) { $SshServer -replace '[^a-zA-Z0-9-]', '-' } else { "rke2" }
        $KubeconfigPath = "$env:USERPROFILE\.kube\rke2-$safeName.yaml"
    }
    $KubeconfigPath = $KubeconfigPath -replace '^~', $env:USERPROFILE

    # Auto-fetch via SSH if server is provided
    if (-not [string]::IsNullOrWhiteSpace($SshServer)) {
        $rawConfig = $null

        if (-not [string]::IsNullOrWhiteSpace($SshPassword)) {
            $plinkExe = Get-Command "plink.exe" -ErrorAction SilentlyContinue
            if (-not $plinkExe) {
                Write-Error "Password-based SSH requires plink.exe. Install PuTTY or use an SSH key instead."
                exit 1
            }
            # Pre-run: accept and cache the host key
            $exitCode = Invoke-WithSpinner -Message "Caching SSH host key for $SshServer..." `
                -Executable "plink.exe" -Arguments @("-ssh", "-pw", $SshPassword, "$SshUser@$SshServer", "exit")
            if ($exitCode -ne 0) { Write-Error "Failed to cache SSH host key for $SshServer"; exit 1 }
            Write-Host "  ✓ SSH host key cached" -ForegroundColor Green
            # Fetch kubeconfig (key is now cached, -batch safe)
            $rawRef = [ref]$null
            $exitCode = Invoke-WithSpinner -Message "Fetching kubeconfig from $SshUser@$SshServer..." `
                -Executable "plink.exe" -Arguments @("-ssh", "-batch", "-pw", $SshPassword, "$SshUser@$SshServer", "cat /etc/rancher/rke2/rke2.yaml") `
                -OutputVariable $rawRef
            $rawConfig = $rawRef.Value
        } else {
            $sshArgs = @("-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes")
            if (-not [string]::IsNullOrWhiteSpace($SshKeyPath)) {
                $SshKeyPath = $SshKeyPath -replace '^~', $env:USERPROFILE
                $sshArgs += @("-i", $SshKeyPath)
            }
            $sshArgs += @("$SshUser@$SshServer", "cat /etc/rancher/rke2/rke2.yaml")
            $rawRef   = [ref]$null
            $exitCode = Invoke-WithSpinner -Message "Fetching kubeconfig from $SshUser@$SshServer..." `
                -Executable "ssh.exe" -Arguments $sshArgs -OutputVariable $rawRef
            $rawConfig = $rawRef.Value
        }

        if ($exitCode -ne 0) { Write-Error "SSH failed — check credentials and server address"; exit 1 }

        # Strip any plink/ssh status lines (stderr mixed in via 2>&1) — keep only the YAML part
        $yamlLines  = @($rawConfig) | ForEach-Object { "$_" }
        $yamlStart  = 0
        for ($i = 0; $i -lt $yamlLines.Count; $i++) {
            if ($yamlLines[$i] -match '^(apiVersion:|---)') { $yamlStart = $i; break }
        }
        $cleanYaml = ($yamlLines[$yamlStart..($yamlLines.Count - 1)] -join "`n")

        # RKE2 kubeconfig has 127.0.0.1 — replace with the actual server IP/VIP
        $patchedConfig = $cleanYaml -replace 'https://127\.0\.0\.1:6443', "https://$SshServer`:6443"

        $kubeconfigDir = Split-Path $KubeconfigPath -Parent
        if (-not (Test-Path $kubeconfigDir)) { New-Item -ItemType Directory -Path $kubeconfigDir -Force | Out-Null }
        Set-Content -Path $KubeconfigPath -Value $patchedConfig -Encoding UTF8
        Write-Host "  ✓ Kubeconfig saved" -ForegroundColor Green
    } elseif (Test-Path $KubeconfigPath) {
        Write-Host "  ✓ Using existing kubeconfig" -ForegroundColor Green
    } else {
        Write-Error "Kubeconfig not found at '$KubeconfigPath'. Copy it from your RKE2 server:  scp user@<node1>:/etc/rancher/rke2/rke2.yaml $KubeconfigPath"
        exit 1
    }

    $env:KUBECONFIG = $KubeconfigPath

    $nodesRef = [ref]$null
    $exitCode = Invoke-WithSpinner -Message "Verifying cluster connectivity..." `
        -Executable "kubectl" -Arguments @("get", "nodes", "--no-headers") -OutputVariable $nodesRef
    if ($exitCode -ne 0) {
        Write-Error "Cannot reach cluster. Check kubeconfig and that the cluster is running."
        exit 1
    }
    $nodeCount = ($nodesRef.Value | Measure-Object).Count
    Write-Host "  ✓ Connected — $nodeCount node(s) ready" -ForegroundColor Green
}

<#
.SYNOPSIS
    Dispatches to the right Initialize-*Cluster function for the given
    platform, passing through only that platform's parameters.
.DESCRIPTION
    Single entry point so a caller doesn't need its own platform switch —
    pass -Platform plus whichever Aks*/Eks*/Gke*/Rke2* parameters are
    relevant; the rest are ignored. No-op for "Kind (Local)" parameters not
    prefixed Kind*, etc.
.PARAMETER Platform
    One of: "Azure AKS", "AWS EKS", "Google GKE", "RKE2 (On-Premise)",
    "Kind (Local)".
.EXAMPLE
    PS> Initialize-ClusterEnvironment -Platform "Kind (Local)" -KindClusterName "my-kind-cluster"
#>
function Initialize-ClusterEnvironment {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Rke2SshPassword',
        Justification = 'Password is passed as CLI argument to plink.exe — SecureString provides no benefit here')]
    param(
        [string]$Platform,
        # Kind
        [string]$KindClusterName   = "my-kind-cluster",
        [bool]$KindReplaceCluster  = $false,
        [string]$KindDomain        = "kubernetes.local",
        # AKS
        [string]$AksSubscriptionId = "",
        [string]$AksResourceGroup  = "",
        [string]$AksLocation       = "",
        [string]$AksClusterName    = "",
        [int]$AksNodeCount         = 1,
        [string]$AksVmSize         = "Standard_D2s_v3",
        [bool]$AksReplaceCluster   = $false,
        [bool]$AksUseExisting      = $false,
        # EKS
        [string]$EksAccessKeyId     = "",
        [string]$EksSecretAccessKey = "",
        [string]$EksRegion          = "",
        [string]$EksClusterName     = "",
        [int]$EksNodeCount          = 1,
        [string]$EksNodeType        = "t3.large",
        [bool]$EksReplaceCluster    = $false,
        [bool]$EksUseExisting       = $false,
        # GKE
        [string]$GkeProjectId    = "",
        [string]$GkeZone         = "",
        [string]$GkeClusterName  = "",
        [int]$GkeNodeCount       = 1,
        [string]$GkeMachineType  = "e2-standard-4",
        [bool]$GkeReplaceCluster = $false,
        [bool]$GkeUseExisting    = $false,
        # RKE2
        [string]$Rke2KubeconfigPath = "",
        [string]$Rke2SshServer      = "",
        [string]$Rke2SshUser        = "root",
        [string]$Rke2SshKeyPath     = "",
        [string]$Rke2SshPassword    = ""
    )

    switch ($Platform) {
        "Azure AKS" {
            Initialize-AksCluster `
                -SubscriptionId $AksSubscriptionId -ResourceGroup $AksResourceGroup `
                -Location $AksLocation -ClusterName $AksClusterName `
                -NodeCount $AksNodeCount -VmSize $AksVmSize `
                -ReplaceCluster $AksReplaceCluster -UseExisting $AksUseExisting
        }
        "AWS EKS" {
            Initialize-EksCluster `
                -AccessKeyId $EksAccessKeyId -SecretAccessKey $EksSecretAccessKey `
                -Region $EksRegion -ClusterName $EksClusterName `
                -NodeCount $EksNodeCount -NodeType $EksNodeType `
                -ReplaceCluster $EksReplaceCluster -UseExisting $EksUseExisting
        }
        "Google GKE" {
            Initialize-GkeCluster `
                -ProjectId $GkeProjectId -Zone $GkeZone -ClusterName $GkeClusterName `
                -NodeCount $GkeNodeCount -MachineType $GkeMachineType `
                -ReplaceCluster $GkeReplaceCluster -UseExisting $GkeUseExisting
        }
        "RKE2 (On-Premise)" {
            Initialize-Rke2Cluster -KubeconfigPath $Rke2KubeconfigPath `
                -SshServer $Rke2SshServer -SshUser $Rke2SshUser `
                -SshKeyPath $Rke2SshKeyPath -SshPassword $Rke2SshPassword
        }
        "Kind (Local)" {
            Initialize-KindCluster -ClusterName $KindClusterName -ReplaceCluster $KindReplaceCluster
        }
    }
}

<#
.SYNOPSIS
    Reconnects kubectl to an already-provisioned cluster, reading whatever
    that platform needs from a per-platform state JSON file in -BaseDir.
.DESCRIPTION
    This is the function every other script in a multi-script installer
    calls to "make sure kubectl is pointed at the right cluster" without
    re-running the full Initialize-*Cluster creation flow. Reads
    "<BaseDir>/.<platform-slug>-state.json" (one of .rke2-state.json,
    .aks-state.json, .eks-state.json, .gke-state.json, .kind-state.json),
    expected to contain at minimum the fields each platform's section below
    reads (ClusterName, ResourceGroup/Region/Zone/Project as applicable,
    KubeconfigPath for RKE2). Caches the last-set (Platform, BaseDir) pair in
    $env:INSTALLER_LAST_CONTEXT for the lifetime of the process so repeated
    calls within one session skip redundant az/aws/gcloud credential calls.
.PARAMETER BaseDir
    Directory containing the platform's state JSON file.
.PARAMETER Platform
    One of: "Azure AKS", "AWS EKS", "Google GKE", "RKE2 (On-Premise)",
    "Kind (Local)". Always required — never auto-detected.
.EXAMPLE
    PS> Set-ClusterContext -BaseDir $PSScriptRoot -Platform "RKE2 (On-Premise)"
#>
function Set-ClusterContext {
    param(
        [string]$BaseDir,
        [Parameter(Mandatory)][string]$Platform
    )

    if ([string]::IsNullOrWhiteSpace($Platform)) {
        Write-Error "Set-ClusterContext: -Platform is required. State files are not auto-detected."
        return
    }

    $contextKey = "$Platform|$BaseDir"
    $alreadySet = $env:INSTALLER_LAST_CONTEXT -eq $contextKey

    $kubeDir = Join-Path $env:USERPROFILE ".kube"
    if (-not (Test-Path $kubeDir)) { New-Item -ItemType Directory -Path $kubeDir -Force | Out-Null }

    switch ($Platform) {
        "RKE2 (On-Premise)" {
            $s = Get-Content (Join-Path $BaseDir ".rke2-state.json") | ConvertFrom-Json
            $env:KUBECONFIG = $s.KubeconfigPath -replace '^~', $env:USERPROFILE
            if (-not $alreadySet) { Write-Host "  Cluster: $($s.SshServer)  [RKE2]" -ForegroundColor DarkGray }
        }
        "Azure AKS" {
            $s        = Get-Content (Join-Path $BaseDir ".aks-state.json") | ConvertFrom-Json
            $kubefile = Join-Path $kubeDir "aks-$($s.ClusterName).yaml"
            if (-not $alreadySet) {
                & az account set --subscription $s.SubscriptionId 2>$null | Out-Null
                & az aks get-credentials --resource-group $s.ResourceGroup `
                    --name $s.ClusterName --overwrite-existing --file $kubefile 2>$null | Out-Null
            }
            $env:KUBECONFIG = $kubefile
            & kubectl config use-context $s.ClusterName 2>$null | Out-Null
            if (-not $alreadySet) { Write-Host "  Cluster: $($s.ClusterName)  ($($s.ResourceGroup) · $($s.Location))  [AKS]" -ForegroundColor DarkGray }
        }
        "AWS EKS" {
            $s        = Get-Content (Join-Path $BaseDir ".eks-state.json") | ConvertFrom-Json
            $kubefile = Join-Path $kubeDir "eks-$($s.ClusterName).yaml"
            if (-not $alreadySet) {
                & aws eks update-kubeconfig --region $s.Region --name $s.ClusterName --kubeconfig $kubefile 2>$null | Out-Null
            }
            $env:KUBECONFIG = $kubefile
            $eksCtx = & kubectl config get-contexts --output name 2>$null | Where-Object { $_ -like "*$($s.ClusterName)*" } | Select-Object -First 1
            if ($eksCtx) { & kubectl config use-context $eksCtx 2>$null | Out-Null }
            if (-not $alreadySet) { Write-Host "  Cluster: $($s.ClusterName)  ($($s.Region))  [EKS]" -ForegroundColor DarkGray }
        }
        "Google GKE" {
            $s        = Get-Content (Join-Path $BaseDir ".gke-state.json") | ConvertFrom-Json
            $kubefile = Join-Path $kubeDir "gke-$($s.ClusterName).yaml"
            if (-not $alreadySet) {
                $env:KUBECONFIG = $kubefile
                & gcloud container clusters get-credentials $s.ClusterName `
                    --zone $s.Zone --project $s.ProjectId 2>$null | Out-Null
            }
            $env:KUBECONFIG = $kubefile
            & kubectl config use-context $s.ClusterName 2>$null | Out-Null
            if (-not $alreadySet) { Write-Host "  Cluster: $($s.ClusterName)  ($($s.Zone))  [GKE]" -ForegroundColor DarkGray }
        }
        "Kind (Local)" {
            $kindState = Join-Path $BaseDir ".kind-state.json"
            if (Test-Path $kindState) {
                $s        = Get-Content $kindState | ConvertFrom-Json
                $kubefile = Join-Path $kubeDir "kind-$($s.ClusterName).yaml"
                if (-not $alreadySet) {
                    $kindExe = Join-Path $script:ToolsDir "kind.exe"
                    if (Test-Path $kindExe) {
                        & $kindExe export kubeconfig --name $s.ClusterName --kubeconfig $kubefile 2>$null | Out-Null
                    }
                }
                $env:KUBECONFIG = $kubefile
                & kubectl config use-context "kind-$($s.ClusterName)" 2>$null | Out-Null
                if (-not $alreadySet) { Write-Host "  Cluster: $($s.ClusterName)  [Kind]" -ForegroundColor DarkGray }
            }
        }
    }
    $env:INSTALLER_LAST_CONTEXT = $contextKey
}

<#
.SYNOPSIS
    Writes a secret to Azure Key Vault, one entry per key.
.DESCRIPTION
    Each key in -Data becomes its own Key Vault secret named "$Path-$key"
    (or just $Path if -Data has exactly one entry) — separate secrets avoid
    needing a JMESPath/jq dependency to read back a single field, and mount
    cleanly as individual files via the Secrets Store CSI driver. Retries
    with increasing delays (0/30/60s) since Azure RBAC role assignments can
    take a minute or two to propagate after being granted.
.PARAMETER Path
    Secret name prefix (or full name, if -Data has one entry).
.PARAMETER Data
    Hashtable of key/value pairs to write.
.PARAMETER BaseDir
    Directory containing ".aks-state.json", which must have a VaultName
    property naming the target Key Vault.
.EXAMPLE
    PS> Write-AzureKeyVaultSecret -Path "grafana" -Data @{ adminPassword = $pw } -BaseDir $PSScriptRoot
.OUTPUTS
    $true on success, $false if the state file/vault name is missing or any
    write failed.
#>
function Write-AzureKeyVaultSecret {
    param([string]$Path, [hashtable]$Data, [string]$BaseDir)

    $stateFile = Join-Path $BaseDir ".aks-state.json"
    if (-not (Test-Path $stateFile)) { return $false }

    $vaultName = (Get-Content $stateFile | ConvertFrom-Json).VaultName
    if (-not $vaultName) { return $false }

    # Azure RBAC can take 1-2 minutes to propagate — retry with increasing delays.
    $frames = @('|','/','-','\'); $fi = 0
    $delays = @(0, 30, 60)

    foreach ($entry in $Data.GetEnumerator()) {
        $secretName = if ($Data.Count -eq 1) { $Path } else { "$Path-$($entry.Key)" }
        $tmpFile = New-TemporaryFile
        Set-Content -Path $tmpFile.FullName -Value $entry.Value -Encoding UTF8 -NoNewline
        $written = $false
        foreach ($delay in $delays) {
            if ($delay -gt 0) {
                for ($i = 0; $i -lt $delay; $i++) {
                    [Console]::Write("`r  $($frames[$fi++ % 4]) Waiting for RBAC propagation... (${i}s)")
                    Start-Sleep -Seconds 1
                }
            }
            & az keyvault secret set --vault-name $vaultName --name $secretName --file $tmpFile.FullName --encoding utf-8 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $written = $true; break }
        }
        Remove-Item $tmpFile.FullName -Force -ErrorAction SilentlyContinue
        if (-not $written) { return $false }
    }
    return $true
}

<#
.SYNOPSIS
    Writes a secret to AWS Secrets Manager, one entry per key.
.DESCRIPTION
    Each key in -Data becomes its own secret named "$Path-$key" (or just
    $Path if -Data has exactly one entry) — creates the secret if it doesn't
    exist yet, otherwise adds a new version to it.
.PARAMETER Path
    Secret name prefix (or full name, if -Data has one entry).
.PARAMETER Data
    Hashtable of key/value pairs to write.
.PARAMETER BaseDir
    Directory containing ".eks-state.json", which must have a Region property.
.EXAMPLE
    PS> Write-AwsSecretsManagerSecret -Path "grafana" -Data @{ adminPassword = $pw } -BaseDir $PSScriptRoot
.OUTPUTS
    $true on success, $false if the state file/region is missing or any
    write failed.
#>
function Write-AwsSecretsManagerSecret {
    param([string]$Path, [hashtable]$Data, [string]$BaseDir)

    $stateFile = Join-Path $BaseDir ".eks-state.json"
    if (-not (Test-Path $stateFile)) { return $false }

    $region = (Get-Content $stateFile | ConvertFrom-Json).Region
    if (-not $region) { return $false }

    foreach ($entry in $Data.GetEnumerator()) {
        $secretName = if ($Data.Count -eq 1) { $Path } else { "$Path-$($entry.Key)" }

        & aws secretsmanager describe-secret --secret-id $secretName --region $region 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & aws secretsmanager create-secret --name $secretName --region $region `
                --secret-string $entry.Value 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { return $false }
        } else {
            & aws secretsmanager put-secret-value --secret-id $secretName --region $region `
                --secret-string $entry.Value 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { return $false }
        }
    }
    return $true
}

<#
.SYNOPSIS
    Writes a secret to GCP Secret Manager, one entry per key.
.DESCRIPTION
    Each key in -Data becomes its own secret named "$Path-$key" (or just
    $Path if -Data has exactly one entry) — creates the secret if it doesn't
    exist yet, then adds a new version with the value.
.PARAMETER Path
    Secret name prefix (or full name, if -Data has one entry).
.PARAMETER Data
    Hashtable of key/value pairs to write.
.PARAMETER BaseDir
    Directory containing ".gke-state.json", which must have a ProjectId property.
.EXAMPLE
    PS> Write-GcpSecretManagerSecret -Path "grafana" -Data @{ adminPassword = $pw } -BaseDir $PSScriptRoot
.OUTPUTS
    $true on success, $false if the state file/project ID is missing or any
    write failed.
#>
function Write-GcpSecretManagerSecret {
    param([string]$Path, [hashtable]$Data, [string]$BaseDir)

    $stateFile = Join-Path $BaseDir ".gke-state.json"
    if (-not (Test-Path $stateFile)) { return $false }

    $projectId = (Get-Content $stateFile | ConvertFrom-Json).ProjectId
    if (-not $projectId) { return $false }

    foreach ($entry in $Data.GetEnumerator()) {
        $secretName = if ($Data.Count -eq 1) { $Path } else { "$Path-$($entry.Key)" }

        $exists = & gcloud secrets describe $secretName --project $projectId 2>$null
        if (-not $exists) {
            & gcloud secrets create $secretName --project $projectId --replication-policy automatic 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { return $false }
        }

        $tmpFile = New-TemporaryFile
        Set-Content -Path $tmpFile.FullName -Value $entry.Value -Encoding UTF8 -NoNewline
        & gcloud secrets versions add $secretName --project $projectId --data-file $tmpFile.FullName 2>$null | Out-Null
        Remove-Item $tmpFile.FullName -Force -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) { return $false }
    }
    return $true
}

<#
.SYNOPSIS
    Generates the "data:" YAML fragment of an ExternalSecret resource for a
    given remote secret path and key list.
.DESCRIPTION
    Generic shape that works against any backend whose External Secrets
    Operator SecretStore returns one property per key under a single remote
    key path (which covers OpenBao KV-v2, Azure Key Vault via the property
    suffix convention, AWS Secrets Manager JSON secrets, and GCP Secret
    Manager JSON secrets). If -Platform isn't given, makes a best-effort
    guess from state files present in -BaseDir.
.PARAMETER Path
    The remote secret's key/path in the backend.
.PARAMETER Keys
    The keys to extract, each becoming one secretKey/remoteRef.property pair.
.PARAMETER BaseDir
    Directory to look for state files in, when -Platform isn't given.
.PARAMETER Platform
    Optional explicit platform — skips the state-file guess.
.EXAMPLE
    PS> Get-ExternalSecretData -Path "grafana" -Keys @("adminPassword") -BaseDir $PSScriptRoot
.OUTPUTS
    System.String — a multi-line YAML fragment to splice into an
    ExternalSecret's spec.data list.
#>
function Get-ExternalSecretData {
    param(
        [string]$Path,
        [string[]]$Keys,
        [string]$BaseDir,
        [string]$Platform = ""
    )

    if ([string]::IsNullOrWhiteSpace($Platform)) {
        if (Test-Path (Join-Path $BaseDir ".openbao-state.json"))       { $Platform = "RKE2 (On-Premise)" }
        elseif (Test-Path (Join-Path $BaseDir ".aks-keyvault-state.json")) { $Platform = "Azure AKS" }
    }

    $lines = @()
    foreach ($key in $Keys) {
        $lines += "  - secretKey: $key"
        $lines += "    remoteRef:"
        $lines += "      key: $Path"
        $lines += "      property: $key"
    }
    return $lines -join "`n"
}

Export-ModuleMember -Function @(
    'Set-ClusterBootstrapToolsDir'
    'Test-CommandExists'
    'Get-Os'
    'Install-Kubectl'
    'Install-Helm'
    'Install-RancherCli'
    'Install-PlatformTools'
    'Update-HostsFile'
    'Reset-StuckHelmRelease'
    'Confirm-KubectlContext'
    'Get-AksIngressIp'
    'Get-EksIngressIp'
    'Get-IngressClass'
    'Initialize-AksCluster'
    'Initialize-EksCluster'
    'Initialize-GkeCluster'
    'Initialize-KindCluster'
    'Initialize-Rke2Cluster'
    'Initialize-ClusterEnvironment'
    'Set-ClusterContext'
    'Write-AzureKeyVaultSecret'
    'Write-AwsSecretsManagerSecret'
    'Write-GcpSecretManagerSecret'
    'Get-ExternalSecretData'
)
