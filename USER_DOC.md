# User Documentation

## Services provided by the stack

- **Website**: a WordPress site, reachable at `https://yabarhda.42.fr`.
- **Administration panel**: the WordPress admin dashboard, at
  `https://yabarhda.42.fr/wp-admin`.
- **Database**: MariaDB, holding all WordPress content — not directly
  exposed outside the Docker network, so it's only reachable by the
  WordPress container.
- **TLS termination**: every request goes through the `nginx` container on
  port 443 using TLSv1.2 or TLSv1.3; there is no plain-HTTP entrypoint.

## Starting and stopping the project

From the root of the repository (where the `Makefile` is):

```bash
make          # first run: creates data folders, builds images, starts everything
make stop     # pause the containers, keep them and their data
make start    # resume stopped containers
make down     # stop and remove the containers (data is preserved in the volumes)
make re       # full reset: wipe data + volumes, rebuild, and start fresh
```

Check that everything is up with:

```bash
make ps
```

You should see `mariadb`, `wordpress`, and `nginx` all `Up`.

## Accessing the website and the admin panel

1. Make sure `yabarhda.42.fr` resolves to the machine running Docker
   (an `/etc/hosts` entry pointing it at `127.0.0.1`, or your local IP, is
   enough for local testing).
2. Open `https://yabarhda.42.fr` in a browser.
   - The browser will flag the certificate as untrusted (it's
     self-signed) — this is expected; accept the risk to continue.
3. To manage the site, go to `https://yabarhda.42.fr/wp-admin` and log in
   with the administrator account described below.

## Locating and managing credentials

All passwords live under the `secrets/` folder at the root of the
repository, and are never stored in `.env` or in the Docker images:

| File                          | Contains                                   |
|--------------------------------|---------------------------------------------|
| `secrets/db_password.txt`      | Password of the WordPress database user     |
| `secrets/db_root_password.txt` | MariaDB root password                       |
| `secrets/credentials.txt`      | WordPress admin & second user's passwords   |

Usernames and non-sensitive settings (database name, DB username,
WordPress admin/user login names and e-mails, the site title, the domain)
are in `srcs/.env`.

To change a password: edit the relevant file under `secrets/`, then
`make re` so the containers pick it up (WordPress and MariaDB only apply
these values on their *first* initialization, so changing a password
after the database already exists requires updating it from within
WordPress/MariaDB directly, or wiping the data with `make fclean` first).

## Checking that services are running correctly

```bash
make ps                 # all three containers should show "Up"
make logs                # tail logs from every container
docker logs mariadb       # MariaDB-specific logs
docker logs wordpress     # WordPress / php-fpm logs
docker logs nginx         # NGINX logs
```

If the site doesn't load:
- `make ps` — is every container `Up` and not restarting in a loop?
- `docker logs wordpress` — did the WordPress install script fail while
  waiting for the database?
- `docker logs nginx` — did the certificate generation or config
  substitution fail?
