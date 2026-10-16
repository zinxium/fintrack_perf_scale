# Model contracts & versioning — FinTrack Perf & Scale

## Contexte

Les contrats dbt (`contract.enforced: true`) verrouillent le schéma d'un modèle :
dbt vérifie à chaque run que les colonnes définies dans le YML correspondent exactement
au SELECT du modèle SQL. Toute divergence fait échouer le build — ce qui protège les
consommateurs downstream (Metabase, Hightouch, Data Science) contre les breaking changes.

## Modèles publics

| Modèle | Accès | Contract | Consommateurs |
|--------|-------|----------|---------------|
| `fct_transactions` (v1, deprecated 2027-06-01) | public | **`enforced: true`** | Metabase, Hightouch, Data Science |
| `fct_transactions` (v2, latest) | public | **`enforced: true`** | Reporting Finance (hors-taxes) |
| `dim_comptes` | public | non enforced | Metabase, CRM sync |
| `dim_tenants` | public | non enforced | Tous les marts |
| `dim_categories` | public | non enforced | Rapports catégoriels |
| `mart_tenant_kpis_daily` | public | non enforced | Dashboard exécutif |
| `bridge_comptes_titulaires` | private | non enforced | Usage interne uniquement |

## ✅ Contract activé sur `fct_transactions` (Sprint 6)

Les étapes ci-dessous ont été appliquées :

1. **Toutes les colonnes documentées** dans `_core.yml` avec `data_type` :

```yaml
- name: montant
  data_type: number
- name: devise
  data_type: varchar
- name: montant_eur
  data_type: number
- name: montant_signe
  data_type: number
- name: montant_signe_eur
  data_type: number
- name: frais
  data_type: number
- name: montant_net
  data_type: number
- name: type_operation
  data_type: varchar
- name: sens
  data_type: varchar
- name: moyen_paiement
  data_type: varchar
- name: canal
  data_type: varchar
- name: type_compte
  data_type: varchar
- name: customer_segment
  data_type: varchar
- name: pays_compte
  data_type: varchar
- name: nom_categorie
  data_type: varchar
- name: type_categorie
  data_type: varchar
- name: groupe
  data_type: varchar
- name: marchand_nom
  data_type: varchar
- name: marchand_categorie
  data_type: varchar
- name: marchand_pays
  data_type: varchar
- name: marchand_mcc
  data_type: number
- name: aml_score
  data_type: number
- name: aml_flag
  data_type: varchar
- name: fraud_score
  data_type: number
- name: is_flagged_for_review
  data_type: boolean
- name: is_reconciled
  data_type: boolean
- name: reconciliation_batch_id
  data_type: varchar
- name: source_system
  data_type: varchar
- name: created_at
  data_type: timestamp_ntz
- name: updated_at
  data_type: timestamp_ntz
- name: _loaded_at
  data_type: timestamp_ntz
- name: jour_transaction
  data_type: date
- name: semaine_transaction
  data_type: date
- name: mois_transaction
  data_type: date
- name: date_valeur
  data_type: timestamp_ntz
- name: date_settlement
  data_type: timestamp_ntz
```

2. **Contract activé** dans `_core.yml` :

```yaml
config:
  contract:
    enforced: true
```

3. **`dbt build --select fct_transactions fct_transactions_v2`** : vert ✅

## Versioning — fct_transactions v1 → v2

### Ce qui change en v2

| Colonne | v1 | v2 |
|---------|----|----|
| `montant_hors_taxes` | absente | `montant_eur / 1.20` pour les débits |

### Modèle v2

`fct_transactions_v2.sql` — construit sur `fct_transactions` avec le champ additionnel.
Consommateurs ciblés : équipe Finance pour reporting hors-taxes.

### Stratégie de migration

Quand un breaking change est nécessaire sur un modèle public :

1. Créer `fct_transactions_v2` avec les changements
2. Marquer v1 comme `deprecated` avec une date de retrait (minimum 30 jours)
3. Notifier les consommateurs via `exposures.yml`
4. Attendre la migration de tous les consommateurs
5. Supprimer v1

### YAML appliqué (dbt 2.x versioning natif)

```yaml
models:
  - name: fct_transactions
    latest_version: 2
    config:
      contract:
        enforced: true
    versions:
      - v: 1
        defined_in: fct_transactions
        deprecation_date: '2027-06-01'
      - v: 2
        defined_in: fct_transactions_v2
        columns:
          - include: all
          - name: montant_hors_taxes
            data_type: number
```

`ref('fct_transactions')` résout vers v2 (latest). Les consommateurs existants qui appelaient
`ref('fct_transactions')` voient maintenant v2 avec `montant_hors_taxes` disponible.
Pour rester sur v1 explicitement : `ref('fct_transactions', v=1)`.

## Règles générales

- Tout modèle `public` doit avoir ses colonnes documentées dans le YML avant d'activer le contract
- Un changement de `data_type` sur une colonne existante est un **breaking change** → nouvelle version obligatoire
- L'ajout d'une colonne nullable n'est **pas** un breaking change → `on_schema_change: append_new_columns`
- La suppression d'une colonne est un **breaking change** → nouvelle version obligatoire
