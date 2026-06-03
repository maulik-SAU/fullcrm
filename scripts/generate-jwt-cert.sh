#!/usr/bin/env bash
#
# Generates the RSA key pair used for the Salesforce JWT bearer flow.
#
#   server.key  -> PRIVATE key. Keep secret. Goes into the SF_JWT_KEY CI secret.
#                  NEVER commit this file (it is git-ignored).
#   server.crt  -> PUBLIC certificate. Upload this to the Connected App in
#                  Salesforce (Setup > App Manager > New Connected App > API).
#
# Usage:
#   ./scripts/generate-jwt-cert.sh
#
set -euo pipefail

DAYS="${1:-365}"

echo "Generating a ${DAYS}-day self-signed cert for the JWT bearer flow..."

openssl req -x509 -sha256 -nodes \
  -days "${DAYS}" \
  -newkey rsa:2048 \
  -keyout server.key \
  -out server.crt \
  -subj "/CN=fullcrm-jwt"

chmod 600 server.key

cat <<'EOF'

Done. Two files were created:

  server.key  -> private key  (CI secret SF_JWT_KEY; do NOT commit)
  server.crt  -> public cert  (upload to the Connected App)

Next steps are in docs/CONNECT_SANDBOX.md.
EOF
