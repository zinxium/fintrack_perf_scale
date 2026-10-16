'''Callbacks Airflow standardisés pour notifications Slack.

Rappel : send_slack_notification retourne un Notifier callable qu'Airflow
invoquera avec context. On l'assigne directement (pas de wrapper def).
Le contenu du text supporte les templates Jinja Airflow.
'''
from airflow.providers.slack.notifications.slack import send_slack_notification


def build_failure_notifier(channel='#data-platform-alerts'):
    return send_slack_notification(
        slack_conn_id='slack_default',
        channel=channel,
        text=(
            ':x: *DAG failure*\n'
            'DAG  : `{{ dag.dag_id }}`\n'
            'Task : `{{ ti.task_id }}`\n'
            'Try  : {{ ti.try_number }}/{{ ti.max_tries }}\n'
            'Logs : {{ ti.log_url }}'
        ),
    )


def build_success_notifier(channel='#data-platform-info'):
    return send_slack_notification(
        slack_conn_id='slack_default',
        channel=channel,
        text=':white_check_mark: DAG `{{ dag.dag_id }}` completed',
    )


# Usage dans un DAG :
#   from slack_callbacks import build_failure_notifier
#   default_args = {..., 'on_failure_callback': build_failure_notifier()}
