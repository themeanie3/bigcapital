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

After the first successful deploy, open the `garage` container terminal in
Dokploy (or `docker exec -it <garage container> bash`) and run:

```bash
bash /garage-setup/setup.sh
```

It prints an access key id and secret. Put them into the Environment tab as
`S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` and redeploy.

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
