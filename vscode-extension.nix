{
  pkgs,
  src,
  naut,
}:
let
  inherit (pkgs) lib;
  extensionPath = "tools/vscode-iec";
  manifest = builtins.fromJSON (builtins.readFile "${src}/${extensionPath}/package.json");
  extensionId = "${manifest.publisher}.${manifest.name}";
  projects = {
    hmi = "hmi";
    hmi3d = "hmi-3d";
    extension = extensionPath;
    webview = "${extensionPath}/webview-ui";
  };
  hashes = builtins.fromJSON (builtins.readFile ./npm-hashes.json);
  npmInputsKeys = lib.mapAttrs (
    _: path: builtins.hashFile "sha256" "${src}/${path}/package-lock.json"
  ) projects;
  npmCaches = lib.mapAttrs (
    name: path:
    pkgs.fetchNpmDeps {
      name = "nautilus-${name}-npm-deps";
      src = "${src}/${path}";
      hash = hashes.${npmInputsKeys.${name}} or lib.fakeHash;
    }
  ) projects;
  cli = lib.getExe naut;
in
pkgs.vscode-utils.buildVscodeExtension {
  pname = "joyauto-vscode-iec";
  version = manifest.version;
  inherit src;
  vscodeExtPublisher = manifest.publisher;
  vscodeExtName = manifest.name;
  vscodeExtUniqueId = extensionId;
  sourceRoot = "source";

  nativeBuildInputs = [
    pkgs.nodejs
    pkgs.nodejs.python
    pkgs.npmHooks.npmConfigHook
    pkgs.jq
  ];
  env = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];
    npm_config_audit = "false";
    npm_config_fund = "false";
  };
  npmRoot = extensionPath;
  npmDeps = npmCaches.extension;
  makeCacheWritable = true;

  buildPhase = ''
    runHook preBuild

    npmProject() (
      cd "$1"
      npmRoot=""
      npmDeps="$2"
      export TMPDIR="$(mktemp -d "$TMPDIR/npm.XXXXXX")"
      export TMP="$TMPDIR"
      npmConfigHook
      npm run "$3"
    )

    npmProject "${projects.hmi}" "${npmCaches.hmi}" package
    npmProject "${projects.hmi3d}" "${npmCaches.hmi3d}" package
    npmProject "${projects.webview}" "${npmCaches.webview}" build
    npm --prefix "${extensionPath}" run compile
    npm --prefix "${extensionPath}" prune --offline --omit=dev --ignore-scripts

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    target="$out/$installPrefix"
    mkdir -p "$target"
    cd "${extensionPath}"
    cp -r \
      CHANGELOG.md LICENSE README.md icon.png icons images \
      language-configuration.json media node_modules out schemas syntaxes walkthroughs \
      "$target/"
    rm -rf "$target/out/e2e"
    find "$target/out" -type f \( -name '*.test.js' -o -name '*.map' \) -delete

    jq --arg cli "${cli}" \
      '.contributes.configuration.properties["nautilus.cliPath"].default = $cli' \
      package.json > "$target/package.json"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    target="$out/$installPrefix"
    test -s "$target/out/extension.js"
    test -s "$target/media/dist/fbd-flow.js"
    test -s "$target/media/dist/diagram-export.cjs"
    jq -e --arg cli "${cli}" \
      '.contributes.configuration.properties["nautilus.cliPath"].default == $cli' \
      "$target/package.json"
    node -e 'require(process.argv[1] + "/node_modules/esbuild").transformSync("let x = 1")' "$target"
    "${cli}" --version

    runHook postInstallCheck
  '';

  passthru = { inherit npmCaches npmInputsKeys; };
  meta = {
    description = "Nautilus IEC 61131-3 extension for Visual Studio Code";
    homepage = "https://github.com/joyautomation/nautilus";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
