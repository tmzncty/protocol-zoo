#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/protocol-zoo-kali-wrappers.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

FIXTURE=$TMP/repo
BIN=$TMP/bin
KEYDIR=$TMP/key
EFFECT_LOG=$TMP/effects.log
mkdir -p "$FIXTURE/scripts/lib" "$FIXTURE/scripts/guest" \
  "$FIXTURE/schemas" "$FIXTURE/captures" "$BIN" "$KEYDIR" "$TMP/caller"
cp "$ROOT/scripts/kali-sctp-capture.sh" \
  "$ROOT/scripts/kali-remaining-capture.sh" \
  "$ROOT/scripts/experiment.sh" "$FIXTURE/scripts/"
cp "$ROOT/scripts/lib/capture-path.sh" "$FIXTURE/scripts/lib/"
cp "$ROOT/scripts/guest/sctp.sh" "$ROOT/scripts/guest/remaining.sh" \
  "$FIXTURE/scripts/guest/"
cp "$ROOT/schemas/experiment.schema.json" "$FIXTURE/schemas/"
printf 'test key\n' >"$KEYDIR/id_ed25519"
FIXTURE=$(CDPATH='' cd -- "$FIXTURE" && pwd -P)
SH_BIN=${PZ_TEST_SHELL:-$(command -v sh)}
PYTHON_BIN=${PZ_TEST_PYTHON:-$(command -v python || command -v python3)}
REAL_MV=$(command -v mv)
REAL_RM=$(command -v rm)
REAL_MKTEMP=$(command -v mktemp)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

cat >"$BIN/python3" <<'EOF'
#!/bin/sh
exec "${PZ_TEST_PYTHON:?}" "$@"
EOF

cat >"$BIN/ssh" <<'EOF'
#!/bin/sh
printf 'ssh|%s\n' "$*" >>"${PZ_EFFECT_LOG:?}"
[ "${PZ_FAIL_SSH-}" != 1 ] || exit 71
exit 0
EOF

cat >"$BIN/mv" <<'EOF'
#!/bin/sh
count_file=${PZ_MV_COUNT_FILE:?}
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
[ "${PZ_FAIL_MV_CALL-}" != "$count" ] || exit 75
[ "${PZ_FAIL_MV_CALL_SECOND-}" != "$count" ] || exit 75
if [ "${PZ_GROUP_SIGNAL_MV_CALL-}" = "$count" ]; then
  kill -"${PZ_GROUP_SIGNAL:?}" "$PPID"
  kill -"$PZ_GROUP_SIGNAL" "$$"
fi
if [ "${PZ_SIGNAL_MV_CALL-}" = "$count" ]; then
  "${PZ_REAL_MV:?}" "$@"
  kill -TERM "$PPID"
  exit 0
fi
exec "${PZ_REAL_MV:?}" "$@"
EOF

cat >"$BIN/rm" <<'EOF'
#!/bin/sh
count_file=${PZ_RM_COUNT_FILE:?}
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
[ "${PZ_FAIL_RM_CALL-}" != "$count" ] || exit 76
if [ "${PZ_SIGNAL_RM_CALL-}" = "$count" ]; then
  kill -"${PZ_RM_SIGNAL:?}" "$PPID"
  kill -"$PZ_RM_SIGNAL" "$$"
fi
exec "${PZ_REAL_RM:?}" "$@"
EOF

cat >"$BIN/mktemp" <<'EOF'
#!/bin/sh
stage=$("${PZ_REAL_MKTEMP:?}" "$@") || exit
if [ -n "${PZ_ABORT_MKTEMP_SIGNAL-}" ]; then
  printf '%s\n' "$stage" >"${PZ_STAGE_RECORD:?}"
  kill -"$PZ_ABORT_MKTEMP_SIGNAL" "$PPID"
  kill -"$PZ_ABORT_MKTEMP_SIGNAL" "$$"
  sleep 1
fi
printf '%s\n' "$stage"
if [ "${PZ_SIGNAL_MKTEMP-}" = 1 ]; then
  kill -TERM "$PPID"
fi
EOF

cat >"$BIN/scp" <<'EOF'
#!/bin/sh
printf 'scp|%s\n' "$*" >>"${PZ_EFFECT_LOG:?}"
count_file=${PZ_SCP_COUNT_FILE:?}
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
[ "${PZ_FAIL_SCP_CALL-}" != "$count" ] || exit 72

source_path=
destination=
for argument do
  destination=$argument
  case "$argument" in root@*:*) source_path=$argument ;; esac
done
remote_file=${source_path##*/}

materialize() {
  shape=$1
  destination=$2
  case "$shape" in
    file) printf 'packet evidence\n' >"$destination" ;;
    empty) : >"$destination" ;;
    missing) ;;
    directory) mkdir -p "$destination" ;;
    link)
      printf 'outside evidence\n' >"${PZ_OUTSIDE_FILE:?}"
      ln -s "$PZ_OUTSIDE_FILE" "$destination"
      ;;
    *) printf 'unknown mock artifact shape: %s\n' "$shape" >&2; exit 73 ;;
  esac
}

