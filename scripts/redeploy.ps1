Param(
  [string]$Namespace = "openmetadata",
  [int]$TimeoutSeconds = 900
)

$ErrorActionPreference = "Stop"

function Write-Info($msg) { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }

$projectRoot = Split-Path -Parent $PSScriptRoot

Write-Info "Clearing namespace '$Namespace' (this wipes PVCs in that namespace)."
try {
  kubectl delete namespace $Namespace --ignore-not-found=true | Out-Host
} catch {
  Write-Warn "kubectl delete namespace returned an error (continuing): $($_.Exception.Message)"
}

Write-Info "Waiting for namespace '$Namespace' to terminate..."
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
  $ns = kubectl get namespace $Namespace -o name 2>$null
  if (-not $ns) { break }
  Start-Sleep -Seconds 5
}

if ($sw.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
  throw "Timeout waiting for namespace '$Namespace' deletion. Check stuck finalizers with: kubectl get ns $Namespace -o json"
}

Write-Info "Re-applying ArgoCD manifests (AppProject + Applications) from ./argocd via kustomize."
kubectl apply -k (Join-Path $projectRoot "argocd") | Out-Host

Write-Info "Done. ArgoCD will recreate '$Namespace' and resync the Helm releases."
Write-Info "Tip: In ArgoCD UI, watch apps: openmetadata-infra -> openmetadata-dependencies -> openmetadata"
