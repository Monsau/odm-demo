#!/usr/bin/env bash
# =============================================================================
# Script de déploiement OpenMetadata via Helm
# =============================================================================
set -euo pipefail

NAMESPACE="${NAMESPACE:-openmetadata}"
RELEASE_NAME="${RELEASE_NAME:-openmetadata}"
DEPS_RELEASE_NAME="${DEPS_RELEASE_NAME:-openmetadata-dependencies}"
HELM_REPO_NAME="open-metadata"
HELM_REPO_URL="https://helm.open-metadata.org"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- Prérequis ----
check_prerequisites() {
    log_info "Vérification des prérequis..."
    for cmd in helm kubectl; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd n'est pas installé. Veuillez l'installer."
            exit 1
        fi
    done
    log_info "Prérequis OK."
}

# ---- Ajouter le repo Helm ----
add_helm_repo() {
    log_info "Ajout du repo Helm Open Metadata..."
    helm repo add "${HELM_REPO_NAME}" "${HELM_REPO_URL}" 2>/dev/null || true
    helm repo update
    log_info "Repo Helm mis à jour."
}

# ---- Créer le namespace ----
create_namespace() {
    log_info "Création du namespace '${NAMESPACE}'..."
    kubectl apply -f "${PROJECT_ROOT}/k8s/namespace.yaml"
}

# ---- Créer les secrets ----
create_secrets() {
    local secrets_file="${PROJECT_ROOT}/k8s/secrets.yaml"
    if [[ -f "${secrets_file}" ]]; then
        log_info "Application des secrets Kubernetes..."
        kubectl apply -f "${secrets_file}"
    else
        log_warn "Fichier secrets.yaml non trouvé. Création des secrets par défaut..."
        kubectl create secret generic mysql-secrets \
            --from-literal=openmetadata-mysql-password=openmetadata_password \
            --namespace="${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
        kubectl create secret generic airflow-secrets \
            --from-literal=openmetadata-airflow-password=admin \
            --namespace="${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    fi
}

# ---- Installer les dépendances ----
install_dependencies() {
    log_info "Installation des dépendances OpenMetadata (MySQL, OpenSearch, Airflow)..."
    helm upgrade --install "${DEPS_RELEASE_NAME}" \
        "${HELM_REPO_NAME}/openmetadata-dependencies" \
        --namespace "${NAMESPACE}" \
        --values "${PROJECT_ROOT}/helm/openmetadata-dependencies/values.yaml" \
        --wait \
        --timeout 10m
    log_info "Dépendances installées."
}

# ---- Installer OpenMetadata ----
install_openmetadata() {
    log_info "Installation d'OpenMetadata..."
    helm upgrade --install "${RELEASE_NAME}" \
        "${HELM_REPO_NAME}/openmetadata" \
        --namespace "${NAMESPACE}" \
        --values "${PROJECT_ROOT}/helm/openmetadata/values.yaml" \
        --wait \
        --timeout 10m
    log_info "OpenMetadata installé."
}

# ---- Vérifier le statut ----
check_status() {
    log_info "Statut des pods dans le namespace '${NAMESPACE}':"
    kubectl get pods -n "${NAMESPACE}"
    echo ""
    log_info "Statut des services:"
    kubectl get svc -n "${NAMESPACE}"
}

# ---- Désinstaller ----
uninstall() {
    log_warn "Désinstallation d'OpenMetadata..."
    helm uninstall "${RELEASE_NAME}" --namespace "${NAMESPACE}" 2>/dev/null || true
    helm uninstall "${DEPS_RELEASE_NAME}" --namespace "${NAMESPACE}" 2>/dev/null || true
    log_info "OpenMetadata désinstallé."
}

# ---- Port Forward ----
port_forward() {
    log_info "Port-forward OpenMetadata sur http://localhost:8585 ..."
    kubectl port-forward svc/openmetadata 8585:8585 -n "${NAMESPACE}"
}

# ---- Main ----
usage() {
    echo "Usage: $0 {install|uninstall|status|port-forward}"
    echo ""
    echo "Commands:"
    echo "  install       - Déployer OpenMetadata et ses dépendances"
    echo "  uninstall     - Supprimer OpenMetadata et ses dépendances"
    echo "  status        - Afficher le statut des pods et services"
    echo "  port-forward  - Ouvrir un port-forward vers OpenMetadata (localhost:8585)"
    exit 1
}

main() {
    local command="${1:-}"

    case "${command}" in
        install)
            check_prerequisites
            add_helm_repo
            create_namespace
            create_secrets
            install_dependencies
            install_openmetadata
            check_status
            echo ""
            log_info "OpenMetadata est déployé !"
            log_info "Pour accéder à l'UI: $0 port-forward puis http://localhost:8585"
            log_info "Identifiants par défaut: admin / admin"
            ;;
        uninstall)
            check_prerequisites
            uninstall
            ;;
        status)
            check_prerequisites
            check_status
            ;;
        port-forward)
            check_prerequisites
            port_forward
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