case "$remote_file" in
  pz-sctp.pcap)
    materialize "${PZ_SCTP_PCAP_SHAPE:-file}" "$destination"
    ;;
  pz-sctp.json)
    case "${PZ_SCTP_JSON_SHAPE:-valid}" in
      valid)
        cat >"$destination" <<'JSON'
{"protocol":"sctp","experiment":"phase-6-sctp-netns-kali","evidence_level":"real-capture","environment":{"os":"kali","kernel":"test","topology":"nested-netns-veth"},"capture_point":"pz-b:pz-veth-b","command":"/root/pz-sctp.sh","capture_filter":"sctp port 19090","result":{"handshake":"pass","capture":"/root/pz-sctp.pcap","frames":1,"future_field":"preserved"},"sanitized":true,"notes":[]}
JSON
        ;;
      empty) : >"$destination" ;;
      whitespace) printf '  \n' >"$destination" ;;
      missing) ;;
      directory) mkdir -p "$destination" ;;
      link)
        printf '{}\n' >"${PZ_OUTSIDE_FILE:?}"
        ln -s "$PZ_OUTSIDE_FILE" "$destination"
        ;;
      null) printf 'null\n' >"$destination" ;;
      array) printf '[]\n' >"$destination" ;;
      scalar) printf '1\n' >"$destination" ;;
      missing-result) printf '{"protocol":"sctp"}\n' >"$destination" ;;
      schema-missing) printf '{"result":{}}\n' >"$destination" ;;
      null-result) printf '{"result":null}\n' >"$destination" ;;
      array-result) printf '{"result":[]}\n' >"$destination" ;;
      malformed) printf '{"result":\n' >"$destination" ;;
      multiple) printf '{"result":{}}\n{"result":{}}\n' >"$destination" ;;
      *) exit 74 ;;
    esac
    ;;
  udplite.pcapng)
    materialize "${PZ_UDPLITE_SHAPE:-file}" "$destination"
    ;;
  gre.pcapng)
    materialize "${PZ_GRE_SHAPE:-file}" "$destination"
    ;;
  ipip.pcapng)
    materialize "${PZ_IPIP_SHAPE:-file}" "$destination"
    ;;
esac
EOF

if [ -n "${PZ_REAL_JQ-}" ]; then
  case "$PZ_REAL_JQ" in
    *.exe)
      cp "$PZ_REAL_JQ" "$BIN/jq-real.exe"
      cat >"$BIN/jq" <<'EOF'
#!/bin/sh
BIN_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec "$BIN_DIR/jq-real.exe" "$@"
EOF
      ;;
    *) cp "$PZ_REAL_JQ" "$BIN/jq" ;;
  esac
else
cat >"$BIN/jq" <<'PY'
#!/usr/bin/env python3
import json
import shlex
import sys

args = sys.argv[1:]

def option(name):
    index = args.index(name)
    return args[index + 1]

try:
    if "-nr" in args:
        print(" ".join(shlex.quote(value) for value in [
            "scripts/kali-sctp-capture.sh", option("target")
        ]))
        raise SystemExit(0)

    capture = option("capture")
    command = option("command")
    text = sys.stdin.read()
    decoder = json.JSONDecoder()
    values = []
    offset = 0
    while True:
        while offset < len(text) and text[offset].isspace():
            offset += 1
        if offset == len(text):
            break
        value, offset = decoder.raw_decode(text, offset)
        values.append(value)
    if len(values) != 1 or not isinstance(values[0], dict):
        raise ValueError("expected exactly one root object")
    result = values[0].get("result")
    if not isinstance(result, dict):
        raise ValueError("expected object result")
    result["capture"] = capture
    values[0]["command"] = command
    json.dump(values[0], sys.stdout, ensure_ascii=False)
    print()
except (KeyError, ValueError, json.JSONDecodeError) as error:
    print(error, file=sys.stderr)
    raise SystemExit(1)
PY
fi

cat >"$BIN/jsonschema" <<'PY'
#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from jsonschema import Draft202012Validator

args = sys.argv[1:]
if len(args) != 3 or args[0] != "-i":
    raise SystemExit(64)
def native(path):
    if os.name == "nt" and path.startswith("/"):
        return subprocess.check_output(["cygpath", "-w", path]).decode("utf-8").strip()
    return path

instance = json.load(open(native(args[1]), encoding="utf-8"))
schema = json.load(open(native(args[2]), encoding="utf-8"))
Draft202012Validator.check_schema(schema)
Draft202012Validator(schema).validate(instance)
PY
chmod +x "$BIN/python3" "$BIN/ssh" "$BIN/scp" "$BIN/mv" "$BIN/rm" "$BIN/mktemp" "$BIN/jq" \
  "$BIN/jsonschema" \
  2>/dev/null || true

run_wrapper() {
  (
  cd "$TMP/caller"
  PZ_EFFECT_LOG=$EFFECT_LOG \
  PZ_SCP_COUNT_FILE=$TMP/scp-count \
  PZ_MV_COUNT_FILE=$TMP/mv-count \
  PZ_RM_COUNT_FILE=$TMP/rm-count \
  PZ_OUTSIDE_FILE=$TMP/outside-file \
  PZ_TEST_PYTHON=$PYTHON_BIN \
  PZ_REAL_MV=$REAL_MV \
  PZ_REAL_RM=$REAL_RM \
  PZ_REAL_MKTEMP=$REAL_MKTEMP \
  PZ_STAGE_RECORD=$TMP/stage-record \
  PZ_KALI_KEYDIR=$KEYDIR \
  PZ_KALI_HOST=203.0.113.77 \
  PZ_FAIL_SSH=${PZ_FAIL_SSH-} \
  PZ_FAIL_SCP_CALL=${PZ_FAIL_SCP_CALL-} \
  PZ_FAIL_MV_CALL=${PZ_FAIL_MV_CALL-} \
  PZ_FAIL_MV_CALL_SECOND=${PZ_FAIL_MV_CALL_SECOND-} \
  PZ_SIGNAL_MV_CALL=${PZ_SIGNAL_MV_CALL-} \
  PZ_GROUP_SIGNAL_MV_CALL=${PZ_GROUP_SIGNAL_MV_CALL-} \
  PZ_GROUP_SIGNAL=${PZ_GROUP_SIGNAL-} \
  PZ_FAIL_RM_CALL=${PZ_FAIL_RM_CALL-} \
  PZ_SIGNAL_RM_CALL=${PZ_SIGNAL_RM_CALL-} \
  PZ_RM_SIGNAL=${PZ_RM_SIGNAL-} \
  PZ_SIGNAL_MKTEMP=${PZ_SIGNAL_MKTEMP-} \
  PZ_ABORT_MKTEMP_SIGNAL=${PZ_ABORT_MKTEMP_SIGNAL-} \
  PZ_SCTP_PCAP_SHAPE=${PZ_SCTP_PCAP_SHAPE-} \
  PZ_SCTP_JSON_SHAPE=${PZ_SCTP_JSON_SHAPE-} \
  PZ_UDPLITE_SHAPE=${PZ_UDPLITE_SHAPE-} \
  PZ_GRE_SHAPE=${PZ_GRE_SHAPE-} \
  PZ_IPIP_SHAPE=${PZ_IPIP_SHAPE-} \
  PATH="$BIN:$PATH" \
  "$SH_BIN" "$@"
  )
}

