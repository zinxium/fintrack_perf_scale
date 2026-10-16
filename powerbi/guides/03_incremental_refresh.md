# Incremental Refresh Power BI ↔ Snowflake

Pour éviter de retirer 100M de lignes à chaque refresh.

## Prérequis

- Premium capacity ou Pro dataset < 1 Go
- Table de faits partitionnée par date (`date_transaction`)

## Configuration

### 1. Paramètres Power Query

Créer deux paramètres date :
- `RangeStart` : DateTime
- `RangeEnd` : DateTime

### 2. Filtrer la table de faits

```m
= Table.SelectRows(fct_transactions,
    each [date_transaction] >= RangeStart
     and [date_transaction] < RangeEnd)
```

### 3. Configurer l'incremental refresh

Right-click sur la table → **Incremental refresh** :
- Store rows in the last : **3 years**
- Refresh rows in the last : **7 days**
- ✅ Get the latest data in real time (DirectQuery pour la période courante)
- ✅ Only refresh complete days

### 4. Détect data changes (optionnel)

Colonne watermark : `_loaded_at`
Power BI ne rafraîchit une partition que si `MAX(_loaded_at)` a changé.

## Résultat

- Premier refresh : ~30 min (tout l'historique)
- Refresh quotidiens : ~2 min (7 derniers jours seulement)
- Gain de coût Snowflake estimé : **-90%** sur le compute BI
