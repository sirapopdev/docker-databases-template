#!/bin/sh
# Runs once on first init. The default pg_hba "host all all all" line does not
# match replication connections, which Databasus physical backups need.
set -e
echo "host replication all all scram-sha-256" >> "$PGDATA/pg_hba.conf"
