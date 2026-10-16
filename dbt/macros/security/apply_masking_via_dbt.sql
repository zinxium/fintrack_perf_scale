{% macro apply_masking_policies() %}
    {#-
        Post-hook macro : applique les masking policies aux colonnes
        appropriées d'un modèle mart après matérialisation.

        Utilisation dans un modèle :
            {{ config(post_hook = "{{ apply_masking_policies() }}") }}

        Détecte les colonnes candidates via leur nom et applique la policy
        correspondante depuis GOVERNANCE.
    -#}

    {% set masking_map = {
        'email':          'mask_email',
        'nom_client':     'mask_name',
        'prenom_client':  'mask_name',
        'telephone':      'mask_phone',
        'iban':           'mask_iban',
        'ip_address':     'mask_ip_address',
        'device_id':      'mask_device_id',
        'date_naissance': 'mask_date_of_birth'
    } %}

    {% set columns_query %}
        select column_name
        from {{ target.database }}.information_schema.columns
        where table_schema = upper('{{ this.schema }}')
          and table_name   = upper('{{ this.name }}')
    {% endset %}

    {% if execute %}
        {% set columns = run_query(columns_query).columns[0].values() %}
        {% set sqls = [] %}
        {% for col in columns %}
            {% set col_lower = col | lower %}
            {% if col_lower in masking_map.keys() %}
                {% set alter = "alter table " ~ this ~ " modify column " ~ col ~
                                " set masking policy FINTRACK_PROD.governance." ~ masking_map[col_lower] %}
                {% do sqls.append(alter) %}
            {% endif %}
        {% endfor %}

        {% for sql in sqls %}
            {% do run_query(sql) %}
            {{ log("Applied masking: " ~ sql, info=True) }}
        {% endfor %}
    {% endif %}

    {{ return('') }}
{% endmacro %}
