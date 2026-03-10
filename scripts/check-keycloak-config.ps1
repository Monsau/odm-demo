# =============================================================================
# Script de vérification de la configuration Keycloak pour OpenMetadata
# =============================================================================

$KEYCLOAK_URL = "http://auth.192.168.11.150.nip.io"
$REALM = "tour-operator"
$CLIENT_ID = "openmetadata"

Write-Host "=== Vérification Configuration Keycloak ===" -ForegroundColor Cyan
Write-Host ""

# 1. Demander les credentials admin Keycloak
Write-Host "Entrez les credentials admin Keycloak:" -ForegroundColor Yellow
$adminUser = Read-Host "Username (admin)"
if ([string]::IsNullOrEmpty($adminUser)) { $adminUser = "admin" }
$adminPass = Read-Host "Password" -AsSecureString
$adminPassPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPass)
)

# 2. Obtenir un token admin
Write-Host "`nObtention du token admin..." -ForegroundColor Cyan
$tokenBody = @{
    client_id = "admin-cli"
    username = $adminUser
    password = $adminPassPlain
    grant_type = "password"
}

try {
    $tokenResponse = Invoke-RestMethod -Uri "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" `
        -Method Post -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
    $token = $tokenResponse.access_token
    Write-Host "✓ Token obtenu" -ForegroundColor Green
} catch {
    Write-Host "✗ Erreur d'authentification: $_" -ForegroundColor Red
    exit 1
}

# 3. Récupérer la configuration du client OpenMetadata
Write-Host "`nRécupération du client '$CLIENT_ID'..." -ForegroundColor Cyan
$headers = @{
    Authorization = "Bearer $token"
}

try {
    $clients = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID" `
        -Method Get -Headers $headers
    
    if ($clients.Count -eq 0) {
        Write-Host "X Client '$CLIENT_ID' non trouve dans le realm '$REALM'" -ForegroundColor Red
        Write-Host "`nActions a effectuer:" -ForegroundColor Yellow
        Write-Host "1. Creer un client '$CLIENT_ID' dans Keycloak"
        Write-Host "2. Configurer Access Type: confidential"
        Write-Host "3. Configurer Valid Redirect URIs"
        exit 1
    }
    
    $client = $clients[0]
    Write-Host "✓ Client trouvé" -ForegroundColor Green
    
} catch {
    Write-Host "✗ Erreur API: $_" -ForegroundColor Red
    exit 1
}

# 4. Afficher la configuration actuelle
Write-Host "`n=== Configuration du client ===" -ForegroundColor Cyan
Write-Host "Client ID: $($client.clientId)"
Write-Host "Client UUID: $($client.id)"
Write-Host "Enabled: $($client.enabled)"
Write-Host "Client Authenticator: $($client.clientAuthenticatorType)"
Write-Host "Public Client: $($client.publicClient)"
Write-Host "Standard Flow Enabled: $($client.standardFlowEnabled)"
Write-Host "Direct Access Grants: $($client.directAccessGrantsEnabled)"
Write-Host "Service Accounts Enabled: $($client.serviceAccountsEnabled)"

# 5. Vérifier les Redirect URIs
Write-Host "`n=== Valid Redirect URIs ===" -ForegroundColor Cyan
$expectedUri = "http://openmetadata.192.168.11.150.nip.io/callback"
$redirectUris = $client.redirectUris

if ($redirectUris) {
    foreach ($uri in $redirectUris) {
        if ($uri -eq $expectedUri) {
            Write-Host "✓ $uri" -ForegroundColor Green
        } else {
            Write-Host "  $uri" -ForegroundColor Gray
        }
    }
    
    if ($redirectUris -notcontains $expectedUri) {
        Write-Host "`n⚠ URI manquant: $expectedUri" -ForegroundColor Yellow
    }
} else {
    Write-Host "✗ Aucun redirect URI configuré" -ForegroundColor Red
}

# 6. Récupérer le client secret
Write-Host "`n=== Client Secret ===" -ForegroundColor Cyan
try {
    $secretResponse = Invoke-RestMethod -Uri "$KEYCLOAK_URL/admin/realms/$REALM/clients/$($client.id)/client-secret" `
        -Method Get -Headers $headers
    
    $keycloakSecret = $secretResponse.value
    Write-Host "Keycloak secret: $keycloakSecret"
    
    # Comparer avec le secret Kubernetes
    $k8sSecret = "ARCaDijupw1TpQOYlySiTvNLEWDkgl3J"
    Write-Host "K8s secret:      $k8sSecret"
    
    if ($keycloakSecret -eq $k8sSecret) {
        Write-Host "✓ Les secrets correspondent" -ForegroundColor Green
    } else {
        Write-Host "✗ Les secrets ne correspondent PAS" -ForegroundColor Red
        Write-Host "`nActions:" -ForegroundColor Yellow
        Write-Host "Option 1: Regénérer le secret dans Keycloak et mettre à jour K8s"
        Write-Host "Option 2: Mettre à jour le secret Keycloak avec: $k8sSecret"
    }
} catch {
    Write-Host "✗ Impossible de récupérer le secret: $_" -ForegroundColor Red
}

# 7. Recommandations
Write-Host "`n=== Configuration requise ===" -ForegroundColor Cyan
Write-Host "Client Authenticator Type: client-secret"
Write-Host "Access Type: confidential (publicClient: false)"
Write-Host "Standard Flow: Enabled"
Write-Host "Direct Access Grants: Enabled"
Write-Host "Valid Redirect URIs:"
Write-Host "  - http://openmetadata.192.168.11.150.nip.io/*"
Write-Host "  - http://openmetadata.192.168.11.150.nip.io/callback"

Write-Host "`n=== Vérifications terminées ===" -ForegroundColor Cyan
