# OpenMetadata - Déploiement Kubernetes via Helm

Déploiement d'[OpenMetadata](https://open-metadata.org/) sur Kubernetes en utilisant les charts Helm officiels.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                │
│                                                     │
│  ┌─────────────┐  ┌────────────┐  ┌──────────────┐ │
│  │  OpenMetadata│  │  OpenSearch│  │    MySQL     │ │
│  │   Server     │  │            │  │              │ │
│  │  :8585       │  │  :9200     │  │  :3306       │ │
│  └──────┬───────┘  └────────────┘  └──────────────┘ │
│         │                                           │
│  ┌──────┴───────┐                                   │
│  │   Airflow    │                                   │
│  │  (Ingestion) │                                   │
│  │  :8080       │                                   │
│  └──────────────┘                                   │
└─────────────────────────────────────────────────────┘
```

## Prérequis

- **Kubernetes** cluster (>= 1.25)
- **Helm** (>= 3.x)
- **kubectl** configuré sur le cluster cible

## Structure du projet

```
.
├── argocd/
│   ├── project.yaml                  # AppProject ArgoCD
│   ├── openmetadata-infra.yaml       # App ArgoCD - namespace
│   ├── openmetadata-dependencies.yaml# App ArgoCD - dépendances (MySQL, OpenSearch, Airflow)
│   └── openmetadata-app.yaml         # App ArgoCD - serveur OpenMetadata (multi-sources)
├── helm/
│   ├── openmetadata/
│   │   └── values.yaml              # Valeurs pour le chart OpenMetadata
│   └── openmetadata-dependencies/
│       └── values.yaml              # Valeurs pour les dépendances (MySQL, OpenSearch, Airflow)
├── k8s/
│   ├── namespace.yaml               # Namespace Kubernetes
│   └── secrets.yaml.example         # Exemple de secrets (à copier en secrets.yaml)
├── scripts/
│   └── deploy.sh                    # Script de déploiement
├── Makefile                         # Commandes Make
└── README.md
```

## Déploiement rapide

### 1. Configurer les secrets

```bash
cp k8s/secrets.yaml.example k8s/secrets.yaml
# Modifier les mots de passe dans k8s/secrets.yaml
```

## Déploiement via ArgoCD (GitOps)

Prérequis:
- ArgoCD installé sur le cluster (namespace `argocd`)
- Le repo Git `git@github.com:Monsau/odm-demo.git` est enregistré dans ArgoCD (SSH)

### Bootstrap (AppProject + Applications)

Option 1 (recommandé): créer l'application racine ArgoCD (app-of-apps). Elle va ensuite créer/synchroniser automatiquement le reste.

```bash
kubectl apply -f argocd/openmetadata-root.yaml
```

Option 2: appliquer directement les manifests (sans app-of-apps).

```bash
kubectl apply -k argocd
```

### Clear + redeploy (Windows / PowerShell)

Supprime le namespace `openmetadata` (incluant les PVC du namespace) puis ré-applique les manifests ArgoCD.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\redeploy.ps1
```

### Clear + redeploy (Linux / WSL / Git Bash)

```bash
chmod +x scripts/redeploy.sh
./scripts/redeploy.sh
```

### 2. Déployer avec Make

```bash
make install
```

### 3. Ou déployer avec le script

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh install
```

### 4. Accéder à OpenMetadata

```bash
make port-forward
# Ouvrir http://localhost:8585
# Login: admin / admin
```

### SSO (Keycloak / OIDC)

Dans ce cluster, Keycloak est exposé via un ingress (namespace `auth`) et le realm initialisé est `atlas-voyage`.

Notes pratiques pour un environnement "local + Traefik":
- Pour éviter de modifier le fichier hosts, ce repo utilise des FQDN nip.io basés sur l'IP Traefik: `192.168.11.150`.
- OpenMetadata: `http://openmetadata.192.168.11.150.nip.io`
- Keycloak: `http://auth.192.168.11.150.nip.io`
- Callback OIDC: `http://openmetadata.192.168.11.150.nip.io/callback`

