#!/bin/bash
# Command Line Tools ship Swift Testing outside the default search paths.
set -euo pipefail
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
exec swift test -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F \
  -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
