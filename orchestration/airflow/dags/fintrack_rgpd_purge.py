'''
FinTrack — DAG de purge RGPD
============================================================
Déclenché manuellement ou par un endpoint API "droit à l'oubli".
Prend un compte_id en paramètre, exécute la procédure Snowflake,
notifie compliance.
'''
from datetime import datetime, timedelta

from airflow import DAG
from airflow.decorators import task
from airflow.models.param import Param
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator


default_args = {
    'owner': 'compliance',
    'retries': 0,  # opérations irréversibles : pas de retry auto
}


with DAG(
    dag_id='fintrack_rgpd_purge',
    default_args=default_args,
    description='Droit à l\'oubli RGPD — purge d\'un compte client',
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=['fintrack', 'rgpd', 'compliance'],
    params={
        'compte_id':      Param(0, type='integer', description='ID du compte à purger'),
        'reason':         Param('', type='string', description='Motif de la purge'),
        'requested_by':   Param('', type='string', description='Email du demandeur'),
        'requested_at':   Param('', type='string', description='Timestamp ISO de la demande'),
        'ticket_ref':     Param('', type='string', description='Référence ticket support'),
    },
) as dag:

    @task
    def validate_params(**context):
        params = context['params']
        assert params['compte_id'] > 0, 'compte_id invalide'
        assert params['reason'], 'reason obligatoire'
        assert params['requested_by'], 'requested_by obligatoire'
        assert '@' in params['requested_by'], 'requested_by doit être un email'
        return params

    execute_purge = SnowflakeOperator(
        task_id='execute_purge',
        snowflake_conn_id='snowflake_compliance',
        sql=(
            "CALL FINTRACK_PROD.GOVERNANCE.rgpd_purge_compte("
            "{{ params.compte_id }}, "
            "'{{ params.reason }}', "
            "'{{ params.requested_by }}', "
            "'{{ params.requested_at }}'::TIMESTAMP_NTZ"
            ")"
        ),
    )

    @task
    def notify_completion(**context):
        # Envoi email compliance + réponse au ticket
        pass

    validate_params() >> execute_purge >> notify_completion()
