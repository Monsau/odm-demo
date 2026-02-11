#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-openmetadata}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

info() { printf "[INFO] %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*"; }

die() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

for cmd in kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || die "Missing required command: $cmd"
 done

info "Clearing namespace '${NAMESPACE}' (this wipes PVCs in that namespace)."
if [[ -t 0 ]]; then
  read -r -p "Type 'yes' to continue: " confirm
  [[ "$confirm" == "yes" ]] || die "Aborted"
else
  warn "Non-interactive shell detected; continuing without confirmation."
fi

kubectl delete namespace "${NAMESPACE}" --ignore-not-found=true >/dev/null 2>&1 || true

info "Waiting for namespace '${NAMESPACE}' to terminate (timeout: ${TIMEOUT_SECONDS}s)..."
start_ts="$(date +%s)"
while true; do
  if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
    break
  fi

  now_ts="$(date +%s)"
  elapsed=$((now_ts - start_ts))
  if (( elapsed >= TIMEOUT_SECONDS )); then
    die "Timeout waiting for namespace '${NAMESPACE}' deletion. Check stuck finalizers with: kubectl get ns ${NAMESPACE} -o json"
  fi

  sleep 5
done

info "Re-applying ArgoCD manifests (AppProject + Applications) from ./argocd via kustomize."
kubectl apply -k "${PROJECT_ROOT}/argocd" >/dev/null

info "Done. ArgoCD will recreate '${NAMESPACE}' and resync the Helm releases."
info "Tip: In ArgoCD UI, watch apps: openmetadata-infra -> openmetadata-dependencies -> openmetadata"
