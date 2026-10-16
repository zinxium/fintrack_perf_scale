# Runbook — Droit à l'oubli RGPD

**Owner :** Compliance Officer
**Fréquence :** À la demande

## Prérequis

- Ticket support avec numéro `RGPD-XXX`
- Vérification que le client a bien clôturé son compte
- Validation par le DPO
- Accès `FINTRACK_ADMIN_ROLE`

## Étapes

### 1. Identification

```sql
-- Vérifier que le compte existe et lister les données concernées
SELECT compte_id, statut, date_derniere_activite
FROM FINTRACK_PROD.RAW.raw_comptes
WHERE email = 'user@example.com';  -- ou par compte_id direct

-- Nombre de transactions concernées
SELECT COUNT(*) FROM FINTRACK_PROD.RAW.raw_transactions
WHERE compte_id = <ID>;
```

### 2. Snapshot de secours (obligatoire)

```sql
-- Sauvegarde encrypted dans un schéma d'archive légale
CREATE TABLE FINTRACK_ARCHIVE.RGPD_BACKUPS.compte_<ID>_<DATE> AS
SELECT * FROM FINTRACK_PROD.RAW.raw_comptes WHERE compte_id = <ID>;
```

### 3. Exécution de la purge

Deux options :

**Via SQL direct** (avec supervision) :
```sql
CALL FINTRACK_PROD.GOVERNANCE.rgpd_purge_compte(
    <compte_id>,
    'RGPD-XXX — motif détaillé',
    'compliance@fintrack.example',
    '<timestamp ISO de la demande>'::TIMESTAMP_NTZ
);
```

**Via DAG Airflow** (recommandé — meilleure traçabilité) :
- UI Airflow → DAG `fintrack_rgpd_purge` → Trigger DAG w/ config
- Renseigner tous les paramètres
- L'exécution notifie compliance en fin de course

### 4. Vérification

```sql
-- Vérifier qu'aucune donnée ne subsiste
SELECT COUNT(*) FROM FINTRACK_PROD.RAW.raw_comptes WHERE compte_id = <ID>;
SELECT COUNT(*) FROM FINTRACK_PROD.RAW.raw_transactions WHERE compte_id = <ID>;
SELECT COUNT(*) FROM FINTRACK_PROD.MARTS_CORE.dim_comptes WHERE compte_id = <ID>;

-- Vérifier le log
SELECT * FROM FINTRACK_PROD.GOVERNANCE.rgpd_purge_log
WHERE compte_id = <ID> ORDER BY executed_at DESC LIMIT 1;
```

### 5. Time Travel

Snowflake garde les données 90 jours en Time Travel. Pour purger réellement :

```sql
ALTER TABLE FINTRACK_PROD.RAW.raw_comptes SET DATA_RETENTION_TIME_IN_DAYS = 0;
-- (la purge ci-dessus a déjà eu lieu)
ALTER TABLE FINTRACK_PROD.RAW.raw_comptes SET DATA_RETENTION_TIME_IN_DAYS = 90;
```

⚠️ Cette opération supprime aussi les points de restore récents.
À faire hors production, ou pendant la fenêtre de maintenance.

### 6. Notification client

Répondre au ticket support avec :
- Confirmation de la purge (référence log purge_id)
- Date d'effet
- Rappel que le Time Travel est actif jusqu'à J+90 mais purgé légalement

## SLA

- Prise en charge : 5 jours ouvrés
- Exécution complète : 30 jours (obligation légale RGPD)

## Escalade

- Anomalie détectée → DPO immédiatement
- Blocage technique → CTO
