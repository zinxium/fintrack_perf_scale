-- ============================================================
-- TEST SINGULIER — les +grants dbt sont bien posés sur les marts
-- ============================================================
-- Équivalent automatisé de `SHOW GRANTS ON TABLE dim_comptes` :
-- chaque mart critique doit être lisible par l'access role
-- FINTRACK_MARTS_R. Retourne les tables pour lesquelles le grant manque.
-- ============================================================
{{ config(tags=['security']) }}

{% set marts = [ref('dim_comptes'), ref('fct_transactions'), ref('fct_virements')] %}

with expected as (
    {% for m in marts %}
    select
        upper('{{ m.schema }}')     as table_schema,
        upper('{{ m.identifier }}') as table_name
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

granted as (
    select table_schema, table_name
    from {{ target.database }}.information_schema.table_privileges
    where grantee = 'FINTRACK_MARTS_R'
      and privilege_type = 'SELECT'
)

select e.*
from expected e
left join granted g
    on e.table_schema = g.table_schema
   and e.table_name = g.table_name
where g.table_name is null
