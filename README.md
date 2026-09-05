*This project has been created as part of the 42 curriculum by yabarhda.*

# Inception

## Description

Inception is a system administration project whose goal is to build a small,
self-contained web infrastructure entirely with Docker, and to understand
*why* each piece of that infrastructure is put together the way it is,
rather than just copy-pasting a working `docker-compose.yml`.

The stack is made of three custom-built containers, each running a single
service, connected through a dedicated Docker network:

| Container   | Role                                             |
|-------------|---------------------------------------------------|
| `nginx`     | Sole entrypoint of the stack, terminates TLS (1.2/1.3 only) on port 443, proxies PHP requests to `wordpress` over FastCGI |
| `wordpress` | WordPress core + `php-fpm`, no bundled webserver   |
| `mariadb`   | The WordPress database                             |

Persistent data (the database, and the WordPress files/uploads) lives in two
Docker named volumes, bind-mounted on the host under `/home/yabarhda/data`,
so the site survives container rebuilds.

Every image is built from a Debian `bookworm-slim` base with our own
Dockerfile — no pre-built images are pulled from Docker Hub for the
services themselves.

## Instructions

### Prerequisites
- A Linux VM with Docker Engine and the Docker Compose plugin installed.
- Root/sudo access (to write to `/home/yabarhda/data` and to edit `/etc/hosts`).

### 1. Point the domain at your machine
Add this line to `/etc/hosts` on the VM (and on your host machine, if you're
testing from a browser outside the VM):

```
127.0.0.1   yabarhda.42.fr
```

### 2. Configure secrets
Edit the placeholder passwords in `secrets/` before building — they are
**not** meant to stay as-is:

```
secrets/db_password.txt        # WordPress DB user password
secrets/db_root_password.txt   # MariaDB root password
secrets/credentials.txt        # WP_ADMIN_PASSWORD / WP_USER_PASSWORD
```

These files are git-ignored on purpose (see `.gitignore`) and are mounted
into the containers as Docker secrets at `/run/secrets/<name>`.

### 3. Build and start everything

```bash
make            # creates /home/yabarhda/data/{mariadb,wordpress}, builds images, starts the stack
```

### 4. Visit the site

```
https://yabarhda.42.fr
```

Your browser will warn about the self-signed certificate the first time —
that's expected for a local project like this.

### Useful commands

```bash
make ps         # container status
make logs       # follow logs of all services
make stop       # stop containers without removing them
make start      # start them again
make down       # stop and remove containers
make clean      # down + prune dangling docker resources
make fclean     # clean + remove named volumes and host data
make re         # fclean + all
```

See `USER_DOC.md` and `DEV_DOC.md` for more detail.

## Resources

- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- [Docker secrets](https://docs.docker.com/engine/swarm/secrets/)
- [Dockerfile best practices](https://docs.docker.com/build/building/best-practices/)
- [WordPress CLI (wp-cli) handbook](https://make.wordpress.org/cli/handbook/)
- [NGINX FastCGI configuration](https://docs.nginx.com/nginx/admin-guide/web-server/app-gateway-uwsgi-django/)
- [MariaDB server documentation](https://mariadb.com/kb/en/documentation/)
- **AI usage**: an AI assistant (Claude) was used to scaffold the initial
  project layout (Makefile, `docker-compose.yml`, the three Dockerfiles,
  their entrypoint scripts, and this documentation set) from the subject
  PDF. Every generated script was read and adjusted line by line (PID 1
  handling in each entrypoint, php-fpm pool/socket configuration, the
  secrets-mounting scheme, and the bind-mount volume paths) rather than
  used as-is, and the resulting stack was reasoned through and is meant to
  be re-verified by running and inspecting it before defense.

## Project design choices

### Virtual Machine vs Docker
A VM virtualizes an entire machine, including its own kernel, which makes
it heavier to boot and run but gives very strong isolation. A Docker
container shares the host's kernel and only packages the application and
its dependencies, so it starts in a fraction of a second and uses far less
RAM/disk — at the cost of a thinner isolation boundary than a VM. This
project runs *inside* one VM and uses Docker *inside* that VM to get
per-service isolation without paying the VM cost three times over.

### Secrets vs Environment Variables
Values passed as plain environment variables (or baked into a
`docker-compose.yml`/`.env`) are visible to anyone who can run
`docker inspect` on the container, and they can leak into logs or crash
dumps. Docker secrets are instead mounted as files under `/run/secrets/`
inside the container, are only readable by processes in that container,
and are never written into the container's image layers or its
`docker inspect` output. In this project, the domain name and non-sensitive
config (database/user *names*, WordPress titles, etc.) go through `.env`,
while every password goes through `secrets/*.txt` and Docker secrets.

### Docker Network vs Host Network
`network: host` makes a container share the host's network namespace
directly — every port the process binds is exposed on the host with no
isolation, and containers can't be given their own private IP or DNS name.
A user-defined Docker network (as used here, `inception`) gives each
container its own network namespace and a DNS-resolvable name (e.g.
`wordpress`, `mariadb`), lets us expose only the ports we choose (only
`nginx:443` is published to the host), and keeps MariaDB and php-fpm
reachable only from other containers on that same network — never directly
from the internet.

### Docker Volumes vs Bind Mounts
A bind mount ties a container path directly to an arbitrary path on the
host filesystem, with permissions and existence entirely managed by the
host — Docker doesn't track or manage that data at all. A named volume is
managed by Docker itself: Docker controls its lifecycle, and it can be
backed by different drivers/backends without changing how the container
uses it. The subject requires named volumes for the database and
WordPress files, so this project uses named volumes configured with the
`local` driver's `bind` option to point at `/home/yabarhda/data` — the
best of both: Docker-managed volumes whose data is still inspectable at a
known host path.
