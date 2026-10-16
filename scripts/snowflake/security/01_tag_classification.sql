-- ============================================================
-- 01 — Tag-based classification des données
-- ============================================================
-- Snowflake supporte des tags attachés à des colonnes, tables, schémas.
-- Usages : classifier la sensibilité, déclencher du masking automatique,
-- auditer via ACCOUNT_USAGE.TAG_REFERENCES.
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FINTRACK_PROD;

CREATE SCHEMA IF NOT EXISTS GOVERNANCE;
USE SCHEMA GOVERNANCE;

-- ============================================
-- TAGS de classification
-- ============================================
CREATE OR REPLACE TAG data_classification
    ALLOWED_VALUES 'public', 'internal', 'confidential', 'restricted'
    COMMENT = 'Niveau de sensibilité de la donnée';

CREATE OR REPLACE TAG pii_type
    ALLOWED_VALUES 'name', 'email', 'phone', 'address', 'iban',
                   'national_id', 'date_of_birth', 'ip_address', 'device_id',
                   'financial_amount', 'none'
    COMMENT = 'Type précis de PII';

CREATE OR REPLACE TAG data_owner
    COMMENT = 'Domaine ou équipe propriétaire';

CREATE OR REPLACE TAG retention_days
    COMMENT = 'Durée de rétention en jours (RGPD)';

CREATE OR REPLACE TAG tenant_scope
    ALLOWED_VALUES 'shared', 'tenant_isolated', 'cross_tenant_aggregated'
    COMMENT = 'Politique multi-tenant à appliquer';

-- ============================================
-- APPLICATION DES TAGS
-- ============================================
USE SCHEMA RAW;

ALTER TABLE raw_tenants SET TAG
    GOVERNANCE.data_classification = 'internal',
    GOVERNANCE.data_owner = 'data-platform',
    GOVERNANCE.tenant_scope = 'shared';

ALTER TABLE raw_comptes SET TAG
    GOVERNANCE.data_classification = 'restricted',
    GOVERNANCE.data_owner = 'core-banking',
    GOVERNANCE.tenant_scope = 'tenant_isolated',
    GOVERNANCE.retention_days = '2555';  -- 7 ans obligation bancaire FR

ALTER TABLE raw_comptes MODIFY COLUMN nom_client SET TAG GOVERNANCE.pii_type = 'name';
ALTER TABLE raw_comptes MODIFY COLUMN prenom_client SET TAG GOVERNANCE.pii_type = 'name';
ALTER TABLE raw_comptes MODIFY COLUMN email SET TAG GOVERNANCE.pii_type = 'email';
ALTER TABLE raw_comptes MODIFY COLUMN telephone SET TAG GOVERNANCE.pii_type = 'phone';
ALTER TABLE raw_comptes MODIFY COLUMN date_naissance SET TAG GOVERNANCE.pii_type = 'date_of_birth';
ALTER TABLE raw_comptes MODIFY COLUMN iban SET TAG GOVERNANCE.pii_type = 'iban';
ALTER TABLE raw_comptes MODIFY COLUMN adresse_ligne1 SET TAG GOVERNANCE.pii_type = 'address';
ALTER TABLE raw_comptes MODIFY COLUMN adresse_ligne2 SET TAG GOVERNANCE.pii_type = 'address';

ALTER TABLE raw_transactions SET TAG
    GOVERNANCE.data_classification = 'restricted',
    GOVERNANCE.data_owner = 'payments',
    GOVERNANCE.tenant_scope = 'tenant_isolated',
    GOVERNANCE.retention_days = '2555';

ALTER TABLE raw_transactions MODIFY COLUMN compte_source_iban SET TAG GOVERNANCE.pii_type = 'iban';
ALTER TABLE raw_transactions MODIFY COLUMN compte_dest_iban   SET TAG GOVERNANCE.pii_type = 'iban';
ALTER TABLE raw_transactions MODIFY COLUMN ip_address         SET TAG GOVERNANCE.pii_type = 'ip_address';
ALTER TABLE raw_transactions MODIFY COLUMN device_id          SET TAG GOVERNANCE.pii_type = 'device_id';
ALTER TABLE raw_transactions MODIFY COLUMN carte_last4        SET TAG GOVERNANCE.pii_type = 'financial_amount';

ALTER TABLE raw_virements SET TAG
    GOVERNANCE.data_classification = 'confidential',
    GOVERNANCE.data_owner = 'payments',
    GOVERNANCE.tenant_scope = 'tenant_isolated';

-- ============================================
-- VÉRIFICATION
-- ============================================
-- Latence ACCOUNT_USAGE : jusqu'à 2h avant que les tags apparaissent
SELECT object_database, object_schema, object_name, column_name, tag_name, tag_value
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE tag_database = 'FINTRACK_PROD'
  AND object_database = 'FINTRACK_PROD'
ORDER BY object_schema, object_name, column_name;
