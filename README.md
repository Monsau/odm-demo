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
