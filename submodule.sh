#!/bin/sh
#
# Adam Sharp
# Aug 21, 2013
#
# Usage: Add it to your PATH and `git remove-submodule path/to/submodule`.
#
# Does the inverse of `git submodule add`:
#  1) `deinit` the submodule
#  2) Remove the submodule from the index and working directory
#  3) Clean up the .gitmodules file
#

# Adapted from: https://gist.githubusercontent.com/sharplet/6289697/raw/2490096d3adb1139cd130faf70a69ed3537ce19e/git-remove-submodule

path=$(echo "$1" | sed 's/\/$//'); shift

exit_err() {
  [ $# -gt 0 ] && echo "fatal: $*" 1>&2
  exit 1
}

if git submodule status "$path" >/dev/null 2>&1; then
  git submodule deinit -f "$path"
  git rm --cached $path
  rm -rf .git/modules/$path
  git commit -m "Removed submodule $path"
  git rm -f "$path"
#  git reset HEAD .gitmodules

  git config -f .gitmodules --remove-section "submodule.$path"
  if [ -z "$(cat .gitmodules)" ]; then
    git rm -f .gitmodules
  else
    git add .gitmodules
  fi
else
  exit_err "Submodule '$path' not found"
fi
