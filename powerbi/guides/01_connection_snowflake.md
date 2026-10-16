# Connexion Power BI ↔ Snowflake

## Modes de connexion — comparatif

| Mode | Latence | Volume | Live | Cas d'usage |
|------|---------|--------|------|-------------|
| **Import** | Rapide | < 10 M lignes | Non | Dashboards statiques quotidiens |
| **DirectQuery** | Moyenne | Illimité | Oui | Data volumineuse, refresh temps réel |
| **Composite** | Mixte | Illimité | Partiel | Recommandé pour FinTrack |
| **Dual** | Mixte | Illimité | Oui | Cas particuliers (rare) |

**Recommandation FinTrack :** Composite Model
- Dimensions (`dim_tenants`, `dim_comptes`, `dim_categories`) en **Import** — petites, stables
- Faits (`fct_transactions`, `mart_tenant_kpis_daily`) en **DirectQuery** — volumes importants

## Paramètres de connexion

1. **Get Data → Snowflake**
2. Server : `<account>.snowflakecomputing.com`
3. Warehouse : `WH_REPORTING`
4. Database : `FINTRACK_PROD`
5. Schema : `MARTS_CORE` (ou `MARTS_ANALYTICS`)
6. Authentication : **Microsoft Account** (SSO) — jamais mot de passe en clair
7. Encryption : **Force TLS 1.2**

## Modèle sémantique — tables recommandées

- `vw_transactions_summary` (secure view — masking déjà appliqué)
- `vw_comptes_masked`
- `dim_tenants`
- `dim_categories`
- `dim_dates` (à créer côté Power BI si absent en marts)
- `mart_tenant_kpis_daily`
- `mart_reconciliation`

## Convention de nommage dans Power BI

- Préfixe `d_` pour dimensions, `f_` pour faits
- Traduction française pour affichage (via Column properties → Display folder)
- Masquer les clés techniques (`Hide from client tools`)

## Rafraîchissement

- **Import** : Scheduled refresh Power BI Service, toutes les 4h en semaine
- **Incremental refresh** : voir `03_incremental_refresh.md`
- Trigger par API depuis Airflow : voir `orchestration/airflow/dags/fintrack_daily_pipeline.py`

## Sécurité

- **RLS composable** : voir `02_composable_rls.md`
- Le masking Snowflake est **respecté nativement** — le rôle utilisé par la connexion Power BI détermine ce qui est masqué
- Ne JAMAIS utiliser un service account admin pour la connexion Power BI
