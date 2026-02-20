"""
Tests Selenium : SSO OIDC via OpenMetadata natif → Keycloak (realm tour-operator)

Scénarios couverts :
  1. Accès non authentifié → page de login OpenMetadata (/signin), pas Keycloak
  2. Page /signin affiche le bouton SSO « Se Connecter avec Tour Operator »
  3. Clic sur le bouton SSO → redirection vers Keycloak
  4. Login complet → retour sur OpenMetadata authentifié
  5. UI OpenMetadata chargée après connexion
  6. Session persistante (refresh ne re-demande pas l'auth)
  7. Endpoint JWKS public accessible sans auth

Dépendances : pip install -r requirements.txt
Lancer : pytest tests/ -v [--no-headless]
"""
import time
import pytest
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException

from conftest import (
    OPENMETADATA_URL,
    KEYCLOAK_URL,
    REALM,
    TEST_USER,
    TEST_PASSWORD,
    TEST_EMAIL,
)

WAIT_TIMEOUT = 30  # secondes
OM_HOST = OPENMETADATA_URL.split("//")[1]  # openmetadata.local
KC_HOST = KEYCLOAK_URL.split("//")[1]       # auth.192.168.11.150.nip.io

SSO_BUTTON_CSS = "button.signin-button"


# ─── helpers ─────────────────────────────────────────────────────────────────

def wait_for_url_contains(driver, fragment: str, timeout: int = WAIT_TIMEOUT):
    WebDriverWait(driver, timeout).until(EC.url_contains(fragment))


def wait_for_om_signin(driver):
    """Attend la page de login OpenMetadata et le bouton SSO."""
    wait = WebDriverWait(driver, WAIT_TIMEOUT)
    wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, SSO_BUTTON_CSS)))


def click_sso_button(driver):
    """Clique sur le bouton SSO OpenMetadata."""
    btn = WebDriverWait(driver, WAIT_TIMEOUT).until(
        EC.element_to_be_clickable((By.CSS_SELECTOR, SSO_BUTTON_CSS))
    )
    btn.click()


def keycloak_login(driver, username: str, password: str):
    """Remplit et soumet le formulaire Keycloak."""
    wait = WebDriverWait(driver, WAIT_TIMEOUT)
    wait.until(EC.presence_of_element_located((By.ID, "username")))
    driver.find_element(By.ID, "username").clear()
    driver.find_element(By.ID, "username").send_keys(username)
    driver.find_element(By.ID, "password").clear()
    driver.find_element(By.ID, "password").send_keys(password)
    driver.find_element(By.ID, "kc-login").click()


def full_sso_login(driver):
    """Flux complet : OM login page → SSO button → Keycloak → retour OM."""
    driver.get(OPENMETADATA_URL)
    wait_for_om_signin(driver)
    click_sso_button(driver)
    # Redirection vers Keycloak
    wait_for_url_contains(driver, KC_HOST)
    keycloak_login(driver, TEST_USER, TEST_PASSWORD)
    # Retour sur OpenMetadata
    wait_for_url_contains(driver, OM_HOST)


# ─── tests ───────────────────────────────────────────────────────────────────

class TestUnauthenticatedAccess:
    """Vérifie que l'accès non authentifié affiche la page OM, pas Keycloak."""

    def test_unauthenticated_shows_om_signin_page(self, driver):
        """
        GET / sans session → OM affiche /signin, NON Keycloak.
        """
        driver.get(OPENMETADATA_URL)
        # Attendre que la page OM soit chargée (et non une redir automatique vers KC)
        wait = WebDriverWait(driver, WAIT_TIMEOUT)
        wait.until(lambda d: "signin" in d.current_url or "openmetadata" in d.current_url.lower())
        assert KC_HOST not in driver.current_url, (
            f"Redirection inattendue vers Keycloak : {driver.current_url}"
        )
        assert OM_HOST in driver.current_url, (
            f"URL attendue sur OpenMetadata, obtenu : {driver.current_url}"
        )

    def test_signin_page_has_sso_button(self, driver):
        """La page /signin doit afficher le bouton SSO Tour Operator."""
        driver.get(f"{OPENMETADATA_URL}/signin")
        wait = WebDriverWait(driver, WAIT_TIMEOUT)
        btn = wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, SSO_BUTTON_CSS)))
        assert btn.is_displayed(), "Le bouton SSO n'est pas visible"
        assert "Tour Operator" in btn.text, (
            f"Texte inattendu sur le bouton SSO : '{btn.text}'"
        )


