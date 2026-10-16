-- ============================================================
-- VUE SÉCURISÉE — comptes avec masking selon le rôle
-- ============================================================
-- Cette vue est exposée aux consommateurs BI (Power BI, Metabase).
-- Les masking policies s'appliquent automatiquement selon CURRENT_ROLE().
-- ============================================================

{{
    config(
        materialized='view',
        secure=true,
        tags=['marts', 'secure_view', 'bi_ready'],
        grants={'select': ['FINTRACK_ANALYST_ROLE', 'FINTRACK_SUPPORT_ROLE',
                           'FINTRACK_COMPLIANCE_ROLE']}
    )
}}

select
    compte_id,
    tenant_id,
    numero_compte,
    iban,                  -- masking policy s'applique automatiquement
    nom_client,            -- idem
    prenom_client,
    email,
    type_compte,
    devise,
    date_ouverture,
    statut,
    kyc_level,
    aml_flag,
    customer_segment,
    is_pep,
    risk_score,
    pays,
    segment_activite,
    anciennete_jours

from {{ ref('dim_comptes') }}
where statut != 'cloture'
