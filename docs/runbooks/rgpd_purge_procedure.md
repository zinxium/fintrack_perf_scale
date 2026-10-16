# Runbook — Droit à l'oubli RGPD (Art. 17)

| | |
|---|---|
| **Owner** | Compliance Officer |
| **Validation** | DPO |
| **Fréquence** | À la demande |
| **Rôle Snowflake** | `FINTRACK_COMPLIANCE_ROLE` (moindre privilège — pas `ADMIN`) |
| **Outillage** | Procédure `FINTRACK_PROD.GOVERNANCE.rgpd_purge_compte` + DAG Airflow `fintrack_rgpd_purge` |
| **Piste d'audit** | `FINTRACK_PROD.GOVERNANCE.rgpd_purge_log` |

---

## 1. Prérequis

- [ ] Ticket support au format `RGPD-XXX` avec la demande écrite du client
- [ ] Identité du demandeur vérifiée (support niveau 2)
- [ ] Compte clôturé (`statut = 'cloture'`), aucune opération en cours
- [ ] Aucune obligation légale de conservation bloquante (voir §7)
- [ ] Validation écrite du DPO dans le ticket

## 2. Périmètre de la purge

La procédure supprime, pour le `compte_id` donné :

| Couche | Table | Filtre |
|---|---|---|
| RAW | `raw_transactions` | `compte_id` |
| RAW | `raw_virements` | `compte_source_id` **ou** `compte_dest_id` |
| RAW | `raw_compte_titulaires` | `compte_id` |
| RAW | `raw_titulaires` | titulaires liés **uniquement** à ce compte |
| RAW | `raw_comptes` | `compte_id` |
| MARTS_CORE | `fct_transactions`, `dim_comptes`, `dim_comptes_scd2`, `bridge_comptes_titulaires` | `compte_id` |
| MARTS_CORE | `fct_virements` | `compte_id` **ou** `contrepartie_compte_id` |
| MARTS_FINANCE | `mart_solde_journalier` | `compte_id` |
| SNAPSHOTS | `snapshot_comptes` | `compte_id` |

Les vues (`STAGING`, `MARTS_SECURE`) n'ont pas de stockage propre : elles
reflètent immédiatement la purge des tables sous-jacentes.

**Co-titulaires** : un titulaire rattaché à un autre compte actif est
**conservé** (seul le lien avec le compte purgé est supprimé). Le préciser
dans la réponse au client.

## 3. Identification

```sql
USE ROLE FINTRACK_COMPLIANCE_ROLE;

SELECT compte_id, tenant_id, statut, date_derniere_activite
FROM FINTRACK_PROD.RAW.raw_comptes
WHERE compte_id = <ID>;

-- Volumétrie concernée (à copier dans le ticket)
SELECT 'raw_transactions' t, COUNT(*) FROM FINTRACK_PROD.RAW.raw_transactions WHERE compte_id = <ID>
UNION ALL SELECT 'raw_virements', COUNT(*) FROM FINTRACK_PROD.RAW.raw_virements
          WHERE compte_source_id = <ID> OR compte_dest_id = <ID>
UNION ALL SELECT 'raw_compte_titulaires', COUNT(*) FROM FINTRACK_PROD.RAW.raw_compte_titulaires WHERE compte_id = <ID>;
```

## 4. Backup légal (obligatoire)

Copie chiffrée, accès restreint DPO, conservée le temps du délai de recours :

```sql
USE ROLE FINTRACK_ADMIN_ROLE;
CREATE TABLE FINTRACK_ARCHIVE.RGPD_BACKUPS.compte_<ID>_<YYYYMMDD> AS
SELECT * FROM FINTRACK_PROD.RAW.raw_comptes WHERE compte_id = <ID>;
```

## 5. Exécution

**Option A — DAG Airflow (recommandé, traçabilité complète)**

UI Airflow → `fintrack_rgpd_purge` → *Trigger DAG w/ config* :

```json
{
  "compte_id": 42,
  "reason": "Demande client du 2026-10-15",
  "requested_by": "compliance@fintrack.example",
  "requested_at": "2026-10-15 14:30:00",
  "ticket_ref": "RGPD-1234"
}
```

Le DAG enchaîne `validate_params → execute_purge → verify_purge → notify_completion`.
Il échoue (et alerte `#compliance-rgpd`) si :
- un paramètre est invalide,
- la procédure renvoie `status = 'partial'`,
- une ligne subsiste dans une des tables du §2,
- l'entrée `rgpd_purge_log` est absente.

**Option B — SQL direct (supervision humaine)**

```sql
USE ROLE FINTRACK_COMPLIANCE_ROLE;
CALL FINTRACK_PROD.GOVERNANCE.rgpd_purge_compte(
    <ID>, 'RGPD-XXX — motif', 'compliance@fintrack.example', '<YYYY-MM-DD HH:MM:SS>'
);
-- Retour attendu : {"status": "completed", "purge_id": "...", ...}
```

## 6. Vérification

