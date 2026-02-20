"""
Configuration pytest pour les tests SSO OpenMetadata.
Gère le cycle de vie du navigateur Selenium.
"""
import os
import pytest
from selenium import webdriver
from selenium.webdriver.chrome.service import Service as ChromeService
from selenium.webdriver.firefox.service import Service as FirefoxService

# ─── URLs (overridables via variables d'environnement) ───────────────────────
OPENMETADATA_URL = os.getenv("OM_URL", "http://openmetadata.192.168.11.150.nip.io")
KEYCLOAK_URL     = os.getenv("KC_URL", "http://auth.192.168.11.150.nip.io")
REALM            = os.getenv("KC_REALM", "atlas-voyage")

# ─── Credentials de test ─────────────────────────────────────────────────────
TEST_USER     = os.getenv("TEST_USER",     "testuser")
TEST_PASSWORD = os.getenv("TEST_PASSWORD", "TestPass1234!")
TEST_EMAIL    = os.getenv("TEST_EMAIL",    "testuser@demo.ai")


def pytest_addoption(parser):
    parser.addoption(
        "--browser",
        action="store",
        default="chrome",
        choices=["chrome", "firefox"],
        help="Navigateur Selenium à utiliser (chrome | firefox)",
    )
    parser.addoption(
        "--headless",
        action="store_true",
        default=True,
        help="Mode headless (ajouter --no-headless pour désactiver)",
    )
    parser.addoption(
        "--no-headless",
        action="store_false",
        dest="headless",
        help="Désactive le mode headless (fenêtre visible)",
    )


@pytest.fixture(scope="session")
def browser_name(request):
    return request.config.getoption("--browser")


@pytest.fixture(scope="session")
def headless(request):
    return request.config.getoption("--headless")


@pytest.fixture(scope="function")
def driver(browser_name, headless):
    """Démarre un navigateur Selenium et le ferme après le test."""
    if browser_name == "firefox":
        options = webdriver.FirefoxOptions()
        if headless:
            options.add_argument("--headless")
        try:
            from webdriver_manager.firefox import GeckoDriverManager
            d = webdriver.Firefox(service=FirefoxService(GeckoDriverManager().install()), options=options)
        except Exception:
            d = webdriver.Firefox(options=options)
    else:
        options = webdriver.ChromeOptions()
        if headless:
            options.add_argument("--headless=new")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--disable-gpu")
        options.add_argument("--window-size=1280,900")
        try:
            from webdriver_manager.chrome import ChromeDriverManager
            d = webdriver.Chrome(service=ChromeService(ChromeDriverManager().install()), options=options)
        except Exception:
            d = webdriver.Chrome(options=options)

    d.implicitly_wait(5)
    yield d
    d.quit()
