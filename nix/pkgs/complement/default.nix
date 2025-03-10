# Dependencies
{ bashInteractive
, buildEnv
, coreutils
, dockerTools
, gawk
, lib
, main
, openssl
, stdenv
, tini
, writeShellScriptBin
}:

let
  main' = main.override {
    profile = "test";
    all_features = true;
    disable_release_max_log_level = true;
    disable_features = [
        # console/CLI stuff isn't used or relevant for complement
        "console"
        "tokio_console"
        # sentry telemetry isn't useful for complement, disabled by default anyways
        "sentry_telemetry"
        "perf_measurements"
        # this is non-functional on nix for some reason
        "hardened_malloc"
        # dont include experimental features
        "experimental"
        # compression isn't needed for complement
        "brotli_compression"
        "gzip_compression"
        "zstd_compression"
        # complement doesn't need hot reloading
        "conduwuit_mods"
        # complement doesn't have URL preview media tests
        "url_preview"
    ];
  };

  start = writeShellScriptBin "start" ''
    set -euxo pipefail

    cp ${./v3.ext} /complement/v3.ext
    echo "DNS.1 = $SERVER_NAME" >> /complement/v3.ext
    echo "IP.1 = $(${lib.getExe gawk} 'END{print $1}' /etc/hosts)" \
      >> /complement/v3.ext
    ${lib.getExe openssl} x509 \
      -req \
      -extfile /complement/v3.ext \
      -in ${./signing_request.csr} \
      -CA /complement/ca/ca.crt \
      -CAkey /complement/ca/ca.key \
      -CAcreateserial \
      -out /complement/certificate.crt \
      -days 1 \
      -sha256

    ${lib.getExe' coreutils "env"} \
      CONDUWUIT_SERVER_NAME="$SERVER_NAME" \
      ${lib.getExe main'}
  '';
in

dockerTools.buildImage {
  name = "complement-conduwuit";
  tag = "main";

  copyToRoot = buildEnv {
    name = "root";
    pathsToLink = [
      "/bin"
    ];
    paths = [
      bashInteractive
      coreutils
      main'
      start
    ];
  };

  config = {
    Cmd = [
      "${lib.getExe start}"
    ];

    Entrypoint = if !stdenv.hostPlatform.isDarwin
      # Use the `tini` init system so that signals (e.g. ctrl+c/SIGINT)
      # are handled as expected
      then [ "${lib.getExe' tini "tini"}" "--" ]
      else [];

    Env = [
      "CONDUWUIT_TLS__KEY=${./private_key.key}"
      "CONDUWUIT_TLS__CERTS=/complement/certificate.crt"
      "CONDUWUIT_CONFIG=${./config.toml}"
      "RUST_BACKTRACE=full"
    ];

    ExposedPorts = {
      "8008/tcp" = {};
      "8448/tcp" = {};
    };
  };
}
