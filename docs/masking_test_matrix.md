# Matrice de test — Dynamic Data Masking

**Date :** À compléter lors de l'exécution
**Exécutant :** Data Platform Team
**Référence :** `scripts/snowflake/security/02_masking_policies.sql` + ADR 002

---

## Méthodologie

Pour chaque rôle testé :

```sql
USE ROLE <ROLE>;
SELECT compte_id, nom_client, prenom_client, email, telephone,
       iban, date_naissance, adresse_ligne1, ip_address, device_id
FROM FINTRACK_PROD.RAW.raw_comptes
LIMIT 1;
```

Résultat attendu documenté ci-dessous. La colonne **Statut** est à renseigner après exécution réelle sur Snowflake.

---

## Matrice — colonne par rôle

| # | Colonne | Policy | ADMIN / PII_UNMASK | SUPPORT | COMPLIANCE | ANALYST | FRAUD | TRANSFORM (bypass) | Statut |
|---|---------|--------|--------------------|---------|------------|---------|-------|--------------------|--------|
| 1 | `email` | `mask_email` | `alice@acme.com` (clair) | `****@acme.com` | `SHA256(...)` | `SHA256(...)` | `SHA256(...)` | clair (bypass RAP) | ☐ |
| 2 | `nom_client` | `mask_name` | `Dupont` (clair) | `D*****` | `***` | `***` | `***` | clair | ☐ |
| 3 | `prenom_client` | `mask_name` | `Alice` (clair) | `A****` | `***` | `***` | `***` | clair | ☐ |
| 4 | `telephone` | `mask_phone` | `+33612345678` (clair) | `**** 5678` | `***` | `***` | `***` | clair | ☐ |
| 5 | `iban` | `mask_iban` | `FR76...` (clair) | `FR76****...3456` | `FR76****...3456` | `****` | `****` | clair | ☐ |
| 6 | `date_naissance` | `mask_date_of_birth` | `1985-07-14` (clair) | `NULL` | `NULL` | `1985-01-01` (année seule) | `NULL` | clair | ☐ |
| 7 | `adresse_ligne1` | `mask_address` | `12 Rue de la Paix` (clair) | `Rue de la Paix` (n° supprimé) | `[redacted]` | `[redacted]` | `[redacted]` | clair | ☐ |
| 8 | `ip_address` (raw_transactions) | `mask_ip_address` | `192.168.1.42` (clair) | `NULL` | `NULL` | `192.168.1.0` (/24) | `192.168.1.42` (clair) | clair | ☐ |
| 9 | `device_id` (raw_transactions) | `mask_device_id` | `abc-123-xyz` (clair) | `SHA256[:12]` | `SHA256[:12]` | `SHA256[:12]` | `abc-123-xyz` (clair) | clair | ☐ |
| 10 | `compte_source_iban` (raw_transactions) | `mask_iban` | clair | 4 premiers + 4 derniers | 4 premiers + 4 derniers | `****` | `****` | clair | ☐ |

---

## Rôles testés

| Rôle Snowflake | Profil utilisateur |
|----------------|--------------------|
| `FINTRACK_ADMIN_ROLE` | Administrateur plateforme — accès full PII |
| `FINTRACK_PII_UNMASK_ROLE` | DPO / compliance — démasquage autorisé, audité |
| `FINTRACK_SUPPORT_ROLE` | Support client — voir initiale + 4 derniers chiffres |
| `FINTRACK_COMPLIANCE_ROLE` | Conformité RGPD — IBAN partiel, IP /24 |
| `FINTRACK_ANALYST_ROLE` | Analyste BI — tout hashé sauf année DoB et IP /24 |
| `FINTRACK_FRAUD_ROLE` | Détection fraude — IP en clair, device_id en clair |

---

## Résultats d'exécution

> **À remplir lors du test réel.**
> Copier ici les outputs Snowflake pour chaque rôle.

### ADMIN

```
compte_id | nom_client | email | iban | date_naissance | ...
<résultat à coller>
```

### SUPPORT

```
<résultat à coller>
```

### COMPLIANCE

```
<résultat à coller>
```

### ANALYST

```
<résultat à coller>
```

### FRAUD

```
<résultat à coller>
```

---

## Critères de validation

- [ ] Aucun email en clair visible par ANALYST ou FRAUD
- [ ] IBAN jamais en clair en dehors de ADMIN / PII_UNMASK
- [ ] `date_naissance` réduit à l'année pour ANALYST, NULL sinon (hors admin)
- [ ] `device_id` en clair uniquement pour ADMIN, PII_UNMASK et FRAUD
- [ ] `FINTRACK_TRANSFORM_ROLE` passe toutes les policies (bypass confirmé)
- [ ] Audit trail créé dans `SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES` pour chaque policy active

---

## Signalement d'anomalie

Tout écart → incident P1, notifier RSSI + DPO dans l'heure.
Runbook : `docs/runbooks/incident_data_quality.md`
