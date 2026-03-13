# Declares what environment variables each service needs.
# Consumers (swancloud, other fleets) wire this to their own secret/URL backends.
{
  linkding = {
    secrets = [ "LINKDING_API_TOKEN" ];
    env = [ "LINKDING_BASE_URL" ];
  };
  paperless = {
    secrets = [ "PAPERLESS_API_TOKEN" ];
    env = [ "PAPERLESS_BASE_URL" ];
  };
}
