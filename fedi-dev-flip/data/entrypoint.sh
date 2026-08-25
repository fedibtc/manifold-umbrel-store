#!/bin/sh
# gatewayd takes a bcrypt hash; Umbrel supplies a plain app password, so hash
# it here (pattern from the official umbrel-apps fedimint-gateway app, minus
# its `$`-doubling sed: that only works by accident of the current bcrypt
# crate's lenient parsing and breaks on newer versions).
export FM_GATEWAY_BCRYPT_PASSWORD_HASH=$(gateway-cli create-password-hash "$APP_PASSWORD" \
  | sed 's/^"//; s/"$//'
)

# LDK-internal Lightning on Mutinynet/Signet: self-contained, no bitcoind or
# LND. `--api-addr` is what FLIP dials on the app-private compose network;
# it is announced to federations but unreachable off-device — the published
# Iroh listener (host 28177/udp) is the reachable path, acceptable for
# staging (same tradeoff as manifold's staging-gatewayd recipe).
exec gatewayd \
  --data-dir /data/gateway \
  --listen 0.0.0.0:8178 \
  --api-addr http://fedi-dev-flip_gatewayd_1:8178 \
  --network signet \
  --esplora-url https://mutinynet.com/api/ \
  --num-route-hints 0 \
  ldk \
  --ldk-lightning-port 9735 \
  --ldk-alias fedi-dev-flip-gateway
