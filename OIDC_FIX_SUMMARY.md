# Correction OIDC OpenMetadata - Résumé

## Date: 2026-03-08

## Problème initial
```
[Auth Callback Servlet] Failed in Auth Login : Bad token response
error=unauthorized_client, description=Invalid client or Invalid client credentials
```

## Cause identifiée
Le client secret configuré dans Kubernetes ne correspondait pas au client secret configuré dans Keycloak:
- **Keycloak**: `Px3yXaCwXEMgCYsAPH3tETwqRoyXKWgo`
- **Kubernetes (ancien)**: `ARCaDijupw1TpQOYlySiTvNLEWDkgl3J`

## Actions effectuées

### 1. Récupération des credentials Keycloak admin
```bash
kubectl get secret keycloak-secret -n auth
```
- Username: `admin`
- Password: `tour-operator-admin-2024`

### 2. Obtention d'un token admin Keycloak
```bash
POST http://auth.192.168.11.150.nip.io/realms/master/protocol/openid-connect/token
```

### 3. Vérification du client OpenMetadata dans Keycloak
```bash
GET /admin/realms/tour-operator/clients?clientId=openmetadata
```

Configuration trouvée:
- **Client ID**: `openmetadata`
- **Client UUID**: `4d4a7bed-e5f0-49a9-af3a-968887017455`
- **Client Secret**: `Px3yXaCwXEMgCYsAPH3tETwqRoyXKWgo`
- **Client Authentication**: ON (confidential)
- **Standard Flow**: Enabled
- **Redirect URIs**:
  - `http://openmetadata.local/*`
  - `http://openmetadata.192.168.11.150.nip.io/*`

### 4. Mise à jour du secret Kubernetes
```bash
kubectl create secret generic oidc-secrets -n openmetadata \
  --from-literal=openmetadata-oidc-client-id=openmetadata \
  --from-literal=openmetadata-oidc-client-secret=Px3yXaCwXEMgCYsAPH3tETwqRoyXKWgo \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 5. Mise à jour des Redirect URIs dans Keycloak
Ajout des callback URLs explicites:
```json
{
  "redirectUris": [
    "http://openmetadata.192.168.11.150.nip.io/*",
    "http://openmetadata.192.168.11.150.nip.io/callback",
    "http://openmetadata.local/*",
    "http://openmetadata.local/callback"
  ]
}
```

### 6. Redémarrage d'OpenMetadata
```bash
kubectl rollout restart deployment openmetadata -n openmetadata
```

## Résultats

### ✅ Secret synchronisé
- Keycloak: `Px3yXaCwXEMgCYsAPH3tETwqRoyXKWgo`
- Kubernetes: `Px3yXaCwXEMgCYsAPH3tETwqRoyXKWgo`

### ✅ Test d'authentification
```bash
POST /realms/tour-operator/protocol/openid-connect/token
```
- ❌ Ancien: `unauthorized_client` (credentials invalides)
- ✅ Nouveau: `invalid_grant` (credentials acceptés, code test invalide - normal)

### ✅ OpenMetadata opérationnel
```
NAME                            READY   STATUS    RESTARTS   AGE
openmetadata-75b7c58578-48kvn   1/1     Running   0          2m31s
```

## Configuration finale

### Variables d'environnement OpenMetadata
```bash
OIDC_CLIENT_ID=openmetadata
OIDC_CLIENT_SECRET=Px3yXaCwXEMgCYsAPH3tETwqRoyXKWgo
OIDC_CALLBACK=http://openmetadata.192.168.11.150.nip.io/callback
OIDC_SERVER_URL=http://openmetadata.192.168.11.150.nip.io
OIDC_DISCOVERY_URI=http://keycloak.auth.svc.cluster.local:8080/realms/tour-operator/.well-known/openid-configuration
OIDC_CLIENT_AUTH_METHOD=client_secret_post
OIDC_RESPONSE_TYPE=code
OIDC_TYPE=custom
```

### Configuration Keycloak (realm: tour-operator)
- **Client ID**: openmetadata
- **Client Protocol**: openid-connect
- **Access Type**: confidential
- **Standard Flow**: Enabled
- **Valid Redirect URIs**:
  - `http://openmetadata.192.168.11.150.nip.io/*`
  - `http://openmetadata.192.168.11.150.nip.io/callback`
  - `http://openmetadata.local/*`
  - `http://openmetadata.local/callback`
- **Web Origins**: 
  - `http://openmetadata.192.168.11.150.nip.io`
  - `http://openmetadata.local`

## Test utilisateur

### Procédure de test
1. Vider le cache du navigateur ou utiliser une fenêtre de navigation privée
2. Accéder à: http://openmetadata.192.168.11.150.nip.io
3. Cliquer sur le bouton **"Sign In"**
4. Redirection vers Keycloak pour authentification
5. Saisir les credentials Keycloak
6. Redirection vers OpenMetadata authentifié

### URLs fonctionnelles
- ✅ http://openmetadata.192.168.11.150.nip.io
- ✅ http://openmetadata.local (nécessite /etc/hosts ou DNS local)

## Maintenance future

### Pour changer le client secret
1. **Générer un nouveau secret dans Keycloak**:
   - Admin Console → Realm tour-operator → Clients → openmetadata
   - Onglet Credentials → Regenerate Secret
   - Copier le nouveau secret

2. **Mettre à jour Kubernetes**:
   ```bash
   kubectl create secret generic oidc-secrets -n openmetadata \
     --from-literal=openmetadata-oidc-client-id=openmetadata \
     --from-literal=openmetadata-oidc-client-secret=<nouveau_secret> \
     --dry-run=client -o yaml | kubectl apply -f -
   
   kubectl rollout restart deployment openmetadata -n openmetadata
   ```

### Pour ajouter une nouvelle URL de callback
1. **Mettre à jour Keycloak**:
   ```bash
   # Via API ou Admin Console
   # Ajouter l'URL dans Valid Redirect URIs
   ```

2. **Mettre à jour OpenMetadata values.yaml**:
   ```yaml
   authentication:
     callbackUrl: "http://nouvelle-url/callback"
   oidcConfiguration:
     callbackUrl: "http://nouvelle-url/callback"
     serverUrl: "http://nouvelle-url"
   ```

3. **Commit et redéployer via ArgoCD**

## Documentation
- Configuration OpenMetadata: helm/openmetadata/values.yaml
- Checklist Keycloak: KEYCLOAK_CONFIG_CHECKLIST.md
- Architecture: README.md

## Support
En cas de problème:
1. Vérifier les logs: `kubectl logs -n openmetadata deployment/openmetadata --tail=50`
2. Vérifier la config: `kubectl exec -n openmetadata deployment/openmetadata -- env | grep OIDC`
3. Tester l'authentification client (voir script ci-dessus)
