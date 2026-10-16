#!/usr/bin/env python3
'''Supprime les schémas CI_* orphelins de plus de N jours.'''
import argparse
import os
import sys
from datetime import datetime, timedelta

import snowflake.connector


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--older-than-days', type=int, default=7)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    conn = snowflake.connector.connect(
        account=os.environ['SNOWFLAKE_ACCOUNT'],
        user=os.environ['SNOWFLAKE_USER'],
        password=os.environ['SNOWFLAKE_PASSWORD'],
        role='FINTRACK_ADMIN_ROLE',
        warehouse='WH_DEV',
    )
    cur = conn.cursor()

    threshold = datetime.utcnow() - timedelta(days=args.older_than_days)
    cur.execute(
        "SELECT schema_name, created "
        "FROM FINTRACK_DEV.INFORMATION_SCHEMA.SCHEMATA "
        "WHERE schema_name LIKE 'CI_%'"
    )
    rows = cur.fetchall()

    for schema, created in rows:
        if created.replace(tzinfo=None) < threshold:
            sql = f"DROP SCHEMA IF EXISTS FINTRACK_DEV.{schema} CASCADE"
            print(f"{'[DRY-RUN] ' if args.dry_run else ''}{sql}")
            if not args.dry_run:
                cur.execute(sql)

    cur.close()
    conn.close()


if __name__ == '__main__':
    main()
