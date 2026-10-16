# Runbook — Incident qualité de données

**Trigger :** Alerte Elementary sur `#data-quality-alerts`

## Diagnostic (5 min)

1. Ouvrir le rapport Elementary : `edr report`
2. Identifier le modèle et le type d'anomalie
3. Contexte : dernier déploiement ? changement source ?

## Classification

| Sévérité | Exemple | Action |
|----------|---------|--------|
| P1 | fct_transactions -50% rows vs J-1 | Bloque le pipeline, incident déclaré |
| P2 | Colonne PII non masquée dans mart | Bloque le release, hotfix |
| P3 | Anomalie ponctuelle 1 métrique | Ticket backlog |

## Actions P1

1. Suspendre le DAG Airflow : `airflow dags pause fintrack_daily_pipeline`
2. Rollback dbt : swap prod ← ancienne version blue/green
3. Notifier `#data-platform-alerts` : « Incident P1 en cours »
4. Investiguer : `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY` sur la fenêtre
5. Fix + PR d'urgence + validation compliance
6. Reprise pipeline
7. Post-mortem sous 48h
