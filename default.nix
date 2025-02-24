{ sources ? import ./nix/sources.nix
, pkgs ? import sources.nixpkgs {
    overlays = [ ];
    config = { };
  }
}:

with pkgs;
let
  customAgda = (import
    (builtins.fetchTarball
      https://github.com/nixos/nixpkgs/tarball/a7ecde854aee5c4c7cd6177f54a99d2c1ff28a31)
    ({
      # 21.11
      overlays = [
        (import (fetchFromGitHub {
          repo = "agda";
          owner = "input-output-hk";
          rev = "d5ea03b96328f38741efef4535197076ff0e05d5";
          sha256 = "WiadZWZvPWcR49JkiXPiMKW3plRjBlR94wyg/aoEoG8=";
        })).overlay
      ];
    } // (if pkgs.system == "aarch64-darwin" then { system = "x86_64-darwin"; } else { })));

  agdaStdlib = customAgda.agdaPackages.standard-library.overrideAttrs (oldAttrs: {
    version = "1.7";
    src = customAgda.fetchFromGitHub {
      repo = "agda-stdlib";
      owner = "input-output-hk";
      rev = "f8fdb925c74e8d3b0c88e2a5520bc11e606d34c6";
      sha256 = "BoK/IZsOn8gnUolI8DOZa6IOoXF8E95s2e8vZyUpMZs=";
    };
  });

  agdaStdlibMeta = customAgda.agdaPackages.mkDerivation {
    pname = "agda-stdlib-meta";
    version = "0.1";
    src = customAgda.fetchFromGitHub {
      repo = "stdlib-meta";
      owner = "omelkonian";
      rev = "dadb6a468b9cdc47442b48a47b848f8e8fbffda7";
      sha256 = "YkUtM5Gos6xd7ZsZPqcuVy6DZqNA7n/exPfQngir+y0=";
    };
    patches = [ ./stdlib-meta-update-imports.patch ];
    meta = { };
    libraryFile = "stdlib-meta.agda-lib";
    everythingFile = "Main.agda";
    buildInputs = [ agdaStdlib ];
  };

  deps = [ agdaStdlib agdaStdlibMeta ];
  agdaWithPkgs = customAgda.agda.withPackages { pkgs = deps; ghc = pkgs.ghc; };

in
rec {

  agda = agdaWithPkgs;
  agdaLedger = customAgda.agdaPackages.mkDerivation {
    pname = "Agda-ledger";
    version = "0.1";
    src = ./src;
    meta = { };
    buildInputs = deps;
    postInstall = "cp -r latex $out";
    extraExtensions = [ "hs" "cabal" ];
  };

  # a parameterized attribute set containing derivations for: 1) executable spec 2) docs
  specsDerivations = { dir, agdaLedgerFile, hsMainFile, doc }:
    let
      hsSrc =
        stdenv.mkDerivation {
          pname = "Agda-ledger-${dir}-hs-src";
          version = "0.1";
          src = "${agdaLedger}";
          meta = { };
          buildInputs = [ agdaWithPkgs ];
          buildPhase = "";
          installPhase = ''
            mkdir -p $out
            agda -c --ghc-dont-call-ghc --compile-dir $out ${dir}/${agdaLedgerFile}
            cp ${dir}/${hsMainFile} $out
            cp ${dir}/agda-ledger-executable-spec.cabal $out
            # Append all the modules generated by MAlonzo to the cabal file
            find $out/MAlonzo -name "*.hs" -print | sed "s#^$out/#        #;s#\.hs##;s#/#.#g" >> $out/agda-ledger-executable-spec.cabal
          '';
        };
      docs = stdenv.mkDerivation {
        pname = "${dir}-docs";
        version = "0.1";
        src = "${agdaLedger}";
        meta = { };
        buildInputs = [
          agdaWithPkgs
          (texlive.combine {
            inherit (texlive)
              scheme-small
              xits
              collection-latexextra
              collection-latexrecommended
              collection-mathscience
              bclogo
              latexmk;
          })
        ];
        buildPhase = ''
          ls ${dir}/*.lagda | xargs -n 1 agda --latex
          cd latex && latexmk -xelatex ${dir}/${doc}.tex && cd ..
        '';
        installPhase = ''
          mkdir -p $out
          agda --html --html-dir $out/html ${dir}/${doc}.lagda
          cp latex/${doc}.pdf $out
        '';
      };
    in
    {
      executableSpec = haskellPackages.callCabal2nix "Agda-ledger-executable-spec" "${hsSrc}" { };
      docs = docs;
    };

  ledger = specsDerivations {
    dir = "Ledger";
    agdaLedgerFile = "Foreign/HSLedger.agda";
    hsMainFile = "HSLedgerTest.hs";
    doc = "Ledger";
  };
  midnight = specsDerivations {
    dir = "MidnightExample";
    agdaLedgerFile = "HSLedger.agda";
    hsMainFile = "Main.hs";
    doc = "PDF";
  };
}
