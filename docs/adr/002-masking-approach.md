# ADR 002 — Approche de masking des PII

**Status:** Accepted

## Context

Les analystes doivent pouvoir travailler sur des données réelles sans
voir les PII en clair. La CNIL exige un principe de minimisation.

## Options

### Option A : Vues avec CASE WHEN CURRENT_ROLE()
- ❌ Duplique la logique dans chaque vue
- ❌ Facile d'oublier une colonne

### Option B : Masking Policies Snowflake (retenue)
- ✅ Déclaratif
- ✅ S'applique automatiquement aux nouvelles requêtes
- ✅ Combinable avec tag-based

### Option C : Anonymisation à l'ingestion
- ❌ Perd de la valeur analytique
- ❌ Impossible de démasquer pour la conformité

## Décision

**Option B** avec deux niveaux :
1. Application explicite colonne par colonne sur les tables RAW critiques
2. Application via post-hook dbt sur les marts (pour ne pas oublier)

## Rôles et niveaux de démasquage

| Rôle | Nom | Email | IBAN | DoB | IP |
|------|-----|-------|------|-----|-----|
| ADMIN | ✅ clair | ✅ clair | ✅ clair | ✅ clair | ✅ clair |
| PII_UNMASK | ✅ clair | ✅ clair | ✅ clair | ✅ clair | ✅ clair |
| SUPPORT | Init.*** | ***@... | 4 first + 4 last | ❌ | ❌ |
| COMPLIANCE | *** | *** | 4 first + 4 last | ❌ | /24 |
| ANALYST | *** | hash | *** | Année seule | /24 |
| FRAUD | *** | hash | *** | ❌ | ✅ clair |

Le rôle PII_UNMASK doit être audité manuellement chaque mois.
