#!/usr/bin/env bash
# Manage app users in the postgres container. Each user gets a database of the
# same name that only it (and superusers) can connect to.
# Delete is left out on purpose: drop roles/databases by hand with psql.
set -eu

usage() {
  cat >&2 <<EOF
Usage: $0 <command> [name]
  create <name>   create user <name> and database <name> owned by it
  update <name>   change the password of user <name>
  list            list login users and the databases they own
EOF
  exit 1
}

run_psql() {
  # The local socket inside the container is trusted, so no admin password is needed.
  # The password travels as env var PW (read by \getenv), never on the command line.
  docker exec -i -e PW postgres sh -c \
    'exec psql -X -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"' sh "$@"
}

check_name() {
  [[ "${1:-}" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || {
    echo "Name must be lowercase letters, digits or _, not start with a digit, max 63 chars" >&2
    exit 1
  }
}

read_password() {
  read -rsp "Password (empty = generate): " PW
  echo >&2
  if [ -z "$PW" ]; then
    PW=$(openssl rand -hex 16)
    echo "Generated password: $PW"
  fi
  export PW
}

case "${1:-}" in
  create)
    check_name "${2:-}"
    read_password
    run_psql -v name="$2" <<'SQL'
\getenv pw PW
CREATE ROLE :"name" LOGIN PASSWORD :'pw';
CREATE DATABASE :"name" OWNER :"name";
REVOKE ALL ON DATABASE :"name" FROM PUBLIC;
SQL
    echo "Created user and database: $2"
    ;;
  update)
    check_name "${2:-}"
    read_password
    run_psql -v name="$2" <<'SQL'
\getenv pw PW
ALTER ROLE :"name" PASSWORD :'pw';
SQL
    echo "Updated password for: $2"
    ;;
  list)
    run_psql <<'SQL'
SELECT r.rolname AS "user",
       r.rolsuper AS superuser,
       coalesce(string_agg(d.datname, ', ' ORDER BY d.datname), '') AS databases
FROM pg_roles r
LEFT JOIN pg_database d ON d.datdba = r.oid AND NOT d.datistemplate
WHERE r.rolcanlogin
GROUP BY r.rolname, r.rolsuper
ORDER BY 1;
SQL
    ;;
  *) usage ;;
esac
