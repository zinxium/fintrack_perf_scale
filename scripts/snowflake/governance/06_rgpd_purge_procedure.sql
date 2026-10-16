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
    // Échappement des chaînes injectées dans le SQL (anti-injection)
    function esc(v) { return String(v === null || v === undefined ? '' : v).replace(/'/g, "''"); }
    var compteId = Math.floor(P_COMPTE_ID);
    if (!(compteId > 0)) { throw "compte_id invalide : " + P_COMPTE_ID; }

    var result = {compte_id: compteId, tables: {}};

    // Titulaires liés à ce compte et à AUCUN autre compte : à purger.
    // Un co-titulaire qui possède un autre compte est conservé.
    var titulaires = [];
    var rsT = snowflake.createStatement({sqlText:
        "SELECT DISTINCT ct.titulaire_id FROM FINTRACK_PROD.RAW.raw_compte_titulaires ct " +
        "WHERE ct.compte_id = " + compteId + " AND ct.titulaire_id IS NOT NULL " +
        "AND NOT EXISTS (SELECT 1 FROM FINTRACK_PROD.RAW.raw_compte_titulaires o " +
        "  WHERE o.titulaire_id = ct.titulaire_id AND o.compte_id <> " + compteId + ")"}).execute();
    while (rsT.next()) { titulaires.push(rsT.getColumnValue(1)); }
    var titulaireFilter = titulaires.length > 0
        ? "titulaire_id IN (" + titulaires.map(function(x) { return Math.floor(x); }).join(",") + ")"
        : "1 = 0";

    var cp = "compte_id = " + compteId;
    var tables = [
        {schema: 'RAW',           table: 'raw_transactions',          where: cp},
        {schema: 'RAW',           table: 'raw_virements',             where: "compte_source_id = " + compteId + " OR compte_dest_id = " + compteId},
        {schema: 'RAW',           table: 'raw_titulaires',            where: titulaireFilter},
        {schema: 'RAW',           table: 'raw_compte_titulaires',     where: cp},
        {schema: 'RAW',           table: 'raw_comptes',               where: cp},
        {schema: 'MARTS_CORE',    table: 'fct_transactions',          where: cp},
        {schema: 'MARTS_CORE',    table: 'fct_virements',             where: cp + " OR contrepartie_compte_id = " + compteId},
        {schema: 'MARTS_CORE',    table: 'bridge_comptes_titulaires', where: cp},
        {schema: 'MARTS_CORE',    table: 'dim_comptes',               where: cp},
        {schema: 'MARTS_CORE',    table: 'dim_comptes_scd2',          where: cp},
        {schema: 'MARTS_FINANCE', table: 'mart_solde_journalier',     where: cp},
        {schema: 'SNAPSHOTS',     table: 'snapshot_comptes',          where: cp}
    ];

    var affected = [];
    var rows = {};
    var errors = 0;

    for (var i = 0; i < tables.length; i++) {
        var t = tables[i];
        var key = t.schema + '.' + t.table;
        var sql = "DELETE FROM FINTRACK_PROD." + key + " WHERE " + t.where;
        try {
            var rs = snowflake.createStatement({sqlText: sql}).execute();
            rs.next();
            affected.push(key);
            rows[key] = rs.getColumnValue(1);
        } catch (err) {
            errors++;
            rows[key] = 'ERROR: ' + err.message.replace(/['\n\r\t\]/g, ' ').substring(0, 150);
        }
    }

    var status = errors === 0 ? 'completed' : 'partial';
    result.tables_affected = affected;
    result.rows_deleted = rows;
    result.titulaires_purges = titulaires.length;
    result.status = status;

    // Journalisation (toutes les valeurs externes sont échappées)
    var log_sql = "INSERT INTO FINTRACK_PROD.GOVERNANCE.rgpd_purge_log " +
        "(compte_id, reason, requested_by, requested_at, executed_by, tables_affected, rows_deleted, status) " +
        "SELECT " + compteId + ", '" + esc(P_REASON) + "', '" + esc(P_REQUESTED_BY) + "', " +
        "TRY_TO_TIMESTAMP_NTZ('" + esc(P_REQUESTED_AT) + "'), CURRENT_USER(), " +
        "ARRAY_CONSTRUCT(" + affected.map(function(t) { return "'" + t + "'"; }).join(",") + "), " +
        "PARSE_JSON('" + esc(JSON.stringify(rows)).replace(/[\n\r\t]/g, ' ') + "'), '" + status + "'";
    snowflake.createStatement({sqlText: log_sql}).execute();

    var rsId = snowflake.createStatement({sqlText:
        "SELECT purge_id FROM FINTRACK_PROD.GOVERNANCE.rgpd_purge_log " +
        "WHERE compte_id = " + compteId + " ORDER BY executed_at DESC LIMIT 1"}).execute();
    if (rsId.next()) { result.purge_id = rsId.getColumnValue(1); }

    return result;
$$;

-- ============================================
-- USAGE
-- ============================================
-- CALL rgpd_purge_compte(
--     42,
--     'Demande client 2024-11-15 ticket #RGPD-1234',
--     'compliance-officer@fintrack.example',
--     '2024-11-15 14:30:00'
-- );
-- Retour : {compte_id, purge_id, status: completed|partial, rows_deleted, ...}

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
