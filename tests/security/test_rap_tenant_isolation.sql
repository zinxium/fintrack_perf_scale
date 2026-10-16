-- ============================================================
-- TEST — Isolation multi-tenant via RAP
-- ============================================================
-- Ce test vérifie que la RAP `rap_tenant_isolation` est bien
-- attachée aux tables sensibles. Il ne teste PAS le comportement
-- runtime (qui nécessite un changement de rôle utilisateur) mais
-- vérifie l'existence des policies via INFORMATION_SCHEMA.
--
-- Pour le test runtime complet, voir docs/adr/001-multi-tenant-strategy.md
-- section "Preuve d'exécution".
-- ============================================================

-- Renvoie 0 ligne si toutes les policies sont en place (test passe).
-- Renvoie les tables manquantes sinon.

with expected_policies as (
    select column1 as table_name, column2 as schema_name
    from (values
        ('RAW_COMPTES',      'RAW'),
        ('RAW_TRANSACTIONS', 'RAW'),
        ('RAW_VIREMENTS',    'RAW'),
        ('DIM_COMPTES',      'MARTS_CORE'),
        ('FCT_TRANSACTIONS', 'MARTS_CORE')
    ) t(column1, column2)
),

applied_policies as (
    select
        ref_entity_name    as table_name,
        ref_schema_name    as schema_name
    from FINTRACK_PROD.information_schema.policy_references
    where policy_name = 'RAP_TENANT_ISOLATION'
      and policy_schema_name = 'GOVERNANCE'
      and ref_entity_domain = 'Table'
)

select
    e.table_name,
    e.schema_name,
    'RAP non appliquée' as issue
from expected_policies e
left join applied_policies a
    on  a.table_name  = e.table_name
    and a.schema_name = e.schema_name
where a.table_name is null
