-- ============================================================
-- 05 — Vues d'audit sur ACCESS_HISTORY
-- ============================================================
-- ACCESS_HISTORY trace qui accède à quoi. Latence 45 min à 3h.
-- Ces vues facilitent les requêtes de conformité.
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FINTRACK_PROD;
USE SCHEMA AUDIT;

-- ============================================
-- Qui a accédé aux PII (colonnes taguées) dans les 30 derniers jours ?
-- ============================================
CREATE OR REPLACE VIEW vw_pii_access_last_30d AS
SELECT
    ah.query_start_time,
    ah.user_name,
    qh.role_name,
    ah.query_id,
    obj.value:"objectName"::STRING AS accessed_object,
    col.value:"columnName"::STRING AS accessed_column,
    qh.query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY ah
   , LATERAL FLATTEN(input => ah.direct_objects_accessed) obj
   , LATERAL FLATTEN(input => obj.value:"columns") col
JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY qh
    ON ah.query_id = qh.query_id
WHERE ah.query_start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
  AND obj.value:"objectDomain"::STRING = 'Table'
  AND obj.value:"objectName"::STRING LIKE 'FINTRACK_PROD.RAW.RAW_COMPTES'
  AND col.value:"columnName"::STRING IN (
      'EMAIL', 'IBAN', 'TELEPHONE', 'DATE_NAISSANCE',
      'NOM_CLIENT', 'PRENOM_CLIENT', 'ADRESSE_LIGNE1'
  );

-- ============================================
-- Utilisateurs par volume de requêtes (7 derniers jours)
-- ============================================
CREATE OR REPLACE VIEW vw_top_users_7d AS
SELECT
    user_name,
    role_name,
    COUNT(*) AS nb_queries,
    SUM(credits_used_cloud_services) AS total_credits,
    SUM(bytes_scanned) / POWER(1024, 3) AS gb_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY user_name, role_name
ORDER BY total_credits DESC NULLS LAST;

-- ============================================
-- Coûts par query_tag / projet
-- ============================================
CREATE OR REPLACE VIEW vw_costs_by_project_7d AS
SELECT
    COALESCE(REGEXP_SUBSTR(query_tag, 'project=([^|]+)', 1, 1, 'e'), '__untagged__') AS project,
    COALESCE(REGEXP_SUBSTR(query_tag, 'target=([^|]+)', 1, 1, 'e'), '__untagged__')  AS target,
    COUNT(*) AS nb_queries,
    ROUND(SUM(credits_used_cloud_services), 2) AS total_credits,
    ROUND(AVG(total_elapsed_time) / 1000, 2)   AS avg_elapsed_sec
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY project, target
ORDER BY total_credits DESC;

-- ============================================
-- LOGIN HISTORY — détection d'anomalies (rôle utilisé hors horaires)
-- ============================================
CREATE OR REPLACE VIEW vw_suspicious_logins AS
SELECT
    event_timestamp,
    user_name,
    client_ip,
    reported_client_type,
    is_success,
    error_message
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE event_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND (
      is_success = 'NO'
      OR HOUR(event_timestamp) NOT BETWEEN 6 AND 22
      OR client_ip NOT LIKE '10.%'
  )
ORDER BY event_timestamp DESC;
