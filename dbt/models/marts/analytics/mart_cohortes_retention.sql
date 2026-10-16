-- ============================================================
-- MART — Analyse de cohortes de rétention (M+0 à M+12)
-- ============================================================
-- Cohorte = mois d'ouverture du compte.
-- Actif = au moins 1 transaction validée dans le mois mesuré.
-- ============================================================

{{
    config(
        materialized='table',
        tags=['marts', 'analytics', 'retention']
    )
}}

with comptes as (
    select
        compte_id,
        date_trunc('month', date_ouverture)::date as cohort_mois
    from {{ ref('dim_comptes') }}
    where date_ouverture is not null
),

activite as (
    select distinct
        compte_id,
        date_trunc('month', date_transaction)::date as mois_activite
    from {{ ref('fct_transactions') }}
    where statut = 'validee'
),

cohorte_activite as (
    select
        c.cohort_mois,
        c.compte_id,
        a.mois_activite,
        datediff('month', c.cohort_mois, a.mois_activite) as mois_offset
    from comptes as c
    left join activite as a on c.compte_id = a.compte_id
),

taille_cohorte as (
    select
        cohort_mois,
        count(distinct compte_id) as nb_utilisateurs_cohorte
    from comptes
    group by cohort_mois
),

actifs as (
    select
        cohort_mois,
        mois_offset,
        count(distinct compte_id) as nb_utilisateurs_actifs
    from cohorte_activite
    where
        mois_offset >= 0
        and mois_offset <= 12
    group by cohort_mois, mois_offset
)

select
    a.cohort_mois,
    a.mois_offset,
    t.nb_utilisateurs_cohorte,
    a.nb_utilisateurs_actifs,
    round(100.0 * a.nb_utilisateurs_actifs / nullif(t.nb_utilisateurs_cohorte, 0), 2) as taux_retention_pct
from actifs as a
inner join taille_cohorte as t on a.cohort_mois = t.cohort_mois
order by a.cohort_mois, a.mois_offset
