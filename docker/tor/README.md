# tor

Minimal Tor image (Alpine + `tor` package) for private mode
(`docker-compose.private.yml`). Unlike `docker/bitcoind`, this image is not
pushed to a registry: compose builds it locally on the Pi from this directory.

## What the entrypoint does

The container runs as the unprivileged `tor` user from the start (`USER tor`),
with all capabilities dropped and a read-only root filesystem.
`/var/lib/tor` is created in the image owned by `tor` (mode 700), so a fresh
`tor_data` volume inherits that ownership.

On every start `entrypoint.sh`:

1. Fails if `TOR_CONTROL_PASSWORD` is not set.
2. Fails if `/var/lib/tor` is not owned by `tor` (Tor refuses to start
   otherwise), and sets it to mode 700.
3. Hashes `TOR_CONTROL_PASSWORD` (fails if hashing fails) and writes
   `/var/lib/tor/torrc` (mode 600) with:
   - SOCKS on `127.0.0.1:9050`
   - control port on `127.0.0.1:9051` (password-protected)
   - logs to stdout
4. Starts tor.

The container shares bitcoind's network namespace
(`network_mode: "service:bitcoin"`), so both ports are reachable by bitcoind
only, not by other containers. The `tor_data` volume keeps the onion address
stable across restarts.

## Build / update

```sh
docker compose -f docker-compose.yml -f docker-compose.private.yml up -d --build tor
```

Rebuild regularly to pick up Alpine and Tor security fixes
(`--pull` also refreshes the `alpine:3` base image):

```sh
docker compose -f docker-compose.yml -f docker-compose.private.yml build --pull tor
```

## Upgrading from the root-based image

Volumes created by the old image were already chowned to `tor` by its
entrypoint, so they normally work as-is. If the container exits with
`/var/lib/tor is not owned by tor`, fix the volume once:

```sh
docker run --rm -u root -v bitcoinnode_tor_data:/var/lib/tor bitcoinnode-tor chown -R tor:tor /var/lib/tor
```

(Check the actual volume/image names with `docker volume ls` / `docker images`.)