class TestSSOLogin:
    """Tests du flux SSO complet OpenMetadata → Keycloak → OpenMetadata."""

    def test_sso_button_opens_keycloak(self, driver):
        """Cliquer sur le bouton SSO redirige vers Keycloak."""
        driver.get(f"{OPENMETADATA_URL}/signin")
        wait_for_om_signin(driver)
        click_sso_button(driver)
        wait_for_url_contains(driver, KC_HOST)
        assert REALM in driver.current_url, (
            f"URL Keycloak sans le realm '{REALM}' : {driver.current_url}"
        )
        # Formulaire Keycloak présent
        WebDriverWait(driver, WAIT_TIMEOUT).until(
            EC.presence_of_element_located((By.ID, "username"))
        )

    def test_login_testuser_redirects_to_openmetadata(self, driver):
        """Connexion avec testuser@demo.ai → retour sur OpenMetadata."""
        full_sso_login(driver)
        assert OM_HOST in driver.current_url, (
            f"Retour attendu sur OpenMetadata, obtenu : {driver.current_url}"
        )

    def test_openmetadata_ui_loads_after_login(self, driver):
        """Après connexion SSO, l'UI OpenMetadata doit être chargée."""
        full_sso_login(driver)
        wait = WebDriverWait(driver, WAIT_TIMEOUT)
        try:
            wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "body")))
            page_source = driver.page_source
            assert len(page_source) > 500, "Page trop courte, l'UI n'a pas chargé"
            assert any(kw in page_source.lower() for kw in ["openmetadata", "métadonnées", "explore", "ant-layout"]), (
                "Aucun indicateur de l'UI OpenMetadata trouvé dans la page"
            )
        except TimeoutException:
            pytest.fail(f"L'UI OpenMetadata n'a pas chargé. URL : {driver.current_url}")

    def test_no_error_after_login(self, driver):
        """Après connexion réussie, aucune page d'erreur ne doit s'afficher."""
        full_sso_login(driver)
        page_source = driver.page_source.lower()
        error_keywords = ["invalid_grant", "client_error", "access denied", "forbidden", "error_description"]
        for kw in error_keywords:
            assert kw not in page_source, f"Mot clé d'erreur détecté : '{kw}'"

    def test_authenticated_session_persists(self, driver):
        """Après connexion, un refresh ne doit pas redemander l'authentification."""
        full_sso_login(driver)
        time.sleep(1)
        driver.refresh()
        time.sleep(3)
        # Ne doit PAS rediriger vers Keycloak
        assert KC_HOST not in driver.current_url, (
            f"Session expirée : redirection vers Keycloak après refresh ({driver.current_url})"
        )
        assert OM_HOST in driver.current_url, (
            f"URL inattendue après refresh : {driver.current_url}"
        )


class TestAuthAPIPublicEndpoints:
    """Vérifie les endpoints publics d'OpenMetadata."""

    def test_jwks_endpoint_accessible(self, driver):
        """Le endpoint JWKS doit répondre sans authentification."""
        jwks_url = f"{OPENMETADATA_URL}/api/v1/system/config/jwks"
        driver.get(jwks_url)
        # Ne doit pas rediriger vers Keycloak
        assert KC_HOST not in driver.current_url, (
            f"JWKS endpoint redirige vers Keycloak : {driver.current_url}"
        )
        page_source = driver.page_source
        assert "keys" in page_source.lower(), (
            f"Réponse JWKS inattendue : {page_source[:200]}"
        )