Configuration "propre" côté OpenMetadata:
- `authority` utilise l'URL *publique* Keycloak (`auth.demo.ai`) car c'est celle utilisée par le navigateur pour la redirection.
- `discoveryUri` et les JWKS (`publicKeys`) utilisent l'URL *interne* Kubernetes (`keycloak.auth.svc.cluster.local`) pour éviter toute dépendance au DNS externe depuis les pods.

#### Vérification Keycloak (issuer / endpoints)

Tu peux vérifier ce que Keycloak annonce via le discovery document (depuis le cluster) :

```bash
kubectl -n openmetadata run tmp-curl --rm -i --restart=Never --image=curlimages/curl:8.6.0 -- \
  sh -c "curl -sS http://keycloak.auth.svc.cluster.local:8080/realms/atlas-voyage/.well-known/openid-configuration \
  | tr ',' '\\n' | grep -E 'issuer|authorization_endpoint|token_endpoint|jwks_uri' | head -n 20"
```

État constaté au 2026-02-20:
- `token_endpoint` et `jwks_uri` sont internes (OK pour OpenMetadata)
- `issuer` et `authorization_endpoint` annoncent `https://auth.demo.ai:8443/...` (pas idéal si ton ingress Keycloak est en HTTP/80)

#### Fix "propre" côté Keycloak (GitOps)

Keycloak est géré par l'Application ArgoCD `auth` (repo `https://github.com/Monsau/auth.git`, chemin `charts/auth`).
Pour avoir des URLs cohérentes, il faut ajuster la config Keycloak afin que le discovery document annonce le bon scheme/port.

Selon ton choix:
- **HTTP**: forcer l'URL publique à `http://auth.demo.ai` (port 80)
- **HTTPS**: activer TLS sur l'ingress `auth.demo.ai` et forcer l'URL publique à `https://auth.demo.ai` (port 443)

Dans tous les cas, l'objectif est de supprimer le `:8443` et d'avoir un `issuer` cohérent avec l'URL réellement utilisée par le navigateur.

## Commandes disponibles

| Commande               | Description                                    |
|------------------------|------------------------------------------------|
| `make install`         | Installer tout (dépendances + OpenMetadata)    |
| `make uninstall`       | Désinstaller tout                              |
| `make status`          | Voir le statut des pods et services            |
| `make port-forward`    | Port-forward vers localhost:8585               |
| `make deps`            | Installer uniquement les dépendances           |
| `make app`             | Installer uniquement OpenMetadata              |
| `make repo`            | Ajouter/mettre à jour le repo Helm             |
| `make lint`            | Valider les templates Helm                     |

## Déploiement manuel étape par étape

```bash
# 1. Ajouter le repo Helm
helm repo add open-metadata https://helm.open-metadata.org
helm repo update

# 2. Créer le namespace
kubectl apply -f k8s/namespace.yaml

# 3. Créer les secrets
kubectl apply -f k8s/secrets.yaml

# 4. Installer les dépendances
helm upgrade --install openmetadata-dependencies open-metadata/openmetadata-dependencies \
  --namespace openmetadata \
  --values helm/openmetadata-dependencies/values.yaml \
  --wait --timeout 10m

# 5. Installer OpenMetadata
helm upgrade --install openmetadata open-metadata/openmetadata \
  --namespace openmetadata \
  --values helm/openmetadata/values.yaml \
  --wait --timeout 10m
```

## Configuration

### Versions

| Composant      | Version |
|----------------|---------|
| OpenMetadata   | 1.11.8  |
| Chart Helm     | 1.11.8  |
| MySQL          | 8.0     |
| OpenSearch     | Latest  |

### Personnalisation

Les fichiers de configuration principaux :