assert_clean_failure() {
  target=$1
  shift
  rm -rf "$FIXTURE/${target:?}"
  : >"$EFFECT_LOG"
  rm -f "$TMP/scp-count"
  rm -f "$TMP/mv-count"
  mkdir -p "$FIXTURE/$target"
  printf 'old final\n' >"$FIXTURE/$target/old.keep"
  if run_wrapper "$@" "$target" >"$TMP/output" 2>&1; then
    fail "$* accepted a failing artifact scenario"
  fi
  [ -f "$FIXTURE/$target/old.keep" ] || fail "$* damaged an old final"
  [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ] || {
    find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 >&2
    fail "$* left staged or partial artifacts"
  }
}

# Direct wrappers accept zero or one destination. Empty is not the default,
# and argument validation happens before any network command.
for script in kali-sctp-capture.sh kali-remaining-capture.sh; do
  : >"$EFFECT_LOG"
  if run_wrapper "$FIXTURE/scripts/$script" '' >"$TMP/output" 2>&1; then
    fail "$script accepted an explicit empty destination"
  fi
  grep -Fq 'path is empty' "$TMP/output" || fail "$script hid the empty-path error"
  [ ! -s "$EFFECT_LOG" ] || fail "$script reached the network for an empty path"
  if run_wrapper "$FIXTURE/scripts/$script" captures/a captures/b \
    >"$TMP/output" 2>&1; then
    fail "$script accepted more than one destination"
  fi
  [ ! -s "$EFFECT_LOG" ] || fail "$script reached the network with extra arguments"
done

# experiment.sh must preserve omitted-versus-explicit-empty behavior instead
# of turning an empty second argument into the default destination.
for action in sctp remaining; do
  : >"$EFFECT_LOG"
  if run_wrapper "$FIXTURE/scripts/experiment.sh" "$action" '' \
    >"$TMP/output" 2>&1; then
    fail "experiment.sh $action accepted an explicit empty destination"
  fi
  grep -Fq 'path is empty' "$TMP/output" || \
    fail "experiment.sh $action did not forward its explicit empty destination"
  [ ! -s "$EFFECT_LOG" ] || \
    fail "experiment.sh $action reached the network for an empty path"
  if run_wrapper "$FIXTURE/scripts/experiment.sh" "$action" captures/a extra \
    >"$TMP/output" 2>&1; then
    fail "experiment.sh $action accepted extra arguments"
  fi
  [ ! -s "$EFFECT_LOG" ] || \
    fail "experiment.sh $action reached the network with extra arguments"
done

# Every remote operation can fail without publishing a final artifact.
for call in 1 2 3; do
  PZ_FAIL_SCP_CALL=$call assert_clean_failure \
    "captures/fail-sctp-scp-$call" \
    "$FIXTURE/scripts/kali-sctp-capture.sh"
done
PZ_FAIL_SSH=1 assert_clean_failure captures/fail-sctp-ssh \
  "$FIXTURE/scripts/kali-sctp-capture.sh"
for call in 1 2 3 4; do
  PZ_FAIL_SCP_CALL=$call assert_clean_failure \
    "captures/fail-remaining-scp-$call" \
    "$FIXTURE/scripts/kali-remaining-capture.sh"
done
PZ_FAIL_SSH=1 assert_clean_failure captures/fail-remaining-ssh \
  "$FIXTURE/scripts/kali-remaining-capture.sh"
for call in 1 2; do
  PZ_FAIL_MV_CALL=$call assert_clean_failure \
    "captures/fail-sctp-mv-$call" \
    "$FIXTURE/scripts/kali-sctp-capture.sh"
done
for call in 1 2 3; do
  PZ_FAIL_MV_CALL=$call assert_clean_failure \
    "captures/fail-remaining-mv-$call" \
    "$FIXTURE/scripts/kali-remaining-capture.sh"
done

# Signals are transactional too. A signal after any successful rename must
# exit nonzero, restore an older complete set byte-for-byte, or remove every
# newly published final when there was no older set. No staging directory may
# survive. These call ranges cover both old-to-backup and stage-to-final moves.
assert_signal_empty_target() {
  target=$1
  call=$2
  script=$3
  rm -rf "$FIXTURE/${target:?}"
  rm -f "$TMP/scp-count" "$TMP/mv-count"
  if PZ_SIGNAL_MV_CALL=$call run_wrapper \
    "$FIXTURE/scripts/$script" "$target" >"$TMP/output" 2>&1; then
    fail "$script swallowed TERM after publication move $call"
  fi
  [ -d "$FIXTURE/$target" ] || fail "$script removed its output directory"
  [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" -eq 0 ] || {
    find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 >&2
    fail "$script left a partial new set after TERM on move $call"
  }
}

