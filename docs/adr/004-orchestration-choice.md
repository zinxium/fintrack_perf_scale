# ADR 004 — Airflow vs Dagster vs dbt Cloud

**Status:** Accepted

## Options

| Critère | Airflow | Dagster | dbt Cloud |
|---------|---------|---------|-----------|
| Courbe apprentissage | Moyenne | Douce | Immédiate |
| Flexibilité | Élevée | Élevée | Limitée |
| Coût | Self-host $0 | Self-host $0 | 100 $/dev/mois |
| Ecosystem | Énorme | Croissant | Focused dbt |
| Sensors / Waits | Excellent | Bon | Basique |
| Notre équipe | ✅ Connait | ❌ | ❌ |

## Décision : Airflow

L'équipe connaît déjà. Deploy sur Astronomer (managed) pour éviter la maintenance.

Migration future Dagster possible si le besoin d'asset-oriented modeling
devient dominant (data mesh).
