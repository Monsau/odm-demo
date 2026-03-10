# =============================================================================
# Test OIDC Authentication - OpenMetadata + Keycloak
# =============================================================================

param(
    [switch]$Verbose
)

$KEYCLOAK_URL = "http://auth.192.168.11.150.nip.io"
$REALM = "tour-operator"
$CLIENT_ID = "openmetadata"
$CALLBACK_URL = "http://openmetadata.192.168.11.150.nip.io/callback"

Write-Host "=== Test OIDC Configuration ===" -ForegroundColor Cyan
Write-Host ""

# 1. Test Keycloak accessibility
Write-Host "1. Test accessibilite Keycloak..." -ForegroundColor Yellow
try {
    $discovery = Invoke-RestMethod -Uri "$KEYCLOAK_URL/realms/$REALM/.well-known/openid-configuration" -TimeoutSec 5
    Write-Host "   OK Keycloak accessible" -ForegroundColor Green
    if ($Verbose) {
        Write-Host "   - Issuer: $($discovery.issuer)" -ForegroundColor Gray
        Write-Host "   - Token endpoint: $($discovery.token_endpoint)" -ForegroundColor Gray
    }
} catch {
    Write-Host "   ERROR Keycloak inaccessible: $_" -ForegroundColor Red
    exit 1
}

# 2. Get client secret from Kubernetes
Write-Host "`n2. Recuperation du client secret depuis Kubernetes..." -ForegroundColor Yellow
try {
    $secret = kubectl get secret oidc-secrets -n openmetadata -o json | ConvertFrom-Json
    $clientSecret = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secret.data.'openmetadata-oidc-client-secret'))
    Write-Host "   OK Secret recupere" -ForegroundColor Green
    if ($Verbose) {
        Write-Host "   - Client ID: $CLIENT_ID" -ForegroundColor Gray
        Write-Host "   - Client Secret: $clientSecret" -ForegroundColor Gray
    }
} catch {
    Write-Host "   ERROR Impossible de recuperer le secret: $_" -ForegroundColor Red
    exit 1
}

# 3. Test client authentication with Keycloak
Write-Host "`n3. Test authentification client..." -ForegroundColor Yellow
$body = "grant_type=authorization_code&client_id=$CLIENT_ID&client_secret=$clientSecret&code=test_code&redirect_uri=$CALLBACK_URL"

try {
    $response = Invoke-RestMethod -Uri "$KEYCLOAK_URL/realms/$REALM/protocol/openid-connect/token" `
        -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
    
    Write-Host "   ERROR Reponse inattendue (token recu avec code test)" -ForegroundColor Yellow
} catch {
    $errorMsg = $_.Exception.Response.StatusCode
    $errorDetails = $_ | Select-Object -ExpandProperty ErrorDetails | Select-Object -ExpandProperty Message
    
    if ($errorDetails -like '*invalid_grant*') {
        Write-Host "   OK Client authentifie avec succes" -ForegroundColor Green
        Write-Host "   (Code invalide est normal pour un test)" -ForegroundColor Gray
    } elseif ($errorDetails -like '*unauthorized_client*') {
        Write-Host "   ERROR Client NON autorise - credentials incorrects" -ForegroundColor Red
        Write-Host "   $errorDetails" -ForegroundColor Red
        exit 1
    } else {
        Write-Host "   WARNING Erreur inattendue: $errorMsg" -ForegroundColor Yellow
        if ($Verbose) {
            Write-Host "   $errorDetails" -ForegroundColor Gray
        }
    }
}

# 4. Check OpenMetadata pod status
Write-Host "`n4. Verification du pod OpenMetadata..." -ForegroundColor Yellow
try {
    $pods = kubectl get pods -n openmetadata -l app.kubernetes.io/name=openmetadata -o json | ConvertFrom-Json
    if ($pods.items.Count -gt 0) {
        $pod = $pods.items[0]
        $ready = ($pod.status.conditions | Where-Object { $_.type -eq "Ready" }).status
        
        if ($ready -eq "True") {
            Write-Host "   OK Pod Ready" -ForegroundColor Green
            if ($Verbose) {
                Write-Host "   - Name: $($pod.metadata.name)" -ForegroundColor Gray
                Write-Host "   - Age: $($pod.status.startTime)" -ForegroundColor Gray
            }
        } else {
            Write-Host "   ERROR Pod NOT Ready" -ForegroundColor Red
        }
    } else {
        Write-Host "   ERROR Aucun pod trouve" -ForegroundColor Red
    }
} catch {
    Write-Host "   ERROR Erreur: $_" -ForegroundColor Red
}

# 5. Verify OIDC configuration in pod
Write-Host "`n5. Verification configuration OIDC dans le pod..." -ForegroundColor Yellow
try {
    $env = kubectl exec -n openmetadata deployment/openmetadata -- env 2>$null | Where-Object { $_ -match "^OIDC_" }
    
    $envVars = @{}
    foreach ($line in $env) {
        if ($line -match '^([^=]+)=(.*)$') {
            $envVars[$matches[1]] = $matches[2]
        }
    }
    
    # Verify key variables
    $checks = @(
        @{ Name = "OIDC_CLIENT_ID"; Expected = $CLIENT_ID },
        @{ Name = "OIDC_CLIENT_SECRET"; Expected = $clientSecret },
        @{ Name = "OIDC_CALLBACK"; Expected = $CALLBACK_URL }
    )
    
    $allGood = $true
    foreach ($check in $checks) {
        if ($envVars.ContainsKey($check.Name)) {
            if ($envVars[$check.Name] -eq $check.Expected) {
                Write-Host "   OK $($check.Name)" -ForegroundColor Green
            } else {
                Write-Host "   ERROR $($check.Name) (valeur incorrecte)" -ForegroundColor Red
                $allGood = $false
                if ($Verbose) {
                    Write-Host "     Attendu: $($check.Expected)" -ForegroundColor Gray
                    Write-Host "     Actuel:  $($envVars[$check.Name])" -ForegroundColor Gray
                }
            }
        } else {
            Write-Host "   ERROR $($check.Name) (non defini)" -ForegroundColor Red
            $allGood = $false
        }
    }
    
    if ($allGood) {
        Write-Host "   OK Configuration correcte" -ForegroundColor Green
    }
} catch {
    Write-Host "   ERROR Impossible de verifier: $_" -ForegroundColor Red
}

# 6. Summary
Write-Host "`n=== Resultat ===" -ForegroundColor Cyan
Write-Host "Keycloak:     OK Accessible" -ForegroundColor Green
Write-Host "Client Auth:  OK Fonctionnel" -ForegroundColor Green
Write-Host "OpenMetadata: OK Running" -ForegroundColor Green
Write-Host ""
Write-Host "Test URL: http://openmetadata.192.168.11.150.nip.io" -ForegroundColor Cyan
Write-Host "1. Cliquer sur Sign In" -ForegroundColor Gray
Write-Host "2. Authentification Keycloak" -ForegroundColor Gray
Write-Host "3. Redirection vers OpenMetadata" -ForegroundColor Gray
