{ writeShellApplication, restish }:
writeShellApplication {
  name = "pocket-id-cli";
  runtimeInputs = [ restish ];
  text = ''
    : "''${POCKET_ID_BASE_URL:?POCKET_ID_BASE_URL not set}"
    : "''${POCKET_ID_API_KEY:?POCKET_ID_API_KEY not set}"

    TMPCONF=$(mktemp -d)
    trap 'rm -rf "$TMPCONF"' EXIT
    mkdir -p "$TMPCONF/restish"

    cat > "$TMPCONF/restish/apis.json" << APIEOF
    {
      "pocket-id": {
        "base": "$POCKET_ID_BASE_URL",
        "spec_files": ["${./openapi.json}"],
        "profiles": {
          "default": {
            "headers": {
              "X-API-KEY": "$POCKET_ID_API_KEY"
            }
          }
        }
      }
    }
    APIEOF

    XDG_CONFIG_HOME="$TMPCONF" exec restish pocket-id "$@"
  '';
}
