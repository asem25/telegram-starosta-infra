# Telegram Starosta infrastructure

Production deployment is split across two servers:

- the backend server runs PostgreSQL and the Spring Boot backend;
- the mini-app server runs the Telegram Mini App container.

Both application ports are bound to `127.0.0.1` and are expected to be exposed
through an HTTPS reverse proxy already configured on each server.

## Initial server setup

The infrastructure workflow uploads deployment files to
`/ru/asem/bot/telegram-starosta-infra` by default. Override the path with the
`BACKEND_DEPLOY_PATH` and `MINI_APP_DEPLOY_PATH` repository variables.

On the backend server:

```bash
cp prod.backend.env.example prod.env
chmod 600 prod.env
```

On the mini-app server:

```bash
cp prod.mini-app.env.example prod.env
chmod 600 prod.env
```

Replace every placeholder before running a deployment. `prod.env` is ignored by
Git and must never be uploaded back to the repository.

## Backend VPS deployment

The commands below assume a Linux VPS, a DNS name that points to it, and a user
that can connect over SSH and run Docker. Install Docker Engine with the Compose
plugin before continuing. Allow inbound SSH, HTTP and HTTPS in the VPS firewall;
do not open PostgreSQL port 5432 publicly.

Check the required Docker commands on the VPS:

```bash
docker --version
docker compose version
```

Create the deployment directory used by the workflows:

```bash
sudo mkdir -p /ru/asem/bot/telegram-starosta-infra
sudo chown -R "$(id -u)":"$(id -g)" /ru/asem/bot/telegram-starosta-infra
cd /ru/asem/bot/telegram-starosta-infra
```

Copy these files from this repository to the directory, either with the
infrastructure workflow or manually with `scp`:

- `docker-compose.yaml`;
- `deploy.sh`;
- `prod.backend.env.example`.

For the initial manual upload, run this from the infrastructure repository on
your workstation:

```bash
scp docker-compose.yaml deploy.sh prod.backend.env.example \
  <server-user>@<backend-server>:/ru/asem/bot/telegram-starosta-infra/
```

Create the production environment file and restrict access to it:

```bash
cp prod.backend.env.example prod.env
chmod 600 prod.env
```

Replace every placeholder in `prod.env`. In particular:

- use a unique PostgreSQL password;
- set `TELEGRAM_BOT_TOKEN` to the production bot token;
- generate `TELEGRAM_AUTH_TOKEN_SECRET` with at least 32 random bytes, for
  example with `openssl rand -base64 48`;
- set `MINI_APP_ALLOWED_ORIGINS` to the public HTTPS origin of the Mini App;
- set the current semester dates.

If the backend image in GHCR is private, authenticate once on the VPS using a
dedicated token with package read access:

```bash
read -rsp 'GHCR read token: ' GHCR_READ_TOKEN && echo
printf '%s' "$GHCR_READ_TOKEN" | docker login ghcr.io -u '<GITHUB_USER>' --password-stdin
unset GHCR_READ_TOKEN
```

Then perform the first deployment:

```bash
chmod +x deploy.sh
./deploy.sh ghcr.io/<github-owner>/<backend-repository> latest
```

The script validates `prod.env`, starts PostgreSQL, waits for an authenticated
database query to succeed, pulls the requested backend image, recreates the
backend container, and waits for `/api/v1/check` to become healthy.

Verify the result:

```bash
docker compose --env-file prod.env -f docker-compose.yaml ps
curl --fail http://127.0.0.1:8081/api/v1/check
docker compose --env-file prod.env -f docker-compose.yaml logs --tail 100 backend
```

The backend listens only on `127.0.0.1:8081`. Configure the HTTPS reverse proxy
on the VPS to forward the public backend domain to `http://127.0.0.1:8081`, then
verify the public endpoint:

```bash
curl --fail https://<backend-domain>/api/v1/check
```

### GitHub Actions configuration

In both the infrastructure repository and the backend repository, configure:

- `BACKEND_SERVER_HOST` secret: VPS address;
- `BACKEND_SERVER_USER` secret: SSH user;
- `BACKEND_SERVER_SSH_KEY` secret: private deployment key;
- `BACKEND_DEPLOY_PATH` variable: deployment directory, or omit it to use
  `/ru/asem/bot/telegram-starosta-infra`.

Run the infrastructure workflow first. It uploads and validates the Compose and
deployment files without replacing `prod.env`. Then push to the backend
repository's `master` branch or run its workflow manually. The backend workflow
builds an immutable `sha-...` image, pushes it to GHCR, and invokes `deploy.sh`
on the VPS with that exact image tag.

For diagnostics on the VPS:

```bash
cd /ru/asem/bot/telegram-starosta-infra
docker compose --env-file prod.env -f docker-compose.yaml ps
docker compose --env-file prod.env -f docker-compose.yaml logs --tail 200 postgres backend
```

PostgreSQL data is stored in the `starosta-backend_pgdata` Docker volume and
survives container recreation. Changing `POSTGRES_PASSWORD` in `prod.env` does
not change the password already stored in an initialized database; rotate the
database role password separately before updating the file.

## GitHub configuration

Configure these secrets in the infrastructure repository:

- `BACKEND_SERVER_HOST`, `BACKEND_SERVER_USER`, `BACKEND_SERVER_SSH_KEY`;
- `MINI_APP_SERVER_HOST`, `MINI_APP_SERVER_USER`, `MINI_APP_SERVER_SSH_KEY`.

The application repositories require the corresponding three secrets as well.
The mini-app repository also requires `NEXT_PUBLIC_API_URL` and
`NEXT_PUBLIC_APP_URL` repository variables containing production HTTPS URLs.

## PostgreSQL access

PostgreSQL is deliberately bound only to the backend server loopback interface.
Connect from an administrator workstation through an SSH tunnel:

```bash
ssh -L 5432:127.0.0.1:5432 <server-user>@<backend-server>
```

Then connect the database client to `127.0.0.1:5432`. This provides external
access without exposing PostgreSQL directly to the public internet.
