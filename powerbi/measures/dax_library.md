# Bibliothèque DAX FinTrack

Mesures certifiées à utiliser dans les rapports Power BI.
Convention : préfixe `[m_]` pour distinguer des colonnes calculées.

## Volumes de base

```dax
m_NbTransactions =
    COUNTROWS(f_transactions)

m_NbTransactionsValidees =
    CALCULATE([m_NbTransactions], f_transactions[statut] = "validee")

m_NbComptesActifs =
    DISTINCTCOUNT(f_transactions[compte_id])
```

## Montants

```dax
m_VolumeCredit_EUR =
    CALCULATE(
        SUM(f_transactions[montant_eur]),
        f_transactions[type_operation] = "credit",
        f_transactions[statut] = "validee"
    )

m_VolumeDebit_EUR =
    CALCULATE(
        SUM(f_transactions[montant_eur]),
        f_transactions[type_operation] = "debit",
        f_transactions[statut] = "validee"
    )

m_FluxNet_EUR = [m_VolumeCredit_EUR] - [m_VolumeDebit_EUR]
```

## Ratios et taux

```dax
m_TauxValidation =
    DIVIDE([m_NbTransactionsValidees], [m_NbTransactions], 0)

m_TauxRejet =
    DIVIDE(
        CALCULATE([m_NbTransactions], f_transactions[statut] = "rejetee"),
        [m_NbTransactions],
        0
    )

m_MontantMoyenTransaction =
    DIVIDE([m_VolumeCredit_EUR] + [m_VolumeDebit_EUR], [m_NbTransactions], 0)
```

## Time intelligence

```dax
m_VolumeMTD =
    CALCULATE([m_FluxNet_EUR], DATESMTD(d_dates[date]))

m_VolumeYTD =
    CALCULATE([m_FluxNet_EUR], DATESYTD(d_dates[date]))

m_VolumeSameMonthLastYear =
    CALCULATE([m_FluxNet_EUR], SAMEPERIODLASTYEAR(d_dates[date]))

m_CroissanceYoY =
    DIVIDE(
        [m_FluxNet_EUR] - [m_VolumeSameMonthLastYear],
        [m_VolumeSameMonthLastYear],
        BLANK()
    )

m_MoyenneMobile30J =
    AVERAGEX(
        DATESINPERIOD(d_dates[date], MAX(d_dates[date]), -30, DAY),
        [m_FluxNet_EUR]
    )
```

## Compliance

```dax
m_NbTransactionsFlagged =
    CALCULATE([m_NbTransactions], f_transactions[is_flagged_for_review] = TRUE)

m_TauxFlagAML =
    DIVIDE([m_NbTransactionsFlagged], [m_NbTransactions], 0)

m_TauxReconciliation =
    DIVIDE(
        CALCULATE([m_NbTransactions], f_transactions[is_reconciled] = TRUE),
        [m_NbTransactions],
        0
    )
```

## Formatage recommandé

- Montants : `#,##0.00 €;(#,##0.00 €);-`
- Taux : `0.00%;(0.00%);0.00%`
- Comptes : `#,##0`
