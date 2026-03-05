{ writeShellApplication, restish }:
writeShellApplication {
  name = "linkding-cli";
  runtimeInputs = [ restish ];
  text = ''
    : "''${LINKDING_BASE_URL:?LINKDING_BASE_URL not set}"
    : "''${LINKDING_API_TOKEN:?LINKDING_API_TOKEN not set}"

    TMPCONF=$(mktemp -d)
    trap 'rm -rf "$TMPCONF"' EXIT
    mkdir -p "$TMPCONF/restish"

    cat > "$TMPCONF/restish/apis.json" << APIEOF
    {
      "linkding": {
        "base": "$LINKDING_BASE_URL",
        "spec_files": ["${./openapi.json}"],
        "profiles": {
          "default": {
            "headers": {
              "Authorization": "Token $LINKDING_API_TOKEN"
            }
          }
        }
      }
    }
    APIEOF

    XDG_CONFIG_HOME="$TMPCONF" exec restish linkding "$@"
  '';
}
