# =============================================================================
# Makefile - OpenMetadata Deployment
# =============================================================================

NAMESPACE       ?= openmetadata
RELEASE_NAME    ?= openmetadata
DEPS_RELEASE_NAME ?= openmetadata-dependencies
HELM_REPO       ?= open-metadata
HELM_REPO_URL   ?= https://helm.open-metadata.org
CHART_VERSION   ?= 2.0.0
JENA_NAMESPACE  ?= arcaq
JENA_SERVICE    ?= arcaq-knowledge-graph

.PHONY: help repo namespace secrets deps app install uninstall status port-forward lint demo jena-check upgrade-check

help: ## Afficher cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

repo: ## Ajouter et mettre à jour le repo Helm
	helm repo add $(HELM_REPO) $(HELM_REPO_URL) || true
	helm repo update

namespace: ## Créer le namespace Kubernetes
	kubectl apply -f k8s/namespace.yaml

secrets: ## Appliquer les secrets Kubernetes
	@if [ -f k8s/secrets.yaml ]; then \
		kubectl apply -f k8s/secrets.yaml; \
	else \
		echo "ATTENTION: k8s/secrets.yaml non trouvé. Copiez k8s/secrets.yaml.example"; \
		exit 1; \
	fi

deps: repo namespace secrets ## Installer les dépendances (MySQL, OpenSearch, Airflow)
	helm upgrade --install $(DEPS_RELEASE_NAME) \
		$(HELM_REPO)/openmetadata-dependencies \
		--namespace $(NAMESPACE) \
		--version $(CHART_VERSION) \
		--values helm/openmetadata-dependencies/values.yaml \
		--wait --timeout 10m

app: ## Installer OpenMetadata
	helm upgrade --install $(RELEASE_NAME) \
		$(HELM_REPO)/openmetadata \
		--namespace $(NAMESPACE) \
		--version $(CHART_VERSION) \
		--values helm/openmetadata/values.yaml \
		--wait --timeout 10m

install: deps app ## Installer tout (dépendances + OpenMetadata)
	@echo ""
	@echo "✅ OpenMetadata $(CHART_VERSION) déployé avec succès !"
	@echo "   Accès : make port-forward puis http://localhost:8585"
	@echo "   Login : admin / admin"

uninstall: ## Désinstaller OpenMetadata et ses dépendances
	helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE) || true
	helm uninstall $(DEPS_RELEASE_NAME) --namespace $(NAMESPACE) || true

status: ## Afficher le statut des pods
	kubectl get pods -n $(NAMESPACE)
	@echo ""
	kubectl get svc -n $(NAMESPACE)

port-forward: ## Port-forward vers OpenMetadata (localhost:8585)
	kubectl port-forward svc/openmetadata 8585:8585 -n $(NAMESPACE)

lint: ## Valider les templates Helm (dry-run)
	helm template $(RELEASE_NAME) $(HELM_REPO)/openmetadata \
		--namespace $(NAMESPACE) \
		--version $(CHART_VERSION) \
		--values helm/openmetadata/values.yaml > /dev/null && echo "✅ openmetadata values OK"
	helm template $(DEPS_RELEASE_NAME) $(HELM_REPO)/openmetadata-dependencies \
		--namespace $(NAMESPACE) \
		--version $(CHART_VERSION) \
		--values helm/openmetadata-dependencies/values.yaml > /dev/null && echo "✅ openmetadata-dependencies values OK"

jena-check: ## Vérifier la connectivité vers Jena Fuseki (arcaq-k8s)
	@echo "→ Test connectivité Jena Fuseki depuis le cluster..."
	kubectl -n $(NAMESPACE) run jena-probe --rm -i --restart=Never \
		--image=curlimages/curl:8.6.0 -- \
		sh -c "curl -sf http://$(JENA_SERVICE).$(JENA_NAMESPACE).svc.cluster.local:3030/$$/ping && echo '✅ Jena OK' || echo '❌ Jena injoignable'"

upgrade-check: repo ## Vérifier les versions disponibles du chart
	@echo "→ Version actuelle : $(CHART_VERSION)"
	@echo "→ Versions disponibles :"
	@helm search repo $(HELM_REPO)/openmetadata --versions | head -8

demo: install jena-check status ## Déploiement complet démo (install + vérifs)
	@echo ""
	@echo "🎯 Stack démo OpenMetadata $(CHART_VERSION) opérationnelle"
	@echo "   OpenMetadata : http://openmetadata.192.168.11.150.nip.io"
	@echo "   Keycloak SSO : https://auth.192.168.11.150.nip.io"
	@echo "   Jena Fuseki  : http://$(JENA_SERVICE).$(JENA_NAMESPACE).svc.cluster.local:3030"
