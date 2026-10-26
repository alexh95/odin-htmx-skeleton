# Sourced by run.sh and lib/parity.sh.
#
# The first port from $1 that nothing listens on. On Windows a server binds a
# taken port without an error while the other listener keeps answering (WSL's
# relay holds some), so k6 would measure that instead. Asked of the socket
# table, not with a request: Windows takes 2 s to refuse a closed port.
case "$(uname -s)" in
  *MINGW*|*MSYS*|*CYGWIN*) listening() { netstat -an -p tcp | grep -Eq "(127\.0\.0\.1|0\.0\.0\.0):$1 .*LISTENING"; } ;;
  *) listening() { ss -ltn | grep -Eq "[:.]$1 "; } ;;
esac
free_port() {
  p="$1"
  while listening "$p"; do p=$((p + 1)); done
  echo "$p"
}
