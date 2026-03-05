---
name: service-auth-setup
description: Provision OIDC authentication for a new LoomOS service using Pocket ID. Use when adding authentication to a new web service, creating OIDC clients, or setting up oauth2-proxy.
---

# Service Auth Setup

Workflow for provisioning Pocket ID OIDC authentication when adding a new LoomOS service. Composes three tool skills:

- **pocket-id** — Create the OIDC client
- **1password** — Store credentials in the vault
- **secretspec** — Wire secrets into the service's Docker Compose stack

## Prerequisites

- The service is deployed and accessible via Tailscale (port allocated, `tailscaleServes` configured)
- You know the service's callback URL (see Callback URL Patterns below)

## Workflow

### Step 1: Choose Authentication Approach

| Approach | When to Use | Callback URL Pattern |
|----------|-------------|---------------------|
| **Native OIDC** | Service has built-in OIDC/OAuth2 support | Varies by service (check its docs) |
| **oauth2-proxy** | Service lacks OIDC support | `https://<service-url>/oauth2/callback` |

**Prefer native OIDC** when available — it's simpler and avoids an extra container.

### Step 2: Create OIDC Client in Pocket ID

Use the **pocket-id** skill. Always check for an existing client first (idempotent):

```bash
# Check if client already exists
restish pocket-id list-clients search="<service-name>" -f 'body.data'

# If no match, create it
restish pocket-id create-client \
  name:"<service-name>" \
  callbackURLs:["<callback-url>"] \
  pkceEnabled:true
```

Save the returned `id` — this is the `client_id`.

Then generate the client secret:

```bash
# Get the client secret (shown only once!)
restish pocket-id regenerate-client-secret <client-id> -f 'body.secret' -r
```

Save both the `client_id` and `secret` for the next step.

### Step 3: Store Credentials in 1Password

Use the **1password** skill. All OIDC client credentials go in the **LoomOS-Services** vault.

```bash
# Create a new item with client ID and secret
op item create \
  --vault "LoomOS-Services" \
  --category "API Credential" \
  --title "<Service Name> Pocket ID OIDC" \
  "client_id=<client-id>" \
  "client_secret=<client-secret>"
```

**Naming convention**: `<Service Name> Pocket ID OIDC` (e.g., "Paperless Pocket ID OIDC")

For oauth2-proxy, also generate and store a cookie secret:

```bash
# Generate cookie secret
COOKIE_SECRET=$(openssl rand -base64 32)

# Store it alongside the OIDC credentials
op item edit "<Service Name> Pocket ID OIDC" \
  --vault "LoomOS-Services" \
  "cookie_secret=$COOKIE_SECRET"
```

### Step 4: Add Secrets to SecretSpec

Use the **secretspec** skill. Add the OIDC credentials to the service's `secretspec.toml`:

```toml
# In services/<service-name>/secretspec.toml

[secrets.<SERVICE>_OIDC_CLIENT_ID]
description = "<Service> Pocket ID OIDC client ID"
providers = ["loomos_services"]

[secrets.<SERVICE>_OIDC_CLIENT_SECRET]
description = "<Service> Pocket ID OIDC client secret"
providers = ["loomos_services"]
```

For oauth2-proxy, also add the cookie secret:

```toml
[secrets.<SERVICE>_OAUTH2_COOKIE_SECRET]
description = "<Service> oauth2-proxy cookie secret"
providers = ["loomos_services"]
```

### Step 5: Configure the Service

**For native OIDC**: Set the service's OIDC environment variables in its `docker-compose.yml` to reference the SecretSpec-injected vars. Point the issuer URL to `config.custom.serviceUrls.pocket-id` (never hardcode).

**For oauth2-proxy**: Add an `oauth2-proxy` container to the service's `docker-compose.yml`:

```yaml
oauth2-proxy:
  image: quay.io/oauth2-proxy/oauth2-proxy:latest
  environment:
    OAUTH2_PROXY_PROVIDER: oidc
    OAUTH2_PROXY_OIDC_ISSUER_URL: ${POCKET_ID_URL}
    OAUTH2_PROXY_CLIENT_ID: ${SERVICE_OIDC_CLIENT_ID}
    OAUTH2_PROXY_CLIENT_SECRET: ${SERVICE_OIDC_CLIENT_SECRET}
    OAUTH2_PROXY_COOKIE_SECRET: ${SERVICE_OAUTH2_COOKIE_SECRET}
    OAUTH2_PROXY_UPSTREAMS: http://service:port
    OAUTH2_PROXY_HTTP_ADDRESS: 0.0.0.0:4180
    OAUTH2_PROXY_REDIRECT_URL: https://<service-url>/oauth2/callback
    OAUTH2_PROXY_EMAIL_DOMAINS: "*"
    OAUTH2_PROXY_COOKIE_SECURE: "true"
    OAUTH2_PROXY_CODE_CHALLENGE_METHOD: S256
  ports:
    - "<host-port>:4180"
```

Remove the service's direct host port binding — let oauth2-proxy handle external traffic.

## Callback URL Patterns

| Approach | Pattern |
|----------|---------|
| Native OIDC (django-allauth) | `https://<service-url>/accounts/oidc/pocket-id/login/callback/` |
| Native OIDC (generic) | Check the service's OIDC documentation |
| oauth2-proxy | `https://<service-url>/oauth2/callback` |

## Checklist

After completing the workflow, verify:

- [ ] OIDC client exists in Pocket ID with correct callback URL
- [ ] Client ID and secret stored in `LoomOS-Services` vault
- [ ] Secrets declared in service's `secretspec.toml`
- [ ] Service configured with OIDC settings pointing to Pocket ID
- [ ] Service accessible and redirects to Pocket ID for login
- [ ] Successful login redirects back to service
