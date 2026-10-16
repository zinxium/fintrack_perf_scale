# ADR 005 — Sécurité Power BI : composable RLS

**Status:** Accepted

## Context

Les analystes des tenants doivent voir uniquement les données de leur tenant
dans Power BI. Deux approches possibles.

## Options

### A — RLS Power BI natif
```dax
[tenant_id] = LOOKUPVALUE(d_users[tenant_id], d_users[email], USERPRINCIPALNAME())
```
- ❌ Un utilisateur avec accès direct Snowflake contourne le filtre
- ❌ Duplique la logique de sécurité

### B — Composable RLS via SSO Snowflake (retenue)
- ✅ Sécurité imposée par Snowflake (single source of truth)
- ✅ Power BI hérite du contexte de sécurité
- ✅ Fonctionne quel que soit l'outil BI (Metabase, Tableau, ad-hoc)

## Décision

**Option B** — SSO Azure AD → Snowflake activé sur toutes les connexions BI.
Row Access Policy Snowflake pilote l'isolation.

Configuration critique : dans Power BI Service, cocher
« End users use their own OAuth2 credentials » sur le dataset.

## Test d'acceptation

Un utilisateur BNP qui ouvre le rapport tenant-overview ne doit voir que la
ligne "BNP" dans le visuel « Volume par tenant », même après drill-through
et export Excel.
