# Checklist Configuration Keycloak pour OpenMetadata

## Problème actuel
```
[Auth Callback Servlet] Failed in Auth Login : Bad token response.
error=unauthorized_client, description=Invalid client or Invalid client credentials
```

## Cause
Le client `openmetadata` dans Keycloak n'est pas correctement configuré ou le client secret ne correspond pas.

## 🔍 Vérification étape par étape

### 1. Accéder à Keycloak Admin Console
```
URL: http://auth.192.168.11.150.nip.io
Username: admin
Password: [votre mot de passe admin]
```

### 2. Sélectionner le Realm
- Dans le menu déroulant en haut à gauche, sélectionner **tour-operator**
- Ne pas rester sur **master**

### 3. Vérifier l'existence du client
- Menu de gauche: **Clients**
- Chercher le client: **openmetadata**

#### Si le client n'existe PAS:
Créer un nouveau client:
- Client ID: `openmetadata`
- Client Protocol: `openid-connect`
- Root URL: `http://openmetadata.192.168.11.150.nip.io`

#### Si le client existe:
Cliquer dessus pour vérifier la configuration ci-dessous 👇

### 4. Onglet "Settings" - Configuration requise

#### General Settings
✅ **Client ID**: `openmetadata`  
✅ **Enabled**: `ON`  
✅ **Client Protocol**: `openid-connect`

#### Access Settings  
✅ **Root URL**: `http://openmetadata.192.168.11.150.nip.io`  
✅ **Valid Redirect URIs**:
```
http://openmetadata.192.168.11.150.nip.io/*
http://openmetadata.192.168.11.150.nip.io/callback
```
⚠️ **IMPORTANT**: Ces URIs doivent correspondre EXACTEMENT

✅ **Valid Post Logout Redirect URIs**: `+` (hérite des redirect URIs)
✅ **Web Origins**: `*` ou `http://openmetadata.192.168.11.150.nip.io`

#### Capability config
✅ **Client authentication**: `ON` (client confidentiel)  
✅ **Authorization**: `OFF` (pas nécessaire)  
✅ **Authentication flow**:
  - ✅ **Standard flow**: `ON` (Authorization Code Flow)
  - ⬜ **Direct access grants**: `OFF` (optionnel)
  - ⬜ **Implicit flow**: `OFF`
  - ⬜ **Service accounts roles**: `OFF`

**⚠️ Sauvegarder** après modification

### 5. Onglet "Credentials" - Vérifier le Client Secret

Le secret dans Kubernetes est actuellement:
```
ARCaDijupw1TpQOYlySiTvNLEWDkgl3J
```

#### Option A: Copier ce secret dans Keycloak (RECOMMANDÉ)
1. Dans l'onglet **Credentials**
2. Si "Client Authenticator" n'est pas `Client Id and Secret`, le changer
3. Cliquer sur **Regenerate** 
4. Remplacer la valeur générée par: `ARCaDijupw1TpQOYlySiTvNLEWDkgl3J`
5. **Sauvegarder**

#### Option B: Mettre à jour le secret Kubernetes
1. Noter le secret affiché dans Keycloak
2. Mettre à jour le secret K8s:
```powershell
kubectl create secret generic oidc-secrets -n openmetadata \
  --from-literal=openmetadata-oidc-client-id=openmetadata \
  --from-literal=openmetadata-oidc-client-secret=<secret_de_keycloak> \
  --dry-run=client -o yaml | kubectl apply -f -

# Redémarrer OpenMetadata pour prendre en compte le nouveau secret
kubectl rollout restart deployment openmetadata -n openmetadata
```

### 6. Onglet "Advanced" - Configuration optionnelle

✅ **Access Token Lifespan**: `5 Minutes` (par défaut OK)  
✅ **OAuth 2.0 Mutual TLS Certificate Bound Access Tokens Enabled**: `OFF`

### 7. Tester la configuration

Après avoir appliqué les changements:

1. **Vider le cache du navigateur** ou utiliser une fenêtre privée
2. Accéder à: `http://openmetadata.192.168.11.150.nip.io`
3. Cliquer sur **Sign In**
4. Vous devriez être redirigé vers Keycloak
5. Après connexion, retour sur OpenMetadata avec succès

## 🔧 Si l'erreur persiste

### Vérifier les logs OpenMetadata
```powershell
kubectl logs -n openmetadata deployment/openmetadata --tail=50 | Select-String "callback|token|Auth"
```

### Vérifier la configuration appliquée
```powershell
kubectl exec -n openmetadata deployment/openmetadata -- env | Select-String "OIDC"
```

Devrait montrer:
```
OIDC_CLIENT_ID=openmetadata
OIDC_CLIENT_SECRET=ARCaDijupw1TpQOYlySiTvNLEWDkgl3J
OIDC_CALLBACK=http://openmetadata.192.168.11.150.nip.io/callback
OIDC_CLIENT_AUTH_METHOD=client_secret_post
```

### Problèmes fréquents

❌ **URLs mixtes** (openmetadata.local vs 192.168.11.150.nip.io)
→ Toujours utiliser: `http://openmetadata.192.168.11.150.nip.io`

❌ **Client secret incorrect**
→ Vérifier correspondance entre Keycloak et K8s secret

❌ **Client authentication OFF**
→ Doit être ON pour un client confidentiel

❌ **Standard flow disabled**
→ Doit être ON pour Authorization Code flow

❌ **Redirect URI manquant ou incorrect**
→ Doit contenir `/callback` exact

## 📞 Support

Configuration actuelle côté OpenMetadata:
- Client ID: `openmetadata`
- Client Secret: `ARCaDijupw1TpQOYlySiTvNLEWDkgl3J`
- Callback URL: `http://openmetadata.192.168.11.150.nip.io/callback`
- Auth Method: `client_secret_post`
- Response Type: `code`
- Discovery URI: `http://keycloak.auth.svc.cluster.local:8080/realms/tour-operator/.well-known/openid-configuration`
