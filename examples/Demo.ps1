<#
.SYNOPSIS
    Walkthrough of the parts of PowerShellClusterBootstrap that are safe to
    run without a cloud account or a brand-new cluster.
.DESCRIPTION
    Installs the CLI tools (cheap, idempotent — just downloads), explains
    the state-file contract that Set-ClusterContext and the cloud
    Write-*Secret functions rely on, and exercises Get-IngressClass /
    Reset-StuckHelmRelease against whatever cluster your current kubeconfig
    already points at (skipped with an explanation if none is configured).
    Does NOT call any Initialize-*Cluster function — those create real
    cloud resources and cost real money, so they're documented via
    Get-Help instead of run here.
#>
[CmdletBinding()]
param()

$ModuleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ModuleRoot "PowerShellClusterBootstrap.psd1") -Force

function Show-Step {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

# ── 1. Tool installation ──────────────────────────────────────────
Show-Step "Install-Kubectl / Install-Helm / Install-RancherCli"
Write-Host "Downloads into: $(Join-Path $env:LOCALAPPDATA 'PowerShellClusterBootstrap\tools')" -ForegroundColor Gray
Write-Host "(no-op if already downloaded — safe to run on every install)" -ForegroundColor Gray
Install-Kubectl
Install-Helm
Install-RancherCli

# ── 2. Overriding the tools directory ─────────────────────────────
Show-Step "Set-ClusterBootstrapToolsDir"
Write-Host "A project with its own .tools\ directory would call this once, before" -ForegroundColor Gray
Write-Host "any Install-* function, e.g.:" -ForegroundColor Gray
Write-Host '  Set-ClusterBootstrapToolsDir -Path "$PSScriptRoot\.tools"' -ForegroundColor White

# ── 3. The state-file contract ─────────────────────────────────────
Show-Step "Set-ClusterContext's state-file contract"
$demoDir = Join-Path $env:TEMP "cluster-bootstrap-demo"
New-Item -ItemType Directory -Path $demoDir -Force | Out-Null
@{ ClusterName = "demo-cluster"; SshServer = "demo.example.com"; KubeconfigPath = "~/.kube/does-not-exist.yaml" } |
    ConvertTo-Json | Set-Content -Path (Join-Path $demoDir ".rke2-state.json") -Encoding UTF8
Write-Host "Wrote a sample $demoDir\.rke2-state.json :" -ForegroundColor Gray
Get-Content (Join-Path $demoDir ".rke2-state.json")
Write-Host ""
Write-Host "Set-ClusterContext -BaseDir '$demoDir' -Platform 'RKE2 (On-Premise)' would now" -ForegroundColor Gray
Write-Host "read that file and point `$env:KUBECONFIG at KubeconfigPath. Not calling it here" -ForegroundColor Gray
Write-Host "since the kubeconfig path above is intentionally fake." -ForegroundColor Gray
Remove-Item $demoDir -Recurse -Force -ErrorAction SilentlyContinue

# ── 4. Functions that need a real cluster ──────────────────────────
Show-Step "Get-IngressClass / Reset-StuckHelmRelease"
$currentCtx = & kubectl config current-context 2>$null
if ($LASTEXITCODE -eq 0 -and $currentCtx) {
    Write-Host "kubectl is currently pointed at: $currentCtx" -ForegroundColor Gray
    Write-Host "Get-IngressClass -> " -NoNewline -ForegroundColor Gray
    Write-Host (Get-IngressClass) -ForegroundColor White
    Write-Host "Reset-StuckHelmRelease -ReleaseName 'this-release-does-not-exist' -Namespace 'default'" -ForegroundColor Gray
    Reset-StuckHelmRelease -ReleaseName "this-release-does-not-exist" -Namespace "default"
    Write-Host "(no output above is correct — it no-ops for a release that doesn't exist)" -ForegroundColor Gray
} else {
    Write-Host "No kubectl context configured — skipping the live cluster checks." -ForegroundColor Yellow
    Write-Host "Connect to any cluster and re-run this script to see them in action." -ForegroundColor Yellow
}

# ── 5. What's not demoed here, and why ─────────────────────────────
Show-Step "Initialize-*Cluster / Write-*Secret / Get-AksIngressIp / Get-EksIngressIp"
Write-Host "These create real cloud resources, write real secrets, or poll a real" -ForegroundColor Gray
Write-Host "LoadBalancer — not safe to run unattended in a demo. See:" -ForegroundColor Gray
Write-Host "  Get-Help Initialize-AksCluster -Full" -ForegroundColor White
Write-Host "  Get-Help Write-AzureKeyVaultSecret -Full" -ForegroundColor White
Write-Host ""

Write-Host "Demo complete." -ForegroundColor Cyan
