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
    # Sonarr package
    # ----------------------------
    sonarr = pkgs.stdenv.mkDerivation {
      pname = "sonarr";
      version = "release";
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
    # Sonarr version: the real product version is embedded in Core.dll as
    # the assembly reference "Sonarr.Common, Version=N.N.N.N" (consistent
    # across Servarr apps). Exposed as the `version` output for CI tagging.
    # ----------------------------
    sonarrVersion = pkgs.runCommand "sonarr-version" {
      nativeBuildInputs = [ pkgs.binutils ];
    } ''
      strings ${sonarr}/app/Sonarr/Sonarr.Core.dll \
        | grep -oE 'Sonarr\.Common, Version=[0-9.]+' \
        | head -n1 | sed 's/.*Version=//' | tr -d '\n' > $out
    '';
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
      version = sonarrVersion;
      sonarr-image = pkgs.dockerTools.buildImage {
        name = "sonarr";
        tag = "latest";
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
