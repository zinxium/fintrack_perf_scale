# Slack Alerting Configuration

## Channels

| Channel | Usage | Volume attendu |
|---------|-------|----------------|
| `#data-platform-alerts` | Échecs pipeline, DAG failures | ~2/semaine |
| `#data-quality-alerts` | Elementary anomalies, tests fail | ~10/jour |
| `#data-platform-info` | Runs successful, deploys | ~30/jour |
| `#data-fraud-critical` | Anomalies transactions temps réel | Variable |

## Sévérités

- **critical** : ping @channel, escalade PagerDuty après 15 min
- **warning** : ping du rôle owner
- **info** : notification passive

## Rate limiting

- Max 5 alertes / minute par channel (aggregation Elementary)
- Silence pendant les fenêtres de maintenance (variable Airflow `MAINTENANCE_MODE`)

## Templates

Voir `orchestration/airflow/plugins/slack_callbacks.py`.