assert_sctp_signal_rollback() {
  call=$1
  target=captures/sctp-signal-old-$call
  rm -rf "$FIXTURE/${target:?}"
  mkdir -p "$FIXTURE/$target"
  printf 'old pcap %s\n' "$call" >"$FIXTURE/$target/sctp.pcap"
  printf 'old json %s\n' "$call" >"$FIXTURE/$target/sctp.json"
  printf 'unrelated\n' >"$FIXTURE/$target/unknown.keep"
  rm -f "$TMP/scp-count" "$TMP/mv-count"
  if PZ_SIGNAL_MV_CALL=$call run_wrapper \
    "$FIXTURE/scripts/kali-sctp-capture.sh" "$target" \
    >"$TMP/output" 2>&1; then
    fail "SCTP swallowed TERM after old-set move $call"
  fi
  [ "$(cat "$FIXTURE/$target/sctp.pcap")" = "old pcap $call" ] && \
    [ "$(cat "$FIXTURE/$target/sctp.json")" = "old json $call" ] && \
    [ "$(cat "$FIXTURE/$target/unknown.keep")" = unrelated ] || \
    fail "SCTP did not restore the complete old set after move $call"
  [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" -eq 3 ] || \
    fail "SCTP left staging or partial files after old-set move $call"
}

assert_remaining_signal_rollback() {
  call=$1
  target=captures/remaining-signal-old-$call
  rm -rf "$FIXTURE/${target:?}"
  mkdir -p "$FIXTURE/$target"
  for protocol in udplite gre ipip; do
    printf 'old %s %s\n' "$protocol" "$call" \
      >"$FIXTURE/$target/$protocol.pcapng"
  done
  printf 'unrelated\n' >"$FIXTURE/$target/unknown.keep"
  rm -f "$TMP/scp-count" "$TMP/mv-count"
  if PZ_SIGNAL_MV_CALL=$call run_wrapper \
    "$FIXTURE/scripts/kali-remaining-capture.sh" "$target" \
    >"$TMP/output" 2>&1; then
    fail "remaining swallowed TERM after old-set move $call"
  fi
  for protocol in udplite gre ipip; do
    [ "$(cat "$FIXTURE/$target/$protocol.pcapng")" = \
      "old $protocol $call" ] || \
      fail "remaining did not restore $protocol after move $call"
  done
  [ "$(cat "$FIXTURE/$target/unknown.keep")" = unrelated ] || \
    fail "remaining damaged an unrelated output after move $call"
  [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" -eq 4 ] || \
    fail "remaining left staging or partial files after old-set move $call"
}

for call in 1 2; do
  assert_signal_empty_target "captures/sctp-signal-new-$call" "$call" \
    kali-sctp-capture.sh
done
for call in 1 2 3; do
  assert_signal_empty_target "captures/remaining-signal-new-$call" "$call" \
    kali-remaining-capture.sh
done
for call in 1 2 3 4; do
  assert_sctp_signal_rollback "$call"
done
for call in 1 2 3 4 5 6; do
  assert_remaining_signal_rollback "$call"
done

# The trap is live before mktemp creates a staging directory.
for script in kali-sctp-capture.sh kali-remaining-capture.sh; do
  target=captures/${script%.sh}-signal-mktemp
  rm -rf "$FIXTURE/${target:?}"
  rm -f "$TMP/scp-count" "$TMP/mv-count"
  if PZ_SIGNAL_MKTEMP=1 run_wrapper "$FIXTURE/scripts/$script" "$target" \
    >"$TMP/output" 2>&1; then
    fail "$script swallowed TERM after creating staging"
  fi
  [ -d "$FIXTURE/$target" ] || fail "$script removed its output directory"
  [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" -eq 0 ] || {
    find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 >&2
    fail "$script leaked staging after TERM from mktemp"
  }
done

# A foreground signal reaches both the wrapper and mktemp. If mktemp dies after
# creating the directory but before returning its pathname, the parent cannot
# remove that otherwise-unreachable staging path. Delay the handoff after each
# injected signal so this does not pass merely because the child exits first.
for signal_and_status in HUP:129 INT:130 TERM:143; do
  signal=${signal_and_status%:*}
  expected_status=${signal_and_status#*:}
  for script in kali-sctp-capture.sh kali-remaining-capture.sh; do
    target=captures/${script%.sh}-aborted-mktemp-${signal}
    rm -rf "$FIXTURE/${target:?}"
    rm -f "$TMP/scp-count" "$TMP/mv-count" "$TMP/stage-record"
    if PZ_ABORT_MKTEMP_SIGNAL=$signal run_wrapper \
      "$FIXTURE/scripts/$script" "$target" >"$TMP/output" 2>&1; then
      fail "$script swallowed $signal that interrupted mktemp before output"
    else
      actual_status=$?
    fi
    [ "$actual_status" -eq "$expected_status" ] || \
      fail "$script translated $signal during mktemp to status $actual_status"
    [ -s "$TMP/stage-record" ] || fail "$script did not reach the mktemp probe"
    [ -d "$FIXTURE/$target" ] || fail "$script removed its output directory"
    [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" -eq 0 ] || {
      find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 >&2
      fail "$script leaked staging when mktemp was interrupted before output"
    }
  done
done

# A foreground signal reaches cleanup's current rm child as well as the
# wrapper. Killing that child before it removes STAGE must not strand the
# otherwise-empty private directory after a complete publication.
for signal_and_status in HUP:129 INT:130 TERM:143; do
  signal=${signal_and_status%:*}
  expected_status=${signal_and_status#*:}
  for script_and_call in kali-sctp-capture.sh:2 kali-remaining-capture.sh:1; do
    script=${script_and_call%:*}
    rm_call=${script_and_call#*:}
    case "$script" in
      kali-sctp-capture.sh) expected_files=2 ;;
      kali-remaining-capture.sh) expected_files=3 ;;
    esac
    target=captures/${script%.sh}-cleanup-rm-${signal}
    rm -rf "$FIXTURE/${target:?}"
    rm -f "$TMP/scp-count" "$TMP/mv-count" "$TMP/rm-count"
    if PZ_SIGNAL_RM_CALL=$rm_call PZ_RM_SIGNAL=$signal run_wrapper \
      "$FIXTURE/scripts/$script" "$target" >"$TMP/output" 2>&1; then
      fail "$script swallowed $signal that interrupted cleanup rm"
    else
      actual_status=$?
    fi
    [ "$actual_status" -eq "$expected_status" ] || \
      fail "$script translated cleanup $signal to status $actual_status"
    [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" \
      -eq "$expected_files" ] || {
      find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 >&2
      fail "$script stranded staging after cleanup $signal"
    }
  done
done

prepare_old_artifact_set() {
  old_script=$1
  old_target=$2
  old_marker=$3
  rm -rf "$FIXTURE/${old_target:?}"
  mkdir -p "$FIXTURE/$old_target"
  printf 'unrelated %s\n' "$old_marker" >"$FIXTURE/$old_target/unknown.keep"
  case "$old_script" in
    kali-sctp-capture.sh)
      printf 'old pcap %s\n' "$old_marker" >"$FIXTURE/$old_target/sctp.pcap"
      printf 'old json %s\n' "$old_marker" >"$FIXTURE/$old_target/sctp.json"
      ;;
    kali-remaining-capture.sh)
      for old_protocol in udplite gre ipip; do
        printf 'old %s %s\n' "$old_protocol" "$old_marker" \
          >"$FIXTURE/$old_target/$old_protocol.pcapng"
      done
      ;;
  esac
}

assert_old_artifact_set() {
  old_script=$1
  old_target=$2
  old_marker=$3
  [ "$(cat "$FIXTURE/$old_target/unknown.keep")" = \
    "unrelated $old_marker" ] || fail "$old_script damaged unrelated output"
  case "$old_script" in
    kali-sctp-capture.sh)
      [ "$(cat "$FIXTURE/$old_target/sctp.pcap")" = \
        "old pcap $old_marker" ] && \
        [ "$(cat "$FIXTURE/$old_target/sctp.json")" = \
        "old json $old_marker" ] || \
        fail "$old_script did not restore its old pair"
      old_expected_count=3
      ;;
    kali-remaining-capture.sh)
      for old_protocol in udplite gre ipip; do
        [ "$(cat "$FIXTURE/$old_target/$old_protocol.pcapng")" = \
          "old $old_protocol $old_marker" ] || \
          fail "$old_script did not restore $old_protocol"
      done
      old_expected_count=4
      ;;
  esac
  [ "$(find "$FIXTURE/$old_target" -mindepth 1 -maxdepth 1 | wc -l)" \
    -eq "$old_expected_count" ] || {
    find "$FIXTURE/$old_target" -mindepth 1 -maxdepth 1 >&2
    fail "$old_script left staging or mixed artifacts"
  }
}

