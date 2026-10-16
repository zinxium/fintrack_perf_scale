'''Smoke tests d'isolation multi-tenant — exécutés après le blue deploy.'''
import os
import pytest
import snowflake.connector


@pytest.fixture(scope='module')
def sf_conn():
    conn = snowflake.connector.connect(
        account=os.environ['SNOWFLAKE_ACCOUNT'],
        user=os.environ['SNOWFLAKE_TEST_USER'],
        password=os.environ['SNOWFLAKE_TEST_PASSWORD'],
        role='FINTRACK_ANALYST_ROLE',
        warehouse='WH_ADHOC',
        database='FINTRACK_PROD',
    )
    yield conn
    conn.close()


def test_analyst_sees_only_authorized_tenants(sf_conn):
    '''L'utilisateur test est attribué aux tenants 1 et 2 uniquement.'''
    cur = sf_conn.cursor()
    cur.execute("SELECT DISTINCT tenant_id FROM RAW.raw_transactions")
    tenants = {row[0] for row in cur.fetchall()}
    assert tenants.issubset({1, 2}), f"Fuite multi-tenant : {tenants}"


def test_pii_masked_for_analyst(sf_conn):
    cur = sf_conn.cursor()
    cur.execute("SELECT email FROM RAW.raw_comptes LIMIT 10")
    emails = [row[0] for row in cur.fetchall()]
    for email in emails:
        assert '@' not in email or email.startswith('****'), \
            f"Email non masqué : {email}"


def test_secure_view_grants(sf_conn):
    '''Vérifier que les grants sont bien posés sur les secure views.'''
    cur = sf_conn.cursor()
    cur.execute("SELECT * FROM MARTS_SECURE.vw_comptes_masked LIMIT 1")
    assert cur.fetchone() is not None
