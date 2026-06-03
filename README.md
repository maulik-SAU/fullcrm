# fullcrm

A Salesforce DX (SFDX) project. This repo holds the Apex and metadata source
for the **fullcrm** package and the configuration needed to connect and deploy
to a Salesforce org.

## Prerequisites

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`)
- A Salesforce org (Developer Edition, sandbox, or a Dev Hub for scratch orgs)

Verify the CLI is installed:

```bash
sf --version
```

## Connect a Salesforce org

You authorize (connect) an org once; the CLI stores the credentials locally
under `.sfdx`/`.sf` (which are git-ignored — credentials are never committed).

### Option A — Connect an existing org (Developer Edition or sandbox)

```bash
# Production / Developer Edition
sf org login web --alias fullcrm --set-default

# Sandbox
sf org login web --alias fullcrm --instance-url https://test.salesforce.com --set-default
```

A browser window opens for you to log in and approve access. Confirm the
connection:

```bash
sf org display --target-org fullcrm
sf org list
```

### Option B — Create a scratch org (requires a Dev Hub)

```bash
# One-time: authorize your Dev Hub
sf org login web --alias DevHub --set-default-dev-hub

# Create a scratch org from config/project-scratch-def.json
sf org create scratch --definition-file config/project-scratch-def.json \
  --alias fullcrm-scratch --set-default --duration-days 7
```

## Deploy & test

```bash
# Deploy source to the connected org
sf project deploy start --target-org fullcrm

# Run Apex tests
sf apex run test --target-org fullcrm --code-coverage --result-format human

# Retrieve metadata changes back from the org
sf project retrieve start --target-org fullcrm
```

## Project layout

```
fullcrm/
├── config/
│   └── project-scratch-def.json   # Scratch org definition
├── force-app/
│   └── main/default/
│       └── classes/               # Apex classes & tests
├── manifest/
│   └── package.xml                # Metadata manifest
├── .forceignore                   # Files excluded from deploy/retrieve
├── sfdx-project.json              # SFDX project config (login URL, API version)
└── README.md
```

> **Security note:** Never commit org credentials, `server.key`, auth files, or
> `.env`. These are already listed in `.gitignore`.
