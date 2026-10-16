#!/usr/bin/env bash
# Container sandbox runner for herdr #5333 repros.
# Usage: sbx.sh <subcommand> [args...]
#   cp        - copy the host release binary into the container
#   server    - start the headless server on an isolated socket/HOME
#   stop      - stop the sandbox server
#   cli ARGS  - run ./herdr CLI args inside the sandbox env
#   sh CMD    - run a shell command inside the sandbox env
#   ready     - wait until the sandbox socket accepts connections
set -u
CT=herdr-sandbox
HBIN=/herdr
SHOME=/tmp/herdr-home
SOCK=/tmp/herdr-home/herdr.sock

docker_env() {
  echo "-e HOME=$SHOME -e HERDR_SOCKET_PATH=$SOCK -e HERDR_CLIENT_SOCKET_PATH=$SHOME/herdr-client.sock -w $SHOME"
}

cmd_cp() {
  local bin="${1:-target/release/herdr}"
  docker cp "$bin" "$CT:$HBIN" >/dev/null
  docker exec "$CT" chmod +x "$HBIN"
  echo "copied $bin -> $CT:$HBIN"
}

cmd_server() {
  docker exec -d $(docker_env) "$CT" "$HBIN" server
  echo "server started (detached)"
}

cmd_ready() {
  for _ in $(seq 1 100); do
    if docker exec "$CT" test -S "$SOCK"; then
      if docker exec -e HOME=$SHOME -e HERDR_SOCKET_PATH=$SOCK "$CT" \
           python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.settimeout(1); s.connect(sys.argv[1]); s.close()" "$SOCK" 2>/dev/null; then
        echo "server ready at $SOCK"
        return 0
      fi
    fi
    sleep 0.2
  done
  echo "server never became ready" >&2
  return 1
}

cmd_stop() {
  docker exec $(docker_env) "$CT" "$HBIN" server stop >/dev/null 2>&1 || true
  echo "stop requested"
}

cmd_cli() {
  docker exec -i $(docker_env) "$CT" "$HBIN" "$@"
}

cmd_sh() {
  docker exec -i $(docker_env) "$CT" sh -c "$*"
}

case "${1:-}" in
  cp) shift; cmd_cp "$@" ;;
  server) cmd_server ;;
  ready) cmd_ready ;;
  stop) cmd_stop ;;
  cli) shift; cmd_cli "$@" ;;
  sh) shift; cmd_sh "$@" ;;
  *) echo "usage: $0 {cp|server|ready|stop|cli|sh}" >&2; exit 2 ;;
esac
