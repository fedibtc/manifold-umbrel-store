# Fedi Dev — Umbrel community app store (internal)

Internal-only Umbrel app store for testing Fleet Manager (FMan) on personal
Umbrel devices against the Manifold **staging** environment
(Mutinynet/Signet). Not for production use; the images and this repo are
private.

## One-time device setup

You need a GitHub personal access token (classic) with `repo` and
`read:packages` scopes ([create one here](https://github.com/settings/tokens)).
If prompted, authorize it for the `fedibtc` org (SSO).

1. **Let the device pull the private images.** SSH in and log Docker into
   GHCR (password = your PAT):

   ```sh
   ssh umbrel@umbrel.local
   docker login ghcr.io -u <your-github-username>
   ```

2. **Add this store.** In umbrelOS: **App Store → ⋯ → Community App Stores**,
   paste (with your PAT embedded):

   ```
   https://<your-github-username>:<your-PAT>@github.com/fedibtc/fman-umbrel-store.git
   ```

3. **Install.** Open the "Fedi Dev" store that appeared and click **Install**
   on *Fleet Manager (staging)*. The dashboard opens via Umbrel's
   authenticated proxy — no separate app login.

If an install fails with a generic error, it is almost always the `docker
login` from step 1 missing or an expired token.

## What the app runs

- `ghcr.io/fedibtc/fleet-manager` — the FMan daemon, `--manifold-environment
  staging`, 1 seat, Bitcoin via the staging profile's default Esplora
  (no Umbrel Bitcoin Core dependency), no push gateway (callback-free).
- `ghcr.io/fedibtc/manifold-operator-ui-fman` — the operator dashboard
  (Caddy), sharing the daemon's network namespace; admin API stays
  loopback-only per the trusted-proxy contract.
- Seat ports `30000-30003` are published on the device. Peers outside your
  LAN can only reach them if you forward those ports on your router.

## Releasing an update

1. Build and push new images (from the manifold repo, via `ms`):
   `nix build .#fleet-manager-oci-image` / `.#operator-ui-fman-oci-image`,
   `docker load`, `docker push`.
2. Bump `version` in `fedi-dev-fleet-manager/umbrel-app.yml` and the image
   tags in `docker-compose.yml`; commit and push here.
3. Devices show a one-click **Update** in the Umbrel UI (store refresh can
   take a few minutes; "Update All" forces a refresh).
