{
  pkgsBuildBuild,
  lib,
  fetchFromGitHub,
  vscode-utils,
  jq,
  rust-analyzer,
  buildNpmPackage,
  moreutils,
  esbuild,
  pkg-config,
  libsecret,
  setDefaultServerPath ? true,
}:

let
  pname = "rust-analyzer";
  publisher = "rust-lang";

  # Use the plugin version as in vscode marketplace, updated by update script.
  inherit (vsix) version;

  releaseTag = "2025-08-25";

  src = fetchFromGitHub {
    owner = "rust-lang";
    repo = "rust-analyzer";
    rev = releaseTag;
    hash = "sha256-apbJj2tsJkL2l+7Or9tJm1Mt5QPB6w/zIyDkCx8pfvk=";
  };

  vsix = buildNpmPackage {
    inherit pname releaseTag;
    version = lib.trim (lib.readFile ./version.txt);
    src = "${src}/editors/code";

    npmDepsHash = "sha256-fV4Z3jj+v56A7wbIEYhVAPVuAMqMds5xSe3OetWAsbw=";

    buildInputs = [ pkgsBuildBuild.libsecret ];
    nativeBuildInputs = [
      jq
      moreutils
      esbuild
      pkg-config
    ];

    # Skip esbuild’s installer, and point to Nix’s esbuild and fake version (no breaking changes)
    # If we don't do this esbuild will fail due to version mismatch.
    npmFlags = [ "--ignore-scripts" ];
    ESBUILD_SKIP_DOWNLOAD = "1";
    ESBUILD_SKIP_BINARY_INSTALL = "1";

    # Make the esbuild wrapper available *before* npmConfigHook runs
    preConfigure = ''
            WRAP="$PWD/esbuild-wrapper"
            cat > "$WRAP" <<'EOF'

            #! /bin/sh
            if [ "$1" = "--version" ]; then
              echo 0.25.0
              exit 0
            fi
            exec '${esbuild}/bin/esbuild' "$@"
            EOF
            
            chmod +x "$WRAP"
            export ESBUILD_BINARY_PATH="$WRAP"
    '';

    installPhase = ''
      jq '
        .version = $ENV.version |
        .releaseTag = $ENV.releaseTag |
        .enableProposedApi = false |
        walk(del(.["$generated-start"]?) | del(.["$generated-end"]?))
      ' package.json | sponge package.json

      mkdir -p $out

      # Avoid non-exec .bin symlink; call the CLI with node directly.
      # patchShebangs already pointed node to the Nix node, so plain `node` works.
      node node_modules/@vscode/vsce/vsce package -o $out/${pname}.zip
    '';
  };

in
vscode-utils.buildVscodeExtension {
  inherit version vsix pname;
  src = "${vsix}/${pname}.zip";
  vscodeExtUniqueId = "${publisher}.${pname}";
  vscodeExtPublisher = publisher;
  vscodeExtName = pname;

  nativeBuildInputs = lib.optionals setDefaultServerPath [
    jq
    moreutils
  ];

  preInstall = lib.optionalString setDefaultServerPath ''
    jq '(.contributes.configuration[] | select(.title == "server") | .properties."rust-analyzer.server.path".default) = $s' \
      --arg s "${rust-analyzer}/bin/rust-analyzer" \
      package.json | sponge package.json
  '';

  meta = {
    description = "Alternative rust language server to the RLS";
    homepage = "https://github.com/rust-lang/rust-analyzer";
    license = [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    maintainers = [ ];
    platforms = lib.platforms.all;
  };
}
