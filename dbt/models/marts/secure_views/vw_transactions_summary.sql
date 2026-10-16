-- ============================================================
-- VUE SÉCURISÉE — transactions agrégées (pas de PII)
-- ============================================================
-- Vue destinée à Power BI. Grain : jour x compte x catégorie.
-- Ne contient AUCUNE PII directe (compte_id est un identifiant technique).
-- ============================================================

{{
    config(
        materialized='view',
        secure=true,
        tags=['marts', 'secure_view', 'bi_ready'],
        grants={'select': ['FINTRACK_ANALYST_ROLE', 'FINTRACK_SUPPORT_ROLE']}
    )
}}

select
    tenant_id,
    compte_id,
    jour_transaction,
    categorie_id,
    nom_categorie,
    groupe,
    type_operation,
    canal,
    count(*) as nb_transactions,
    sum(montant_eur) as montant_total_eur,
    sum(montant_signe_eur) as flux_net_eur,
    avg(montant_eur) as montant_moyen_eur,
    max(montant_eur) as montant_max_eur

from {{ ref('fct_transactions') }}
where statut = 'validee'
group by 1, 2, 3, 4, 5, 6, 7, 8
