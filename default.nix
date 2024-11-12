{ stdenv, zig }:
stdenv.mkDerivation rec {
  name = "OkBob";
  src = ./.; # This refers to the current directory (your project source)

  buildInputs = [ zig sqlite ];

  buildPhase = ''
    export XDG_CACHE_HOME=$(mktemp -d)
    mkdir $out
    zig build install --prefix $out -Doptimize=ReleaseSafe -v
    rm -rf $XDG_CACHE_HOME
  '';
}

