# Architecture — Flux de données

```
┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
│  Core Banking   │───────▶│  S3 / Blob      │───────▶│  Snowflake RAW  │
│  (15 tenants)   │  CDC   │  (staging)      │ COPY   │  + Tags + RAP   │
└─────────────────┘        └─────────────────┘  INTO  └────────┬────────┘
                                                                │
                                                                ▼
                                                       ┌─────────────────┐
                                                       │  dbt STAGING    │
                                                       │  (views typées) │
                                                       └────────┬────────┘
                                                                │
                                                                ▼
                                                       ┌─────────────────┐
                                                       │  dbt MARTS      │
                                                       │  (tables + SCD2)│
                                                       └────────┬────────┘
                                                                │
                             ┌──────────────────┬───────────────┼───────────────┬──────────────┐
                             ▼                  ▼               ▼               ▼              ▼
                    ┌────────────────┐  ┌──────────────┐ ┌───────────┐ ┌─────────────┐ ┌───────────┐
                    │ Secure Views   │  │ Elementary   │ │ Power BI  │ │ Hightouch   │ │ Metabase  │
                    │ (masking)      │  │ Observability│ │ (RLS SSO) │ │ Reverse ETL │ │ Ops       │
                    └────────────────┘  └──────────────┘ └───────────┘ └─────────────┘ └───────────┘
                                                                │             │
                                                                ▼             ▼
                                                          ┌──────────┐  ┌──────────┐
                                                          │ Business │  │ HubSpot  │
                                                          │  Users   │  │   CRM    │
                                                          └──────────┘  └──────────┘

  Orchestration : Airflow  ─┬─▶ ingestion
                            ├─▶ dbt build
                            ├─▶ observability
                            └─▶ reverse ETL

  Gouvernance   : Row Access Policies (multi-tenant) + Masking (PII) + Tags (classification)
```