```sql
-- Doit renvoyer 0 partout
SELECT COUNT(*) FROM FINTRACK_PROD.RAW.raw_comptes            WHERE compte_id = <ID>;
SELECT COUNT(*) FROM FINTRACK_PROD.RAW.raw_transactions       WHERE compte_id = <ID>;
SELECT COUNT(*) FROM FINTRACK_PROD.MARTS_CORE.dim_comptes     WHERE compte_id = <ID>;
SELECT COUNT(*) FROM FINTRACK_PROD.MARTS_CORE.fct_virements
WHERE compte_id = <ID> OR contrepartie_compte_id = <ID>;

-- Journal
SELECT purge_id, status, executed_by, executed_at, rows_deleted
FROM FINTRACK_PROD.GOVERNANCE.rgpd_purge_log
WHERE compte_id = <ID> ORDER BY executed_at DESC LIMIT 1;
```

`status` doit valoir `completed`. Si `partial` : voir `rows_deleted`
(les tables en erreur y apparaissent avec `ERROR: ...`), corriger, relancer.
La procédure est idempotente (un DELETE déjà fait supprime 0 ligne).

Les marts incrémentaux ne réintroduisent pas le compte : la source RAW est purgée.
Un `dbt build --select tag:marts` au run suivant suffit à tout réaligner.

## 7. Time Travel et Fail-safe

Une ligne supprimée reste récupérable :
- **Time Travel** : jusqu'à `DATA_RETENTION_TIME_IN_DAYS` (90 j en prod)
- **Fail-safe** : 7 jours supplémentaires, accessibles **uniquement** au
  support Snowflake, non purgeables par le client

Pour purger le Time Travel, sur **chaque** table du §2 :

```sql
USE ROLE FINTRACK_ADMIN_ROLE;
ALTER TABLE FINTRACK_PROD.RAW.raw_comptes SET DATA_RETENTION_TIME_IN_DAYS = 0;
ALTER TABLE FINTRACK_PROD.RAW.raw_comptes SET DATA_RETENTION_TIME_IN_DAYS = 90;
-- répéter pour raw_transactions, raw_virements, raw_titulaires,
-- raw_compte_titulaires et les tables MARTS / SNAPSHOTS
```

⚠️ Supprime aussi les points de restauration récents de la table.
À faire en fenêtre de maintenance, regrouper les purges (batch hebdomadaire).

Le délai Time Travel + Fail-safe (≤ 97 j) est déclaré dans le registre des
traitements (Art. 30) et reste compatible avec le délai d'1 mois (Art. 12.3)
car les données ne sont plus accessibles aux utilisateurs métier.

**Conservation légale** : les données de transaction soumises à l'obligation
bancaire de 5 ans (LCB-FT) ne peuvent pas être purgées avant échéance.
Dans ce cas : refus motivé au client, ou pseudonymisation au lieu de suppression
(décision DPO).

## 8. Simulation sur compte de test (preuve d'exécution)

À faire sur un compte de test (pas un vrai client), idéalement en DEV :

```sql
-- a) Choisir un compte clôturé avec des transactions
SELECT c.compte_id, COUNT(t.transaction_id) nb_tx
FROM FINTRACK_PROD.RAW.raw_comptes c
JOIN FINTRACK_PROD.RAW.raw_transactions t USING (compte_id)
WHERE c.statut = 'cloture'
GROUP BY 1 ORDER BY 2 DESC LIMIT 1;

-- b) Capture AVANT (screenshot)
-- c) Lancer le DAG ou le CALL (§5)
-- d) Capture APRÈS : requêtes du §6 = 0, log = completed (screenshot)
```

Joindre les deux captures et le `purge_id` au dossier de preuves CNIL.

## 9. Rollback

Une purge est irréversible par conception. En cas d'erreur (mauvais `compte_id`) :
1. Arrêter immédiatement, prévenir DPO + CTO
2. Restaurer depuis Time Travel si la rétention n'a pas été mise à 0 :
   `INSERT INTO raw_comptes SELECT * FROM raw_comptes AT(OFFSET => -3600) WHERE compte_id = <ID>;`
   (idem pour chaque table du §2), sinon depuis le backup légal (§4)
3. `dbt build --select tag:marts` pour reconstruire les marts
4. Documenter l'incident dans le ticket et dans `rgpd_purge_log` (ligne `status = 'rolled_back'`)

## 10. Notification client

Répondre au ticket avec :
- Confirmation de la purge et référence `purge_id`
- Date d'effet
- Mention du délai technique de suppression des sauvegardes (≤ 97 j)
- Le cas échéant : données conservées au titre d'une obligation légale

## SLA

| Étape | Délai |
|---|---|
| Prise en charge | 5 jours ouvrés |
| Exécution complète | 30 jours (Art. 12.3 RGPD) |

## Escalade

- Anomalie ou purge `partial` → DPO immédiatement
- Blocage technique → CTO / astreinte data (`#data-platform-alerts`)