assert_cleanup_child_signal_rollback() {
  rollback_signal=$1
  rollback_expected_status=$2
  rollback_script=$3
  rollback_phase=$4
  case "$rollback_script:$rollback_phase" in
    kali-sctp-capture.sh:published-remove)
      rollback_publish_fail=4
      rollback_child_call=1
      rollback_child='rm'
      ;;
    kali-sctp-capture.sh:restore)
      rollback_publish_fail=4
      rollback_child_call=5
      rollback_child='mv'
      ;;
    kali-remaining-capture.sh:published-remove)
      rollback_publish_fail=6
      rollback_child_call=1
      rollback_child='rm'
      ;;
    kali-remaining-capture.sh:restore)
      rollback_publish_fail=6
      rollback_child_call=7
      rollback_child='mv'
      ;;
  esac
  rollback_marker=$rollback_phase-$rollback_signal
  rollback_target=captures/${rollback_script%.sh}-$rollback_marker
  prepare_old_artifact_set \
    "$rollback_script" "$rollback_target" "$rollback_marker"
  rm -f "$TMP/scp-count" "$TMP/mv-count" "$TMP/rm-count"
  if [ "$rollback_child" = rm ]; then
    if PZ_FAIL_MV_CALL=$rollback_publish_fail \
      PZ_SIGNAL_RM_CALL=$rollback_child_call \
      PZ_RM_SIGNAL=$rollback_signal run_wrapper \
      "$FIXTURE/scripts/$rollback_script" "$rollback_target" \
      >"$TMP/output" 2>&1; then
      fail "$rollback_script swallowed $rollback_signal during published removal"
    else
      rollback_status=$?
    fi
  else
    if PZ_FAIL_MV_CALL=$rollback_publish_fail \
      PZ_GROUP_SIGNAL_MV_CALL=$rollback_child_call \
      PZ_GROUP_SIGNAL=$rollback_signal run_wrapper \
      "$FIXTURE/scripts/$rollback_script" "$rollback_target" \
      >"$TMP/output" 2>&1; then
      fail "$rollback_script swallowed $rollback_signal during restore"
    else
      rollback_status=$?
    fi
  fi
  [ "$rollback_status" -eq "$rollback_expected_status" ] || \
    fail "$rollback_script translated rollback $rollback_signal to $rollback_status"
  assert_old_artifact_set \
    "$rollback_script" "$rollback_target" "$rollback_marker"
}

