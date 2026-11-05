#!/bin/sh
# vp-frames for Unix-style shells on Windows: Claude Code in WSL or in Git Bash. Runs the Windows app's own
# Electron with Windows paths, so Claude needs nothing installed. Same arguments as vp-frames. In WSL it
# prints the frames as WSL paths. (Git Bash can't use vp-frames.cmd: cmd splits its path at spaces.)
set -eu
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) to_win() { cygpath -w "$1"; }; from_win() { printf '%s\n' "$1"; } ;;
  *)
    to_win() { wslpath -w "$1"; }
    from_win() { wslpath -u "$1"; }
    # Hands ELECTRON_RUN_AS_NODE to the Windows program.
    export WSLENV="${WSLENV:+$WSLENV:}ELECTRON_RUN_AS_NODE"
    ;;
esac
here="$(dirname "$(readlink -f "$0")")"
electron="$here/../../../Video Prompt.exe"                                     # installed: resources/app/bin
[ -f "$electron" ] || electron="$here/../node_modules/electron/dist/electron.exe"  # from source
script="$(to_win "$here/../dist/frames/main.js")"

# The video and the --out folder are paths, so Electron gets their Windows form. The rest passes through.
next=""
seen_video=0
n=$#
while [ "$n" -gt 0 ]; do
  a="$1"
  shift
  n=$((n - 1))
  if [ "$next" = value ]; then
    set -- "$@" "$a"
    next=""
  elif [ "$next" = out ]; then
    mkdir -p "$a"
    set -- "$@" "$(to_win "$a")"
    next=""
  else
    case "$a" in
      --out) set -- "$@" "$a"; next=out ;;
      --from | --to | --fps) set -- "$@" "$a"; next=value ;;
      --*) set -- "$@" "$a" ;;
      *)
        if [ "$seen_video" = 0 ]; then
          set -- "$@" "$(to_win "$a")"
          seen_video=1
        else
          set -- "$@" "$a"
        fi
        ;;
    esac
  fi
done

# Errors go straight to stderr, and a failure keeps its exit code.
frames="$(ELECTRON_RUN_AS_NODE=1 "$electron" "$script" "$@")"
printf '%s\n' "$frames" | tr -d '\r' | while IFS= read -r line; do
  [ -n "$line" ] && from_win "$line"
done
