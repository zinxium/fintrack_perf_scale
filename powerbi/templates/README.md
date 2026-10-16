# Templates Power BI

## Fichier `.pbit`

Le fichier `.pbit` (Power BI Template) n'est pas versionnable en texte —
c'est un ZIP binaire. Pour ce projet, nous fournissons :

1. Le **modèle sémantique** documenté (`../model/semantic_model.md`)
2. La **bibliothèque DAX** (`../measures/dax_library.md`)
3. Les **guides de connexion** (`../guides/`)

## Reconstruction du .pbit à partir de la doc

1. Power BI Desktop → Get Data → Snowflake → suivre `guides/01_connection_snowflake.md`
2. Importer les 7 tables listées dans `model/semantic_model.md`
3. Créer les relations selon le diagramme
4. Créer la table `d_dates` (script DAX fourni)
5. Copier les mesures depuis `measures/dax_library.md`
6. Configurer RLS selon `guides/02_composable_rls.md`
7. File → Export → Power BI Template (.pbit)

## Rapports de référence à construire

- **Tenant Overview** : volumes, KPIs, tendances par tenant
- **Compliance Monitoring** : flags AML, taux de rapprochement, alerts fraud
- **Executive Summary** : synthèse mensuelle 1 page

## Versionning

- Le `.pbit` peut être stocké dans un blob (Azure Storage / S3)
- Le CI publie la nouvelle version après validation
- L'API Power BI trigger le refresh après chaque dbt build production
