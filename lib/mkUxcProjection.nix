# mkUxcProjection — convert a service's endpoints + credentials into UXC's
# on-disk JSON shapes (credentials / bindings) and link-shim metadata.
#
# Pure data transformer: no pkgs, no IO. `host` / `scheme` / `pathPrefix` /
# `urlTemplate` / `schemaSource.url` may be either strings or functions of the
# client's settings — they are resolved against `clientSettings` here.
#
# Arguments:
#   lib               — nixpkgs lib (for string helpers)
#   serviceName       — string, e.g. "atomic"
#   clientName        — string, the inventory client key (namespaces ids)
#   clientSettings    — the resolved per-client settings attrset (fn arg)
#   endpoints         — list of normalized endpoint records (see below)
#   secrets           — normalized secret list ({ name; mode; reference?; ... })
#   referencedSecrets — list of secret names referenced by endpoint `auth.secret`
#
# Endpoint record shapes (protocol-tagged):
#   { protocol = "mcp";     urlTemplate; auth = { secret; type; }; linkName?; priority?; }
#   { protocol = "openapi"; host; scheme?; pathPrefix?; schemaSource; auth = { secret; type; }; linkName?; priority?; }
#
# Returns: { credentials; bindings; links; } where
#   credentials — attrset keyed by credential id
#   bindings    — list of binding entries
#   links       — attrset keyed by link name
{
  lib,
  serviceName,
  clientName,
  clientSettings,
  endpoints ? [ ],
  secrets ? [ ],
  referencedSecrets ? [ ],
}:
let
  idPrefix = "agentplot-${serviceName}-${clientName}";

  # Resolve a string-or-fn-of-clientSettings to a string.
  resolveStringOrFn = v: if builtins.isFunction v then v clientSettings else v;

  # Parse "scheme://host/path" into its parts. path_prefix defaults to "/".
  parseUrl =
    url:
    let
      m = builtins.match "^(https?)://([^/]+)(/.*)?$" url;
    in
    if m == null then
      throw "mkUxcProjection: cannot parse URL '${url}' for service '${serviceName}'"
    else
      {
        scheme = builtins.elemAt m 0;
        host = builtins.elemAt m 1;
        path_prefix = let p = builtins.elemAt m 2; in if p == null then "/" else p;
      };

  # Resolve schemaSource (OpenAPI only) to a `--schema-url` string.
  resolveSchemaUrl =
    schemaSource:
    let
      type = schemaSource.type;
    in
    if type == "static" then
      # Path literal coerced to a store path; UXC reads via file:// URL.
      "file://${schemaSource.path}"
    else if type == "derivation" then
      "file://${schemaSource.drv}"
    else if type == "url" then
      resolveStringOrFn schemaSource.url
    else
      throw "mkUxcProjection: unknown schemaSource.type '${type}' for service '${serviceName}'";

  # Normalize one endpoint record into resolved fields.
  resolveEndpoint =
    ep:
    let
      protocol = ep.protocol;
      priority = ep.priority or 100;
      authSecret = ep.auth.secret;
      authType = ep.auth.type;
    in
    if protocol == "mcp" then
      let
        url = resolveStringOrFn ep.urlTemplate;
        parts = parseUrl url;
      in
      {
        inherit protocol priority authSecret authType;
        inherit (parts) scheme host path_prefix;
        # MCP link shim targets the full endpoint URL so UXC matches the binding.
        linkHost = url;
        linkName = ep.linkName or "${serviceName}-mcp-cli";
        schemaUrl = null;
      }
    else if protocol == "openapi" then
      let
        host = resolveStringOrFn ep.host;
        scheme = if ep ? scheme then resolveStringOrFn ep.scheme else "https";
        path_prefix = if ep ? pathPrefix then resolveStringOrFn ep.pathPrefix else "/";
      in
      {
        inherit protocol priority authSecret authType scheme host path_prefix;
        # OpenAPI link shim targets the bare host + --schema-url.
        linkHost = host;
        linkName = ep.linkName or "${serviceName}-openapi-cli";
        schemaUrl = resolveSchemaUrl ep.schemaSource;
      }
    else
      throw "mkUxcProjection: unknown endpoint protocol '${protocol}' for service '${serviceName}'";

  resolved = builtins.map resolveEndpoint endpoints;

  # secretName -> auth_type, taken from the first endpoint that references it.
  secretAuthType = builtins.listToAttrs (
    builtins.map (ep: lib.nameValuePair ep.authSecret ep.authType) resolved
  );

  secretByName = builtins.listToAttrs (
    builtins.map (s: lib.nameValuePair s.name s) secrets
  );

  # ── Credentials ──────────────────────────────────────────────────────────
  # One credential per *referenced* secret. Unreferenced secrets produce none.
  credentials = builtins.listToAttrs (
    builtins.map (
      secretName:
      let
        secret = secretByName.${secretName};
      in
      if (secret.mode or null) != "op" then
        throw "mkUxcProjection: endpoint auth references secret '${secretName}' (mode '${secret.mode or "?"}') in service '${serviceName}', but UXC projection requires an op-mode secret in v1"
      else
        lib.nameValuePair "${idPrefix}-${secretName}" {
          auth_type = secretAuthType.${secretName};
          secret_source = {
            kind = "op";
            reference = secret.reference;
          };
        }
    ) referencedSecrets
  );

  # ── Bindings ─────────────────────────────────────────────────────────────
  # One binding per endpoint, keyed on scheme + host + path_prefix.
  bindings = builtins.map (ep: {
    id = "${idPrefix}-${ep.protocol}";
    inherit (ep) scheme host path_prefix priority;
    credential = "${idPrefix}-${ep.authSecret}";
    enabled = true;
  }) resolved;

  # ── Links ────────────────────────────────────────────────────────────────
  # One link shim per endpoint, keyed by link name.
  links = builtins.listToAttrs (
    builtins.map (
      ep:
      lib.nameValuePair ep.linkName (
        { host = ep.linkHost; }
        // lib.optionalAttrs (ep.schemaUrl != null) { schemaUrl = ep.schemaUrl; }
      )
    ) resolved
  );
in
{
  inherit credentials bindings links;
}
