# Connecting to a Salesforce Sandbox

You can connect this project without ever touching the command line. The
sandbox environments for this project are:

| Env | Sandbox | My Domain URL (use for login)                              |
|-----|---------|------------------------------------------------------------|
| SIT | sadev   | `https://serversaustralia--sadev.sandbox.my.salesforce.com` |
| UAT | fcsb    | `https://serversaustralia--fcsb.sandbox.my.salesforce.com`  |

> **Multiple orgs coexist.** Authorizing an org here does **not** disconnect
> any other project's org. Only the *default* org could clash — and the options
> below set the default **per workspace**, so your other project is unaffected.

---

## 0. No terminal — authorize from VS Code (recommended)

Use this if you don't want to run CLI commands (e.g. another project is already
connected in your terminal). Requires the
[Salesforce Extension Pack](https://marketplace.visualstudio.com/items?itemName=salesforce.salesforcedx-vscode).

1. Open the **`fullcrm`** folder in VS Code.
2. Press `Cmd/Ctrl + Shift + P` to open the Command Palette.
3. Run **`SFDX: Authorize an Org`**.
4. Login URL — choose one:
   - **Sandbox** (uses `https://test.salesforce.com`), **or**
   - **Custom** and paste the My Domain URL from the table above
     (e.g. `https://serversaustralia--sadev.sandbox.my.salesforce.com` for SIT).
5. Enter an alias when prompted — use **`sit`** or **`uat`**.
6. A browser opens → log in with your sandbox user → **Allow**.

Because you authorize from inside this workspace, the org becomes the default
**for this project only**. Your other project's default org is never changed.

Deploy / retrieve / run tests from the Command Palette or by right-clicking
files in the **Org Browser** — no terminal needed:
- `SFDX: Deploy This Source to Org`
- `SFDX: Retrieve Source from Org`
- `SFDX: Run Apex Tests`

---

## 1. Local / interactive (web login via CLI)

Best for day-to-day development from your own machine. To **avoid changing your
other project's default org, omit `--set-default`** — the org is still
authorized and usable via its alias:

```bash
# SIT — note: NO --set-default, so your global default is untouched
sf org login web \
  --alias sit \
  --instance-url https://serversaustralia--sadev.sandbox.my.salesforce.com

# UAT
sf org login web \
  --alias uat \
  --instance-url https://serversaustralia--fcsb.sandbox.my.salesforce.com
```

Then make it the default for **this project only** (local config, not global):

```bash
sf config set target-org sit          # writes to ./.sf/config.json (this folder)
```

Older example (sets a machine-wide default — avoid if another project relies on it):

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