for signal_and_status in HUP:129 INT:130 TERM:143; do
  signal=${signal_and_status%:*}
  expected_status=${signal_and_status#*:}
  for script in kali-sctp-capture.sh kali-remaining-capture.sh; do
    assert_cleanup_child_signal_rollback \
      "$signal" "$expected_status" "$script" published-remove
    assert_cleanup_child_signal_rollback \
      "$signal" "$expected_status" "$script" restore
  done
done

# A persistent cleanup failure without a newly pending signal is not retried
# or hidden. The complete new set remains published and the private staging
# directory is retained for inspection.
for script_and_call in kali-sctp-capture.sh:2 kali-remaining-capture.sh:1; do
  script=${script_and_call%:*}
  rm_call=${script_and_call#*:}
  target=captures/${script%.sh}-persistent-cleanup-rm
  rm -rf "$FIXTURE/${target:?}"
  rm -f "$TMP/scp-count" "$TMP/mv-count" "$TMP/rm-count"
  if PZ_FAIL_RM_CALL=$rm_call run_wrapper \
    "$FIXTURE/scripts/$script" "$target" >"$TMP/output" 2>&1; then
    fail "$script hid a persistent staging cleanup failure"
  fi
  [ "$(cat "$TMP/rm-count")" -eq "$rm_call" ] || \
    fail "$script retried a cleanup failure without a pending signal"
  grep -Fq 'retained failed Kali' "$TMP/output" || \
    fail "$script hid its retained staging diagnostic"
  [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 \
    -name '.kali-*' | wc -l)" -eq 1 ] || \
    fail "$script did not retain exactly one failed staging directory"
  case "$script" in
    kali-sctp-capture.sh)
      [ -s "$FIXTURE/$target/sctp.pcap" ] && \
        [ -s "$FIXTURE/$target/sctp.json" ] || \
        fail "$script damaged the committed pair after cleanup failure"
      ;;
    kali-remaining-capture.sh)
      for protocol in udplite gre ipip; do
        [ -s "$FIXTURE/$target/$protocol.pcapng" ] || \
          fail "$script damaged committed $protocol after cleanup failure"
      done
      ;;
  esac
done

# A persistent restore failure is likewise not retried. It returns nonzero,
# keeps the old missing artifact in its exact backup, and never leaves a new
# version of that artifact in the final path.
for script in kali-sctp-capture.sh kali-remaining-capture.sh; do
  target=captures/${script%.sh}-persistent-restore-mv
  marker=persistent-restore
  prepare_old_artifact_set "$script" "$target" "$marker"
  rm -f "$TMP/scp-count" "$TMP/mv-count" "$TMP/rm-count"
  case "$script" in
    kali-sctp-capture.sh)
      publish_fail=4
      restore_fail=5
      failed_name=sctp.pcap
      failed_label=pcap
      expected_mv_count=6
      ;;
    kali-remaining-capture.sh)
      publish_fail=6
      restore_fail=7
      failed_name=udplite.pcapng
      failed_label=udplite
      expected_mv_count=9
      ;;
  esac
  if PZ_FAIL_MV_CALL=$publish_fail PZ_FAIL_MV_CALL_SECOND=$restore_fail \
    run_wrapper "$FIXTURE/scripts/$script" "$target" \
    >"$TMP/output" 2>&1; then
    fail "$script hid a persistent restore failure"
  fi
  [ "$(cat "$TMP/mv-count")" -eq "$expected_mv_count" ] || \
    fail "$script retried a restore failure without a pending signal"
  [ ! -e "$FIXTURE/$target/$failed_name" ] || \
    fail "$script left a new final after its old restore failed"
  retained_stage=$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 \
    -type d -name '.kali-*')
  [ -n "$retained_stage" ] && \
    [ "$(cat "$retained_stage/.previous.$failed_name")" = \
      "old $failed_label $marker" ] || \
    fail "$script did not retain the failed old-artifact backup"
  grep -Fq 'unable to restore previous Kali' "$TMP/output" && \
    grep -Fq 'retained failed Kali' "$TMP/output" || \
    fail "$script hid its restore failure diagnostics"
done

# A mid-publication failure restores an older complete set, not a mixture.
target=captures/sctp-rollback
mkdir -p "$FIXTURE/$target"
printf 'old pcap\n' >"$FIXTURE/$target/sctp.pcap"
printf 'old json\n' >"$FIXTURE/$target/sctp.json"
rm -f "$TMP/scp-count" "$TMP/mv-count"
if PZ_FAIL_MV_CALL=4 run_wrapper "$FIXTURE/scripts/kali-sctp-capture.sh" \
  "$target" >"$TMP/output" 2>&1; then
  fail 'SCTP accepted a failed second publication move'
fi
if [ "$(cat "$FIXTURE/$target/sctp.pcap")" != 'old pcap' ] || \
  [ "$(cat "$FIXTURE/$target/sctp.json")" != 'old json' ]; then
  fail 'SCTP rollback did not restore the old artifact pair'
