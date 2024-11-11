# default.nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs;[
	zig
	valgrind
];

  # Optionally, you can set environment variables
  shellHook = ''
	zig zen
'';
}

