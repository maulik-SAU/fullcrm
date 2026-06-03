# Connecting to a Salesforce Sandbox

There are two supported ways to connect this project to your sandbox.
Sandboxes **always** authenticate against `https://test.salesforce.com`.

---

## 1. Local / interactive (web login)

Best for day-to-day development from your own machine.

```bash
sf org login web \
  --alias fullcrm \
  --instance-url https://test.salesforce.com \
  --set-default
```

- A browser opens; log in with your **sandbox** username
  (typically `you@company.com.<sandboxname>`) and approve access.
- Credentials are stored locally under `.sfdx`/`.sf` (git-ignored).

Verify and deploy:

```bash
sf org display --target-org fullcrm
sf project deploy start --target-org fullcrm
sf apex run test --target-org fullcrm --code-coverage --result-format human
```

---

## 2. Headless / CI (JWT bearer flow)

Best for CI (GitHub Actions) where there is no browser. Used by
`.github/workflows/deploy-sandbox.yml`.

### Step 1 — Generate a key pair

```bash
./scripts/generate-jwt-cert.sh
```

Produces:
- `server.key` — private key (kept secret, never committed)
- `server.crt` — public certificate (uploaded to Salesforce)

### Step 2 — Create a Connected App in the sandbox

In your sandbox: **Setup → App Manager → New Connected App**.

1. Enable **OAuth Settings**.
2. **Callback URL:** `http://localhost:1717/OauthRedirect` (unused by JWT, but required).
3. **Use digital signatures:** upload `server.crt`.
4. **OAuth Scopes:** add `Manage user data via APIs (api)` and
   `Perform requests at any time (refresh_token, offline_access)`.
5. Save. Copy the **Consumer Key**.

### Step 3 — Pre-authorize the user

Connected App → **Manage → Edit Policies** → set
**Permitted Users = "Admin approved users are pre-authorized"**, then assign
the running user's profile or permission set to the app. This lets the JWT
flow succeed without interactive consent.

### Step 4 — Add the GitHub repository secrets

**Settings → Secrets and variables → Actions → New repository secret:**

| Secret name       | Value                                            |
|-------------------|--------------------------------------------------|
| `SF_CONSUMER_KEY` | Connected App Consumer Key (from Step 2)         |
| `SF_USERNAME`     | Sandbox username, e.g. `you@company.com.sandbox` |
| `SF_JWT_KEY`      | Full contents of `server.key`                    |

### Step 5 — Test the connection locally (optional)

```bash
sf org login jwt \
  --username "you@company.com.sandbox" \
  --jwt-key-file server.key \
  --client-id "<consumer-key>" \
  --instance-url https://test.salesforce.com \
  --alias fullcrm
```

Once the secrets are set, the `Deploy to Salesforce Sandbox` workflow will
authenticate, validate, run tests, and deploy automatically.

---

### Security reminders

- `server.key`, `*.crt`, and auth files are git-ignored — never commit them.
- Rotate the certificate periodically (`generate-jwt-cert.sh` accepts a days arg).
- The CI workflow writes `server.key` from a secret at runtime and deletes it
  in an `always()` cleanup step.
