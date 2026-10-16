{% macro create_audit_run_row() %}
    {#-
        Crée une ligne de démarrage dans AUDIT.pipeline_run_metrics.
        Appelée via on-run-start.
    -#}
    {% if execute and flags.WHICH in ('run', 'build') %}
        {% set sql %}
            insert into {{ target.database }}.audit.pipeline_run_metrics
                (run_id, run_started_at, target, status, triggered_by, airflow_dag_run_id)
            values (
                '{{ invocation_id }}',
                current_timestamp(),
                '{{ target.name }}',
                'running',
                '{{ env_var("USER", "unknown") }}',
                '{{ env_var("AIRFLOW_DAG_RUN_ID", "") }}'
            )
        {% endset %}
        {% do run_query(sql) %}
    {% endif %}
{% endmacro %}


{% macro update_audit_run_row(results) %}
    {#- Met à jour la ligne créée en on-run-start avec le résultat final. -#}
    {% if execute and flags.WHICH in ('run', 'build') %}
        {% set nb_success = results | selectattr('status', 'equalto', 'success') | list | length %}
        {% set nb_error   = results | selectattr('status', 'equalto', 'error')   | list | length %}
        {% set overall = 'success' if nb_error == 0 else 'error' %}

        {% set sql %}
            update {{ target.database }}.audit.pipeline_run_metrics
            set
                run_ended_at = current_timestamp(),
                duration_seconds = datediff('second', run_started_at, current_timestamp()),
                status = '{{ overall }}',
                nb_models_success = {{ nb_success }},
                nb_models_error   = {{ nb_error }}
            where run_id = '{{ invocation_id }}'
        {% endset %}
        {% do run_query(sql) %}
    {% endif %}
{% endmacro %}
