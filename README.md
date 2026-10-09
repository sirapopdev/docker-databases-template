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
| `POSTGRES_BIND` | `127.0.0.1` (default): this server only. `0.0.0.0`: open to the internet, see [Connecting from another server](#connecting-from-another-server) |
| `POSTGRES_PORT` | Host port for PostgreSQL (default `5432`) |
| `DATABASUS_PORT` | Host port for the Databasus web UI (default `4005`) |

`POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_DB` are only read when the data volume is empty.
Changing them in `.env` later does not change the running database; use `ALTER USER` instead.

Databasus listens on all interfaces. Block port `4005` in your cloud provider's firewall if the server is
reachable from the internet: `ufw` does not apply to ports published by Docker.

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

## Connecting from another server

Set `POSTGRES_BIND=0.0.0.0` in `.env` and run `docker compose up -d`. Access is then controlled by
[pg_hba.conf](pg_hba.conf):

| From | Allowed |
|---|---|
| Inside the container (`db.sh`, `docker exec`) | Yes, no password |
| Docker networks and the server itself (Databasus, SSH tunnel) | Yes, password, TLS optional |
| The internet | App users only, password and TLS required. The `postgres` superuser and replication are rejected |

The app connects with TLS:

```
postgres://blog:<password>@<server-ip>:5432/blog?sslmode=require
```

With node-postgres (`pg`), use `sslmode=no-verify` instead: it treats `require` as `verify-full`,
which fails against the self-signed certificate.

The certificate is self-signed and created on first start in the data volume (`/var/lib/postgresql/ssl`).
Traffic is encrypted, but clients cannot verify the server's identity. If your provider has a firewall,
allow port `5432` there. For admin work (DataGrip and similar), keep using an SSH tunnel to `localhost:5432`.

Stick to IPv4 for `POSTGRES_BIND`. Docker forwards IPv6 through `docker-proxy`, which hides the client
address and would let internet clients pass as Docker-network clients.

## Backups

Open Databasus at `http://<server>:4005` and add the PostgreSQL database there.
The stack is already prepared for Databasus physical backups: `summarize_wal` is on, and
[pg_hba.conf](pg_hba.conf) allows replication connections from Docker networks.
