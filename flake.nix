{
  # Keep this line accurate and one line long: `nix flake metadata` prints it,
  # and it is the first thing a cold agent learns about the repo.
  description = "Noita Shock Mod -- Noita Lua mod, Python serial bridge and Arduino TENS firmware. Run `nix flake show` for the command map.";

  # nixpkgs is the only input, on purpose. flake-utils would buy exactly one
  # thing here -- eachDefaultSystem -- and the canonical machinery below already
  # provides it, without a second lock node and a second upstream that can break
  # this repo on its own schedule.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    # `self` is mandatory: the canonical machinery anchors $REPO_ROOT on it.
    # `...` keeps the argument set open, so a second input can be added later
    # without editing this line.
    { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;

      # Printed by the interactive dev-shell banner; nothing else reads it.
      repoName = "noita_shock_mod";

      # ======================================================================
      # PER-REPO BLOCK 1 -- the toolchain
      # ======================================================================
      # Three ecosystems live in this one repo and each needs its own tools:
      #
      #   init.lua        the Noita mod, loaded by the game's embedded Lua
      #   python/         the bridge that reads Noita's flag files and drives
      #                   the Arduino over a serial port
      #   ardu/ardu.ino   the firmware that clicks the TENS unit's relays
      #
      # Explicit `pkgs.foo`, never `with pkgs; [ ... ]`: when an attr disappears
      # in a nixpkgs bump, `with` reports a bare undefined identifier with no
      # hint of which set it came from, and the name is not greppable.
      toolchain = pkgs: [
        # ---- python/ : the Noita-to-serial bridge ----
        #
        # withPackages rather than a uv/pip venv, and this is load-bearing.
        # python/requirements.txt has exactly two lines, `asyncio` and
        # `pyserial`; asyncio is part of the standard library (measured:
        # python3.13 resolves it to .../lib/python3.13/asyncio/__init__.py), so
        # pyserial is the entire real dependency. nixpkgs ships it and it is
        # pure Python (measured: no .so anywhere under site-packages/serial),
        # so this shell needs neither a network nor a bootstrap step.
        #
        # Do NOT "fix" this by adding uv and a `setup` verb that builds a .venv:
        # that trades a shell which works offline for one that must download
        # before it can run anything.
        (pkgs.python313.withPackages (ps: [ ps.pyserial ]))
        pkgs.ruff

        # ---- init.lua : the Noita mod ----
        #
        # luajit, not lua5_4: the Noita wiki's Lua API page documents the game's
        # scripting as Lua 5.1, and LuaJIT is the 5.1-dialect front end in
        # nixpkgs, so `luajit -b` in `lint` parses the mod as the game will
        # (measured: it exits 0 on a pristine init.lua).
        #
        # Never add lua5_4 alongside it. Both ship `bin/lua` (measured), and the
        # two ways of combining them disagree: buildEnv refuses outright with
        # "collision between .../lua-5.4.7/bin/lua and .../luajit-*/bin/lua",
        # while mkShell silently lets one shadow the other (measured: luajit
        # won), so you would be syntax-checking against whichever package
        # happened to come first on PATH.
        pkgs.luajit
        pkgs.lua-language-server
        pkgs.stylua

        # ---- ardu/ardu.ino : the relay firmware ----
        #
        # Measured 504 MiB of closure (`nix path-info -S` on arduino-cli 1.5.1
        # from this flake.lock), and worth it: the repo's own ReadMe TODO -- "Add
        # shock + intensity function in ardu" -- points squarely at this sketch,
        # and without a compiler an agent editing it cannot tell whether its
        # change even builds. See `setup` for what this does NOT bring with it.
        pkgs.arduino-cli

        # ---- general-purpose, used by no verb below ----
        #
        # Measured: this repo has no Makefile, and no command text below shells
        # out to git or jq. They are here for the human or agent at the prompt,
        # not for the command map.
        pkgs.git
        pkgs.jq
        pkgs.gnumake
      ];

      # ======================================================================
      # PER-REPO BLOCK 2 -- libraries that get dlopened, not linked
      # ======================================================================
      # Empty, and legitimately so: every tool above comes from nixpkgs already
      # correctly linked, and the one Python dependency is pure Python (measured
      # above), so there is no manylinux wheel here carrying a dlopened .so that
      # needs libstdc++ put on a search path. Adding entries "just in case"
      # exports an LD_LIBRARY_PATH that can only shadow libraries for host
      # binaries the user launches from this shell.
      #
      # This would change the moment a real wheel enters the picture -- give it
      # pkgs.stdenv.cc.cc.lib and pkgs.zlib then, and no more than that. Both
      # are Linux-only attrs and safe here: the machinery forces nativeLibs on
      # Linux only.
      #
      # Note what an entry here could not have fixed anyway: `setup` downloads a
      # PREBUILT avr-gcc, and a prebuilt executable carries a hardcoded ELF
      # interpreter path -- measured on the one arduino-cli 1.5.1 fetched here,
      # `interpreter /lib64/ld-linux-x86-64.so.2`. LD_LIBRARY_PATH does not
      # affect that path. On this host `build` works because something already
      # provides /lib64/ld-linux-x86-64.so.2 (it is a symlink into a glibc store
      # path); on a NixOS machine without it, `build` fails at exec and no
      # nativeLibs entry will help.
      nativeLibs = pkgs: [ ];

      # ======================================================================
      # PER-REPO BLOCK 3 -- constant environment variables
      # ======================================================================
      # Constants only. Anything that must READ an existing value
      # (LD_LIBRARY_PATH) or UNSET something (SOURCE_DATE_EPOCH) is the
      # machinery's business, not this block's. This attrset is applied to BOTH
      # surfaces -- the dev shell and every `nix run` wrapper -- so a command
      # cannot behave differently depending on how it was invoked.
      envVars = pkgs: {
        # python/main.py is a print-heavy poll loop: `while True` around a 20 ms
        # asyncio.sleep, printing every frame it sends. With stdout on a pipe --
        # which is exactly how an agent captures it -- Python block-buffers and
        # the agent sees nothing at all until the buffer fills, which reads as a
        # hang. Measured with this python3.13: a script that prints and then
        # sleeps 3 s shows nothing through a pipe after 1 s with this variable
        # unset, and shows the line immediately with it set to 1.
        PYTHONUNBUFFERED = "1";
        # Keeps __pycache__ out of the work tree. The ReadMe tells users to drop
        # this repo straight into Noita's mods folder, and it is also published
        # to the Steam Workshop (workshop.xml, workshop_id.txt), so stray
        # generated directories here are not merely untidy.
        PYTHONDONTWRITEBYTECODE = "1";

        # Both keys default to true in arduino-cli 1.5.1 (measured: on a fresh
        # config `arduino-cli config get metrics.enabled` and
        # `... updater.enable_notification` both print `true`). Each variable
        # overrides its own key and only its own key -- measured both ways
        # round: with ARDUINO_METRICS_ENABLED=false, metrics.enabled reads false
        # while updater.enable_notification still reads true. Hence both names:
        # an unattended run should not phone home, and an upgrade nag has no
        # business in an agent's captured output.
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
      # not -- it is an interactive calibration REPL built on input(), whose
      # `shock` command writes a trigger frame that ardu/ardu.ino turns into a
      # pulse on SHOCK_PIN. Measured: with the config the repo ships it never
      # reaches its prompt, it dies in Noita2Serial.__init__ with
      # `SerialException: [Errno 2] could not open port COM6`. Given a real port
      # it would stop at that input() prompt instead, which under `nix run` with
      # no tty is an immediate `EOFError: EOF when reading a line` (measured) --
      # and on a bench with a flashed Arduino and a wired-up TENS unit it fires
      # a real shock. Add `test` when there are actual tests: `ps.pytest` in the
      # toolchain and three lines here.
      #
      # Flashing the board is likewise not a verb, because the house vocabulary
      # (setup / build / test / lint / fmt / run) has no `upload` and inventing
      # one would break the fleet-wide contract. The toolchain can do it in one
      # line when a board is actually attached:
      #   arduino-cli upload -p /dev/ttyUSB0 --fqbn arduino:avr:uno ardu
      commands = pkgs: {
        setup = {
          # Python needs no bootstrap -- nixpkgs supplies pyserial (see the
          # toolchain). This exists purely for the AVR compiler, which
          # arduino-cli fetches at runtime rather than shipping: measured, a
          # `build` before this verb fails with "Platform 'arduino:avr' not
          # found: platform not installed". Writes to arduino-cli's own data
          # directory under $HOME, never to the work tree, so it needs no
          # writable checkout.
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
          # The sketch names no board and arduino-cli requires one (measured: a
          # compile without --fqbn exits 1 with "Missing FQBN (Fully Qualified
          # Board Name)"), so this defaults to the Uno. The sketch drives only
          # digital pins 2/3/4 and Serial at 115200, so any AVR board will do:
          #   ARDUINO_FQBN=arduino:avr:nano nix run .#build
          description = "compile ardu/ardu.ino (needs `setup`; board via ARDUINO_FQBN, default arduino:avr:uno)";
          text = ''
            arduino-cli compile --fqbn "''${ARDUINO_FQBN:-arduino:avr:uno}" "$REPO_ROOT/ardu" "$@"
          '';
        };
        lint = {
          description = "static checks over init.lua and python/ (non-mutating)";
          text = ''
            # Cheapest gate first, and the most faithful one: the same 5.1
            # dialect the game parses the mod with. Output goes to /dev/null
            # because we want the parse, not the bytecode.
            luajit -b "$REPO_ROOT/init.lua" /dev/null

            # --checklevel=Error is mandatory here, do not drop it. init.lua
            # calls the Noita engine API -- EntityGetWithTag, AddFlagPersistent,
            # ComponentGetValueFloat and friends -- which exists only inside the
            # running game. Measured on a pristine checkout with
            # lua-language-server 3.19.0: the default level reports 13 problems,
            # every one of them `undefined-global`, and exits 1; at Error level
            # it reports none and exits 0. Thirteen unfixable warnings on every
            # run is how an agent is trained to ignore lint, while real mistakes
            # -- a missing `end`, a malformed expression -- still fail at Error.
            lua-language-server --check "$REPO_ROOT" --checklevel=Error

            # --no-cache is load-bearing, not tidiness: ruff writes its
            # .ruff_cache into the PROCESS's cwd, not beside the files it was
            # given. Measured -- checking a read-only store path from an
            # unrelated directory left a .ruff_cache in that directory, which is
            # precisely the "verb littered a tree that is not this repo" bug the
            # anchoring machinery exists to prevent.
            #
            # Heads up, so nobody mistakes inherited debt for their own bug:
            # this exits 1 on an untouched checkout. Measured with ruff 0.16.2,
            # the version this flake.lock pins: 12 findings in python/ -- three
            # unsorted import blocks, an unused `array` import in decoder.py, an
            # unused `asyncio` import and an unused `e` binding in
            # test_serial.py, deprecated typing.List (UP035 plus one UP006), two
            # redundant `pass` statements, and two over-broad handlers (a blind
            # `except Exception` and a bare `except:` in main.py that swallows
            # KeyboardInterrupt along with everything else). All real, none of
            # them yours. Nine are `--fix`-able and this verb forwards
            # arguments, so `nix run .#lint -- --fix` clears those.
            #
            # Expect that count to move when flake.lock is bumped: it is ruff's
            # default rule set, not a pinned selection, and 0.16 widened it
            # (measured: ruff 0.15.22 finds 4 of these 12). Deliberately left as
            # the default -- narrowing `--select` until the repo is green would
            # make this verb quiet rather than honest.
            ruff check --no-cache "$REPO_ROOT/python" "$@"
          '';
        };
        fmt = {
          description = "stylua on init.lua + ruff format on python/ (rewrites files)";
          text = ''
            need_writable_checkout
            stylua "$REPO_ROOT/init.lua"
            # --no-cache for the same reason as in `lint`: ruff's cache lands in
            # the caller's cwd, which here can be any subdirectory of the repo.
            ruff format --no-cache "$REPO_ROOT/python" "$@"
          '';
        };
        run = {
          description = "start the Noita-to-serial bridge (needs a serial port; edit python/config.json first)";
          text = ''
            # The cd is required. python/main.py resolves its config as the bare
            # relative path "config.json", and when it does not find one it
            # *writes a stub* {"flag_path": ""} into whatever directory it was
            # started from and then dies with KeyError: 'time_prefix' -- measured
            # in an empty directory, both the stub file and the traceback. So
            # running this from anywhere else does not merely fail, it litters
            # that tree with a broken config that shadows the real one on the
            # next attempt. main.py takes no config argument, so anchoring the
            # cwd is the only fix available from out here.
            cd "$REPO_ROOT/python"
            python main.py "$@"
          '';
        };
      };

      # ======================================================================
      # PER-REPO BLOCK 5 -- checks beyond the canonical two
      # ======================================================================
      # `verbAnchoring` is the per-repo half of the anchoring gate: the
      # canonical `anchoring` check proves the mechanism behaves, this one
      # proves THIS repo's verbs actually use it. It drives the read-only verb
      # (`lint`) and the mutating verb (`fmt`) inside a decoy that carries the
      # marker files a naive anchor would accept for this repo's ecosystems.
      #
      # The decoy's python file is named python/noita_shock_decoy_only.py -- a
      # name this repo does not contain, in the directory `lint` would grade if
      # it adopted the decoy -- and the grep is by NAME rather than by
      # directory: a verb that wrongly adopts the decoy is also standing in it
      # and prints bare relative paths, so grepping for "decoy" would match
      # nothing and the leak would sail through.
      #
      # The second grep proves `lint` graded something real: ruff prints the
      # absolute path of each of its 12 findings, and those paths are inside
      # $SRC_ROOT. If somebody ever fixes all 12, ruff prints no paths and this
      # grep stops matching -- at which point make `lint` name its target
      # instead of deleting the assertion.
      #
      # No exit code is asserted for `lint`: it is non-zero today because of
      # those findings and flips to zero the day they are fixed. Asserting it
      # would turn good news into a broken check.
      extraChecks = pkgs: {
        verbAnchoring =
          pkgs.runCommand "verb-anchoring-check"
            {
              nativeBuildInputs = lib.attrValues (wrappers pkgs);
            }
            ''
              set -euo pipefail

              mkdir -p decoy/python
              cd decoy
              printf 'import os\nx  =1\n' > python/noita_shock_decoy_only.py
              printf 'pyserial\n' > python/requirements.txt
              printf 'Decoy  =  1\n' > init.lua
              printf '{ description = "a different repo"; outputs = _: { }; }\n' > flake.nix
              cp -r . ../decoy.orig

              # Read-only verb: it must grade this repo, not the tree we stand in.
              dev-lint > lint.log 2>&1 || true
              if grep -q noita_shock_decoy_only lint.log; then
                echo "dev-lint graded the decoy" >&2
                cat lint.log >&2
                exit 1
              fi
              if ! grep -q ${lib.escapeShellArg "${self}"} lint.log; then
                echo "dev-lint graded neither the decoy nor this repo" >&2
                cat lint.log >&2
                exit 1
              fi

              # Mutating verb: refusal, not silence, and not a rewrite of the
              # decoy's init.lua.
              if dev-fmt > fmt.log 2>&1; then
                echo "dev-fmt succeeded in a foreign tree; it must refuse" >&2
                exit 1
              fi

              # `*.log`, and every log file must match it -- a file named plainly
              # `log` is not excluded by `--exclude='*.log'` and fails this diff.
              diff -r --exclude='*.log' . ../decoy.orig
              touch "$out"
            '';
      };

      # >>>>> BEGIN CANONICAL MACHINERY v1 <<<<<
      # ======================================================================
      # Everything from the BEGIN sentinel above to the END sentinel on the last
      # line of this file is fleet-canonical text: the same bytes in every repo
      # that carries this flake style. That is a checkable claim, not a boast --
      #
      #   sed -n '/BEGIN CANONICAL MACHINERY v1/,$p' flake.nix | sha256sum
      #
      # prints the same digest in every repo, or one of them has been edited.
      # (`,$p`, not a range ending on the END sentinel: a range whose closing
      # pattern were spelled out here would terminate on this very comment.)
      # Nothing here names a repository, a language, a tool or a project file.
      # If you find such a name below, it is contamination: the fix is to move
      # it into the per-repo section above, never to special-case it here.
      #
      # This region READS exactly these names from the per-repo section:
      #   nixpkgs  self  lib  repoName  toolchain  nativeLibs  envVars
      #   commands  extraChecks
      # and DEFINES exactly these:
      #   systems  forAllSystems  ldPreamble  rootPreamble  guardPreamble
      #   wrappers  helpFor  anchorCheck
      # plus the four flake outputs apps / devShells / checks / formatter.
      # Anything else in scope is invisible to it. The types of those eight
      # inputs, and the shell variables this region exports into command texts,
      # are specified in INTERFACE.md, which travels with this block.
      #
      # To change behaviour here you change it in every repo at once and bump
      # the version in both sentinels. A local edit is a bug by construction:
      # the digest above stops matching, and -- because rootPreamble anchors on
      # flake.nix byte-identity -- an edited working tree also stops being
      # recognised by wrappers built from the previous revision.
      # ======================================================================

      # ---- systems policy: decided once for the whole fleet ----
      #
      # Read this list as "evaluated on three, built on one". That is what was
      # measured, and it is all it means:
      #   * `nix flake check --all-systems` passes, so every output attribute
      #     below EVALUATES on all three systems.
      #   * only x86_64-linux has ever been BUILT. The machine this was verified
      #     on has no aarch64 emulation -- no binfmt handler, and `extra-
      #     platforms` is x86-only -- so aarch64 cannot be built there at all.
      # It is not a statement that anything works on aarch64. Do not upgrade it
      # into one in a README.
      #
      # Evaluating all three is still worth its seconds, because the failure it
      # catches is an eval-time failure: a `pkgs.<attr>` that exists on Linux
      # and not on darwin (`stdenv.cc.cc.lib` is the usual one) throws during
      # evaluation, and `nix flake check` without --all-systems checks only the
      # current system and sails straight past it.
      #
      # x86_64-darwin is deliberately absent. nixpkgs 26.11 replaced that whole
      # attribute set with a `throw`. genAttrs is lazy, so plain `nix develop`
      # on Linux would not notice -- it detonates later, on the --all-systems
      # run this policy requires. Add it back only against a separate
      # nixpkgs-26.05-darwin input.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      # Stand-in for flake-utils.lib.eachDefaultSystem. Passes `pkgs` rather
      # than a system string, because that is what every call site wants, and
      # keeps the system list in this file rather than in a second input's
      # hardcoded copy of it.
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Prepend, never assign: a host LD_LIBRARY_PATH may be carrying something
      # the user needs, and clobbering it breaks binaries they launch from here.
      # Linux only -- on darwin the loader variable is DYLD_*, and exporting a
      # Linux-shaped value there is at best useless.
      #
      # `&&` short-circuits in Nix, so on darwin `nativeLibs pkgs` is never
      # forced. That is load-bearing for the systems policy above: it is what
      # lets a repo list Linux-only attrs in nativeLibs and still evaluate on
      # aarch64-darwin. Do not reorder the two operands.
      ldPreamble =
        pkgs:
        lib.optionalString (pkgs.stdenv.hostPlatform.isLinux && nativeLibs pkgs != [ ]) ''
          export LD_LIBRARY_PATH="${lib.makeLibraryPath (nativeLibs pkgs)}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        '';

      # Every command gets $SRC_ROOT and $REPO_ROOT. `nix run` and `nix develop`
      # both start in whatever directory they were invoked from, and no verb may
      # act on that directory -- these two are what it acts on instead.
      #
      # $SRC_ROOT is this flake's own source, snapshotted into the store when
      # the flake was evaluated. It is the one anchor that is always available:
      # `nix run /path/to/repo#lint` tells the running program nothing whatever
      # about /path/to/repo (flake refs are location-independent by design, and
      # there is no $FLAKE_DIR to read), so without `self` a wrapper invoked
      # that way has literally no way to name the repo it belongs to. Two
      # limitations worth knowing: it is read-only, being a store path, and in a
      # git checkout it contains only TRACKED files.
      #
      # $REPO_ROOT is the writable checkout when the caller is standing in one,
      # and $SRC_ROOT when they are not. Three things this deliberately is NOT:
      #
      #   * NOT `pwd`. A fallback to the caller's directory is how `fmt`
      #     rewrites a stranger's source tree and how `lint` prints "all checks
      #     passed" having read none of this repo.
      #   * NOT `git rev-parse --show-toplevel`. Run from inside some OTHER git
      #     repo it cheerfully answers with THAT repo's top level. It also needs
      #     git on PATH and a .git directory, so it fails on an export and in
      #     any wrapper whose toolchain omits git.
      #   * NOT an inherited $REPO_ROOT from the environment. The dev shell
      #     EXPORTS this variable, so honouring it would mean that running
      #     `nix run /path/to/B#fmt` from inside repo A's dev shell points B's
      #     formatter at A. An explicit path argument is how a caller overrides
      #     a verb's target; an ambient variable is how they do it by accident.
      #
      # Instead: walk up from $PWD and take the first ancestor that IS this
      # repo, proved by carrying a byte-identical flake.nix. A single tracked
      # filename, a marker directory, or a set of them is not proof -- sibling
      # repos in a fleet share those, and a decoy can be built to carry any list
      # of names you care to publish. The whole flake.nix is what distinguishes
      # repos, because description, toolchain and command map all differ, so the
      # whole flake.nix is what gets compared. Compared with bash's own
      # `$(<file)` rather than cmp or sha256sum, so the check depends on no
      # package at all -- pure builtins, correct even in a wrapper whose PATH
      # carries nothing but the repo's own toolchain.
      #
      # Consequence worth knowing: edit flake.nix and the dev-* wrappers in an
      # already-open `nix develop` stop recognising the tree, because they were
      # built from the previous flake.nix. That is a stale shell telling you so
      # -- re-enter it. `nix run` re-evaluates every time and never sees this.
      rootPreamble = ''
        SRC_ROOT=${lib.escapeShellArg "${self}"}
        export SRC_ROOT

        _dev_find_root() {
          local dir ref
          ref=$(<"$SRC_ROOT/flake.nix") || return 1
          dir=$(
            unset CDPATH
            cd -P -- "''${1:-.}" 2>/dev/null && pwd
          ) || return 1
          while [ -n "$dir" ]; do
            if [ -f "$dir/flake.nix" ] && [ "$(<"$dir/flake.nix")" = "$ref" ]; then
              printf '%s\n' "$dir"
              return 0
            fi
            dir=''${dir%/*}
          done
          return 1
        }

        REPO_ROOT="$(_dev_find_root "$PWD" || printf '%s\n' "$SRC_ROOT")"
        export REPO_ROOT
      '';

      # Wrappers only, not the shellHook -- an interactive shell has no business
      # carrying this function around. Any command text that writes files calls
      # it first, and it is the reason a mutating verb can fail loudly instead
      # of falling back to "well, the cwd then".
      #
      # The test is $REPO_ROOT != $SRC_ROOT, i.e. "rootPreamble found a real
      # checkout", not a permission or a store-path-prefix test. Both of those
      # answer a narrower question: a checkout may be read-only for unrelated
      # reasons, and a store path is not the only tree we must refuse to write.
      guardPreamble = ''
        need_writable_checkout() {
          if [ "$REPO_ROOT" != "$SRC_ROOT" ]; then
            return 0
          fi
          echo "''${0##*/}: this command rewrites files, so it needs a writable" >&2
          echo "checkout of this repo -- and standing in $PWD there is none: no" >&2
          echo "parent directory carries this flake's flake.nix. The only tree in" >&2
          echo "reach is the read-only store snapshot $SRC_ROOT, and rewriting" >&2
          echo "$PWD instead is exactly the bug this guard exists to prevent." >&2
          echo "cd into the repo (or \`nix develop\` it), or pass an explicit path." >&2
          exit 1
        }
      '';

      # One derivation per command, reused by both `apps` and the dev shell, so
      # the two can never diverge. `dev-` prefixed because a bare `test` binary
      # earlier on PATH would shadow the POSIX shell builtin and quietly break
      # every script in the repo that uses it.
      #
      # writeShellApplication, not writeShellScriptBin: it runs shellcheck at
      # BUILD time and sets `set -euo pipefail`, so an unquoted $@ or a silently
      # ignored failure is a `nix flake check` failure rather than a surprise in
      # front of an agent.
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
              ${guardPreamble}
              ${ldPreamble pkgs}
              ${cmd.text}
            '';
          }
        ) (commands pkgs);

      # `dev-help` is generated from the same attrset as everything else, so it
      # cannot describe a verb that does not exist or miss one that does. No
      # runtimeInputs: printing the map must work with nothing installed.
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

      # The regression gate for rootPreamble and guardPreamble, which are the
      # two pieces of this flake that can silently damage a tree that is not
      # this repo. It tests the MECHANISM, not any verb, which is precisely what
      # makes it fleet-generic: it needs to know nothing about what this repo
      # does, only that the anchor resolves and the guard refuses.
      #
      # The decoy is a real directory carrying a real flake.nix that differs.
      # Marker-file anchors pass a decoy like this -- that is the whole point of
      # the probe -- and so does any anchor that trusts `pwd`. Probe 2 is the
      # other half, and without it a guard that refused everything would score a
      # perfect pass: a tree that IS byte-identical must still be adopted, or
      # every mutating verb in the repo is dead. Probe 3 pins the subdirectory
      # case, which is the normal one for an agent working inside a repo.
      #
      # A per-repo probe that drives the actual verbs is strictly better and
      # cannot live here -- it has to know which verb writes and which needs a
      # network. INTERFACE.md shows how to add one via `extraChecks`.
      anchorCheck =
        pkgs:
        pkgs.runCommand "anchor-check" { } ''
          set -euo pipefail

          # The two preambles under test, verbatim, in a file the probes source.
          # A quoted heredoc, so every $ below is the bash the wrappers see.
          cat > preamble.sh <<'CANONICAL_PREAMBLE_EOF'
          ${rootPreamble}
          ${guardPreamble}
          CANONICAL_PREAMBLE_EOF

          mkdir decoy
          printf '{\n  description = "a different repo";\n  outputs = _: { };\n}\n' > decoy/flake.nix
          printf 'do not touch me\n' > decoy/victim.txt
          cp -r decoy decoy.orig

          # ---- probe 1: a foreign tree must not be adopted ----
          if ! ( cd decoy && . ../preamble.sh && [ "$REPO_ROOT" = "$SRC_ROOT" ] ); then
            echo "anchor adopted a directory that is not this repo" >&2
            exit 1
          fi
          # In a subshell: need_writable_checkout ends in `exit`, which would
          # otherwise take this whole build down instead of failing a condition.
          if ( cd decoy && . ../preamble.sh && need_writable_checkout ) > guard.log 2>&1; then
            echo "need_writable_checkout accepted a tree that is not this repo" >&2
            exit 1
          fi
          if ! diff -r decoy decoy.orig; then
            echo "the probes modified the foreign tree" >&2
            exit 1
          fi

          # ---- probe 2: a byte-identical checkout must be adopted ----
          cp -r ${lib.escapeShellArg "${self}"} checkout
          chmod -R u+w checkout
          if ! ( cd checkout && . ../preamble.sh &&
                 [ "$REPO_ROOT" = "$(pwd -P)" ] && need_writable_checkout ); then
            echo "anchor refused a byte-identical checkout of this repo" >&2
            exit 1
          fi

          # ---- probe 3: from a subdirectory, still the checkout root ----
          mkdir -p checkout/probe3/deeper
          if ! ( cd checkout/probe3/deeper && . ../../../preamble.sh &&
                 [ "$REPO_ROOT" = "$(cd -P ../.. && pwd)" ] ); then
            echo "anchor did not walk up to the checkout root from a subdirectory" >&2
            exit 1
          fi

          touch "$out"
        '';
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

          # Natively-compiled extension modules are routinely built at -O0,
          # where glibc's _FORTIFY_SOURCE stops being a warning and becomes a
          # hard error.
          hardeningDisable = [ "fortify" ];

          shellHook = ''
            # mkShell inherits SOURCE_DATE_EPOCH=315532800 (1980-01-01) from
            # stdenv, and any wheel or zip built in here then dies with "ZIP does
            # not support timestamps before 1980".
            unset SOURCE_DATE_EPOCH

            # $REPO_ROOT and $SRC_ROOT are exported here as a convenience for
            # the human at the prompt. Every wrapper re-resolves them from
            # scratch and none of them reads these, on purpose: a stale value
            # exported by one repo's shell must never steer another repo's verb.
            ${rootPreamble}
            ${ldPreamble pkgs}

            # Nothing networked, nothing stateful and nothing interactive above
            # this line, and nothing below it either. No environment
            # bootstrapping, no dependency installation, no `read`, no
            # `exec $SHELL`. Bootstrapping in the hook makes a cold
            # `nix develop -c <anything>` start downloading before it runs
            # anything, on EVERY invocation -- the exact failure an unattended
            # agent cannot diagnose. That is what a `setup` verb is for.

            # The banner is interactive-only, and this guard is load-bearing:
            # shellHook output lands on the STDOUT of `nix develop -c <cmd>`, so
            # an unguarded echo corrupts anything parsing it
            # (`nix develop -c cat x.json | jq` fails to parse). $- is the only
            # reliable discriminator here -- it lacks `i` for `nix develop -c`
            # and has it at an interactive prompt. Do not test $PS1 (unset in
            # both) or $IN_NIX_SHELL (set in both). >&2 is the second layer, for
            # the case where a caller runs us on a pty.
            case $- in
              *i*) echo "${repoName} dev shell -- 'dev-help' for the command map" >&2 ;;
            esac
          '';
        };
      });

      # `nix flake check` -- honest by construction, and the only gate this
      # style has. `toolchain` realises the whole toolchain closure (so a typo'd
      # or currently-broken attr fails here, not halfway through a task) and
      # builds every wrapper, which runs shellcheck over every command text.
      # `anchoring` is the regression test described above.
      #
      # Repo-specific checks go in `extraChecks`, never here. They may not
      # shadow either canonical name: silently replacing `anchoring` with
      # something weaker is the exact failure this whole file exists to make
      # impossible, so a collision is an eval error with both names in it.
      #
      # NEVER add a check that always passes. An agent reads "all checks
      # passed!" as a signal, and a fake check makes `nix flake check` a liar.
      checks = forAllSystems (
        pkgs:
        let
          canonical = {
            toolchain =
              pkgs.runCommand "toolchain-check"
                {
                  nativeBuildInputs = toolchain pkgs ++ lib.attrValues (wrappers pkgs) ++ [ (helpFor pkgs) ];
                }
                ''
                  set -euo pipefail
                  dev-help > help.txt

                  # A while-read over a heredoc rather than `for x in <list>`,
                  # which is a bash syntax error when the list is empty -- and a
                  # repo with no verbs yet is a legitimate state.
                  while IFS= read -r verb; do
                    [ -n "$verb" ] || continue
                    command -v "dev-$verb" > /dev/null || {
                      echo "dev-$verb is not on PATH" >&2
                      exit 1
                    }
                    grep -q -- "dev-$verb" help.txt || {
                      echo "dev-$verb is missing from the dev-help map" >&2
                      exit 1
                    }
                  done <<'CANONICAL_VERBS_EOF'
                  ${lib.concatStringsSep "\n" (lib.attrNames (commands pkgs))}
                  CANONICAL_VERBS_EOF

                  touch "$out"
                '';
            anchoring = anchorCheck pkgs;
          };
          extra = extraChecks pkgs;
          clash = lib.intersectLists (lib.attrNames canonical) (lib.attrNames extra);
        in
        if clash != [ ] then
          throw "extraChecks must not redefine canonical checks: ${lib.concatStringsSep ", " clash}"
        else
          canonical // extra
      );

      # `nix fmt` -- formats the *Nix* in this repo; project code gets a `fmt`
      # verb. nixfmt-tree (the treefmt wrapper) rather than bare nixfmt, because
      # bare nixfmt tries to parse every path handed to it and fails on non-Nix
      # files. This file ships already formatted, so `nix fmt` is a no-op rather
      # than a diff across the fleet.
      #
      # This is the one verb here NOT anchored to $REPO_ROOT, and it cannot be:
      # `nix fmt` is nix's own verb, and nix -- not this flake -- decides which
      # paths the formatter receives, passing the cwd when the user names none.
      # A wrapper that overrode them would break `nix fmt path/to/one/file.nix`,
      # and it cannot tell that "." apart from the default. So `nix fmt` formats
      # where you stand, by design; the `fmt` verb is the anchored one.
      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
# >>>>> END CANONICAL MACHINERY v1 <<<<<
