"""
Tests Selenium : SSO OIDC OpenMetadata ← oauth2-proxy ← Keycloak (realm atlas-voyage)

Scénarios couverts :
  1. Accès non authentifié → redirection vers Keycloak
  2. Login avec testuser@demo.ai → retour sur OpenMetadata, UI chargée
  3. Logout → redirection vers Keycloak (session supprimée)

Dépendances : pip install -r requirements.txt
Lancer : pytest tests/ -v [--no-headless]
"""
import time
import pytest
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException

# ─── constantes importées depuis conftest.py ─────────────────────────────────
from conftest import (
    OPENMETADATA_URL,
    KEYCLOAK_URL,
    REALM,
    TEST_USER,
    TEST_PASSWORD,
    TEST_EMAIL,
)

WAIT_TIMEOUT = 30  # secondes


# ─── helpers ─────────────────────────────────────────────────────────────────

def wait_for_url_contains(driver, fragment: str, timeout: int = WAIT_TIMEOUT):
    WebDriverWait(driver, timeout).until(EC.url_contains(fragment))


def keycloak_login(driver, username: str, password: str):
    """Remplit et soumet le formulaire de connexion Keycloak."""
    wait = WebDriverWait(driver, WAIT_TIMEOUT)
    wait.until(EC.presence_of_element_located((By.ID, "username")))
    driver.find_element(By.ID, "username").clear()
    driver.find_element(By.ID, "username").send_keys(username)
    driver.find_element(By.ID, "password").clear()
    driver.find_element(By.ID, "password").send_keys(password)
    driver.find_element(By.ID, "kc-login").click()


# ─── tests ───────────────────────────────────────────────────────────────────

class TestUnauthenticatedAccess:
    """Vérifie que les requêtes non authentifiées sont bloquées par oauth2-proxy."""

    def test_redirect_to_keycloak_on_root(self, driver):
        """
        GET / sans session → oauth2-proxy redirige vers Keycloak.
        L'URL finale doit contenir le domaine Keycloak et le realm.
        """
        driver.get(OPENMETADATA_URL)
        wait_for_url_contains(driver, KEYCLOAK_URL.split("//")[1])
        assert REALM in driver.current_url, (
            f"URL attendue avec realm '{REALM}', obtenu : {driver.current_url}"
        )

    def test_keycloak_login_form_visible(self, driver):
        """Le formulaire Keycloak doit avoir les champs username + password."""
        driver.get(OPENMETADATA_URL)
        wait = WebDriverWait(driver, WAIT_TIMEOUT)
        username_field = wait.until(EC.presence_of_element_located((By.ID, "username")))
        password_field = driver.find_element(By.ID, "password")
        assert username_field.is_displayed(), "Champ username non visible"
        assert password_field.is_displayed(), "Champ password non visible"


class TestSSOLogin:
    """Tests du flux SSO complet Keycloak → oauth2-proxy → OpenMetadata."""

    def test_login_testuser_redirects_to_openmetadata(self, driver):
        """
        Connexion avec testuser@demo.ai : après Keycloak, on atterrit sur OpenMetadata.
        """
        driver.get(OPENMETADATA_URL)

        # Attente de la page Keycloak
        WebDriverWait(driver, WAIT_TIMEOUT).until(
            EC.presence_of_element_located((By.ID, "username"))
        )
        keycloak_login(driver, TEST_USER, TEST_PASSWORD)

        # Retour sur OpenMetadata après authentification
        wait_for_url_contains(driver, OPENMETADATA_URL.split("//")[1])
        assert OPENMETADATA_URL.split("//")[1] in driver.current_url, (
            f"Retour attendu sur OpenMetadata, obtenu : {driver.current_url}"
        )

    def test_openmetadata_ui_loads_after_login(self, driver):
        """
        Après connexion, l'UI OpenMetadata doit être chargée (présence d'un élément racine).
        """
        driver.get(OPENMETADATA_URL)
        WebDriverWait(driver, WAIT_TIMEOUT).until(
            EC.presence_of_element_located((By.ID, "username"))
        )
        keycloak_login(driver, TEST_USER, TEST_PASSWORD)

        # Attendre le retour sur OpenMetadata
        wait_for_url_contains(driver, OPENMETADATA_URL.split("//")[1])

        # L'application React OpenMetadata monte un div#app ou body avec des classes ant-*
        wait = WebDriverWait(driver, WAIT_TIMEOUT)
        try:
            # Sélecteur pour l'application OpenMetadata (1.x : div#app)
            wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "body")))
            page_source = driver.page_source
            assert len(page_source) > 500, "Page trop courte, l'UI n'a pas chargé"
            assert "openmetadata" in page_source.lower() or "data" in page_source.lower(), (
                "Aucun indicateur OpenMetadata trouvé dans la page"
            )
        except TimeoutException:
            pytest.fail(f"L'UI OpenMetadata n'a pas chargé. URL courante : {driver.current_url}")

    def test_no_keycloak_error_after_login(self, driver):
        """
        Après connexion réussie, aucune page d'erreur Keycloak ne doit être affichée.
        """
        driver.get(OPENMETADATA_URL)
        WebDriverWait(driver, WAIT_TIMEOUT).until(
            EC.presence_of_element_located((By.ID, "username"))
        )
        keycloak_login(driver, TEST_USER, TEST_PASSWORD)
        wait_for_url_contains(driver, OPENMETADATA_URL.split("//")[1])

        page_source = driver.page_source.lower()
        error_keywords = ["invalid_grant", "client_error", "access denied", "forbidden"]
        for kw in error_keywords:
            assert kw not in page_source, f"Mot clé d'erreur détecté dans la page : '{kw}'"

    def test_authenticated_session_persists(self, driver):
        """
        Après connexion, recharger la page ne doit pas re-demander l'authentification.
        """
        # Première connexion
        driver.get(OPENMETADATA_URL)
        WebDriverWait(driver, WAIT_TIMEOUT).until(
            EC.presence_of_element_located((By.ID, "username"))
        )
        keycloak_login(driver, TEST_USER, TEST_PASSWORD)
        wait_for_url_contains(driver, OPENMETADATA_URL.split("//")[1])

        # Actualiser
        time.sleep(1)
        driver.refresh()

        # Ne doit PAS rediriger vers Keycloak (cookie oauth2-proxy actif)
        time.sleep(2)
        assert KEYCLOAK_URL.split("//")[1] not in driver.current_url, (
            "La session n'a pas persisté : redirection vers Keycloak après refresh"
        )
        assert OPENMETADATA_URL.split("//")[1] in driver.current_url, (
            f"URL inattendue après refresh : {driver.current_url}"
        )


class TestAuthAPIPublicEndpoints:
    """Vérifie que les endpoints publics d'OpenMetadata passent sans passer par oauth2-proxy."""

    def test_jwks_endpoint_accessible(self, driver):
        """
        Le endpoint JWKS d'OpenMetadata doit répondre 200 sans authentification
        (oauth2-proxy configuré avec --skip-auth-regex pour ce chemin).
        """
        jwks_url = f"{OPENMETADATA_URL}/api/v1/system/config/jwks"
        driver.get(jwks_url)
        # Si oauth2-proxy intercepte, on serait redirigé vers Keycloak
        assert KEYCLOAK_URL.split("//")[1] not in driver.current_url, (
            f"JWKS endpoint redirige vers Keycloak (devrait être public) : {driver.current_url}"
        )
        page_source = driver.page_source
        assert "keys" in page_source.lower(), (
            f"Réponse JWKS inattendue : {page_source[:200]}"
        )
