-- ============================================================
-- TEST SINGULIER — aucune colonne PII dans les marts analytics
-- ============================================================
-- Les marts analytics sont consommés largement (Power BI, analystes) :
-- ils ne doivent contenir aucune colonne identifiante, même masquée.
-- Retourne les colonnes PII trouvées.
-- ============================================================
{{ config(tags=['security']) }}

select table_schema, table_name, column_name
from {{ target.database }}.information_schema.columns
where table_schema = upper('{{ ref('mart_tenant_kpis_daily').schema }}')
  and lower(column_name) in (
      'email', 'iban', 'telephone', 'nom_client', 'prenom_client',
      'date_naissance', 'adresse_ligne1', 'adresse_ligne2',
      'ip_address', 'device_id', 'compte_source_iban', 'compte_dest_iban'
  )
