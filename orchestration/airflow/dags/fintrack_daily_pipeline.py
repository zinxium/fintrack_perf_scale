'''
FinTrack — DAG quotidien production
============================================================
Orchestration complète :
    ingestion → snapshot → dbt build → tests → observability → reverse ETL
'''
from datetime import datetime, timedelta

from airflow import DAG
from airflow.models import Variable
from airflow.operators.bash import BashOperator
from airflow.operators.empty import EmptyOperator
from airflow.providers.slack.notifications.slack import send_slack_notification
from airflow.sensors.external_task import ExternalTaskSensor
from airflow.utils.task_group import TaskGroup


DBT_DIR = Variable.get('DBT_PROJECT_DIR', '/opt/dbt/fintrack_production_platform')
SLACK_CHANNEL = '#data-platform-alerts'


# ATTENTION : send_slack_notification retourne un Notifier callable.
# Il DOIT être assigné directement à on_failure_callback (Airflow l'appellera
# avec context). Ne PAS le wrapper dans un def qui retournerait le Notifier
# sans l'invoquer — sinon aucune alerte n'est envoyée.
slack_failure_notifier = send_slack_notification(
    slack_conn_id='slack_default',
    channel=SLACK_CHANNEL,
    text=(
        ':x: *DAG {{ dag.dag_id }}* failed\n'
        'Task : `{{ ti.task_id }}`\n'
        'Run  : {{ run_id }}\n'
        'Logs : {{ ti.log_url }}'
    ),
)


def slack_on_sla_miss(dag, task_list, blocking_task_list, slas, blocking_tis):
    # sla_miss_callback a une signature spécifique — on invoque le Notifier
    # à la main avec un mini contexte.
    notifier = send_slack_notification(
        slack_conn_id='slack_default',
        channel=SLACK_CHANNEL,
        text=f':alarm_clock: SLA miss on {dag.dag_id} — tasks: {[t.task_id for t in slas]}',
    )
    notifier({'dag': dag})


default_args = {
    'owner': 'data-platform',
    'depends_on_past': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'retry_exponential_backoff': True,
    'max_retry_delay': timedelta(hours=1),
    'on_failure_callback': slack_failure_notifier,
    'sla': timedelta(hours=2),
}


with DAG(
    dag_id='fintrack_daily_pipeline',
    default_args=default_args,
    description='Pipeline FinTrack quotidien — ingestion + dbt + observability + reverse ETL',
    schedule='0 3 * * *',
    start_date=datetime(2024, 1, 1),
    catchup=False,
    max_active_runs=1,
    sla_miss_callback=slack_on_sla_miss,
    tags=['fintrack', 'dbt', 'prod'],
) as dag:

    start = EmptyOperator(task_id='start')

    with TaskGroup('ingestion') as ingestion:
        wait_upstream = ExternalTaskSensor(
            task_id='wait_core_banking_export',
            external_dag_id='core_banking_export_daily',
            external_task_id='export_completed',
            timeout=3600,
            mode='reschedule',
            poke_interval=300,
            allowed_states=['success'],
            failed_states=['failed', 'skipped'],
        )

        run_ingestion = BashOperator(
            task_id='snowflake_copy_into',
            bash_command='snowsql -f /opt/scripts/03_stage_and_copy.sql',
        )

        wait_upstream >> run_ingestion

    with TaskGroup('dbt') as dbt_group:
        dbt_deps = BashOperator(
            task_id='dbt_deps',
            bash_command=f'cd {DBT_DIR} && dbt deps',
        )
        dbt_snapshot = BashOperator(
            task_id='dbt_snapshot',
            bash_command=f'cd {DBT_DIR} && dbt snapshot --target prod',
        )
        dbt_run_staging = BashOperator(
            task_id='dbt_run_staging',
            bash_command=f'cd {DBT_DIR} && dbt run --target prod --select tag:staging',
        )
        dbt_run_marts = BashOperator(
            task_id='dbt_run_marts',
            bash_command=f'cd {DBT_DIR} && dbt run --target prod --select tag:marts',
        )
        dbt_test = BashOperator(
            task_id='dbt_test',
            bash_command=f'cd {DBT_DIR} && dbt test --target prod --exclude tag:todo',
        )
        dbt_deps >> dbt_snapshot >> dbt_run_staging >> dbt_run_marts >> dbt_test

    with TaskGroup('observability') as observability:
        elementary_report = BashOperator(
            task_id='elementary_report',
            bash_command=f'edr monitor --project-dir {DBT_DIR}',
        )
        elementary_send_report = BashOperator(
            task_id='elementary_send_report',
            bash_command=f'edr send-report --slack-channel {SLACK_CHANNEL}',
        )
        elementary_report >> elementary_send_report

    with TaskGroup('reverse_etl') as reverse_etl:
        hightouch_sync = BashOperator(
            task_id='hightouch_trigger',
            bash_command=(
                'curl -X POST -H "Authorization: Bearer $HIGHTOUCH_TOKEN" '
                'https://api.hightouch.io/api/v1/syncs/12345/trigger'
            ),
        )
        powerbi_refresh = BashOperator(
            task_id='powerbi_refresh_dataset',
            bash_command='python /opt/scripts/powerbi_refresh.py --dataset tenant_overview',
        )

    end = EmptyOperator(task_id='end', trigger_rule='none_failed_min_one_success')

    start >> ingestion >> dbt_group >> observability >> reverse_etl >> end
