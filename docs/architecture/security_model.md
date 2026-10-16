# Architecture — Modèle de sécurité

## Couches

```
┌─────────────────────────────────────────────────────────────┐
│  1. Authentication                                          │
│     SSO Azure AD → Snowflake (tous les rôles humains)       │
│     Key Pair Auth pour les rôles techniques (CI/CD, dbt)    │
└─────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│  2. Authorization (RBAC)                                    │
│     Functional roles → Access roles → Object grants         │
│     dbt gère les grants MARTS via +grants                   │
└─────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│  3. Row-level (RAP)                                         │
│     tenant_id filtré selon user_tenant_access               │
│     Bypass pour rôles techniques                            │
└─────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│  4. Column-level (Masking Policies)                         │
│     PII masquées selon rôle                                 │
│     Tag-based pour couverture exhaustive                    │
└─────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│  5. Audit                                                   │
│     ACCESS_HISTORY, QUERY_HISTORY, LOGIN_HISTORY            │
│     Vues d'audit dans AUDIT schema                          │
│     Rétention 365 jours                                     │
└─────────────────────────────────────────────────────────────┘
```

## Matrice rôles / accès

Voir `docs/adr/002-masking-approach.md` (matrice détaillée par colonne).

## Conformité RGPD

- Art. 5 (minimisation) : masking par défaut, démasquage sur besoin
- Art. 15 (accès) : procédure d'extraction dans un runbook
- Art. 17 (oubli) : procédure `rgpd_purge_compte` + DAG dédié
- Art. 25 (privacy by design) : tags + policies dès le RAW
- Art. 30 (registre traitements) : ACCESS_HISTORY archivé
- Art. 32 (sécurité) : chiffrement Snowflake AES-256 at rest + TLS 1.2 in transit
