{
  description = "A practice project that creates an development environment for Rust with Nix flake.";
  nixConfig.bash-prompt-prefix = "\\e[0;34m(nix develop)\\e[0m ";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    flake-utils.url = "github:numtide/flake-utils";
    mission-control.url = "github:Platonic-Systems/mission-control";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = inputs@{ nixpkgs, flake-parts, fenix, crane, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        # To import a flake module
        # 1. Add foo to inputs
        # 2. Add foo as a parameter to the outputs function
        # 3. Add here: foo.flakeModule
        inputs.flake-root.flakeModule
        inputs.mission-control.flakeModule
      ];
      systems = [ "x86_64-linux" ];
      perSystem = { config, self', inputs', lib, pkgs, system, ... }:
        let
          name = "nix-rs-prac-nodevenv";

          fenixStable = fenix.packages.${system}.stable;

          rustToolchain = fenixStable.withComponents [
            "rustc"
            "cargo"
            "clippy"
            "rust-src"
            "rust-docs"
            "llvm-tools-preview"
          ];
          craneLib = crane.lib.${system}.overrideToolchain (rustToolchain);
          src = craneLib.cleanCargoSource (craneLib.path ./.);

          # Common arguments can be set here to avoid repeating them later
          commonArgs = {
            inherit src;

            buildInputs = [
              # Add additional build inputs here
            ] ++ lib.optionals pkgs.stdenv.isDarwin [
              # Additional darwin specific inputs can be set here
              pkgs.libiconv
            ];

            # Additional environment variables can be set directly
            # MY_CUSTOM_VAR = "some value";
          };

          # Build *just* the cargo dependencies, so we can reuse
          # all of that work (e.g. via cachix) when running in CI
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          # Build the actual crate itself, reusing the dependency
          # artifacts from above.
          my-crate = craneLib.buildPackage (commonArgs // {
            inherit cargoArtifacts;
          });
        in
        {
          # Per-system attributes can be defined here. The self' and inputs'
          # module parameters provide easy access to attributes of the same
          # system.

          mission-control.scripts = {
            build-container = {
              description = "Build container image that can run this project in it.";
              exec = "nix build '.#container'";
            };
            copy-container = {
              description = "Copy container to \"containers-storage\" (requires podman).";
              exec = with config; ''
                IMAGE_PATH=$(nix eval --raw '.#packages.${system}.container')
                ${lib.getExe packages.skopeo} --insecure-policy copy docker-archive:"$IMAGE_PATH" containers-storage:localhost/${name}:latest
              '';
            };
          };

          packages.default = my-crate;
          packages.skopeo = pkgs.skopeo;

          packages.container = with config; pkgs.dockerTools.buildLayeredImage {
            name = name;
            tag = "latest";
            created = "now";
            contents = [ packages.default ];
            config = {
              EntryPoint = [ "${packages.default}/bin/nix-rs-prac-nodevenv" ];
            };
          };

          devShells.default = with pkgs; mkShell {
            inputsFrom = [ config.mission-control.devShell ];
            packages = [
              git
            ] ++ [
              rustToolchain
              config.packages.skopeo
            ];

            nativeBuildInputs = [
              rustToolchain
            ];
          };
        };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.
      };
    };
}
