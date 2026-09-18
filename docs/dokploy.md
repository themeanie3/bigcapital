# Deploying this fork on Dokploy

`docker-compose.dokploy.yml` builds the `server` and `webapp` images from this
repository (not from the upstream `bigcapitalhq/*` images) and runs the full
stack (MariaDB, Redis, Gotenberg, Garage, ClickHouse, Envoy) behind Dokploy's
Traefik.

## 1. Create the service

1. Dokploy → **Projects** → your project → **Create Service** → **Compose**.
2. Name it (e.g. `bigcapital`), Compose type **Docker Compose**.
3. **Provider**: GitHub (if the Dokploy GitHub app is installed) or **Git** with
   the fork URL `https://github.com/themeanie3/bigcapital.git`.
   - Branch: `develop` (or the branch you want deployed).
   - **Compose Path**: `./docker-compose.dokploy.yml`.
4. **Environment** tab: paste `.env.dokploy.example` with the secrets filled in
   (generation commands are in the file). Leave `S3_ACCESS_KEY_ID` /
   `S3_SECRET_ACCESS_KEY` empty for now.
5. **Domains** tab → **Add Domain**:
   - Host: your domain (must equal `BASE_URL` without the scheme).
   - Service Name: `proxy`, Container Port: `80`, HTTPS on, certificate
     **Let's Encrypt**.
6. **Deploy**. The first build compiles both packages and takes several
   minutes.

Dokploy attaches Traefik through the external `dokploy-network`; only the
`proxy` service joins it. Nothing binds host ports, so it coexists with other
Dokploy apps.

## 2. One-time Garage bootstrap (attachments storage)

The `garage` image is distroless (no `sh`), so Dokploy's container terminal
cannot open it and `setup.sh` cannot run inside it. Run the bootstrap from the
**host** instead: Dokploy → **Settings → Server → Terminal** (or SSH in), then:

```bash
curl -fsSL https://raw.githubusercontent.com/themeanie3/bigcapital/develop/docker/garage/bootstrap-from-host.sh | bash
```

(or `bash docker/garage/bootstrap-from-host.sh` from a checkout). It finds the
running garage container, applies the single-node layout, creates the
`bigcapital` key and bucket, and prints `S3_ACCESS_KEY_ID` /
`S3_SECRET_ACCESS_KEY`. Put them in the Environment tab and redeploy.

Manual equivalent, one command at a time (`C` = garage container name from
`docker ps`):

```bash
docker exec $C /garage status
docker exec $C /garage layout assign $(docker exec $C /garage node id | awk 'NR==1{print $1}') -z dc1 -c 10G
docker exec $C /garage layout apply --version 1
docker exec $C /garage key create --name bigcapital      # prints Key ID + Secret key
docker exec $C /garage bucket create bigcapital
docker exec $C /garage bucket allow --read --write --owner --key bigcapital --bucket bigcapital
```

## 3. Migrations

`database_migration` runs `system:migrate:latest` and `tenants:migrate:latest`
against the freshly built server image on every deploy and then exits; it is
expected to show as "exited (0)". The `server` service uses the same image.

## 4. Auto-deploy on push

Compose service → **Deployments** → enable **Auto Deploy** (with the GitHub
provider) or copy the webhook URL into the fork's GitHub webhooks
(`Settings → Webhooks`, content type `application/json`, push events).

## Notes

- Sign-ups are open by default (`SIGNUP_DISABLED=false`). Create the first
  account, then set `SIGNUP_DISABLED=true` or restrict via
  `SIGNUP_ALLOWED_EMAILS` and redeploy.
- Data lives in named volumes `mysql`, `redis`, `garage`, `clickhouse`
  (prefixed by Dokploy with the compose project name). Back up `mysql` and
  `garage` at minimum; Dokploy's Backups tab can target the MariaDB container.
- Cloudflare: if the domain is orange-clouded, set SSL/TLS mode to **Full
  (strict)** and make sure WAF rules do not block `/api/*`.
