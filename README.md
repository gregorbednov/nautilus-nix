# Nautilus for Nix

This flake packages the `naut` CLI for x86-64 and AArch64 Linux. Its default
source is the fork's `omron-cj1-experiment` branch. The `upstream` output
uses `joyautomation/nautilus` at its locked `main` revision.

## Run or build

```sh
nix run github:gregorbednov/nautilus-nix -- --version
nix run github:gregorbednov/nautilus-nix#upstream -- --version
nix build github:gregorbednov/nautilus-nix#naut
```

## Choose a source branch

Override the `nautilus` input to use a branch, tag, or commit from another
repository. The option applies to both `nix run` and `nix build`.

```sh
nix run github:gregorbednov/nautilus-nix#naut \
  --override-input nautilus github:joyautomation/nautilus/main \
  -- --version
```

For a persistent choice in your own flake, set the nested input:

```nix
inputs.nautilus-nix = {
  url = "github:gregorbednov/nautilus-nix";
  inputs.nautilus = {
    url = "github:gregorbednov/nautilus/omron-cj1-experiment";
    flake = false;
  };
};
```

Use `inputs.nautilus-nix.packages.${system}.naut` in your configuration. To
refresh a locked branch in a local checkout of this repository, run
`nix flake update nautilus` or `nix flake update nautilus-upstream`.

## When Go dependencies change

Branches with the same `go.mod` and `go.sum` share a Go module cache hash.
For a new dependency set, the first build prints the hash calculated by Nix.
Run these commands from a clone of this packaging repository:

```sh
source=github:joyautomation/nautilus/main
nix eval --raw .#naut.goInputsKey --override-input nautilus "$source"
nix build .#naut.goModules --override-input nautilus "$source" --no-link
```

Add the key from the first command and the `got:` hash from the second
command to `vendor-hashes.json`, then rerun the build. A downstream flake
can also use `packages.${system}.naut.override { vendorHash = "..."; }`.
