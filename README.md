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
| `POSTGRES_TLS_HOST` | IP or domain that apps connect to. It is written into the TLS certificate so clients can verify the server |
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

In `.env`, set `POSTGRES_BIND=0.0.0.0` and `POSTGRES_TLS_HOST` to the IP or domain the app will connect to,
then run `docker compose up -d`. Access is then controlled by [pg_hba.conf](pg_hba.conf):

| From | Allowed |
|---|---|
| Inside the container (`db.sh`, `docker exec`) | Yes, no password |
| Docker networks and the server itself (Databasus, SSH tunnel) | Yes, password, TLS optional |
| The internet | App users only, password and TLS required. The `postgres` superuser and replication are rejected |

On first start the stack creates its own CA and a server certificate signed by it, both in the data volume
(`/var/lib/postgresql/ssl`). The certificate belongs to the server, so every user and database on it shares
the same CA. Give the CA certificate to each app so it can verify the server. It is not a secret:

```bash
docker exec postgres cat /var/lib/postgresql/ssl/ca.crt
```

The app then connects to the host named in `POSTGRES_TLS_HOST`, trusting that CA:

```
postgres://blog:<password>@<POSTGRES_TLS_HOST>:5432/blog?sslmode=verify-full
```

How the CA is supplied depends on the client: `sslrootcert=<file>` for libpq-style clients, or the certificate
text in an environment variable passed to the driver's TLS options. Without the CA, `sslmode=require` still
encrypts but does not verify the server (with node-postgres, use `sslmode=no-verify` for that).

Changing `POSTGRES_TLS_HOST` and running `docker compose up -d` reissues the server certificate. The CA stays
the same, so apps keep working without a new CA certificate. Stacks started with the earlier single
self-signed certificate get the CA and a new server certificate on the next `docker compose up -d`.

If your provider has a firewall, allow port `5432` there. For admin work (DataGrip and similar), keep using
an SSH tunnel to `localhost:5432`.

### Certificate expiry

The CA and the server certificate are valid for 10 years and are not renewed automatically. Check the date with:

```bash
docker exec postgres openssl x509 -in /var/lib/postgresql/ssl/ca.crt -noout -enddate
```

To renew, delete the CA and restart. This creates a new CA and server certificate:

```bash
docker exec postgres rm /var/lib/postgresql/ssl/ca.crt
docker compose restart postgres
docker exec postgres cat /var/lib/postgresql/ssl/ca.crt
```

Apps that verify the server cannot connect until they are given the new CA certificate, so plan for downtime.

Stick to IPv4 for `POSTGRES_BIND`. Docker forwards IPv6 through `docker-proxy`, which hides the client
address and would let internet clients pass as Docker-network clients.

## Backups

Open Databasus at `http://<server>:4005` and add the PostgreSQL database there. Databasus reaches PostgreSQL
over the Docker network, so use host `postgres` and port `5432` (not the server's IP, and not `POSTGRES_PORT`).
SSL mode can be `Disable` or `Require`; the traffic never leaves the server.
The stack is already prepared for Databasus physical backups: `summarize_wal` is on, and
[pg_hba.conf](pg_hba.conf) allows replication connections from Docker networks.
