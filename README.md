# Fedi Dev — Umbrel community app store (internal)

Internal-only Umbrel app store for testing Fleet Manager (FMan) on personal
Umbrel devices against the Manifold **staging** environment
(Mutinynet/Signet). Not for production use; this repo is private and the
images pull from private GHCR (published by manifold CI on every master merge).

Current package: `0.1.2-master.0bfc7a32` — built from manifold master,
fedimintd `0.11.1-fedi13`, operator dashboard embedded in the daemon.

## One-time device setup

You need the shared machine-account token from the team Slack pin /
password manager (one classic PAT covering the store repo and the GHCR
packages).

umbrelOS cannot pull private registry images itself (its app engine does
unauthenticated pulls only — no `docker login` helps), so each device runs a
loopback **pull-through proxy** that holds the credential and caches images
from GHCR; the app pulls anonymously from the proxy.

1. **Start the registry proxy** (one-time; paste the shared token in place of
   `<PAT>`):

   ```sh
   ssh umbrel@umbrel.local docker run -d --restart always \
     --name fedi-dev-registry -p 127.0.0.1:5000:5000 \
     -e REGISTRY_PROXY_REMOTEURL=https://ghcr.io \
     -e REGISTRY_PROXY_USERNAME=x \
     -e REGISTRY_PROXY_PASSWORD=<PAT> \
     registry:2
   ```

2. **Add this store.** In umbrelOS: **App Store → ⋯ → Community App Stores**,
   paste (with the same shared token embedded):

   ```
   https://x:<PAT>@github.com/fedibtc/fman-umbrel-store.git
   ```

3. **Install** *Fleet Manager (staging)* from the "Fedi Dev" store, open it,
   and **onboard from the dashboard** (`onboard new`). The dashboard is
   served during the onboarding phase behind Umbrel's authenticated proxy —
   no separate app login.

   Known quirk: the pre-onboarding screen may flash an `[object Object]`
   error (frontend rendering bug; the wizard still works — see the operator
   UI underwriting in manifold PR #330).

If an install or update fails instantly with a generic error, it is almost
always the proxy from step 1 missing (`docker ps | grep fedi-dev-registry`)
or its baked-in token expired/rotated (recreate the container with the
current one).

## Make it discoverable (staging trust material)

A fresh FMan is invisible to FIs until it has a peer badge, an offer, and a
receivable setup-payment wallet. From the manifold repo:

Everything except badge issuance is done in the operator dashboard; badge
issuance needs a dev (until the planned staging badge bot lands).

1. Note your FMan's `service_nostr_pubkey` from the dashboard and send it to
   a dev on the team.
2. **Dev**: issue a level-9 badge. With PR #405 (issuer authorities pinned in
   the environment profile) the tool signs with the committed staging
   authority — never pass an ad-hoc keyfile, that's how the staging authority
   got rotated on 2026-08-18:

   ```sh
   cargo run -p devmon --bin manifold-test-issuer -- \
     --environment staging \
     --authorization-request '{"subject_pubkey":"<service_nostr_pubkey>"}' \
     --publish-fman-authorization
   ```

3. Back in the dashboard: open the enrollment/authorization screen (opening
   it triggers the on-demand fetch — there is no background poll) and confirm
   the badge shows up.
4. Set your offer price in the dashboard's plans form (a nonzero price also
   requires the setup-payment wallet gate below).
5. Restart the app from the Umbrel UI (app → ⋯ → Restart): the daemon
   auto-joins the staging setup-payment federation from the relay's
   kind-37707 policy, but the advertisement loop silently skips while that
   wallet gate is closed and nothing wakes it when the join lands (manifold
   #399). A restart after the join publishes immediately.
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

Manifold CI publishes `ghcr.io/fedibtc/manifold-fman:<git-sha>` (multi-arch,
private) on every master merge — no manual image building or streaming.

1. Pick the master commit to ship (its publish run must be green).
2. Point the `image:` tag in `fedi-dev-fleet-manager/docker-compose.yml` at
   that `<git-sha>` (keeping the `127.0.0.1:5000/fedibtc/` proxy prefix) and bump `version` in `umbrel-app.yml`
   (`0.1.N-master.<shortsha>`); commit and push here. Keep the version
   semver-sortable **above** the previous one (`0.1.2-…` after `0.1.1-…`; a
   `-suffix` sorts *below* its bare version).
3. Devices show a one-click **Update** in the Umbrel UI (store refresh can
   take a few minutes; "Update All" forces a refresh).
4. Data (`${APP_DATA_DIR}`) survives updates but **not** uninstall/reinstall.
   Note master and pre-master builds have incompatible SQLite migrations: a
   downgrade or a stale-branch image against a master-created `/data` will
   crash-loop with a migration error — uninstall/reinstall and redo the
   trust-material steps in that case.
