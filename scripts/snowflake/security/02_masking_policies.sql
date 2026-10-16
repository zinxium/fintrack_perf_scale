-- ============================================================
-- 02 — Dynamic Data Masking Policies
-- ============================================================
-- Le contenu de la colonne est transformé au SELECT selon le rôle.
-- On combine column-level explicite et tag-based (couverture exhaustive).
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FINTRACK_PROD;
USE SCHEMA GOVERNANCE;

-- Email : masque local part, garde le domaine pour analytics
CREATE OR REPLACE MASKING POLICY mask_email AS
    (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'FINTRACK_ADMIN_ROLE',
                                'FINTRACK_PII_UNMASK_ROLE') THEN val
        WHEN CURRENT_ROLE() IN ('FINTRACK_SUPPORT_ROLE') THEN
            REGEXP_REPLACE(val, '^[^@]+', '****')
        ELSE
            SHA2(val, 256)
    END;

CREATE OR REPLACE MASKING POLICY mask_name AS
    (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'FINTRACK_ADMIN_ROLE',
                                'FINTRACK_PII_UNMASK_ROLE') THEN val
        WHEN CURRENT_ROLE() IN ('FINTRACK_SUPPORT_ROLE') THEN
            LEFT(val, 1) || REPEAT('*', GREATEST(LENGTH(val) - 1, 0))
        ELSE
            '***'
    END;

CREATE OR REPLACE MASKING POLICY mask_phone AS
    (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'FINTRACK_ADMIN_ROLE',
                                'FINTRACK_PII_UNMASK_ROLE') THEN val
        WHEN CURRENT_ROLE() IN ('FINTRACK_SUPPORT_ROLE') THEN
            '**** ' || RIGHT(REGEXP_REPLACE(val, '[^0-9]', ''), 4)
        ELSE
            '***'
    END;

CREATE OR REPLACE MASKING POLICY mask_iban AS
    (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'FINTRACK_ADMIN_ROLE',
                                'FINTRACK_PII_UNMASK_ROLE') THEN val
        WHEN CURRENT_ROLE() IN ('FINTRACK_SUPPORT_ROLE',
                                'FINTRACK_COMPLIANCE_ROLE') THEN
            LEFT(val, 4) || REPEAT('*', GREATEST(LENGTH(val) - 8, 0)) || RIGHT(val, 4)
        ELSE
            '****'
    END;

CREATE OR REPLACE MASKING POLICY mask_date_of_birth AS
    (val DATE) RETURNS DATE ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'FINTRACK_ADMIN_ROLE',
                                'FINTRACK_PII_UNMASK_ROLE') THEN val
        WHEN CURRENT_ROLE() IN ('FINTRACK_ANALYST_ROLE') THEN
            DATE_FROM_PARTS(YEAR(val), 1, 1)
        ELSE NULL
    END;

CREATE OR REPLACE MASKING POLICY mask_address AS
    (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'FINTRACK_ADMIN_ROLE',
                                'FINTRACK_PII_UNMASK_ROLE') THEN val
        WHEN CURRENT_ROLE() IN ('FINTRACK_SUPPORT_ROLE') THEN
            REGEXP_REPLACE(val, '^[0-9]+\\s+', '')
        ELSE '[redacted]'
    END;

CREATE OR REPLACE MASKING POLICY mask_ip_address AS
    (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'FINTRACK_ADMIN_ROLE',
                                'FINTRACK_PII_UNMASK_ROLE') THEN val
        WHEN CURRENT_ROLE() IN ('FINTRACK_ANALYST_ROLE',
                                'FINTRACK_FRAUD_ROLE') THEN
            REGEXP_REPLACE(val, '\\.[0-9]+$', '.0')
        ELSE NULL
    END;

CREATE OR REPLACE MASKING POLICY mask_device_id AS
    (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'FINTRACK_ADMIN_ROLE',
                                'FINTRACK_PII_UNMASK_ROLE',
                                'FINTRACK_FRAUD_ROLE') THEN val
        ELSE LEFT(SHA2(val, 256), 12)
    END;

-- ============================================
-- APPLICATION EXPLICITE (approche colonne par colonne)
-- ============================================
USE SCHEMA RAW;

ALTER TABLE raw_comptes MODIFY COLUMN email          SET MASKING POLICY GOVERNANCE.mask_email;
ALTER TABLE raw_comptes MODIFY COLUMN nom_client     SET MASKING POLICY GOVERNANCE.mask_name;
ALTER TABLE raw_comptes MODIFY COLUMN prenom_client  SET MASKING POLICY GOVERNANCE.mask_name;
ALTER TABLE raw_comptes MODIFY COLUMN telephone      SET MASKING POLICY GOVERNANCE.mask_phone;
ALTER TABLE raw_comptes MODIFY COLUMN iban           SET MASKING POLICY GOVERNANCE.mask_iban;
ALTER TABLE raw_comptes MODIFY COLUMN date_naissance SET MASKING POLICY GOVERNANCE.mask_date_of_birth;
ALTER TABLE raw_comptes MODIFY COLUMN adresse_ligne1 SET MASKING POLICY GOVERNANCE.mask_address;
ALTER TABLE raw_comptes MODIFY COLUMN adresse_ligne2 SET MASKING POLICY GOVERNANCE.mask_address;

ALTER TABLE raw_transactions MODIFY COLUMN compte_source_iban SET MASKING POLICY GOVERNANCE.mask_iban;
ALTER TABLE raw_transactions MODIFY COLUMN compte_dest_iban   SET MASKING POLICY GOVERNANCE.mask_iban;
ALTER TABLE raw_transactions MODIFY COLUMN ip_address         SET MASKING POLICY GOVERNANCE.mask_ip_address;
ALTER TABLE raw_transactions MODIFY COLUMN device_id          SET MASKING POLICY GOVERNANCE.mask_device_id;

-- ============================================
-- TEST
-- ============================================
-- USE ROLE FINTRACK_ANALYST_ROLE;
-- SELECT compte_id, nom_client, email, iban FROM RAW.raw_comptes LIMIT 5;
-- (attendus : nom_client masqué, email hashé, iban avec ****)
