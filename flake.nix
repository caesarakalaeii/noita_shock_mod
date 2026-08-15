{
  # Keep this line accurate and one line long: `nix flake metadata` prints it,
  # and it is the first thing a cold agent learns about the repo.
  description = "Noita Shock Mod -- Noita Lua mod, Python serial bridge and Arduino TENS firmware. Run `nix flake show` for the command map.";

  # nixpkgs is the only input, on purpose.
  #
  # flake-utils would buy exactly one thing here -- eachDefaultSystem -- which is
  # the three-line genAttrs below. In exchange it costs a second lock node in
  # every repo (flake-utils transitively pulls `systems`, so really two), a
  # second upstream that can break one repo and not the other forty, and a
  # hardcoded system list this repo cannot edit. That list is currently broken:
  # it still contains x86_64-darwin, which now throws (see `systems` below).
  #
  # nixos-unstable is the same channel the author's own NixOS config tracks, so
  # `nix develop` here and `nixos-rebuild` there resolve the same store paths and
  # share one cache.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    # `...` rather than a closed { self, nixpkgs }: adding a second input later
    # would otherwise fail with "called with unexpected argument 'self'".
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;

      # x86_64-darwin is deliberately absent. nixpkgs 26.11 replaced that whole
      # attribute set with `throw "Nixpkgs 26.11 has dropped support for
      # x86_64-darwin"`. genAttrs is lazy, so plain `nix develop` on Linux would
      # not notice -- it detonates later, on `nix flake check --all-systems`.
      # Add it back only against a separate nixpkgs-26.05-darwin input.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Stand-in for flake-utils.lib.eachDefaultSystem. Passes `pkgs` rather than
      # a system string, because that is what every call site below wants.
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # ======================================================================
      # PER-REPO BLOCK 1 -- the toolchain
      # ======================================================================
      # Three ecosystems live in this one repo and each needs its own tools:
      #
      #   init.lua        the Noita mod, loaded by the game's embedded Lua
      #   python/         the bridge that tails Noita's flag files and drives
      #                   the Arduino over a serial port
      #   ardu/ardu.ino   the firmware that clicks the TENS unit's relays
      #
      # Explicit `pkgs.foo`, never `with pkgs; [ ... ]`: when an attr disappears
      # in a nixpkgs bump, `with` reports a bare undefined identifier with no
      # hint of which set it came from, and the name is not greppable.
      toolchain = pkgs: [
        # ---- python/ : the Noita-to-serial bridge ----
        #
        # withPackages rather than a uv/pip venv, and this is load-bearing: the
        # whole dependency set is one pure-python library. python/requirements.txt
        # lists `asyncio` and `pyserial`; `asyncio` has been in the standard
        # library since 3.4, and the PyPI package of that name is an abandoned
        # 2015 backport that would only shadow the real one. So pyserial is the
        # entire real dependency, nixpkgs has it, and the shell therefore works
        # with no network and no bootstrap step at all.
        #
        # Do NOT "fix" this by adding uv and a `setup` verb that builds a .venv.
        # That would trade a shell that works offline for one that needs the
        # network before it can run anything, to install a single pure-python
        # module nixpkgs already ships.
        (pkgs.python313.withPackages (ps: [ ps.pyserial ]))
        pkgs.ruff

        # ---- init.lua : the Noita mod ----
        #
        # luajit, not lua5_4: Noita embeds LuaJIT, so the mod is Lua 5.1 dialect
        # and `luajit -b` below parses it with the same front end the game will.
        # Never add lua5_4 alongside this -- both ship `bin/lua`, and while
        # buildEnv refuses the collision outright, mkShell silently lets one
        # shadow the other and you would be syntax-checking against the wrong
        # language version without any warning.
        pkgs.luajit
        pkgs.lua-language-server
        pkgs.stylua

        # ---- ardu/ardu.ino : the relay firmware ----
        #
        # Worth its ~500 MB closure because the repo's own TODO ("Add shock +
        # intensity function in ardu") points squarely at this sketch, and
        # without a compiler an agent editing it cannot tell whether its change
        # even builds. See `setup` for what this does NOT bring with it.
        pkgs.arduino-cli

        # ---- present in every repo in the fleet ----
        pkgs.git
        pkgs.jq
        pkgs.gnumake
      ];

      # ======================================================================
      # PER-REPO BLOCK 2 -- libraries that get dlopened, not linked
      # ======================================================================
      # Empty, and legitimately so: every tool above comes from nixpkgs already
      # correctly linked, and the one Python dependency is pure Python, so there
      # is no manylinux wheel here carrying a dlopened .so that needs libstdc++
      # put on a search path. Adding entries "just in case" would export a
      # LD_LIBRARY_PATH that can only shadow libraries for host binaries the
      # user launches from this shell.
      #
      # This would change the moment a real wheel enters the picture -- give it
      # pkgs.stdenv.cc.cc.lib and pkgs.zlib then, and no more than that.
      #
      # Note what this could not have fixed anyway: `arduino-cli` downloads a
      # prebuilt avr-gcc, and prebuilt *executables* carry a hardcoded
      # PT_INTERP of /lib64/ld-linux-x86-64.so.2. LD_LIBRARY_PATH does nothing
      # for those -- see the `build` verb.
      nativeLibs = pkgs: [ ];

      # ======================================================================
      # PER-REPO BLOCK 3 -- constant environment variables
      # ======================================================================
      # Only values that are constants belong here. Anything that must READ an
      # existing value (LD_LIBRARY_PATH), UNSET something (SOURCE_DATE_EPOCH) or
      # touch the work tree goes in the shellHook further down.
      #
      # This attrset is applied to BOTH surfaces -- the dev shell and every
      # `nix run` wrapper -- so a command cannot behave differently depending on
      # how it was invoked.
      envVars = pkgs: {
        # python/main.py is a long-running print-heavy poll loop. With stdout on
        # a pipe -- which is exactly how an agent captures it -- Python block
        # buffers and the agent sees nothing at all until the buffer fills or
        # the process is killed. That reads as a hang.
        PYTHONUNBUFFERED = "1";
        # Keeps __pycache__ out of the work tree. This repo is copied wholesale
        # into Noita's mods folder and pushed to the Steam Workshop, so stray
        # generated directories are not merely untidy here.
        PYTHONDONTWRITEBYTECODE = "1";

        # arduino-cli phones home for telemetry and for a "new version
        # available" nag on ordinary commands. Both are pure noise in an agent's
        # captured output. Verified these two env names really do override the
        # config: `arduino-cli config get updater.enable_notification` reports
        # false with the first one set.
        ARDUINO_METRICS_ENABLED = "false";
        ARDUINO_UPDATER_ENABLE_NOTIFICATION = "false";
      };

      # ======================================================================
      # PER-REPO BLOCK 4 -- the command map
      # ======================================================================
      # THE single source of truth. It generates `apps` (so `nix run .#build`
      # works), the `dev-*` wrappers on PATH inside the shell, and `dev-help`.
      # Nothing is written twice, so `nix flake show` can never disagree with
      # what `dev-build` actually runs.
      #
      # `test` is deliberately absent, and the absence is the honest report:
      # this repo has no test suite. python/test_serial.py looks like one and is
      # not -- it is an interactive calibration REPL built on input(), and it
      # needs a tty, an open serial port, a flashed Arduino and a wired-up TENS
      # unit to do anything at all. Wiring it to `test` would give an agent a
      # verb that hangs on a stdin read under `nix run` and, if it did get that
      # far, fires a real electric shock. Add `test` when there are actual
      # tests: `ps.pytest` in the toolchain above and three lines here.
      #
      # Flashing the board is likewise not a verb, because the house vocabulary
      # has no `upload` and inventing one would break the fleet-wide contract.
      # The toolchain can do it in one line when a board is actually attached:
      #   arduino-cli upload -p /dev/ttyUSB0 --fqbn arduino:avr:uno ardu
      commands = pkgs: {
        setup = {
          # Python needs no bootstrap -- nixpkgs supplies pyserial (see the
          # toolchain). This exists purely for the AVR compiler, which
          # arduino-cli fetches at runtime rather than shipping.
          description = "(network) install the Arduino AVR core needed to compile ardu/ardu.ino";
          text = ''
            arduino-cli core update-index
            arduino-cli core install arduino:avr "$@"
          '';
        };
        build = {
          # ardu/ardu.ino is the only artifact this repo compiles; the Lua mod
          # and the Python bridge are both interpreted at their point of use.
          #
          # The sketch never names a board, and arduino-cli requires one, so
          # this picks the Uno -- the sketch only uses digital pins 2/3/4 and
          # Serial at 115200, which every AVR board provides. Override without
          # editing this file: ARDUINO_FQBN=arduino:avr:nano nix run .#build
          description = "compile ardu/ardu.ino (needs `setup`; board via ARDUINO_FQBN, default arduino:avr:uno)";
          text = ''
            arduino-cli compile --fqbn "''${ARDUINO_FQBN:-arduino:avr:uno}" "$REPO_ROOT/ardu" "$@"
          '';
        };
        lint = {
          description = "static checks over init.lua and python/ (non-mutating)";
          text = ''
            # Cheapest gate first, and the most faithful one: this is the exact
            # front end Noita will parse the mod with. Output goes to /dev/null
            # because we want the parse, not the bytecode.
            luajit -b "$REPO_ROOT/init.lua" /dev/null

            # --checklevel=Error is mandatory here, do not drop it. init.lua
            # calls the Noita engine API -- EntityGetWithTag, GamePrint,
            # AddFlagPersistent and friends -- which exists only inside the
            # running game. At the default level lua-language-server reports 13
            # `undefined-global` warnings on a pristine checkout and exits 1,
            # every time, for nothing an agent can fix. That trains an agent to
            # ignore lint. At Error level a pristine checkout passes and real
            # mistakes -- a missing `end`, a malformed expression -- still fail.
            lua-language-server --check "$REPO_ROOT" --checklevel=Error

            # Heads up, so nobody mistakes inherited debt for their own bug:
            # this exits 1 on an untouched checkout. ruff 0.16.2 reports 12
            # pre-existing findings in python/ -- unsorted imports, an unused
            # `array` import in decoder.py, an unused `asyncio` import and an
            # unused `e` binding in test_serial.py, deprecated typing.List,
            # redundant `pass`, and two over-broad handlers (a blind
            # `except Exception` and a bare `except:` in main.py that swallows
            # KeyboardInterrupt along with everything else). All real, none of
            # them yours. Nine are `--fix`-able and this verb forwards
            # arguments, so `nix run .#lint -- --fix` clears those.
            #
            # Expect that count to move when flake.lock is bumped: it is ruff's
            # default rule set, not a pinned selection, and 0.16 already
            # widened it (0.15 found only 4 of these). Deliberately left as the
            # default -- narrowing `--select` until the repo is green would
            # make this verb quiet rather than honest.
            ruff check "$REPO_ROOT/python" "$@"
          '';
        };
        fmt = {
          description = "stylua on init.lua + ruff format on python/ (rewrites files)";
          text = ''
            stylua "$REPO_ROOT/init.lua"
            ruff format "$REPO_ROOT/python" "$@"
          '';
        };
        run = {
          description = "start the Noita-to-serial bridge (needs a serial port; edit python/config.json first)";
          text = ''
            # The cd is required, and this is the one command in the file that
            # does not act on the caller's cwd. python/main.py resolves its
            # config as the bare relative path "config.json", and when it does
            # not find one it *writes a stub* {"flag_path": ""} into whatever
            # directory it was started from and then dies on a KeyError for
            # "time_prefix". So running this from anywhere else does not merely
            # fail, it litters the tree with a broken config that shadows the
            # real one on the next attempt. main.py takes no config argument, so
            # anchoring the cwd is the only fix available from out here.
            cd "$REPO_ROOT/python"
            python main.py "$@"
          '';
        };
      };

      # ======================================================================
      # GENERIC MACHINERY -- byte-identical in all 41 repos, do not edit
      # ======================================================================

      # Prepend, never assign: a host LD_LIBRARY_PATH may be carrying something
      # the user needs, and clobbering it breaks binaries they launch from here.
      # Linux only -- on darwin the loader variable is DYLD_*, and exporting a
      # Linux-shaped value there is at best useless.
      ldPreamble =
        pkgs:
        lib.optionalString (pkgs.stdenv.hostPlatform.isLinux && nativeLibs pkgs != [ ]) ''
          export LD_LIBRARY_PATH="${lib.makeLibraryPath (nativeLibs pkgs)}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        '';

      # Every command gets $REPO_ROOT. `nix run` and `nix develop` both start in
      # whatever directory they were invoked from, so a bare `.venv` silently
      # forks a second environment as soon as an agent works from a subdirectory.
      # Note we do NOT cd there: commands act on the caller's cwd on purpose.
      rootPreamble = ''
        REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
        export REPO_ROOT
      '';

      # One derivation per command, reused by both `apps` and the dev shell, so
      # the two can never diverge. `dev-` prefixed because a bare `test` binary
      # earlier on PATH would shadow the POSIX shell builtin and quietly break
      # every script in the repo that uses it.
      wrappers =
        pkgs:
        lib.mapAttrs (
          name: cmd:
          pkgs.writeShellApplication {
            name = "dev-${name}";
            runtimeInputs = toolchain pkgs;
            runtimeEnv = envVars pkgs;
            meta.description = cmd.description;
            text = ''
              ${rootPreamble}
              ${ldPreamble pkgs}
              ${cmd.text}
            '';
          }
        ) (commands pkgs);

      helpFor =
        pkgs:
        let
          cmds = commands pkgs;
          names = lib.attrNames cmds;
          width = lib.foldl' (a: n: lib.max a (builtins.stringLength n)) 0 names;
          pad = n: n + lib.concatStrings (lib.genList (_: " ") (width - builtins.stringLength n));
          line = n: c: "  dev-${pad n}  ${c.description}";
        in
        pkgs.writeShellApplication {
          name = "dev-help";
          meta.description = "print this repo's command map (works offline)";
          text = ''
            cat <<'EOF'
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList line cmds)}
            EOF
          '';
        };
    in
    {
      # `nix flake show` -- the discovery entrypoint, and deliberately the whole
      # machine-facing contract: every app carries a meta.description, which
      # `nix flake show` prints inline and `nix flake show --json` exposes at
      # .apps.<system>.<name>.description. Pure evaluation, so an agent gets the
      # entire command map in one cheap call without reading a README.
      #
      # Do NOT invent a top-level output for this (`agentManifest`, `probeThing`
      # ...). Nix answers with `warning: unknown flake output '<name>'` on every
      # single `nix flake check`, forever.
      apps = forAllSystems (
        pkgs:
        lib.mapAttrs (name: cmd: {
          type = "app";
          program = "${(wrappers pkgs).${name}}/bin/dev-${name}";
          meta.description = cmd.description;
        }) (commands pkgs)
      );

      # `nix develop` -- the toolchain, plus a dev-<verb> for every app.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = toolchain pkgs ++ lib.attrValues (wrappers pkgs) ++ [ (helpFor pkgs) ];

          env = envVars pkgs;

          # Some C extensions and node-gyp addons compile at -O0, where glibc's
          # _FORTIFY_SOURCE becomes a hard error instead of a warning.
          hardeningDisable = [ "fortify" ];

          shellHook = ''
            # mkShell inherits SOURCE_DATE_EPOCH=315532800 (1980-01-01) from
            # stdenv, and any wheel or zip built in here then dies with "ZIP does
            # not support timestamps before 1980".
            unset SOURCE_DATE_EPOCH

            ${rootPreamble}
            ${ldPreamble pkgs}

            # Nothing networked, nothing stateful and nothing interactive above
            # this line, and nothing below it either. No venv creation, no
            # `npm install`, no `dotnet restore`, no `read`, no `exec $SHELL`.
            # Bootstrapping in the hook makes a cold `nix develop -c pytest`
            # start downloading before it runs anything, on EVERY invocation --
            # the exact failure an unattended agent cannot diagnose. That is what
            # `dev-setup` is for.

            # The banner is interactive-only, and this guard is load-bearing:
            # shellHook output lands on the STDOUT of `nix develop -c <cmd>`, so
            # an unguarded echo corrupts anything parsing it
            # (`nix develop -c cat x.json | jq` fails to parse). $- is the only
            # reliable discriminator here -- it lacks `i` for `nix develop -c`
            # and has it at an interactive prompt. Do not test $PS1 (unset in
            # both) or $IN_NIX_SHELL (set in both). >&2 is the second layer, for
            # the case where a caller runs us on a pty.
            case $- in
              *i*) echo "noita_shock_mod dev shell -- 'dev-help' for the command map" >&2 ;;
            esac
          '';
        };
      });

      # `nix flake check` -- honest by construction. It realises the toolchain
      # closure (so a typo'd or currently-broken attr fails here) and builds
      # every wrapper, which runs shellcheck over every command text. Add real
      # test derivations beside it. NEVER add a check that always passes: an
      # agent reads "all checks passed!" as a signal, and a fake check makes
      # `nix flake check` a liar.
      checks = forAllSystems (pkgs: {
        toolchain =
          pkgs.runCommand "toolchain-check"
            {
              nativeBuildInputs = toolchain pkgs ++ lib.attrValues (wrappers pkgs);
            }
            ''
              for verb in ${lib.escapeShellArgs (lib.attrNames (commands pkgs))}; do
                command -v "dev-$verb" > /dev/null || {
                  echo "dev-$verb is not on PATH" >&2
                  exit 1
                }
              done
              touch "$out"
            '';
      });

      # `nix fmt` -- formats the *Nix* in this repo; project code is `dev-fmt`.
      # nixfmt-tree (the treefmt wrapper) rather than bare nixfmt, because bare
      # nixfmt tries to parse every path handed to it and fails on non-Nix files.
      # This file ships already formatted, so `nix fmt` is a no-op rather than a
      # diff in 41 repos.
      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
