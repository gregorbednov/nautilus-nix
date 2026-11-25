{
  description = "Nautilus CLI and VS Code extension with a selectable source branch";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nautilus = {
      url = "github:gregorbednov/nautilus/omron-cj1-experiment";
      flake = false;
    };

    nautilus-upstream = {
      url = "github:joyautomation/nautilus/main";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, nautilus, nautilus-upstream }:
    let
      inherit (nixpkgs) lib;
      eachSystem = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      hashes = builtins.fromJSON (builtins.readFile ./vendor-hashes.json);

      makeNaut =
        pkgs: src:
        let
          goInputsKey = builtins.hashString "sha256" (
            builtins.concatStringsSep "\n" [
              (builtins.hashFile "sha256" (src + "/go.mod"))
              (builtins.hashFile "sha256" (src + "/go.sum"))
            ]
          );
        in
        lib.makeOverridable (
          { vendorHash ? hashes.${goInputsKey} or lib.fakeHash }:
          pkgs.buildGoModule {
            pname = "nautilus";
            version = "0-unstable-${builtins.substring 0 12 (src.rev or "local")}";
            inherit src vendorHash;
            proxyVendor = true;
            env.CGO_ENABLED = "0";
            subPackages = [ "cmd/naut" ];
            doCheck = false;
            passthru = { inherit goInputsKey; };
            meta = {
              description = "Nautilus PLC engineering CLI";
              homepage = "https://github.com/joyautomation/nautilus";
              license = lib.licenses.asl20;
              mainProgram = "naut";
            };
          }
        ) { };

      makeExtension = pkgs: naut: import ./vscode-extension.nix {
        inherit pkgs naut;
        src = nautilus;
      };

      asApp = package: {
        type = "app";
        program = lib.getExe package;
        meta.description = "Run the Nautilus CLI";
      };
    in
    {
      packages = eachSystem (
        system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in rec {
          default = naut;
          naut = makeNaut pkgs nautilus;
          upstream = makeNaut pkgs nautilus-upstream;
          vscode-extension = makeExtension pkgs naut;
        }
      );

      legacyPackages = eachSystem (system: {
        vscode-extensions.joyauto.vscode-iec = self.packages.${system}.vscode-extension;
      });

      overlays.default = final: prev: {
        vscode-extensions = prev.vscode-extensions // {
          joyauto = (prev.vscode-extensions.joyauto or { }) // {
            vscode-iec = makeExtension final (makeNaut final nautilus);
          };
        };
      };

      apps = eachSystem (
        system: {
          default = asApp self.packages.${system}.naut;
          naut = asApp self.packages.${system}.naut;
          upstream = asApp self.packages.${system}.upstream;
        }
      );

      checks = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          extension = self.packages.${system}.vscode-extension;
          extensionIndex = pkgs.writeText "nautilus-vscode-extensions.json" (
            pkgs.vscode-utils.toExtensionJson [ extension ]
          );
          smoke = name: package: pkgs.runCommand "nautilus-${name}-smoke" { } ''
            ${lib.getExe package} --version > "$out"
            grep -F 'nautilus ' "$out"
          '';
        in {
          naut = smoke "omron" self.packages.${system}.naut;
          upstream = smoke "upstream" self.packages.${system}.upstream;
          vscode-extension = pkgs.runCommand "nautilus-vscode-extension-check" {
            nativeBuildInputs = [ pkgs.jq ];
          } ''
            asset="${extension}/share/vscode/extensions/joyauto.vscode-iec"
            jq -e --arg path "$asset" \
              'length == 1 and .[0].identifier.id == "joyauto.vscode-iec" and .[0].location.fsPath == $path' \
              ${extensionIndex} > "$out"
            test -s "$asset/package.json"
          '';
        }
      );
    };
}
