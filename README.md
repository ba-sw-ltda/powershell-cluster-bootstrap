# PowerShellClusterBootstrap

Cluster bootstrap for PowerShell installer scripts: install the CLI tools
you need (kubectl, helm, cloud CLIs), then create-or-connect to a cluster on
Azure AKS, AWS EKS, Google GKE, RKE2, or Kind — plus a handful of small,
genuinely platform-agnostic utilities (Helm release recovery, ingress/LB IP
discovery, cloud-native secret writing) that come up in basically every
Kubernetes installer script and have nothing to do with any one project's
own component architecture.

Extracted from [ba-sw-ltda/kubernetes-base-installer](https://github.com/ba-sw-ltda/kubernetes-base-installer),
where it still does this exact job for ~30 component installers, alongside
[powershell-menu-ui](https://github.com/ba-sw-ltda/powershell-menu-ui) for
the interactive prompts.

## Concept

Two halves:

1. **Bootstrap** — `Install-Kubectl`/`Install-Helm`/`Install-RancherCli`/
   `Install-PlatformTools` get the CLIs you need onto `$env:PATH`, then
   `Initialize-ClusterEnvironment` (or one of the per-platform
   `Initialize-*Cluster` functions it dispatches to) creates a cluster or
   connects to an existing one and leaves you with a working kubeconfig.
   Do this once, at the start of an install.
2. **Reconnect** — every *other* script in a multi-script installer (one
   script per component, run independently, possibly on a different day)
   needs to point kubectl at the right cluster again without recreating
   anything. `Set-ClusterContext` does that: give it a platform and a
   directory containing that platform's small state JSON file, and it sets
   `$env:KUBECONFIG` accordingly — cheaply, caching the last context for the
   life of the process so repeated calls don't re-authenticate every time.

Everything else (`Reset-StuckHelmRelease`, `Get-IngressClass`,
`Get-AksIngressIp`/`Get-EksIngressIp`, the `Write-*Secret` functions) is a
standalone utility you reach for as needed — no setup, no shared state, just
call them.

### The state-file contract

`Set-ClusterContext` and the three cloud `Write-*Secret` functions don't
take cluster details as parameters — they read a small JSON file from
`-BaseDir`, one per platform, that *you* write after creating the cluster:

| Platform | File | Fields read |
|---|---|---|
| RKE2 | `.rke2-state.json` | `KubeconfigPath`, `SshServer` (display only) |
| Azure AKS | `.aks-state.json` | `SubscriptionId`, `ResourceGroup`, `ClusterName`, `Location`, `VaultName` (for `Write-AzureKeyVaultSecret`) |
| AWS EKS | `.eks-state.json` | `Region`, `ClusterName` |
| Google GKE | `.gke-state.json` | `ProjectId`, `Zone`, `ClusterName` |
| Kind | `.kind-state.json` | `ClusterName` |

This is the one piece of "shared contract" between your installer and this
module — write these files once after `Initialize-ClusterEnvironment`
succeeds, and every later script that calls `Set-ClusterContext` can find
its way back to the cluster.

## Install

Not published to the PowerShell Gallery. Vendor it as a git submodule:

```powershell
git submodule add https://github.com/ba-sw-ltda/powershell-cluster-bootstrap.git _lib/powershell-cluster-bootstrap
```

```powershell
Import-Module "$PSScriptRoot/_lib/powershell-cluster-bootstrap/PowerShellClusterBootstrap.psd1"
```

Downloaded CLI tools (kubectl.exe, helm.exe, ...) are cached in
`%LOCALAPPDATA%\PowerShellClusterBootstrap\tools` by default. If your
project already has its own tools directory, point the module at it once,
before calling any `Install-*` function:

```powershell
Set-ClusterBootstrapToolsDir -Path "$PSScriptRoot\.tools"
```

**Cross-module note:** every `Install-*` function (`Install-Kubectl`,
`Install-Helm`, `Install-RancherCli`, `Install-PlatformTools`) and every
`Initialize-*Cluster` function render their single-line "Checking.../
Downloading.../✓ done" status via `Invoke-ScriptBlockWithSpinner` and
`Invoke-WithSpinner`, which live in
[powershell-menu-ui](https://github.com/ba-sw-ltda/powershell-menu-ui), not
in this module. Import that module too before calling them.

Requires Windows PowerShell 5.1+ or PowerShell 7+. Tested on Windows; the
cloud-CLI installers and `Update-HostsFile` are Windows-specific (MSI/EXE
installers, `C:\Windows\System32\drivers\etc\hosts`).

## Functions

| Function | What it does |
|---|---|
| `Install-Kubectl` / `Install-Helm` / `Install-RancherCli` | Download a pinned version into the tools directory if not already present. |
| `Install-PlatformTools` | Installs the CLI for one platform (`az`, `aws`+`eksctl`, `gcloud`+auth plugin, `kind`, or `plink` for RKE2 password SSH). |
| `Initialize-ClusterEnvironment` | Dispatches to the right `Initialize-*Cluster` function for `-Platform`. |
| `Initialize-AksCluster` / `Initialize-EksCluster` / `Initialize-GkeCluster` / `Initialize-KindCluster` / `Initialize-Rke2Cluster` | Create-or-connect for one platform; ends with a working kubeconfig and confirmed kubectl context. |
| `Set-ClusterContext` | Reconnects kubectl to an already-provisioned cluster, reading that platform's state file from `-BaseDir`. |
| `Confirm-KubectlContext` | Verifies/fixes the active kubectl context after a get-credentials call. |
| `Reset-StuckHelmRelease` | Recovers a Helm release stuck in `pending-*`/`failed` (rollback, or uninstall if there's nothing to roll back to). |
| `Get-IngressClass` | Returns the cluster's default IngressClass (falls back to first available, then `"nginx"`). |
| `Get-AksIngressIp` / `Get-EksIngressIp` | Poll a Service for its LoadBalancer IP (AKS) or hostname-then-resolve (EKS). |
| `Write-AzureKeyVaultSecret` / `Write-AwsSecretsManagerSecret` / `Write-GcpSecretManagerSecret` | Write a secret to the respective cloud-native secret manager, one entry per key. |
| `Update-HostsFile` | Adds/updates hostnames in the local hosts file, one UAC prompt for the whole batch. |
| `Test-CommandExists` / `Get-Os` | Small lookups used internally and useful standalone. |
| `Set-ClusterBootstrapToolsDir` | Override where downloaded CLI tools are cached (see Install above). |

Every function has full comment-based help — run `Get-Help <FunctionName> -Full`
after importing the module.

## Try it

[`examples/Demo.ps1`](examples/Demo.ps1) walks through the parts that don't
require an actual cloud account or cluster: tool installation, the
state-file contract, and `Get-IngressClass`/`Reset-StuckHelmRelease` against
whatever cluster your current kubeconfig already points at (skipped if none
is configured).

```powershell
.\examples\Demo.ps1
```
