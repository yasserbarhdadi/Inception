# Developer Documentation

## Project layout

```
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── .gitignore
├── secrets/
│   ├── db_password.txt
│   ├── db_root_password.txt
│   └── credentials.txt
└── srcs/
    ├── .env
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/my.cnf
        │   └── tools/init_db.sh
        ├── wordpress/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/www.conf
        │   └── tools/setup_wp.sh
        └── nginx/
            ├── Dockerfile
            ├── .dockerignore
            ├── conf/nginx.conf.template
            └── tools/entrypoint.sh
```

## How each container is built and started

### mariadb
- Base: `debian:bookworm-slim` + `mariadb-server`/`mariadb-client`.
- `conf/my.cnf` forces `bind-address = 0.0.0.0` so the container can be
  reached from other containers on the `inception` network (default is
  `127.0.0.1`, which would make it unreachable from `wordpress`).
- `tools/init_db.sh` is the container's `ENTRYPOINT`:
  1. On first boot only (`/var/lib/mysql/mysql` doesn't exist yet), it runs
     `mariadb-install-db`, starts a temporary `mariadbd` bound only to a
     local socket, creates the WordPress database/user from the values in
     `MYSQL_DATABASE` / `MYSQL_USER` / the `db_password` secret, sets the
     root password from the `db_root_password` secret, then shuts that
     temporary instance down.
  2. It then `exec`s `mariadbd` in the foreground — this makes `mariadbd`
     PID 1 in the container, so `docker stop` delivers `SIGTERM` straight
     to it and Docker can correctly track the process's exit code.
  3. On subsequent boots, the data directory already exists, so step 1 is
     skipped and we go straight to step 2 — the volume-mounted data
     persists across `make down` / `make up`.

### wordpress
- Base: `debian:bookworm-slim` + `php-fpm` and the PHP extensions
  WordPress needs (`php-mysql`, `php-curl`, `php-gd`, `php-mbstring`,
  `php-xml`, `php-zip`, `php-intl`).
- No web server is installed in this image — `nginx` is a separate
  container and reaches php-fpm over FastCGI/TCP.
- `conf/www.conf` overrides the default php-fpm pool to `listen = 9000`
  (TCP, all interfaces) instead of the default Unix socket, since the
  `nginx` container needs to reach it over the Docker network.
- `wp-cli` is downloaded once at build time and used to script the whole
  WordPress setup non-interactively (`wp core download`, `wp config
  create`, `wp core install`, `wp user create`) instead of relying on the
  browser install wizard.
- `tools/setup_wp.sh` (the `ENTRYPOINT`):
  1. Polls `mariadb-admin ping` until MariaDB is reachable and accepting
     the WordPress DB user's credentials (removes the race condition
     between the two containers starting up).
  2. On first boot (`wp-config.php` doesn't exist yet), runs the `wp-cli`
     install sequence above, reading the admin/user passwords out of the
     `credentials` secret.
  3. `exec`s `php-fpm8.2 -F` (foreground mode) as PID 1.

### nginx
- Base: `debian:bookworm-slim` + `nginx` + `openssl` (to self-sign a
  certificate) + `gettext-base` (for `envsubst`).
- The default `sites-enabled/default` is removed at build time so nothing
  but our own server block is ever served.
- `conf/nginx.conf.template` is a full `nginx.conf` with `${DOMAIN_NAME}`
  as a placeholder in `server_name`.
- `tools/entrypoint.sh` (the `ENTRYPOINT`):
  1. Generates a self-signed certificate for `${DOMAIN_NAME}` on first
     boot if one doesn't already exist.
  2. Runs `envsubst` on the template to produce the real
     `/etc/nginx/nginx.conf`, injecting the domain name from the
     container's environment.
  3. `exec`s `nginx -g "daemon off;"` as PID 1.
- Only `location ~ \.php$` is forwarded to `wordpress:9000`; everything
  else is served from the shared `wordpress_data` volume (mounted
  read/write here too so `nginx` can see the WordPress static files).

## Networking

All three containers share one user-defined bridge network, `inception`,
declared in `docker-compose.yml`. Docker's embedded DNS lets each
container resolve the others by service name (`mariadb`, `wordpress`),
which is why `MYSQL_HOST=mariadb` and `fastcgi_pass wordpress:9000;` work
without hardcoding IPs. Only `nginx` publishes a port to the host
(`443:443`); `mariadb` and `wordpress` use `expose` only, so they are
reachable from other containers on `inception` but not from outside
Docker at all.

## Data persistence

`docker-compose.yml` declares two named volumes, `mariadb_data` and
`wordpress_data`, both using the `local` driver with `type: none,
o: bind, device: ...` pointing at `${DATA_PATH}/mariadb` and
`${DATA_PATH}/wordpress` (i.e. `/home/yabarhda/data/...`). This satisfies
the subject's "named volumes, data must be on the host under
`/home/login/data`" requirement while still letting Docker manage the
volume's lifecycle normally (`docker volume ls`, `docker volume rm`,
etc.).

## Secrets handling

`docker-compose.yml`'s top-level `secrets:` block maps three logical
secret names (`db_password`, `db_root_password`, `credentials`) to the
three files under `secrets/`. Compose mounts each one, read-only, at
`/run/secrets/<name>` inside any service that lists it under its own
`secrets:` key — that's why `mariadb` only gets `db_password` and
`db_root_password`, while `wordpress` gets `db_password` and
`credentials` (it never sees the DB root password). Nothing in
`srcs/.env` or in `docker-compose.yml`'s plain `environment:` blocks is
ever a password.

## Restart behavior

Every service is declared with `restart: unless-stopped`, so Docker
restarts a container automatically if its process crashes, without
retrying forever if you deliberately `make stop` it — satisfying the
subject's "your containers must restart in case of a crash" requirement
without adding any extra process supervisor inside the containers
themselves.

## Rebuilding after a change

- Changed a `Dockerfile`, a `conf/` file, or a `tools/*.sh` script?
  `make re` (rebuilds images, wipes and recreates the data volumes).
- Changed only `srcs/.env` values that aren't used at first-boot
  initialization (e.g. `DOMAIN_NAME`)? `make down && make up` is usually
  enough, since those are read fresh by the `nginx`/`wordpress`
  entrypoints on every start — but anything baked into MariaDB/WordPress
  at install time (DB name, usernames) needs a full `make re` to take
  effect on a fresh install.
