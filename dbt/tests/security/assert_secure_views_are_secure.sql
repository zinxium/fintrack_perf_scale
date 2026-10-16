-- ============================================================
-- TEST SINGULIER — les vues de marts_secure sont des SECURE VIEWS
-- ============================================================
-- Une vue non sécurisée expose sa définition SQL et permet au
-- optimiseur de court-circuiter les filtres. Retourne les vues
-- du schéma sécurisé qui ne sont pas marquées secure.
-- ============================================================
{{ config(tags=['security']) }}

select table_schema, table_name, is_secure
from {{ target.database }}.information_schema.views
where table_schema = upper('{{ ref('vw_comptes_masked').schema }}')
  and is_secure <> 'YES'
