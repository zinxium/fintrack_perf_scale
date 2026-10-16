# Performance Log — FinTrack Perf & Scale

À remplir pendant la mission. Ce document est un livrable obligatoire.

## Chargement initial

| Scale | Taille CSV (Go) | Durée génération | Durée PUT | Durée COPY | Erreurs |
|-------|-----------------|------------------|-----------|------------|---------|
| S     | ~0.05           | 43s              | ~30s      | ~15s       | 0       |
| M     | —               | —                | —         | —          | —       |
| L     | —               | —                | —         | —          | —       |

## Baseline (avant optimisations)

Warehouse : WH_DEV (XSMALL)  Target : dev  Date : 2026-10-13

| Modèle | Rows | Elapsed (s) | Notes |
|--------|------|-------------|-------|
| stg_transactions | 100 000 | ~19s | incremental merge |
| fct_transactions | 100 000 | ~15s | incremental merge, clustering (tenant_id, mois) |
| fct_transactions_microbatch | 100 000 | ~42s | microbatch par jour, lookback=3 |
| mart_solde_journalier | — | ~9s | table |
| mart_tenant_kpis_daily | — | ~8s | table |
| **Full run tag:marts** | — | **58.9s** | 17 modèles, WH_DEV XSMALL |

## Après optimisations Sprint 3

Warehouse : WH_DEV (XSMALL)  Target : dev  Date : 2026-10-13

| Modèle | Elapsed (s) | Gain | Notes |
|--------|-------------|------|-------|
| stg_transactions | ~19s | — | incremental merge opérationnel |
| fct_transactions | ~15s | — | clustering depth=2.0 < 3 ✓ |
| fct_transactions_microbatch | ~42s | — | event_time configuré, warning supprimé |
| **Full run tag:marts** | **58.9s** | — | Scale S, WH XSMALL — à réévaluer sur scale L |

> **Note :** la baseline est mesurée sur scale S (100k transactions) avec WH_DEV XSMALL.
> L'objectif de < 1h est atteint. Sur scale M/L (1M-10M transactions) avec WH_TRANSFORM MEDIUM,
> les gains de clustering et d'incremental seront significativement plus visibles.

## Clustering Analysis — fct_transactions (Sprint 3)

Date : 2026-09-08 | Scale : M (945 243 lignes) | Warehouse : WH_TRANSFORM

```json
{
  "cluster_by_keys": "LINEAR(tenant_id, date_trunc('month', date_transaction))",
  "total_partition_count": 8,
  "average_overlaps": 1.75,
  "average_depth": 2.0
}
```

**Résultat :** `average_depth = 2.0` < 3 → objectif atteint. Clustering efficace sur scale M.
À réévaluer sur scale L (10M+ lignes) où la profondeur augmentera naturellement.

## Search Optimization — fct_transactions

Date : 2026-09-08

```json
{
  "BuildCosts":    { "value": 0.000879, "unit": "Credits" },
  "StorageCosts":  { "value": 0.000037, "unit": "TB/mois" },
  "MaintenanceCosts": "Insufficient data (table < 7 jours)"
}
```

**Décision : non activée.** Sur scale M le coût est négligeable mais le bénéfice aussi.
À activer sur scale L/XL si les lookups sur `external_transaction_id` ou `iban` deviennent fréquents (dashboards compliance, rapprochement bancaire).

## Analyse Query Profile

Date : 2026-09-08 | Warehouse : WH_REPORTING (ou ADHOC) | Scale M

### Query 1 — Agrégat par tenant et mois

```sql
SELECT tenant_id, mois_transaction, SUM(montant_eur), COUNT(*)
FROM fct_transactions GROUP BY 1, 2 ORDER BY 1, 2;
```

- **Elapsed :** 702 ms
- **Résultat :** 192 lignes (8 tenants × 24 mois)
- **Profil :** scan full table + agrégat — efficace grâce au clustering sur `tenant_id`
- **Recommandation :** envisager une `dynamic table` ou `materialized view` sur cet agrégat en prod si rafraîchissement < 1h requis

### Query 2 — Point lookup par transaction_id

```sql
SELECT * FROM fct_transactions WHERE transaction_id = 500000;
```

- **Elapsed :** 482 ms
- **Résultat :** 1 ligne
- **Profil :** scan de partitions — `transaction_id` n'est pas dans la clustering key, Snowflake doit scanner toutes les partitions
- **Recommandation :** activer Search Optimization sur `transaction_id` si ce type de lookup est fréquent (support client, debugging)

### Query 3 — Filtre AML

```sql
SELECT tenant_id, COUNT(*), AVG(aml_score)
FROM fct_transactions WHERE aml_flag != 'clean' GROUP BY 1;
```

- **Elapsed :** 390 ms
- **Résultat :** 8 lignes
- **Profil :** le filtre `aml_flag != 'clean'` élimine ~98.5% des lignes — très sélectif
- **Recommandation :** sur scale L, envisager une table matérialisée `mart_aml_suspects` pour éviter le scan complet

## Décisions prises

- **Clustering key sur fct_transactions :** `(tenant_id, date_trunc('month', date_transaction))` → Justification : requêtes BI filtrées par tenant et période
- **Search Optimization :** non activée sur scale M → coût < bénéfice ; à réévaluer sur scale L sur `transaction_id` et `external_transaction_id`
- **Merge vs Microbatch :** merge retenu → raison : les transactions changent de statut après insertion (`en_attente` → `validee`), ce que microbatch ne gère pas (remplace le batch entier sans merge row-by-row)

## Coûts Snowflake

| Semaine | Credits WH_INGESTION | Credits WH_TRANSFORM | Credits WH_REPORTING | Total |
|---------|----------------------|----------------------|----------------------|-------|
|         |                      |                      |                      |       |
