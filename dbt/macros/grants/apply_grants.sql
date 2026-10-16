{% macro fintrack_apply_grants(model, grants_dict) %}
    {#-
        Applique une liste de grants à un modèle.
        Alternative si les +grants dans dbt_project.yml ne suffisent pas
        (cas des futures grants, ou grants conditionnels).
    -#}
    {% if execute %}
        {% for privilege, roles in grants_dict.items() %}
            {% for role in roles %}
                {% set sql = "grant " ~ privilege ~ " on " ~ model ~ " to role " ~ role %}
                {% do run_query(sql) %}
                {{ log("Granted " ~ privilege ~ " on " ~ model ~ " to " ~ role, info=True) }}
            {% endfor %}
        {% endfor %}
    {% endif %}
{% endmacro %}
