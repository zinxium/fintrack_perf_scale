-- ============================================================
-- MART — Détection d'anomalies sur transactions (Z-score)
-- ============================================================
-- Une transaction est anormale si son montant dépasse de plus de
-- 3 écarts-types la moyenne glissante sur les 90 derniers jours
-- du même compte.
--
-- Sévérité :
--   high   → |z| > 5
--   medium → |z| > 3
--   low    → |z| <= 3  (normal)
-- ============================================================

{{
    config(
        materialized='table',
        tags=['marts', 'analytics', 'anomalies']
    )
}}

with base as (
    select
        transaction_id,
        compte_id,
        tenant_id,
        date_transaction,
        montant_eur,
        -- Moyenne et écart-type glissants sur les 90 derniers jours
        -- (fenêtre de date, excluant la transaction courante)
        avg(montant_eur) over (
            partition by compte_id
            order by date_transaction::date
            range between interval '90 days' preceding and interval '1 day' preceding  -- noqa: PRS
        ) as moyenne_90j,
        stddev_pop(montant_eur) over (
            partition by compte_id
            order by date_transaction::date
            range between interval '90 days' preceding and interval '1 day' preceding  -- noqa: PRS
        ) as ecart_type_90j
    from {{ ref('fct_transactions') }}
    where statut = 'validee'
),

z_scores as (
    select
        *,
        case
            when coalesce(ecart_type_90j, 0) > 0
                then (montant_eur - moyenne_90j) / ecart_type_90j
            else 0.0
        end as z_score
    from base
)

select
    transaction_id,
    compte_id,
    tenant_id,
    date_transaction,
    montant_eur,
    round(coalesce(moyenne_90j, montant_eur), 2) as moyenne_90j,
    round(coalesce(ecart_type_90j, 0), 2) as ecart_type_90j,
    round(z_score, 3) as z_score,
    abs(z_score) > 3 as is_anomalie,
    case
        when abs(z_score) > 5 then 'high'
        when abs(z_score) > 3 then 'medium'
        else 'low'
    end as severite
from z_scores
