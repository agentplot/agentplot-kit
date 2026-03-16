{ writeShellApplication, restish }:
writeShellApplication {
  name = "linkding-cli";
  runtimeInputs = [ restish ];
  text = ''
    : "''${LINKDING_BASE_URL:?LINKDING_BASE_URL not set}"
    : "''${LINKDING_API_TOKEN:?LINKDING_API_TOKEN not set}"

    TMPHOME=$(mktemp -d)
    trap 'rm -rf "$TMPHOME"' EXIT

    # restish uses configdir: ~/Library/Application Support on macOS, ~/.config on Linux
    if [[ "$(uname)" == "Darwin" ]]; then
      CFGDIR="$TMPHOME/Library/Application Support/restish"
    else
      CFGDIR="$TMPHOME/.config/restish"
    fi
    mkdir -p "$CFGDIR"

    cat > "$CFGDIR/apis.json" << APIEOF
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

    HOME="$TMPHOME" exec restish linkding "$@"
  '';
}
