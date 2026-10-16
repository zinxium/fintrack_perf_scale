-- ============================================================
-- 07 — Tables et vues de métriques du pipeline
-- ============================================================
-- Persistance des métriques opérationnelles pour dashboarding.
-- Alimentée par les hooks dbt et le DAG Airflow.
-- ============================================================

USE ROLE FINTRACK_TRANSFORM_ROLE;
USE DATABASE FINTRACK_PROD;
USE SCHEMA AUDIT;

CREATE TABLE IF NOT EXISTS pipeline_run_metrics (
    run_id                VARCHAR(100),
    run_started_at        TIMESTAMP_NTZ,
    run_ended_at          TIMESTAMP_NTZ,
    duration_seconds      INTEGER,
    target                VARCHAR(20),
    status                VARCHAR(20),
    nb_models_success     INTEGER,
    nb_models_error       INTEGER,
    nb_tests_pass         INTEGER,
    nb_tests_fail         INTEGER,
    nb_tests_warn         INTEGER,
    triggered_by          VARCHAR(100),
    airflow_dag_run_id    VARCHAR(200),
    metadata              VARIANT,
    logged_at             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS model_execution_metrics (
    run_id                VARCHAR(100),
    model_name            VARCHAR(300),
    materialization       VARCHAR(30),
    execution_time_sec    NUMBER(10, 3),
    rows_affected         NUMBER(20, 0),
    bytes_scanned         NUMBER(20, 0),
    partitions_scanned    INTEGER,
    warehouse_size        VARCHAR(20),
    status                VARCHAR(20),
    logged_at             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Vue de synthèse quotidienne
CREATE OR REPLACE VIEW vw_pipeline_health_daily AS
SELECT
    DATE(run_started_at) AS run_date,
    target,
    COUNT(*) AS nb_runs,
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS nb_success,
    SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END) AS nb_error,
    ROUND(100.0 * SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) / COUNT(*), 2) AS success_rate_pct,
    AVG(duration_seconds) AS avg_duration_sec,
    MAX(duration_seconds) AS max_duration_sec,
    SUM(nb_tests_fail) AS total_tests_fail
FROM pipeline_run_metrics
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
