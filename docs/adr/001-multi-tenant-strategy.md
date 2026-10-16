# ADR 001 — Stratégie multi-tenant

**Status:** Accepted
**Date:** À dater à la mise en œuvre
**Decision-makers:** Data Platform Team + RSSI

## Context

FinTrack devient une plateforme B2B2C. Chaque tenant (banque partenaire)
doit être strictement isolé — un incident chez un tenant ne doit jamais
exposer les données d'un autre.

## Options évaluées

### Option A : Base Snowflake par tenant
- ✅ Isolation absolue
- ❌ Explosion de la maintenance (15 pipelines dbt)
- ❌ Coûts × 15 (warehouses par base)
- ❌ Impossible d'agréger cross-tenant

### Option B : Schéma par tenant, base unique
- ✅ Isolation forte
- ❌ 15 schémas RAW à alimenter
- ❌ Union dbt lourde à maintenir

### Option C : Table unique + Row Access Policy (retenue)
- ✅ Simple à maintenir
- ✅ Aggregation cross-tenant possible (via rôle admin)
- ✅ Policies évoluent sans migration de données
- ⚠️ Une erreur de policy = fuite immédiate — tests obligatoires

## Décision

**Option C** avec les garanties :
1. Table `GOVERNANCE.user_tenant_access` comme source de vérité
2. Row Access Policy testée dans CI (jeu de test isolé par PR)
3. Alerting sur toute modification de `user_tenant_access`
4. Audit mensuel de `ACCESS_HISTORY` pour détecter des cross-tenant leaks

## Conséquences

- Rôle `FINTRACK_TRANSFORM_ROLE` doit être court-circuité (accès total nécessaire pour dbt)
- Consommateurs BI (Power BI) doivent utiliser SSO (voir ADR 005)
- La CNIL considère cette approche acceptable si les audits sont documentés