fi
[ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" -eq 2 ] || \
  fail 'SCTP rollback left staging artifacts'

# A second signal delivered while EXIT cleanup is restoring backups is
# deferred until that one cleanup pass completes. It must not recursively
# remove a file that the outer cleanup has just restored.
for signal_call in 5 6; do
  target=captures/sctp-failure-signal-restore-$signal_call
  rm -rf "$FIXTURE/${target:?}"
  mkdir -p "$FIXTURE/$target"
  printf 'old pcap restore %s\n' "$signal_call" >"$FIXTURE/$target/sctp.pcap"
  printf 'old json restore %s\n' "$signal_call" >"$FIXTURE/$target/sctp.json"
  rm -f "$TMP/scp-count" "$TMP/mv-count"
  if PZ_FAIL_MV_CALL=4 PZ_SIGNAL_MV_CALL=$signal_call run_wrapper \
    "$FIXTURE/scripts/kali-sctp-capture.sh" "$target" \
    >"$TMP/output" 2>&1; then
    fail "SCTP swallowed TERM during restore move $signal_call"
  fi
  [ "$(cat "$FIXTURE/$target/sctp.pcap")" = \
    "old pcap restore $signal_call" ] && \
    [ "$(cat "$FIXTURE/$target/sctp.json")" = \
    "old json restore $signal_call" ] || \
    fail "SCTP recursive cleanup damaged restore move $signal_call"
  [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" -eq 2 ] || \
    fail "SCTP restore signal left staging or partial files at $signal_call"
done

for signal_call in 7 8 9; do
  target=captures/remaining-failure-signal-restore-$signal_call
  rm -rf "$FIXTURE/${target:?}"
  mkdir -p "$FIXTURE/$target"
  for protocol in udplite gre ipip; do
    printf 'old %s restore %s\n' "$protocol" "$signal_call" \
      >"$FIXTURE/$target/$protocol.pcapng"
  done
  rm -f "$TMP/scp-count" "$TMP/mv-count"
  if PZ_FAIL_MV_CALL=6 PZ_SIGNAL_MV_CALL=$signal_call run_wrapper \
    "$FIXTURE/scripts/kali-remaining-capture.sh" "$target" \
    >"$TMP/output" 2>&1; then
    fail "remaining swallowed TERM during restore move $signal_call"
  fi
  for protocol in udplite gre ipip; do
    [ "$(cat "$FIXTURE/$target/$protocol.pcapng")" = \
      "old $protocol restore $signal_call" ] || \
      fail "remaining recursive cleanup damaged $protocol at $signal_call"
  done
  [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" -eq 3 ] || \
    fail "remaining restore signal left partial files at $signal_call"
done

# Successful transfers that produce anything other than a nonempty regular
# file fail closed. Symlinks run where the platform supports them.
for shape in missing empty directory; do
  PZ_SCTP_PCAP_SHAPE=$shape assert_clean_failure \
    "captures/sctp-pcap-$shape" "$FIXTURE/scripts/kali-sctp-capture.sh"
done
if ln -s "$TMP/outside-file" "$TMP/link-probe" 2>/dev/null && \
  [ -L "$TMP/link-probe" ]; then
  rm -f "$TMP/link-probe"
  PZ_SCTP_PCAP_SHAPE='link' assert_clean_failure captures/sctp-pcap-link \
    "$FIXTURE/scripts/kali-sctp-capture.sh"
  PZ_SCTP_JSON_SHAPE='link' assert_clean_failure captures/sctp-json-link \
    "$FIXTURE/scripts/kali-sctp-capture.sh"
  for protocol in udplite gre ipip; do
    case "$protocol" in
      udplite) PZ_UDPLITE_SHAPE='link' ;;
      gre) PZ_GRE_SHAPE='link' ;;
      ipip) PZ_IPIP_SHAPE='link' ;;
    esac
    export PZ_UDPLITE_SHAPE PZ_GRE_SHAPE PZ_IPIP_SHAPE
    assert_clean_failure "captures/remaining-$protocol-link" \
      "$FIXTURE/scripts/kali-remaining-capture.sh"
    unset PZ_UDPLITE_SHAPE PZ_GRE_SHAPE PZ_IPIP_SHAPE
  done
else
  printf 'SKIP: Kali staged symlink regressions (platform cannot create symlinks)\n'
fi
for shape in empty whitespace missing directory null array scalar missing-result \
  schema-missing null-result array-result malformed multiple; do
  PZ_SCTP_JSON_SHAPE=$shape assert_clean_failure \
    "captures/sctp-json-$shape" "$FIXTURE/scripts/kali-sctp-capture.sh"
done
for protocol in udplite gre ipip; do
  for shape in missing empty directory; do
    case "$protocol" in
      udplite) PZ_UDPLITE_SHAPE=$shape ;;
      gre) PZ_GRE_SHAPE=$shape ;;
      ipip) PZ_IPIP_SHAPE=$shape ;;
    esac
    export PZ_UDPLITE_SHAPE PZ_GRE_SHAPE PZ_IPIP_SHAPE
    assert_clean_failure "captures/remaining-$protocol-$shape" \
      "$FIXTURE/scripts/kali-remaining-capture.sh"
    unset PZ_UDPLITE_SHAPE PZ_GRE_SHAPE PZ_IPIP_SHAPE
  done
done

# One deliberately hostile but legal repository path checks jq @sh quoting.
# Replaying the recorded command must deliver one literal argument and must
# not execute the embedded command substitution, semicolon or glob.
quoted_target="captures/quote space 'semi;\$(touch PZ_QUOTE_EXECUTED)' *?[x]"
: >"$EFFECT_LOG"
rm -f "$TMP/scp-count"
run_wrapper "$FIXTURE/scripts/kali-sctp-capture.sh" "$quoted_target" || {
  cat "$EFFECT_LOG" >&2
  fail 'valid SCTP artifacts were rejected'
}
sctp_json=$FIXTURE/$quoted_target/sctp.json
sctp_json_native=$sctp_json
if command -v cygpath >/dev/null 2>&1; then
  sctp_json_native=$(cygpath -w "$sctp_json")
fi
if [ ! -s "$FIXTURE/$quoted_target/sctp.pcap" ] || [ ! -s "$sctp_json" ]; then
  fail 'successful SCTP run did not publish both artifacts'
fi
! grep -Fq '172.31.250.195' "$EFFECT_LOG" || fail 'SCTP ignored PZ_KALI_HOST'
[ "$(grep -c 'root@203.0.113.77' "$EFFECT_LOG")" -eq 4 ] || \
  fail 'not every SCTP ssh/scp operation used PZ_KALI_HOST'
[ ! -e "$TMP/caller/captures" ] || \
  fail 'Kali wrapper wrote captures under the caller CWD'
"$PYTHON_BIN" - "$sctp_json_native" "$quoted_target" <<'PY'
import json
import sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["result"]["capture"] == sys.argv[2] + "/sctp.pcap"
assert value["result"]["future_field"] == "preserved"
assert value["command"]
PY
REPLAY=$TMP/replay
mkdir -p "$REPLAY/scripts"
cat >"$REPLAY/scripts/kali-sctp-capture.sh" <<'EOF'
#!/bin/sh
printf '%s\n' "$#" >"${PZ_ARGV_LOG:?}"
for argument do printf '%s\n' "$argument" >>"$PZ_ARGV_LOG"; done
EOF
chmod +x "$REPLAY/scripts/kali-sctp-capture.sh" 2>/dev/null || true
command_value=$("$PYTHON_BIN" -c \
  'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["command"])' \
  "$sctp_json_native")
