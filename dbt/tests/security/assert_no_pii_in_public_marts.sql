-- ============================================================
-- TEST SINGULIER — aucune PII en clair dans les modèles publics
-- ============================================================
-- Vérifie qu'aucune colonne PII des marts publics ne contient une
-- valeur qui ressemble à un email en clair, un IBAN, un numéro long.
--
-- Si ce test échoue → un masking policy manque quelque part.
-- ============================================================

with suspects as (
    select
        'dim_comptes' as model,
        'email'       as column_name,
        count(*)      as nb_suspects
    from {{ ref('dim_comptes') }}
    where email like '%@%.%'
      and not (email like '****%' or length(email) = 64)  -- 64 = SHA256 hex
    group by 1, 2

    union all

    select
        'dim_comptes',
        'iban',
        count(*)
    from {{ ref('dim_comptes') }}
    where regexp_like(iban, '^[A-Z]{2}[0-9]{2}[A-Z0-9]{8,30}$')
      and not iban like '%****%'
    group by 1, 2
)

select * from suspects
where nb_suspects > 0