- **`helm/openmetadata/values.yaml`** : Configuration du serveur OpenMetadata (authentification, base de données, Elasticsearch, etc.)
- **`helm/openmetadata-dependencies/values.yaml`** : Configuration des dépendances (MySQL, OpenSearch, Airflow)

### Exemples de personnalisation courantes

#### Activer un Ingress

Dans `helm/openmetadata/values.yaml` :
```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: openmetadata.mondomaine.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: openmetadata-tls
      hosts:
        - openmetadata.mondomaine.com
```

#### Augmenter les ressources

```yaml
resources:
  requests:
    cpu: 1
    memory: 2Gi
  limits:
    cpu: 4
    memory: 8Gi
```

## Dépannage

```bash
# Vérifier les pods
kubectl get pods -n openmetadata

# Logs du serveur OpenMetadata
kubectl logs -f deployment/openmetadata -n openmetadata

# Logs des dépendances
kubectl logs -f statefulset/mysql -n openmetadata
kubectl logs -f statefulset/opensearch -n openmetadata

# Décrire un pod en erreur
kubectl describe pod <pod-name> -n openmetadata
```

## Liens utiles

- [Documentation OpenMetadata](https://docs.open-metadata.org/)
- [Chart Helm sur Artifact Hub](https://artifacthub.io/packages/helm/open-metadata/openmetadata)
- [GitHub OpenMetadata](https://github.com/open-metadata/OpenMetadata)
- [Helm Values Reference](https://docs.open-metadata.org/latest/deployment/kubernetes/helm-values)

---

## Déploiement avec ArgoCD (GitOps)

### Prérequis

- ArgoCD installé sur le cluster
- Le repo Git accessible par ArgoCD (ajouter la clé SSH dans ArgoCD Settings > Repositories)

### 1. Enregistrer le repo dans ArgoCD

```bash
argocd repo add git@github.com:Monsau/odm-demo.git --ssh-private-key-path ~/.ssh/id_rsa
```

### 2. Créer les secrets manuellement (non gérés par ArgoCD)

```bash
kubectl create namespace openmetadata
kubectl create secret generic mysql-secrets \
  --from-literal=openmetadata-mysql-password=openmetadata_password \
  -n openmetadata
kubectl create secret generic airflow-secrets \
  --from-literal=openmetadata-airflow-password=admin \
  -n openmetadata

# (Optionnel) Si vous activez l'auth OIDC / Keycloak
kubectl create secret generic oidc-secrets \
  --from-literal=openmetadata-oidc-client-id=<client_id> \
  --from-literal=openmetadata-oidc-client-secret=<client_secret> \
  -n openmetadata
```

### 3. Appliquer les manifestes ArgoCD

```bash
# Créer le projet ArgoCD
kubectl apply -f argocd/project.yaml

# Déployer l'infra (namespace)
kubectl apply -f argocd/openmetadata-infra.yaml

# Déployer les dépendances (MySQL, OpenSearch, Airflow)
kubectl apply -f argocd/openmetadata-dependencies.yaml

# Déployer OpenMetadata (utilise les values du repo Git)
kubectl apply -f argocd/openmetadata-app.yaml
```

### 4. Suivre le déploiement

```bash
argocd app list
argocd app get openmetadata-dependencies
argocd app get openmetadata
```

### Architecture ArgoCD

```
ArgoCD
├── openmetadata-infra          → k8s/namespace.yaml (repo Git)
├── openmetadata-dependencies   → chart helm open-metadata/openmetadata-dependencies
└── openmetadata                → chart helm open-metadata/openmetadata
                                  + values depuis git@github.com:Monsau/odm-demo.git
```

L'application `openmetadata-app.yaml` utilise la fonctionnalité **multi-sources** d'ArgoCD : le chart Helm est récupéré depuis le repo Helm officiel, et les `values.yaml` sont lus depuis le repo Git. Toute modification des values dans Git déclenche automatiquement un sync.
