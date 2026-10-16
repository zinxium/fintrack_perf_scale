-- ============================================================
-- FCT TRANSACTIONS v2 — Ajout montant_hors_taxes
-- ============================================================
-- Breaking change par rapport à v1 : ajout de la colonne
-- montant_hors_taxes (montant_eur hors TVA 20%).
-- v1 deprecated au 2027-06-01 — migrer les consommateurs avant.
-- ============================================================

{{
    config(
        materialized='incremental',
        unique_key='transaction_id',
        incremental_strategy='merge',
        merge_update_columns=['statut', 'is_reconciled', 'aml_flag',
                              'aml_score', 'fraud_score', 'montant_eur',
                              'montant_hors_taxes', 'updated_at'],
        cluster_by=['tenant_id', "date_trunc('month', date_transaction)"],
        on_schema_change='append_new_columns',
        tags=['marts', 'core', 'fct', 'incremental', 'critical', 'v2'],
        pre_hook=[
            "{{ log_incremental_run('fct_transactions_v2', 'pre') }}"
        ],
        post_hook=[
            "{{ log_incremental_run('fct_transactions_v2', 'post') }}"
        ]
    )
}}

select
    -- Toutes les colonnes de v1
    transaction_id,
    external_transaction_id,
    tenant_id,
    compte_id,
    categorie_id,
    date_transaction,
    jour_transaction,
    semaine_transaction,
    mois_transaction,
    date_valeur,
    date_settlement,
    montant,
    devise,
    montant_eur,
    montant_signe,
    montant_signe_eur,
    frais,
    montant_net,
    type_operation,
    sens,
    statut,
    moyen_paiement,
    canal,
    type_compte,
    customer_segment,
    pays_compte,
    nom_categorie,
    type_categorie,
    groupe,
    marchand_nom,
    marchand_categorie,
    marchand_pays,
    marchand_mcc,
    aml_score,
    aml_flag,
    fraud_score,
    is_flagged_for_review,
    is_reconciled,
    reconciliation_batch_id,
    source_system,
    created_at,
    updated_at,
    _loaded_at,

    -- Nouvelle colonne v2 : montant hors TVA 20% (débits uniquement)
    case
        when sens = 'debit'
            then round(montant_eur / 1.20, 2)
        else montant_eur
    end as montant_hors_taxes

from {{ ref('fct_transactions', v=1) }}  -- noqa: TMP

{% if is_incremental() %}
    where _loaded_at >= (
        select dateadd('day', -{{ var('incremental_lookback_days', 7) }}, max(_loaded_at))
        from {{ this }}
    )
{% endif %}
