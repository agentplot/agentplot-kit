{ writeShellApplication, restish }:
writeShellApplication {
  name = "paperless-cli";
  runtimeInputs = [ restish ];
  text = ''
    : "''${PAPERLESS_BASE_URL:?PAPERLESS_BASE_URL not set}"
    : "''${PAPERLESS_API_TOKEN:?PAPERLESS_API_TOKEN not set}"

    TMPCONF=$(mktemp -d)
    trap 'rm -rf "$TMPCONF"' EXIT
    mkdir -p "$TMPCONF/restish"

    cat > "$TMPCONF/restish/apis.json" << APIEOF
    {
      "paperless": {
        "base": "$PAPERLESS_BASE_URL",
        "spec_files": ["$PAPERLESS_BASE_URL/api/schema/?format=json"],
        "profiles": {
          "default": {
            "headers": {
              "Authorization": "Token $PAPERLESS_API_TOKEN"
            }
          }
        }
      }
    }
    APIEOF

    XDG_CONFIG_HOME="$TMPCONF" exec restish paperless "$@"
  '';
}
