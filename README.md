# Fedi Dev — Umbrel community app store (internal)

Internal-only Umbrel app store for testing Fleet Manager (FMan) on personal
Umbrel devices against the Manifold **staging** environment
(Mutinynet/Signet). Not for production use; this repo is private and the
images pull from private GHCR (published by manifold CI on every master merge).

Current package: `0.1.2-master.0bfc7a32` — built from manifold master,
fedimintd `0.11.1-fedi13`, operator dashboard embedded in the daemon.

## One-time device setup

You need two GitHub tokens (or one token covering both), each SSO-authorized
for `fedibtc` if prompted:

- a token with **read access to this repo** (fine-grained works) for the
  store URL, and
- a **classic** PAT with **`read:packages`** (fine-grained does not work with
  GHCR) for the image pull — until the shared machine-user token lands in the
  team password manager, mint your own.

1. **Log the device's Docker into GHCR** (one-time; images are published to
   private GHCR by manifold CI on every master merge):

   ```sh
   ssh umbrel@umbrel.local
   docker login ghcr.io -u <your-github-username>
   ```

   Paste the classic `read:packages` PAT as the password.

2. **Add this store.** In umbrelOS: **App Store → ⋯ → Community App Stores**,
   paste (with your PAT embedded):

   ```
   https://<your-github-username>:<your-PAT>@github.com/fedibtc/fman-umbrel-store.git
   ```

3. **Install** *Fleet Manager (staging)* from the "Fedi Dev" store, open it,
   and **onboard from the dashboard** (`onboard new`). The dashboard is
   served during the onboarding phase behind Umbrel's authenticated proxy —
   no separate app login.

   Known quirk: the pre-onboarding screen may flash an `[object Object]`
   error (frontend rendering bug; the wizard still works — see the operator
   UI underwriting in manifold PR #330).

If an install or update fails instantly with a generic error, it is almost
always the GHCR `docker login` from step 1 missing or an expired token.
Devices set up before the GHCR flip may still run the old loopback registry;
it is no longer used and can be removed
(`docker rm -f fedi-dev-registry`).

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

Manifold CI publishes `ghcr.io/fedibtc/manifold-fman:<git-sha>` (multi-arch,
private) on every master merge — no manual image building or streaming.

1. Pick the master commit to ship (its publish run must be green).
2. Point the `image:` tag in `fedi-dev-fleet-manager/docker-compose.yml` at
   that `<git-sha>` and bump `version` in `umbrel-app.yml`
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
