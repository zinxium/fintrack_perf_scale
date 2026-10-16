-- ============================================================
-- 06 — Procédure de droit à l'oubli (RGPD Art. 17)
-- ============================================================
-- Suppression sélective des données d'un client, en cascade sur
-- toutes les tables RAW et MARTS. Historisation dans AUDIT.
--
-- ATTENTION : opération irréversible. Time Travel actif pendant
-- 90 jours doit lui aussi être purgé (voir fin du script).
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FINTRACK_PROD;
USE SCHEMA GOVERNANCE;

-- Journal des purges (piste d'audit obligatoire)
CREATE TABLE IF NOT EXISTS rgpd_purge_log (
    purge_id            VARCHAR(50) DEFAULT UUID_STRING(),
    compte_id           INTEGER,
    reason              VARCHAR(500),
    requested_by        VARCHAR(255),
    requested_at        TIMESTAMP_NTZ,
    executed_by         VARCHAR(255),
    executed_at         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    tables_affected     ARRAY,
    rows_deleted        VARIANT,
    status              VARCHAR(20) DEFAULT 'completed'
);

-- ============================================
-- PROCÉDURE DE PURGE
-- ============================================
CREATE OR REPLACE PROCEDURE rgpd_purge_compte(
    p_compte_id FLOAT,
    p_reason VARCHAR,
    p_requested_by VARCHAR,
    p_requested_at VARCHAR
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var result = {compte_id: P_COMPTE_ID, tables: {}};

    var tables = [
        {schema: 'RAW',        table: 'raw_transactions', col: 'compte_id'},
        {schema: 'RAW',        table: 'raw_virements',    col: 'compte_source_id'},
        {schema: 'RAW',        table: 'raw_virements',    col: 'compte_dest_id'},
        {schema: 'RAW',        table: 'raw_comptes',      col: 'compte_id'},
        {schema: 'MARTS_CORE', table: 'fct_transactions', col: 'compte_id'},
        {schema: 'MARTS_CORE', table: 'fct_virements',    col: 'compte_id'},
        {schema: 'MARTS_CORE', table: 'dim_comptes',      col: 'compte_id'},
        {schema: 'MARTS_CORE', table: 'dim_comptes_scd2', col: 'compte_id'},
        {schema: 'MARTS_FINANCE',   table: 'mart_solde_journalier', col: 'compte_id'},
        {schema: 'SNAPSHOTS',       table: 'snapshot_comptes',      col: 'compte_id'}
    ];

    var affected = [];
    var rows = {};

    for (var i = 0; i < tables.length; i++) {
        var t = tables[i];
        var sql = "DELETE FROM FINTRACK_PROD." + t.schema + "." + t.table +
                  " WHERE " + t.col + " = " + P_COMPTE_ID;
        try {
            var stmt = snowflake.createStatement({sqlText: sql});
            var rs = stmt.execute();
            rs.next();
            var deleted = rs.getColumnValue(1);
            affected.push(t.schema + '.' + t.table);
            rows[t.schema + '.' + t.table] = deleted;
        } catch (err) {
            rows[t.schema + '.' + t.table] = err.message.replace(/['\n\r\t\\]/g, ' ').substring(0, 150);
        }
    }

    result.tables_affected = affected;
    result.rows_deleted = rows;

    // Journalisation
    var log_sql = "INSERT INTO GOVERNANCE.rgpd_purge_log " +
        "(compte_id, reason, requested_by, requested_at, executed_by, tables_affected, rows_deleted) " +
        "SELECT " + P_COMPTE_ID + ", '" + P_REASON.replace(/'/g, "''") + "', '" +
        P_REQUESTED_BY + "', TO_TIMESTAMP_NTZ('" + P_REQUESTED_AT + "'), CURRENT_USER(), " +
        "ARRAY_CONSTRUCT(" + affected.map(function(t) { return "'" + t + "'"; }).join(",") + "), " +
        "PARSE_JSON('" + JSON.stringify(rows).replace(/'/g, "''").replace(/[\n\r\t]/g, ' ') + "')";
    snowflake.createStatement({sqlText: log_sql}).execute();

    return result;
$$;

-- ============================================
-- USAGE
-- ============================================
-- CALL rgpd_purge_compte(
--     42,
--     'Demande client 2024-11-15 ticket #RGPD-1234',
--     'compliance-officer@fintrack.example',
--     '2024-11-15 14:30:00'::TIMESTAMP_NTZ
-- );

-- ============================================
-- PURGE DU TIME TRAVEL (obligatoire pour RGPD complet)
-- ============================================
-- Snowflake conserve les données supprimées 90 jours par défaut.
-- Pour purger immédiatement, il faut réduire le retention à 0
-- temporairement, ou attendre l'expiration.
--
-- Approche recommandée : réduire le DATA_RETENTION_TIME sur les tables
-- concernées avant la purge, puis restaurer.
--
-- ALTER TABLE RAW.raw_comptes SET DATA_RETENTION_TIME_IN_DAYS = 0;
-- CALL rgpd_purge_compte(...);
-- ALTER TABLE RAW.raw_comptes SET DATA_RETENTION_TIME_IN_DAYS = 90;
--
-- ATTENTION : cette approche supprime aussi les autres restore points
-- récents. À faire hors production ou avec accord explicite.
