# Row-Level Security composable Snowflake ↔ Power BI

## Objectif

Chaque utilisateur Power BI ne doit voir que les données de son tenant,
et cette isolation doit être imposée par **Snowflake** (pas juste par Power BI).

## Pattern : passthrough de l'identité

### Étape 1 — SSO end-to-end

- Power BI utilise SSO Azure AD → Snowflake
- La connexion Snowflake utilise l'identité de l'utilisateur final
- Snowflake applique automatiquement les Row Access Policies définies

### Étape 2 — Configuration Snowflake

```sql
-- Chaque utilisateur Power BI est mappé à ses tenants dans user_tenant_access :
INSERT INTO GOVERNANCE.user_tenant_access
VALUES ('user@bnp.com', 'FINTRACK_ANALYST_ROLE', 1, ...);
```

### Étape 3 — Configuration Power BI Desktop

- Connexion Snowflake : sélectionner "Microsoft account"
- ⚠️ **DÉCOCHER** "Suppress Privacy Level warning"
- Data source privacy : **Organizational**

### Étape 4 — Configuration Power BI Service

Après publication du rapport :

1. Dataset settings → Data source credentials
2. Authentication method : **OAuth2**
3. **Cochez "End users use their own OAuth2 credentials..."**
4. Single sign-on : **Enable**

Sans cette configuration finale, tous les utilisateurs verraient les données
avec le compte du publieur — trou de sécurité majeur.

## Alternative : RLS Power BI + fallback Snowflake

Si SSO impossible :
1. Créer une table `dim_users_tenants` dans Snowflake
2. Import dans Power BI
3. Créer un rôle DAX : `USERPRINCIPALNAME()` → filtre `tenant_id`
4. Assigner les utilisateurs au rôle dans Power BI Service

⚠️ Cette approche est moins robuste — un utilisateur avec accès direct à
Snowflake contournerait le filtre Power BI.

## Test

Un utilisateur BNP qui ouvre le rapport ne doit voir que les données
BNP dans tous les visuels, même en drill-through vers `fct_transactions`.
