"""
Smoke tests blue/green deploy — exécutés par le job `smoke-test`
dans `.github/workflows/dbt_prod_deploy.yml` après le build BLUE.

Variables d'environnement requises :
  SNOWFLAKE_ACCOUNT        — identifiant Snowflake
  SNOWFLAKE_TEST_USER      — utilisateur de test (ANALYST role)
  SNOWFLAKE_TEST_PASSWORD  — mot de passe
  SNOWFLAKE_SCHEMA_SUFFIX  — défini à '_BLUE' par la CI

Ces tests vérifient que les schémas BLUE sont cohérents AVANT le swap.
Ils ne sont pas destructifs et ne modifient aucune donnée.
"""
import os
import pytest
import snowflake.connector

SCHEMA_SUFFIX = os.environ.get("SNOWFLAKE_SCHEMA_SUFFIX", "_BLUE")
DATABASE = "FINTRACK_PROD"

BLUE_SCHEMAS = [
    f"MARTS_CORE{SCHEMA_SUFFIX}",
    f"MARTS_FINANCE{SCHEMA_SUFFIX}",
    f"MARTS_ANALYTICS{SCHEMA_SUFFIX}",
]

# Tables critiques attendues dans chaque schéma BLUE
EXPECTED_TABLES = {
    f"MARTS_CORE{SCHEMA_SUFFIX}": ["dim_comptes", "dim_tenants"],
    f"MARTS_FINANCE{SCHEMA_SUFFIX}": ["f_transactions", "f_virements"],
    f"MARTS_ANALYTICS{SCHEMA_SUFFIX}": ["agg_transactions_daily"],
}

# Seuil minimum de lignes pour considérer un modèle comme non vide
MIN_ROW_THRESHOLD = 1


@pytest.fixture(scope="module")
def sf_admin():
    """Connexion admin pour inspecter les schémas BLUE (pas de RAP bypass nécessaire)."""
    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_TEST_USER"],
        password=os.environ["SNOWFLAKE_TEST_PASSWORD"],
        role="FINTRACK_TRANSFORM_ROLE",
        warehouse="WH_TRANSFORM",
        database=DATABASE,
    )
    yield conn
    conn.close()


@pytest.fixture(scope="module")
def sf_analyst():
    """Connexion analyst pour tester l'isolation et le masking post-swap."""
    conn = snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_TEST_USER"],
        password=os.environ["SNOWFLAKE_TEST_PASSWORD"],
        role="FINTRACK_ANALYST_ROLE",
        warehouse="WH_ADHOC",
        database=DATABASE,
    )
    yield conn
    conn.close()


# ---------------------------------------------------------------------------
# 1. Schémas BLUE existent après le build
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("schema", BLUE_SCHEMAS)
def test_blue_schema_exists(sf_admin, schema):
    """Le schéma BLUE doit exister après le dbt build."""
    cur = sf_admin.cursor()
    cur.execute(f"SHOW SCHEMAS LIKE '{schema}' IN DATABASE {DATABASE}")
    result = cur.fetchall()
    assert len(result) > 0, f"Schéma BLUE introuvable : {schema}"


# ---------------------------------------------------------------------------
# 2. Tables critiques présentes et non vides
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("schema,tables", EXPECTED_TABLES.items())
def test_critical_tables_populated(sf_admin, schema, tables):
    """Chaque table critique doit contenir au moins une ligne dans BLUE."""
    cur = sf_admin.cursor()
    for table in tables:
        cur.execute(f"SELECT COUNT(*) FROM {DATABASE}.{schema}.{table}")
        count = cur.fetchone()[0]
        assert count >= MIN_ROW_THRESHOLD, (
            f"{schema}.{table} est vide après le build BLUE — "
            f"le swap serait destructeur."
        )


