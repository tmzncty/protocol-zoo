#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
[ "$#" -le 1 ] || {
  echo 'usage: scripts/kali-remaining-capture.sh [captures/output-directory]' >&2
  exit 2
}
if [ "$#" -eq 1 ]; then
  OUT=$1
else
  OUT=captures/kali-remaining
fi
# shellcheck source=scripts/lib/capture-path.sh
. "$ROOT/scripts/lib/capture-path.sh"
pz_require_capture_path "$ROOT" "$OUT" directory
OUT_DIR=$PZ_CAPTURE_PATH
OUT=$PZ_CAPTURE_RELATIVE
pz_require_capture_children "$ROOT" "$OUT" \
  udplite.pcapng \
  gre.pcapng \
  ipip.pcapng
KEYDIR=${PZ_KALI_KEYDIR:-/media/tmzn/DATA5/qemu_vms/protocol-zoo-kali}
HOST=${PZ_KALI_HOST:-172.31.250.195}
for tool in mktemp mv scp ssh; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "missing required command: $tool" >&2
    exit 1
  }
done
[ -r "$KEYDIR/id_ed25519" ] || {
  echo "missing Kali key: $KEYDIR/id_ed25519" >&2
  exit 1
}
STAGE=
COMMITTED=false
PUBLISHED=
CLEANING=false
PENDING_SIGNAL_STATUS=
cleanup_remove() {
  cleanup_remove_target=$2
  cleanup_remove_pending_before=$PENDING_SIGNAL_STATUS
  if rm "$@"; then
    return 0
  fi
  if [ ! -e "$cleanup_remove_target" ] && \
    [ ! -L "$cleanup_remove_target" ]; then
    return 0
  fi
  if [ -z "$cleanup_remove_pending_before" ] && \
    [ -n "$PENDING_SIGNAL_STATUS" ]; then
    if rm "$@"; then
      return 0
    fi
    [ ! -e "$cleanup_remove_target" ] && \
      [ ! -L "$cleanup_remove_target" ] && return 0
  fi
  return 1
}
cleanup_move() {
  cleanup_move_source=$1
  cleanup_move_destination=$2
  cleanup_move_pending_before=$PENDING_SIGNAL_STATUS
  if mv "$cleanup_move_source" "$cleanup_move_destination"; then
    return 0
  fi
  if [ ! -e "$cleanup_move_source" ] && \
    [ -f "$cleanup_move_destination" ]; then
    return 0
  fi
  if [ -z "$cleanup_move_pending_before" ] && \
    [ -n "$PENDING_SIGNAL_STATUS" ] && \
    [ -e "$cleanup_move_source" ]; then
    if mv "$cleanup_move_source" "$cleanup_move_destination"; then
      return 0
    fi
    [ ! -e "$cleanup_move_source" ] && \
      [ -f "$cleanup_move_destination" ] && return 0
  fi
  return 1
}
cleanup() {
  [ "$CLEANING" != true ] || return 0
  CLEANING=true
  cleanup_status=0
  if [ -n "$STAGE" ]; then
    rollback_ok=true
    if [ "$COMMITTED" != true ]; then
      for name in udplite.pcapng gre.pcapng ipip.pcapng; do
        backup=$STAGE/.previous.$name
        case " $PUBLISHED " in
          *" $name "*)
            cleanup_remove -f "$OUT_DIR/$name" || rollback_ok=false
            ;;
        esac
        if [ -e "$backup" ]; then
          if ! cleanup_move "$backup" "$OUT_DIR/$name"; then
            echo "unable to restore previous Kali remaining artifact: $name" >&2
            rollback_ok=false
          fi
        fi
      done
    fi
    if [ "$rollback_ok" = true ]; then
      if cleanup_remove -rf "$STAGE"; then
        STAGE=
        PUBLISHED=
      else
        echo "unable to remove failed Kali remaining staging directory: $STAGE" >&2
        rollback_ok=false
      fi
    fi
    if [ "$rollback_ok" != true ]; then
      echo "retained failed Kali remaining staging directory: $STAGE" >&2
      cleanup_status=1
    fi
  fi
  if [ -z "$STAGE" ]; then
    CLEANING=false
  fi
  if [ -n "$PENDING_SIGNAL_STATUS" ]; then
    signal_status=$PENDING_SIGNAL_STATUS
    PENDING_SIGNAL_STATUS=
    CLEANING=false
    exit "$signal_status"
  fi
  return "$cleanup_status"
}
handle_signal() {
  PENDING_SIGNAL_STATUS=$1
  trap - EXIT
  trap '' HUP INT TERM
  if [ "$CLEANING" = true ]; then
    return 0
  fi
  cleanup
  exit "$1"
}
publish() {
  source=$1
  name=$2
  if [ -e "$OUT_DIR/$name" ]; then
    mv "$OUT_DIR/$name" "$STAGE/.previous.$name"
  fi
  PUBLISHED="$PUBLISHED $name"
  mv "$source" "$OUT_DIR/$name"
}
trap cleanup EXIT
trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 143' TERM

mkdir -p "$OUT_DIR"
# The parent trap must receive signals, but the creator must survive long
# enough to return the pathname of any directory it creates. Otherwise a
# signal between mkdir(2) and command-substitution output makes cleanup blind.
STAGE=$(
  trap '' HUP INT TERM
  exec mktemp -d "$OUT_DIR/.kali-remaining.XXXXXX"
)

scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/pz-known-hosts \
  -o ConnectTimeout=8 -i "$KEYDIR/id_ed25519" \
  "$ROOT/scripts/guest/remaining.sh" \
  "root@$HOST:/tmp/protocol-zoo-remaining.sh"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/pz-known-hosts \
  -o ConnectTimeout=8 -i "$KEYDIR/id_ed25519" \
  "root@$HOST" bash /tmp/protocol-zoo-remaining.sh
for f in udplite gre ipip; do
  scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/tmp/pz-known-hosts \
    -i "$KEYDIR/id_ed25519" \
    "root@$HOST:/root/pz-remaining/$f.pcapng" "$STAGE/$f.pcapng"
done

for file in "$STAGE/udplite.pcapng" "$STAGE/gre.pcapng" \
  "$STAGE/ipip.pcapng"; do
  if [ -L "$file" ] || [ ! -f "$file" ] || [ ! -s "$file" ]; then
    echo "invalid staged Kali remaining artifact: $file" >&2
    exit 1
  fi
done

for f in udplite gre ipip; do
  publish "$STAGE/$f.pcapng" "$f.pcapng"
done
COMMITTED=true
cleanup
trap - EXIT HUP INT TERM
