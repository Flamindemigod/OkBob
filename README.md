# OkBob is a small reminder tool
Essentially it's built for my own personal use to keep track of my reminders.
I've been considering doing something like this for a long time.
But seeing rexim's own personal project he uses called (tore)[https://github.com/rexim/tore/]
I've been motivated to make my own. I'm not entirely famililar of all the internals of his project,
other than the interface he uses to interact with it which i personally love.
So any similarity other than that is purely coincidental.

## Quick Start for Nix
```console
nix-build -E 'with import <nixpkgs> {}; callPackage ./default.nix {}'
./result/bin/OkBob

```

## Anything else
```
zig build
./zig-out/bin/OkBob
```