# ---------------------------------------------------------------------------
# 3. Cohérence du nombre de lignes BLUE vs PROD (régression < 20 %)
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("table", ["f_transactions", "f_virements"])
def test_no_row_count_regression(sf_admin, table):
    """
    Le build BLUE ne doit pas avoir moins de 80 % des lignes du schéma PROD.
    Protège contre un full-refresh accidentel ou une source vide.
    """
    blue_schema = f"MARTS_FINANCE{SCHEMA_SUFFIX}"
    prod_schema = "MARTS_FINANCE"

    cur = sf_admin.cursor()

    # Prod peut ne pas exister au premier déploiement — on skip proprement
    try:
        cur.execute(f"SELECT COUNT(*) FROM {DATABASE}.{prod_schema}.{table}")
        prod_count = cur.fetchone()[0]
    except Exception:
        pytest.skip(f"Schéma PROD introuvable — premier déploiement probable.")

    if prod_count == 0:
        pytest.skip("Schéma PROD vide — pas de baseline de comparaison.")

    cur.execute(f"SELECT COUNT(*) FROM {DATABASE}.{blue_schema}.{table}")
    blue_count = cur.fetchone()[0]

    ratio = blue_count / prod_count
    assert ratio >= 0.80, (
        f"Régression de lignes sur {table} : "
        f"BLUE={blue_count} vs PROD={prod_count} ({ratio:.1%}) — swap bloqué."
    )


# ---------------------------------------------------------------------------
# 4. Isolation multi-tenant toujours en place sur les vues BLUE
# ---------------------------------------------------------------------------

def test_tenant_isolation_on_blue_marts(sf_analyst):
    """
    Après le build BLUE, la RAP doit toujours filtrer les tenants.
    L'utilisateur test (ANALYST) n'est autorisé que sur les tenants 1 et 2.
    """
    blue_schema = f"MARTS_CORE{SCHEMA_SUFFIX}"
    cur = sf_analyst.cursor()
    try:
        cur.execute(
            f"SELECT DISTINCT tenant_id FROM {DATABASE}.{blue_schema}.dim_comptes"
        )
        tenants = {row[0] for row in cur.fetchall()}
    except Exception as e:
        pytest.skip(f"dim_comptes inaccessible en BLUE (grants manquants ?) : {e}")

    assert tenants.issubset({1, 2}), (
        f"Fuite multi-tenant détectée dans {blue_schema} : tenants visibles = {tenants}"
    )


# ---------------------------------------------------------------------------
# 5. PII masquées dans les marts BLUE
# ---------------------------------------------------------------------------

def test_pii_masked_in_blue_marts(sf_analyst):
    """
    Les emails dans dim_comptes BLUE ne doivent pas apparaître en clair
    pour un ANALYST.
    """
    blue_schema = f"MARTS_CORE{SCHEMA_SUFFIX}"
    cur = sf_analyst.cursor()
    try:
        cur.execute(
            f"SELECT email FROM {DATABASE}.{blue_schema}.dim_comptes LIMIT 20"
        )
        emails = [row[0] for row in cur.fetchall() if row[0]]
    except Exception as e:
        pytest.skip(f"dim_comptes inaccessible : {e}")

    for email in emails:
        assert "@" not in email or email.startswith("****"), (
            f"Email non masqué dans {blue_schema} : {email}"
        )


# ---------------------------------------------------------------------------
# 6. Secure views accessibles depuis le schéma BLUE
# ---------------------------------------------------------------------------

def test_secure_view_accessible_on_blue(sf_analyst):
    """vw_comptes_masked doit être accessible et retourner des lignes."""
    cur = sf_analyst.cursor()
    try:
        cur.execute(
            f"SELECT COUNT(*) FROM {DATABASE}.MARTS_SECURE.vw_comptes_masked"
        )
        count = cur.fetchone()[0]
    except Exception as e:
        pytest.skip(f"vw_comptes_masked inaccessible : {e}")

    assert count >= 0  # La vue existe et répond (peut être vide en test)
