# Fedi Dev — Umbrel community app store

Umbrel app store for testing Fleet Manager (FMan) and FLIP on personal Umbrel
devices against the Manifold **staging** environment (Mutinynet/Signet). Not
for production use: no warranty, staging trust material only, and data can be
invalidated by any master build (see the migration note at the bottom).

The images are the public `ghcr.io/fedibtc/manifold-*` packages, published by
manifold CI on every master merge.

Current packages: FMan `0.1.7-master.d090989b`, FLIP `0.1.4-master.d090989b` —
built from manifold master, fedimintd `0.11.1-fedi15`, operator dashboard
embedded in the daemon.

## One-time device setup

1. **Add this store.** In umbrelOS: **App Store → ⋯ → Community App Stores**,
   paste:

   ```
   https://github.com/fedibtc/manifold-umbrel-store.git
   ```

2. **Install** *Fleet Manager (staging)* from the "Fedi Dev" store, open it,
   and **onboard from the dashboard** (`onboard new`). The dashboard is
   served during the onboarding phase behind Umbrel's authenticated proxy —
   no separate app login.

   Known quirk: the pre-onboarding screen may flash an `[object Object]`
   error (frontend rendering bug; the wizard still works — see the operator
   UI underwriting in manifold PR #330).

Devices that used the old private setup (the `fedi-dev-registry` pull-through
proxy container and the token-embedded store URL): remove the proxy container
(`docker rm -f fedi-dev-registry`), re-add the store with the plain URL above,
and drop the old token — images pull anonymously now.

## Make it discoverable (staging trust material)

A fresh FMan is invisible to FIs until it has a peer badge, an offer, and a
receivable setup-payment wallet. From the manifold repo:

Everything except badge issuance is done in the operator dashboard; badge
issuance needs a dev (until the planned staging badge bot lands).

1. Note your FMan's `service_nostr_pubkey` from the dashboard and send it to
   a dev on the team.
2. **Dev**: issue a level-9 badge from manifold master. The issuer
   authorities are pinned in the environment profile and the tool signs with
   the committed staging authority — there is no keyfile to pass, and old
   checkouts with ad-hoc keyfiles must not be used:

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

- `fleet-manager` (master build, fedimintd `0.11.1-fedi15`) — the FMan
  daemon, `--manifold-environment staging`, Bitcoin via the staging profile's
  default Esplora (no Umbrel Bitcoin Core dependency), no push gateway
  (callback-free). Seat capacity is self-sized from available RAM (1 seat per
  1.5 GiB, capped at 8 — REQ-seat-capacity-default in manifold); the operator
  can override it in the daemon config. The operator dashboard is embedded in
  the binary and served on the admin HTTP listener behind Umbrel's
  authenticated proxy (trusted-proxy contract: the listener has no host port).
- Seat iroh UDP ports `30000-30031` are published (UDP only, matching the
  official upstream `fedimintd` Umbrel app). Since master ac735450 the
  daemon binds seat iroh sockets on all interfaces, so guardians hole-punch
  direct peer paths; relays remain the fallback, so no router port
  forwarding is required (forwarding the UDP range improves direct-path
  odds). The range covers the first 8 lifetime seat ordinals; later
  ordinals fall back to relays until the range is extended.

## FLIP (`fedi-dev-flip`)

Same store as above. Install *Liquidity Provider (staging)*; the dashboard's
access token is the app password Umbrel shows on open (don't rotate it from
the dashboard — the modal keeps showing the original). The bundled gatewayd
sidecar is LDK-internal on Mutinynet/Signet: no Bitcoin or Lightning app
needed.

Setup-wizard values to type (the wizard's "Connect to gateway" probe fills
the gateway id itself):

| Field | Value |
| --- | --- |
| Gateway admin URL | `http://fedi-dev-flip_gatewayd_1:8178` |
| Gateway admin credential | the app password (same token) |
| Chain observer | Esplora, `https://mutinynet.com/api/` |
| Network | `signet` |

Funding, trust material, and the full walkthrough: internal runbook (Phase 2).

## Releasing an update

Manifold CI publishes `ghcr.io/fedibtc/manifold-fman:<git-sha>` (multi-arch,
public) on every master merge — no manual image building or streaming.

1. Pick the master commit to ship (its publish run must be green).
2. Point the `image:` tag in `fedi-dev-fleet-manager/docker-compose.yml` at
   that `<git-sha>` and bump `version` in `umbrel-app.yml`
   (`0.1.N-master.<shortsha>`); commit and push here. Keep the version
   semver-sortable **above** the previous one (`0.1.2-…` after `0.1.1-…`; a
   `-suffix` sorts *below* its bare version).
3. Devices show a one-click **Update** in the Umbrel UI (store refresh can
   take a few minutes; "Update All" forces a refresh).
4. Data (`${APP_DATA_DIR}`) survives updates but **not** uninstall/reinstall.
   Note that builds with different applied SQLite migrations are
   incompatible: an image whose migrations differ from the ones already in
   `/data` will crash-loop with a migration error — uninstall/reinstall and
   redo the trust-material steps in that case. The `d090989b` updates are this case
   for BOTH apps: FMan's and FLIP's migration files each changed since the
   previous pins, so existing installs of either app need
   uninstall/reinstall.
