-- ============================================================
-- 03 — Row Access Policies (isolation multi-tenant)
-- ============================================================
-- FinTrack étant B2B2C, chaque tenant (banque partenaire) ne doit
-- voir QUE ses propres données. Une seule table physique, isolation
-- par RAP au niveau ligne.
--
-- Fonctionnement :
--   1. Une table de mapping utilisateur → tenants autorisés
--   2. Une policy qui filtre selon CURRENT_USER() ou CURRENT_ROLE()
--   3. La policy est attachée à chaque table sensible
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FINTRACK_PROD;
USE SCHEMA GOVERNANCE;

-- ============================================
-- TABLE DE MAPPING utilisateur ↔ tenants
-- ============================================
CREATE TABLE IF NOT EXISTS user_tenant_access (
    user_name       VARCHAR(255),
    role_name       VARCHAR(255),
    tenant_id       INTEGER,
    granted_by      VARCHAR(255),
    granted_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    revoked_at      TIMESTAMP_NTZ,
    PRIMARY KEY (user_name, tenant_id)
);

-- Exemples d'attribution (à adapter à vos utilisateurs) :
-- INSERT INTO user_tenant_access (user_name, role_name, tenant_id, granted_by)
-- VALUES ('ANALYSTE_BNP', 'FINTRACK_ANALYST_ROLE', 1, CURRENT_USER());

-- ============================================
-- ROLES INTERNES qui court-circuitent le RAP
-- ============================================
-- Certains rôles (transformation dbt, admin) doivent voir tous les tenants.
-- On crée un tag pour marquer ces rôles.

CREATE OR REPLACE TAG bypass_row_access
    ALLOWED_VALUES 'true'
    COMMENT = 'Marque les rôles qui court-circuitent les RAP';

-- ============================================
-- ROW ACCESS POLICY : multi-tenant
-- ============================================
CREATE OR REPLACE ROW ACCESS POLICY rap_tenant_isolation
    AS (p_tenant_id INTEGER) RETURNS BOOLEAN ->
    CASE
        -- Rôles techniques : accès total
        WHEN CURRENT_ROLE() IN (
            'ACCOUNTADMIN',
            'FINTRACK_ADMIN_ROLE',
            'FINTRACK_TRANSFORM_ROLE',
            'FINTRACK_INGESTION_ROLE'
        ) THEN TRUE

        -- Rôles métier : filtrage par tenant autorisé
        -- ATTENTION : le paramètre est préfixé `p_` pour éviter la
        -- collision avec la colonne `tenant_id` de user_tenant_access —
        -- sans ce préfixe, `uta.tenant_id = tenant_id` deviendrait
        -- `uta.tenant_id = uta.tenant_id` (toujours TRUE), fuite majeure.
        WHEN EXISTS (
            SELECT 1
            FROM GOVERNANCE.user_tenant_access uta
            WHERE uta.user_name = CURRENT_USER()
              AND uta.tenant_id = p_tenant_id
              AND uta.revoked_at IS NULL
        ) THEN TRUE

        ELSE FALSE
    END;

-- ============================================
-- APPLICATION SUR LES TABLES SENSIBLES
-- ============================================
USE SCHEMA RAW;

ALTER TABLE raw_comptes      ADD ROW ACCESS POLICY GOVERNANCE.rap_tenant_isolation ON (tenant_id);
ALTER TABLE raw_transactions ADD ROW ACCESS POLICY GOVERNANCE.rap_tenant_isolation ON (tenant_id);
ALTER TABLE raw_virements    ADD ROW ACCESS POLICY GOVERNANCE.rap_tenant_isolation ON (tenant_id);

-- Pour les marts on applique aussi (obligation US 1.1 de MISSION.md)
USE SCHEMA MARTS_CORE;
ALTER TABLE dim_comptes      ADD ROW ACCESS POLICY GOVERNANCE.rap_tenant_isolation ON (tenant_id);
ALTER TABLE fct_transactions ADD ROW ACCESS POLICY GOVERNANCE.rap_tenant_isolation ON (tenant_id);
ALTER TABLE fct_virements    ADD ROW ACCESS POLICY GOVERNANCE.rap_tenant_isolation ON (tenant_id);

-- ============================================
-- TEST
-- ============================================
-- 1. Attribuer un utilisateur à quelques tenants :
--    INSERT INTO GOVERNANCE.user_tenant_access VALUES
--        ('DEMO_USER', 'FINTRACK_ANALYST_ROLE', 1, CURRENT_USER(), CURRENT_TIMESTAMP(), NULL),
--        ('DEMO_USER', 'FINTRACK_ANALYST_ROLE', 2, CURRENT_USER(), CURRENT_TIMESTAMP(), NULL);
--
-- 2. Bascule sur DEMO_USER + FINTRACK_ANALYST_ROLE :
--    SELECT DISTINCT tenant_id FROM RAW.raw_transactions;
--    -- doit renvoyer 1 et 2 uniquement
