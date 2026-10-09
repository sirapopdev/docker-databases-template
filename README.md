# docker-databases-template

PostgreSQL 18 with [Databasus](https://hub.docker.com/r/databasus/databasus) for backups, run with Docker Compose.

## Requirements

- Docker Engine with the Compose v2 plugin (`docker compose`, not `docker-compose`).
  On Ubuntu, follow the [official install guide](https://docs.docker.com/engine/install/ubuntu/).

## Setup

```bash
cp .env.example .env
# edit .env and set POSTGRES_PASSWORD before the first start
docker compose up -d
```

| Variable | Purpose |
|---|---|
| `POSTGRES_USER` | Superuser created on first start |
| `POSTGRES_PASSWORD` | Password for that superuser |
| `POSTGRES_DB` | Default database created on first start |
| `POSTGRES_PORT` | Host port for PostgreSQL (default `5432`) |
| `DATABASUS_PORT` | Host port for the Databasus web UI (default `4005`) |

`POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB` are only read when the data volume is empty.
Changing them in `.env` later does not change the running database; use `ALTER USER` instead.

PostgreSQL listens on `127.0.0.1` only. Databasus listens on all interfaces, so firewall port `4005`
if the server is reachable from the internet.

## Managing app users and databases

`db.sh` creates one login user per app, together with a database of the same name that the user owns.
Only that user (and superusers) can connect to it.

```bash
./db.sh create blog   # create user "blog" and database "blog"
./db.sh update blog   # change the password of user "blog"
./db.sh list          # list login users and the databases they own
```

- You are prompted for the password. Leave it empty to generate a random one; it is printed once, so save it.
- Names must be lowercase letters, digits or `_`, must not start with a digit, and are at most 63 characters.
- The script runs `psql` inside the `postgres` container, so the stack must be running.
  No `psql` on the host and no admin password are needed.

The app then connects with:

```
postgres://blog:<password>@localhost:5432/blog
```

There is no delete command on purpose. To remove a user and its database, run this in `psql` as the superuser
(it permanently deletes the data):

```sql
DROP DATABASE blog;
DROP ROLE blog;
```

## Backups

Open Databasus at `http://<server>:4005` and add the PostgreSQL database there.
The stack is already prepared for Databasus physical backups: `summarize_wal` is on, and
[initdb/10-allow-replication.sh](initdb/10-allow-replication.sh) allows replication connections.
