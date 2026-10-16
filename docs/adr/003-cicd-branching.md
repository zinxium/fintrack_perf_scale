# ADR 003 — Stratégie de branching et CI/CD

**Status:** Accepted

## Décision

**GitHub Flow adapté** :
- `main` → production, protégée, revue obligatoire
- `staging` → pré-production automatique
- `feat/*` → feature branches, PR obligatoire

**CI sur PR** : Slim CI (`state:modified+ --defer`) + tests + lint + secrets scan
**CD sur main** : Blue/green deploy avec smoke tests

## Blue/Green pattern

1. Build dbt vers schémas suffixés `_BLUE`
2. Smoke tests sur les schémas BLUE
3. Si OK : `ALTER SCHEMA SWAP` atomique
4. Si KO : les schémas prod restent intacts, alert Slack

## Rollback

`ALTER SCHEMA SWAP` inverse en cas d'incident post-swap découvert < 4h.
Au-delà : Time Travel Snowflake (`AT (TIMESTAMP => ...)`)