(
  cd "$REPLAY"
  PZ_ARGV_LOG=$TMP/argv "$SH_BIN" -c "$command_value"
)
[ "$(sed -n '1p' "$TMP/argv")" = 1 ] || fail 'quoted command changed argv count'
[ "$(sed -n '2p' "$TMP/argv")" = "$quoted_target" ] || \
  fail 'quoted command did not round-trip its target'
[ ! -e "$REPLAY/PZ_QUOTE_EXECUTED" ] || \
  fail 'quoted command executed target contents'

# The default remains stable, every remote call honors the host override, and
# remaining publishes all three captures only after validating the set.
: >"$EFFECT_LOG"
rm -f "$TMP/scp-count"
run_wrapper "$FIXTURE/scripts/kali-sctp-capture.sh" || {
  cat "$EFFECT_LOG" >&2
  fail 'default SCTP artifacts were rejected'
}
default_command=$("$PYTHON_BIN" -c \
  'import json,sys; print(json.load(open(sys.argv[1]))["command"])' \
  "$FIXTURE/captures/kali-sctp/sctp.json")
[ "$default_command" = scripts/kali-sctp-capture.sh ] || \
  fail 'default SCTP command changed'
rm -rf "$FIXTURE/captures/kali-sctp"
rm -f "$TMP/scp-count"
run_wrapper "$FIXTURE/scripts/experiment.sh" sctp || {
  cat "$EFFECT_LOG" >&2
  fail 'experiment.sh rejected default SCTP artifacts'
}
[ -s "$FIXTURE/captures/kali-sctp/sctp.json" ] || \
  fail 'experiment.sh sctp did not preserve the omitted default'
: >"$EFFECT_LOG"
rm -f "$TMP/scp-count"
run_wrapper "$FIXTURE/scripts/kali-remaining-capture.sh" captures/remaining-ok || {
  cat "$EFFECT_LOG" >&2
  fail 'valid remaining artifacts were rejected'
}
for file in udplite gre ipip; do
  [ -s "$FIXTURE/captures/remaining-ok/$file.pcapng" ] || \
    fail "remaining did not publish $file"
done
! grep -Fq '172.31.250.195' "$EFFECT_LOG" || \
  fail 'remaining ignored PZ_KALI_HOST'
[ "$(grep -c 'root@203.0.113.77' "$EFFECT_LOG")" -eq 5 ] || \
  fail 'not every remaining ssh/scp operation used PZ_KALI_HOST'
rm -rf "$FIXTURE/captures/kali-remaining"
rm -f "$TMP/scp-count"
run_wrapper "$FIXTURE/scripts/experiment.sh" remaining || {
  cat "$EFFECT_LOG" >&2
  fail 'experiment.sh rejected default remaining artifacts'
}
for file in udplite gre ipip; do
  [ -s "$FIXTURE/captures/kali-remaining/$file.pcapng" ] || \
    fail "experiment.sh remaining did not publish $file"
done

# A signal delivered while cleanup performs its final pending-signal test must
# not fall between the last test and resetting CLEANING. Bash can override the
# `[` builtin deterministically at that exact point; other shells still cover
# the portable signal matrix above.
if command -v bash >/dev/null 2>&1; then
  cat >"$TMP/tail-signal.bash" <<'BASH'
function [ {
  if builtin [ -n "${CLEANING+x}" ] && \
    builtin [ -z "${STAGE-}" ] && \
    builtin [ -z "${PENDING_SIGNAL_STATUS-}" ] && \
    builtin [ "${1-}" = -n ]; then
    printf 'TAIL_SIGNAL_SENT pid=%s cleaning=%s\n' "$$" "$CLEANING" >&2
    kill -TERM "$$"
  fi
  builtin [ "$@"
}
export -f \[
exec bash "$@"
BASH
  target=captures/sctp-tail-signal
  rm -rf "$FIXTURE/${target:?}"
  rm -f "$TMP/scp-count" "$TMP/mv-count"
  if (
    cd "$TMP/caller"
    PZ_EFFECT_LOG=$EFFECT_LOG \
    PZ_SCP_COUNT_FILE=$TMP/scp-count \
    PZ_MV_COUNT_FILE=$TMP/mv-count \
    PZ_RM_COUNT_FILE=$TMP/rm-count \
    PZ_OUTSIDE_FILE=$TMP/outside-file \
    PZ_TEST_PYTHON=$PYTHON_BIN \
    PZ_REAL_MV=$REAL_MV \
    PZ_REAL_RM=$REAL_RM \
    PZ_REAL_MKTEMP=$REAL_MKTEMP \
    PZ_KALI_KEYDIR=$KEYDIR \
    PZ_KALI_HOST=203.0.113.77 \
    PATH="$BIN:$PATH" \
    bash "$TMP/tail-signal.bash" \
      "$FIXTURE/scripts/kali-sctp-capture.sh" "$target"
  ) >"$TMP/tail-output" 2>&1; then
    fail 'SCTP swallowed TERM during the final pending-signal check'
  fi
  grep -Fq 'TAIL_SIGNAL_SENT' "$TMP/tail-output" || \
    fail 'tail-signal probe did not reach the final pending-signal check'
  [ -s "$FIXTURE/$target/sctp.pcap" ] && \
    [ -s "$FIXTURE/$target/sctp.json" ] || \
    fail 'late post-commit TERM left an incomplete SCTP set'
  [ "$(find "$FIXTURE/$target" -mindepth 1 -maxdepth 1 | wc -l)" -eq 2 ] || \
    fail 'late post-commit TERM left staging or unrelated output'
else
  printf 'SKIP: cleanup-tail signal regression (Bash unavailable)\n'
fi

printf 'Kali capture wrapper regressions: pass (%s)\n' "$SH_BIN"
