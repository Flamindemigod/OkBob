# default.nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs;[
	zig
	valgrind
	sqlite
	zls
  ];

  # Optionally, you can set environment variables
  shellHook = ''
	zig zen
'';
}

