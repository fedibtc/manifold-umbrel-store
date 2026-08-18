# Fedi Dev — Umbrel community app store (internal)

Internal-only Umbrel app store for testing Fleet Manager (FMan) on personal
Umbrel devices against the Manifold **staging** environment
(Mutinynet/Signet). Not for production use; this repo is private and the
image is distributed out-of-band (no public registry yet).

Current package: `0.1.1-master.f7b7500c` — built from manifold master,
fedimintd `0.11.1-fedi13`, operator dashboard embedded in the daemon.

## One-time device setup

You need a GitHub personal access token with read access to this repo
([create one here](https://github.com/settings/tokens); authorize it for the
`fedibtc` org if prompted).

1. **Run the device-local image registry.** There is no GHCR publication yet
   (needs a `write:packages` token), so the compose file pulls from a
   loopback registry on the device — umbreld force-pulls on install, so
   pre-loaded images alone are not enough, and Docker trusts `127.0.0.1`
   registries without TLS:

   ```sh
   ssh umbrel@umbrel.local docker run -d --restart unless-stopped \
     --name fedi-dev-registry -p 127.0.0.1:5000:5000 registry:2
   ```

2. **Stream the image in** from wherever it was built (`ms`:
   `nix build .#fleet-manager-oci-image`, then `docker load`). The Nix image
   tag is the Cargo workspace version (`0.1.0`); retag it to the package's
   provenance tag from `docker-compose.yml` when pushing:

   ```sh
   ssh ms "docker save fleet-manager:0.1.0 | gzip" | ssh umbrel@umbrel.local "docker load && \
     docker tag fleet-manager:0.1.0 127.0.0.1:5000/fleet-manager:0.1.1-master.f7b7500c && \
     docker push -q 127.0.0.1:5000/fleet-manager:0.1.1-master.f7b7500c"
   ```

3. **Add this store.** In umbrelOS: **App Store → ⋯ → Community App Stores**,
   paste (with your PAT embedded):

   ```
   https://<your-github-username>:<your-PAT>@github.com/fedibtc/fman-umbrel-store.git
   ```

4. **Install** *Fleet Manager (staging)* from the "Fedi Dev" store, open it,
   and **onboard from the dashboard** (`onboard new`). The dashboard is
   served during the onboarding phase behind Umbrel's authenticated proxy —
   no separate app login.

   Known quirk: the pre-onboarding screen may flash an `[object Object]`
   error (frontend rendering bug; the wizard still works — see the operator
   UI underwriting in manifold PR #330).

If an install fails instantly with a generic error, the registry from step 1
is missing or the image/tag in step 2 doesn't match `docker-compose.yml`.

## Make it discoverable (staging trust material)

A fresh FMan is invisible to FIs until it has a peer badge, an offer, and a
receivable setup-payment wallet. From the manifold repo:

1. Get the FMan's identity: dashboard, or
   `docker exec fedi-dev-fleet-manager_app_1 fleet-manager admin --data-dir /data onboarding`
   → note `service_nostr_pubkey`.
2. Issue a badge from the staging test issuer (level = the staging profile's
   required minimum, currently 9):

   ```sh
   cargo run -p devmon --bin manifold-test-issuer -- \
     --environment staging \
     --issuer-secret-keys <persistent-keyfile> \
     --authorization-request '{"subject_pubkey":"<service_nostr_pubkey>"}' \
     --publish-fman-authorization
   ```

3. Tell the daemon to look (authorization fetches are on-demand, not polled):
   `… admin --data-dir /data refresh-holder-authorizations`
4. Set an offer: `… admin --data-dir /data plans set --price-msats <msats>`
   (a nonzero price also requires the setup-payment wallet gate below).
5. Restart the app container once
   (`docker restart fedi-dev-fleet-manager_app_1`): the daemon auto-joins the
   staging setup-payment federation from the relay's kind-37707 policy, but
   the advertisement loop silently skips while that wallet gate is closed and
   nothing wakes it when the join lands (manifold #399). A restart after the
   join publishes immediately.
6. Verify: the staging relay should carry a kind-37701 advertisement from
   your `service_nostr_pubkey` with your plans, fedimintd version, and
   holder authorization.

Staging gotcha: the relay's kind-37707 setup-payment policy must parse under
the *current* master schema (`fman_version` is required again; rejections are
silent — manifold #396/#397). If `payment-federations list` stays empty with
no log lines, republish the policy with `nak` signed by staging test key 4.

## What the app runs

- `fleet-manager` (master build, fedimintd `0.11.1-fedi13`) — the FMan
  daemon, `--manifold-environment staging`, 1 seat, Bitcoin via the staging
  profile's default Esplora (no Umbrel Bitcoin Core dependency), no push
  gateway (callback-free). The operator dashboard is embedded in the binary
  and served on the admin HTTP listener behind Umbrel's authenticated proxy
  (trusted-proxy contract: the listener has no host port).
- Seat ports `30000-30003` are published on the device. Peers outside your
  LAN can only reach them if you forward those ports on your router.

## Releasing an update

1. Build the image from the manifold commit you're shipping
   (`nix build .#fleet-manager-oci-image` on `ms`) and stream it to each
   device under a new provenance tag (step 2 above), e.g.
   `0.1.2-master.<commit>`.
2. Bump `version` in `fedi-dev-fleet-manager/umbrel-app.yml` and the image
   tag in `docker-compose.yml` to the same provenance tag; commit and push
   here. Keep the version semver-sortable **above** the previous one
   (`0.1.2-…` after `0.1.1-…`; a `-suffix` sorts *below* its bare version).
3. Devices show a one-click **Update** in the Umbrel UI (store refresh can
   take a few minutes; "Update All" forces a refresh).
4. Data (`${APP_DATA_DIR}`) survives updates but **not** uninstall/reinstall.
   Note master and pre-master builds have incompatible SQLite migrations: a
   downgrade or a stale-branch image against a master-created `/data` will
   crash-loop with a migration error — uninstall/reinstall and redo the
   trust-material steps in that case.

When GHCR publishing lands, the compose file switches back to `ghcr.io/...`
refs and the local registry can be removed (`docker rm -f fedi-dev-registry`).
