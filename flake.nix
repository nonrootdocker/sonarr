{
  description = "minimalbase + sonarr service";
  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase";
    sonarr-src = {
      type = "tarball";
      url = "https://services.sonarr.tv/v1/download/main/latest?version=4&os=linux&arch=x64";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, minimalbase, sonarr-src }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };
    opensslLib = pkgs.openssl.out;
    sqliteLib = pkgs.sqlite.out;
    # ----------------------------
    # Sonarr version (read from the release's deps.json, so it always
    # matches the exact binary pinned by the sonarr-src lock entry)
    # ----------------------------
    sonarrDeps =
      let
        p1 = "${sonarr-src}/Sonarr.deps.json";
        p2 = "${sonarr-src}/Sonarr/Sonarr.deps.json";
      in if builtins.pathExists p1 then p1 else p2;
    sonarrVersion =
      let
        deps = builtins.fromJSON (builtins.readFile sonarrDeps);
        keys = builtins.attrNames deps.libraries;
        key = builtins.head (builtins.filter (k: builtins.match "Sonarr/.*" k != null) keys);
      in pkgs.lib.removePrefix "Sonarr/" key;
    # ----------------------------
    # Sonarr package
    # ----------------------------
    sonarr = pkgs.stdenv.mkDerivation {
      pname = "sonarr";
      version = sonarrVersion;
      src = sonarr-src;
      nativeBuildInputs = [
        pkgs.autoPatchelfHook
      ];
      buildInputs = [
        pkgs.icu
        pkgs.curl
        pkgs.sqlite
        opensslLib
        sqliteLib
        pkgs.zlib
        pkgs.lttng-ust_2_12
        pkgs.stdenv.cc.cc.lib
      ];
      installPhase = ''
        mkdir -p $out/app/Sonarr
        cp -r . $out/app/Sonarr/
      '';
    };
    # ----------------------------
    # User database configuration (/etc/passwd)
    # ----------------------------
    passwdFile = pkgs.writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/sh
      sonarr:x:1000:1000:sonarr:/data:/bin/sh
    '';
    # ----------------------------
    # ABI generator (Points directly to Nix Store)
    # ----------------------------
    sonarrAbi = pkgs.writeTextFile {
      name = "sonarr-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          exec = "${sonarr}/app/Sonarr/Sonarr";
          args = [
            "-nobrowser"
            "-data=/data"
          ];
        };
      };
      destination = "/app/main";
    };
  in {
    packages.${system} = {
      default = self.packages.${system}.sonarr-image;
      sonarr-image = pkgs.dockerTools.buildImage {
        name = "minimalbase";
        tag = sonarrVersion;
        fromImage = minimalbase.packages.${system}.base-image;
        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert
            sonarr
            sonarrAbi
            passwdFile
          ];
        };
        config = {
          Entrypoint = [ "${minimalbase.packages.${system}.container-init}/bin/container-init" ];
          User = "1000:1000";
          Env = [
            "PATH=/bin"
            "TZ=UTC"
            "LANG=en_US.UTF-8"
            "LD_LIBRARY_PATH=${pkgs.icu}/lib:${opensslLib}/lib:${pkgs.zlib}/lib:${pkgs.lttng-ust_2_12}/lib:${sqliteLib}/lib"
          ];
        };
      };
    };
  };
}
