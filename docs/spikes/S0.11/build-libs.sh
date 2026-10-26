#!/usr/bin/env sh
# S0.11: compile the pinned SQLite amalgamation three ways.
#   build-libs.sh <dir with sqlite3.c> <out dir>
# CC=gcc picks another compiler on Linux and macOS.
# Writes <out>/{default,tuned,tuned_nofts}/sqlite3.{lib|a} and build.txt.
# Windows (Git Bash): clang -fms-runtime-lib=static + llvm-lib -> sqlite3.lib.
# Linux and macOS: clang + ar -> sqlite3.a.
set -e
CC=${CC:-clang} # Linux and macOS only; Windows always uses clang here
src=$1; out=$2
TUNED="-DSQLITE_DQS=0 -DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DSQLITE_THREADSAFE=2 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_ENABLE_FTS5"
NOFTS="-DSQLITE_DQS=0 -DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DSQLITE_THREADSAFE=2 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_SHARED_CACHE"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) win=1 ;;
  *) win=0 ;;
esac
one() { # <name> <defines...>
  name=$1; shift
  d="$out/$name"; mkdir -p "$d"
  t0=$(date +%s)
  if [ $win = 1 ]; then
    clang -O2 -c -fms-runtime-lib=static "$@" "$src/sqlite3.c" -o "$d/sqlite3.obj"
    (cd "$d" && llvm-lib -nologo -out:sqlite3.lib sqlite3.obj && rm -f sqlite3.obj)
  else
    "$CC" -O2 -c "$@" "$src/sqlite3.c" -o "$d/sqlite3.o"
    ar rcs "$d/sqlite3.a" "$d/sqlite3.o"
    rm -f "$d/sqlite3.o"
  fi
  t1=$(date +%s)
  echo "$name $( [ $win = 1 ] && echo clang || echo "$CC") -O2 $* : $((t1 - t0)) s" | tee "$d/build.txt"
}
one default
# shellcheck disable=SC2086
one tuned $TUNED
# shellcheck disable=SC2086
one tuned_nofts $NOFTS
