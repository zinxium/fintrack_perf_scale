# Modèle sémantique Power BI

## Diagramme de relations

```
d_tenants ─────< f_transactions >───── d_categories
                    │
                    ├──── d_comptes (Hidden — clé compte_id via bridge)
                    │
                    └──── d_dates (Marked as date table)

d_tenants ─────< mart_tenant_kpis_daily
d_tenants ─────< mart_reconciliation
```

## Tables importées

| Nom Power BI | Table Snowflake | Mode | Cardinalité |
|--------------|-----------------|------|-------------|
| f_transactions | vw_transactions_summary | DirectQuery | ~10M |
| f_virements | fct_virements | DirectQuery | ~1M |
| d_tenants | dim_tenants | Import | 15 lignes |
| d_comptes | vw_comptes_masked | DirectQuery | 1M |
| d_categories | dim_categories | Import | 30 lignes |
| d_dates | (calculated) | Calculated | 730 lignes |
| mart_tenant_kpis_daily | mart_tenant_kpis_daily | DirectQuery | ~30k |

## Table de dates calculée

```dax
d_dates =
ADDCOLUMNS(
    CALENDAR(DATE(2023,1,1), DATE(2026,12,31)),
    "Année", YEAR([Date]),
    "Trimestre", "Q" & QUARTER([Date]),
    "Mois", FORMAT([Date], "yyyy-MM"),
    "MoisNom", FORMAT([Date], "MMM yyyy"),
    "JourSemaine", FORMAT([Date], "dddd"),
    "IsWeekend", WEEKDAY([Date], 2) > 5,
    "SemaineISO", WEEKNUM([Date], 21)
)
```

Puis Model view → d_dates → **Mark as date table** → colonne `Date`.

## Hiérarchies recommandées

- **Temps** : Année > Trimestre > Mois > Date
- **Catégorie** : groupe > nom_categorie
- **Géographie** : pays > tenant_name

## Relations

- `f_transactions[tenant_id]` → `d_tenants[tenant_id]` (many-to-one, active)
- `f_transactions[categorie_id]` → `d_categories[categorie_id]` (many-to-one, active)
- `f_transactions[jour_transaction]` → `d_dates[Date]` (many-to-one, active)
- `f_transactions[compte_id]` → `d_comptes[compte_id]` (many-to-one, **inactive** — activer via USERELATIONSHIP pour éviter les auto-joins Snowflake coûteux)

## Sécurité RLS

Voir `guides/02_composable_rls.md`.

## Optimisations

- Colonnes techniques cachées : `_loaded_at`, `source_system`, tous les `*_id`
- Agrégations Power BI configurées sur `d_dates[Mois]` pour éviter les scans quotidiens
- Colonnes de tri : `MoisNom` triée par `Mois`
