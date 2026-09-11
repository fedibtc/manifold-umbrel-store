# Fedi Dev — Umbrel community app store

Umbrel app store for Fleet Manager (FMan) and staging FLIP. The apps marked
**staging** use Mutinynet/Signet, staging trust material, and disposable data
that any master build may invalidate (see the migration note at the bottom).

The images are the public `ghcr.io/fedibtc/manifold-*` packages, published by
manifold CI on every master merge.

## Production Fleet Manager

**Fleet Manager** (`fedi-dev-fleet-manager-production`) requires the local
Bitcoin Core app on mainnet and keeps its own data, dashboard port (8482), and
guardian UDP ports (31000–31031). **Fleet Manager (staging)** remains a separate
app. Both use the same layout and manual update process: `docker-compose.yml`
pins the image commit and `umbrel-app.yml` sets the app version.

The initial production app version is `0.1.0`, pinned to Manifold commit
`510747ab84234d130d1cb0bad7476d2f4206054c`, published for amd64 and arm64.

Production updates must preserve data: never uninstall or reset to update.
Use production issuer authorization; the staging badge steps below do not
apply. Telemetry registers using the signed production setup-payment policy;
push notifications are deferred. See Manifold's
[release and data policy](https://github.com/fedibtc/manifold/blob/master/packages/fleet-manager/production-releases.md).

To release a production update:

1. Choose a successful amd64 + arm64 Manifold image publish and put its full
   commit in `fedi-dev-fleet-manager-production/docker-compose.yml`.
2. Increase the version in that app's `umbrel-app.yml` and record the image
   commit and changes in its release notes.
3. Verify installation and data-preserving update on Umbrel, then publish the
   reviewed commit. Devices receive the normal one-click Update.

## Staging device setup

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

- `fleet-manager` (master build, fedimintd `0.11.2-fedi4`) — the FMan
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

## Releasing a staging update

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
   redo the trust-material steps in that case. The `1bd22f38` update is not
   this case for FMan — its migration files are unchanged since the
   `af81a01a` pin, so existing FMan installs keep their data. FLIP's
   persisted allocation record dropped two gateway-observation fields in the
   same range; unknown fields deserialize away, but uninstall/reinstall a
   FLIP install that misbehaves after the update rather than debugging it.
