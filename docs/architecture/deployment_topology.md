# Architecture — Topologie de déploiement

## Environnements

| Env | Base Snowflake | Warehouse | Usage |
|-----|----------------|-----------|-------|
| **prod** | FINTRACK_PROD | WH_TRANSFORM | Production, tenants live |
| **staging** | FINTRACK_STAGING | WH_TRANSFORM | Preprod, test des releases |
| **ci** | FINTRACK_DEV (schéma CI_PR_N) | WH_DEV | Tests PR |
| **dev** | FINTRACK_DEV (schéma DEV_USER) | WH_DEV | Développement local |

## Flux de déploiement

```
Feature branch (dev local) ──PR──▶ Slim CI (ci schema) ──merge──▶ main ──▶ Blue deploy ──swap──▶ Prod
                                                                              │
                                                                     Smoke tests
                                                                              │
                                                                     Auto-rollback si KO
```

## Airflow deployment

- Managed via Astronomer (compte Business tier)
- 2 environnements : `astro-staging`, `astro-prod`
- Deploy via CI GitHub → `astro deploy`
- Connections gérées via secrets AWS Secrets Manager (backend)

## Power BI deployment

- Workspace `FinTrack Analytics [PROD]`
- Deployment pipelines Power BI : Dev → Test → Prod
- Datasets : SSO Snowflake, refresh 6x/jour + trigger API
