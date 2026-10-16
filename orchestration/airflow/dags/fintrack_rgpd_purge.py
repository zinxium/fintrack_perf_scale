'''
FinTrack — DAG de purge RGPD
============================================================
Déclenché manuellement ou par un endpoint API "droit à l'oubli".
Prend un compte_id en paramètre, exécute la procédure Snowflake,
vérifie qu'aucune donnée ne subsiste, notifie compliance.

    validate_params → execute_purge → verify_purge → notify_completion
'''
import json
import re
from datetime import datetime

from airflow import DAG
from airflow.decorators import task
from airflow.exceptions import AirflowFailException
from airflow.models.param import Param
from airflow.providers.slack.notifications.slack import send_slack_notification
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook

from slack_callbacks import build_failure_notifier


SNOWFLAKE_CONN_ID = 'snowflake_compliance'   # rôle FINTRACK_COMPLIANCE_ROLE
COMPLIANCE_CHANNEL = '#compliance-rgpd'

# Tables à contrôler après purge : (table, filtre)
VERIFY_CHECKS = [
    ('RAW.raw_comptes',                  'compte_id = %(compte_id)s'),
    ('RAW.raw_transactions',             'compte_id = %(compte_id)s'),
    ('RAW.raw_virements',                'compte_source_id = %(compte_id)s OR compte_dest_id = %(compte_id)s'),
    ('RAW.raw_compte_titulaires',        'compte_id = %(compte_id)s'),
    ('MARTS_CORE.fct_transactions',      'compte_id = %(compte_id)s'),
    ('MARTS_CORE.fct_virements',         'compte_id = %(compte_id)s OR contrepartie_compte_id = %(compte_id)s'),
    ('MARTS_CORE.dim_comptes',           'compte_id = %(compte_id)s'),
    ('MARTS_CORE.dim_comptes_scd2',      'compte_id = %(compte_id)s'),
    ('MARTS_CORE.bridge_comptes_titulaires', 'compte_id = %(compte_id)s'),
    ('MARTS_FINANCE.mart_solde_journalier',  'compte_id = %(compte_id)s'),
    ('SNAPSHOTS.snapshot_comptes',       'compte_id = %(compte_id)s'),
]


default_args = {
    'owner': 'compliance',
    'retries': 0,  # opérations irréversibles : pas de retry auto
    'on_failure_callback': build_failure_notifier(channel=COMPLIANCE_CHANNEL),
}


with DAG(
    dag_id='fintrack_rgpd_purge',
    default_args=default_args,
    description='Droit à l\'oubli RGPD — purge d\'un compte client',
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=['fintrack', 'rgpd', 'compliance'],
    params={
        'compte_id':      Param(0, type='integer', description='ID du compte à purger'),
        'reason':         Param('', type='string', description='Motif de la purge'),
        'requested_by':   Param('', type='string', description='Email du demandeur'),
        'requested_at':   Param('', type='string', description='Timestamp ISO de la demande (YYYY-MM-DD HH:MM:SS)'),
        'ticket_ref':     Param('', type='string', description='Référence ticket (RGPD-XXX)'),
    },
) as dag:

    @task
    def validate_params(**context):
        params = context['params']
        if params['compte_id'] <= 0:
            raise AirflowFailException('compte_id invalide')
        if not params['reason']:
            raise AirflowFailException('reason obligatoire')
        if '@' not in params['requested_by']:
            raise AirflowFailException('requested_by doit être un email')
        if not re.fullmatch(r'RGPD-[0-9]+', params['ticket_ref']):
            raise AirflowFailException('ticket_ref doit être au format RGPD-XXX')
        try:
            datetime.fromisoformat(params['requested_at'])
        except ValueError:
            raise AirflowFailException('requested_at doit être au format ISO')
        return dict(params)

    @task
    def execute_purge(params: dict):
        hook = SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID)
        # Paramètres liés : aucune valeur utilisateur n'est concaténée au SQL
        row = hook.get_first(
            'CALL FINTRACK_PROD.GOVERNANCE.rgpd_purge_compte('
            '%(compte_id)s, %(reason)s, %(requested_by)s, %(requested_at)s)',
            parameters={
                'compte_id': params['compte_id'],
                'reason': f"{params['ticket_ref']} — {params['reason']}",
                'requested_by': params['requested_by'],
                'requested_at': params['requested_at'],
            },
        )
        result = json.loads(row[0]) if isinstance(row[0], str) else row[0]
        if result.get('status') != 'completed':
            raise AirflowFailException(f'Purge partielle : {result.get("rows_deleted")}')
        return result

    @task
    def verify_purge(params: dict, purge_result: dict):
        hook = SnowflakeHook(snowflake_conn_id=SNOWFLAKE_CONN_ID)
        leftovers = {}
        for table, where in VERIFY_CHECKS:
            count = hook.get_first(
                f'SELECT COUNT(*) FROM FINTRACK_PROD.{table} WHERE {where}',
                parameters={'compte_id': params['compte_id']},
            )[0]
            if count:
                leftovers[table] = count
        if leftovers:
            raise AirflowFailException(f'Données résiduelles après purge : {leftovers}')

        log = hook.get_first(
            'SELECT purge_id, status FROM FINTRACK_PROD.GOVERNANCE.rgpd_purge_log '
            'WHERE compte_id = %(compte_id)s ORDER BY executed_at DESC LIMIT 1',
            parameters={'compte_id': params['compte_id']},
        )
        if not log or log[1] != 'completed':
            raise AirflowFailException('Entrée rgpd_purge_log absente ou non completed')
        return {'purge_id': log[0], 'ticket_ref': params['ticket_ref']}

    @task
    def notify_completion(verification: dict, **context):
        notifier = send_slack_notification(
            slack_conn_id='slack_default',
            channel=COMPLIANCE_CHANNEL,
            text=(
                ':white_check_mark: *Purge RGPD terminée*\n'
                f"Ticket   : `{verification['ticket_ref']}`\n"
                f"Purge ID : `{verification['purge_id']}`\n"
                'Rappel : Time Travel à purger selon le runbook (étape 5).'
            ),
        )
        notifier(context)

    params = validate_params()
    purge = execute_purge(params)
    verification = verify_purge(params, purge)
    notify_completion(verification)
