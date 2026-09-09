#!/bin/sh
# Offline GNU make scheduling regression; requires sh, make and GNU timeout.
# Only copied fixture recipes run. Protocol tools, captures and namespaces do not.
# PZ_CHECK_ORDER_KEEP_TMP=1 retains diagnostics under TMPDIR for local review.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
MAKE_BIN=${1:-make}
[ "$#" -le 1 ] || { echo 'usage: check-order-regression.sh [make]' >&2; exit 2; }
command -v "$MAKE_BIN" >/dev/null
command -v timeout >/dev/null
SH_BIN=$(command -v sh)
TMP_BASE=$(CDPATH='' cd -- "${TMPDIR:-/tmp}" && pwd -P)
TMP=$(mktemp -d "$TMP_BASE/protocol-zoo-check-order.XXXXXX")
TMP=$(CDPATH='' cd -- "$TMP" && pwd -P)
case "$TMP" in "$TMP_BASE"/protocol-zoo-check-order.*) ;; *) exit 2 ;; esac
cleanup() {
  if [ "${PZ_CHECK_ORDER_KEEP_TMP:-0}" = 1 ]; then
    printf 'check-order diagnostics: %s\n' "$TMP"
  else
    rm -rf -- "$TMP"
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  echo "FAIL: $*" >&2
  [ ! -f "$TMP/output" ] || cat "$TMP/output" >&2
  exit 1
}

# One explicit test double per actual Makefile recipe. Unexpected commands fail;
# notably the copied test-check-order recipe records one call, never recurses.
cat > "$TMP/recipe.sh" <<'EOF'
#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
EVENTS=$ROOT/events
case "${0##*/}" in
  experiment.sh) [ "$#" -eq 1 ]; target=$1 ;;
  era2-fixtures.sh) target=era2-fixtures ;;
  era2-static-results.sh) target=era2-static ;;
  era2-validate.sh) target=era2-validate ;;
  era3-validate.sh) target=era3-validate ;;
  capture-path-regression.sh) target=test-capture-paths ;;
  kali-capture-wrapper-regression.sh) target=test-kali-capture-wrappers ;;
  era3-validator-regression.sh) target=test-era3-validator ;;
  check-order-regression.sh) target=test-check-order ;;
  *) echo 'unexpected fixture recipe' >&2; exit 91 ;;
esac
case "$target" in
  fixtures|capabilities|era2-fixtures|era2-static) kind=generator ;;
  validate|era2-validate|era3-validate|test-capture-paths|test-kali-capture-wrappers|test-era3-validator|test-check-order) kind=consumer ;;
  *) echo "unexpected fixture target: $target" >&2; exit 92 ;;
esac
mkdir "$EVENTS/start.$target" || { echo "duplicate recipe: $target" >&2; exit 93; }
wait_for() {
  attempts=0
  while [ ! -e "$1" ] && [ "$attempts" -lt 100 ]; do
    sleep 0.05
    attempts=$((attempts + 1))
  done
  [ -e "$1" ] || { echo "bounded event wait expired: $1" >&2; exit 94; }
}
if [ "$PZ_CHECK_MODE" = race ]; then
  case "$target" in
    era2-fixtures)
      printf() {
        case "$1" in
          'RARP request:'*)
            # The unmodified producer has already opened/truncated rarp.txt.
            : > "$EVENTS/truncated"
            attempts=0
            while [ ! -e "$EVENTS/consumer-finished" ] && [ "$attempts" -lt 50 ]; do
              sleep 0.1
              attempts=$((attempts + 1))
            done
            ;;
        esac
        command printf "$@"
      }
      . "$ROOT/originals/era2-fixtures.sh"
      ;;
    era2-validate)
      wait_for "$EVENTS/truncated"
      trap 'rc=$?; : > "$EVENTS/consumer-finished"; exit "$rc"' EXIT
      node() {
        # Stop after the real fixture/docs guards, before production tools.
        : > "$EVENTS/passed-real-fixture-guard"
        : > "$EVENTS/done.$target"
        exit 0
      }
      . "$ROOT/originals/era2-validate.sh"
      echo 'fixture validator escaped the Node boundary' >&2
      exit 95
      ;;
  esac
else
  if [ "$kind" = consumer ] && [ "$PZ_CHECK_MODE" != standalone ]; then
    for generator in fixtures capabilities era2-fixtures era2-static; do
      [ -e "$EVENTS/done.$generator" ] || {
        echo "reader $target started before $generator completed" >&2
        exit 96
      }
    done
  fi
  if [ "$PZ_CHECK_MODE:$target" = fail-generator:era2-fixtures ]; then
    : > "$EVENTS/injected-generator-failure"
    exit 31
  fi
  if [ "$PZ_CHECK_MODE:$target" = fail-consumer:validate ]; then
    : > "$EVENTS/injected-consumer-failure"
    exit 32
  fi
  if [ "$PZ_CHECK_MODE" = parallel ]; then
    case "$target" in
      fixtures) wait_for "$EVENTS/start.capabilities" ;;
      capabilities) wait_for "$EVENTS/start.fixtures" ;;
      validate) wait_for "$EVENTS/start.era2-validate" ;;
      era2-validate) wait_for "$EVENTS/start.validate" ;;
    esac
  fi
fi
: > "$EVENTS/done.$target"
EOF

new_fixture() {
  name=$1
  FIXTURE=$TMP/$name
  mkdir -p "$FIXTURE/scripts" "$FIXTURE/tests" "$FIXTURE/events"
  cp "$ROOT/Makefile" "$FIXTURE/Makefile"
  cmp "$ROOT/Makefile" "$FIXTURE/Makefile" || fail 'Makefile copy differs'
  for script in experiment.sh era2-fixtures.sh era2-static-results.sh era2-validate.sh era3-validate.sh; do
    cp "$TMP/recipe.sh" "$FIXTURE/scripts/$script"
  done
  for script in capture-path-regression.sh kali-capture-wrapper-regression.sh era3-validator-regression.sh check-order-regression.sh; do
    cp "$TMP/recipe.sh" "$FIXTURE/tests/$script"
  done
  chmod +x "$FIXTURE"/scripts/*.sh "$FIXTURE"/tests/*.sh
}

run_make() {
  mode=$1
  inherited=$2
  shift 2
  status=0
  # Strip unrelated inherited makefile/shell injection, but exercise job flags
  # either explicitly or through MAKEFLAGS, including recursive stage makes.
  PZ_CHECK_MODE=$mode MAKEFLAGS=$inherited MFLAGS= GNUMAKEFLAGS= MAKEFILES= BASH_ENV= ENV= \
    timeout -k 2s 25s "$MAKE_BIN" --no-print-directory -C "$FIXTURE" "SHELL=$SH_BIN" "$@" \
    > "$TMP/output" 2>&1 || status=$?
  cp "$TMP/output" "$FIXTURE/make.log"
  case "$status" in 0|2) ;; *) fail "unexpected make/timeout exit $status" ;; esac
}

assert_all_done() {
  for target in fixtures capabilities era2-fixtures era2-static validate era2-validate test-capture-paths test-kali-capture-wrappers test-era3-validator era3-validate test-check-order; do
    [ -e "$FIXTURE/events/done.$target" ] || fail "missing completed target: $target"
  done
}

# The identical test must fail on the original unordered Makefile: its real
# Era 2 validator sees rarp.txt during the instrumented, bounded write window.
new_fixture real-write-window
mkdir -p "$FIXTURE/originals" "$FIXTURE/captures/fixtures/era2" "$FIXTURE/research" "$FIXTURE/docs" "$FIXTURE/species/_template"
cp "$ROOT/scripts/era2-fixtures.sh" "$ROOT/scripts/era2-validate.sh" "$FIXTURE/originals/"
cp "$ROOT/captures/fixtures/era2/"* "$FIXTURE/captures/fixtures/era2/"
for document in second-era-natural-history.md pre-ip-ncp.md era2-sources.md era2-experiment-matrix.md era2-blockers.md; do
  cp "$ROOT/research/$document" "$FIXTURE/research/$document"
done
cp "$ROOT/docs/ERA2-STATUS.md" "$FIXTURE/docs/"
cp "$ROOT/species/_template/README.md" "$FIXTURE/species/_template/"
cp "$ROOT/ROADMAP.md" "$ROOT/IMPLEMENTATION_PLAN.md" "$FIXTURE/"
run_make race '' -j10 check
[ "$status" -eq 0 ] || fail 'parallel check raced the real fixture write'
[ -e "$FIXTURE/events/passed-real-fixture-guard" ] || fail 'real fixture guard did not pass'
assert_all_done
echo 'PASS: parallel check waits for the real fixture write'

new_fixture serial
run_make ordered '' -j1 check
[ "$status" -eq 0 ] || fail 'serial check failed'
assert_all_done
echo 'PASS: serial check invokes every target once'

new_fixture phase-parallelism
run_make parallel '' -j4 check
[ "$status" -eq 0 ] || fail 'independent recipes lost phase-local parallelism'
assert_all_done
echo 'PASS: independent generators and consumers remain parallel'

new_fixture inherited-jobs
run_make parallel '-j8' check
[ "$status" -eq 0 ] || fail 'inherited parallel MAKEFLAGS lost ordering or parallelism'
assert_all_done
echo 'PASS: inherited MAKEFLAGS preserves ordering and parallelism'

new_fixture generator-failure
run_make fail-generator '' -j4 check
[ "$status" -eq 2 ] && [ -e "$FIXTURE/events/injected-generator-failure" ] || fail 'generator failure did not propagate'
for target in validate era2-validate test-capture-paths test-kali-capture-wrappers test-era3-validator era3-validate test-check-order; do
  [ ! -e "$FIXTURE/events/start.$target" ] || fail "consumer ran after generation failure: $target"
done
echo 'PASS: generation failure prevents all consumer recipes'

new_fixture consumer-failure
run_make fail-consumer '' -j4 check
[ "$status" -eq 2 ] && [ -e "$FIXTURE/events/injected-consumer-failure" ] || fail 'consumer failure did not propagate'
echo 'PASS: consumer failure propagates to check'

new_fixture standalone
run_make standalone '' -j4 validate era2-validate
[ "$status" -eq 0 ] || fail 'standalone validation failed'
for target in fixtures capabilities era2-fixtures era2-static; do
  [ ! -e "$FIXTURE/events/start.$target" ] || fail "standalone validation generated data: $target"
done
[ -e "$FIXTURE/events/done.validate" ] && [ -e "$FIXTURE/events/done.era2-validate" ] || fail 'standalone validator was skipped'
echo 'PASS: standalone validators do not invoke generators'

new_fixture default-target
run_make standalone ''
[ "$status" -eq 0 ] && [ -e "$FIXTURE/events/done.validate" ] || fail 'default target is no longer validation'
for target in fixtures capabilities era2-fixtures era2-static era2-validate test-capture-paths test-kali-capture-wrappers test-era3-validator era3-validate test-check-order; do
  [ ! -e "$FIXTURE/events/start.$target" ] || fail "default validation invoked unexpected target: $target"
done
echo 'PASS: default make remains standalone validation'

new_fixture standalone-test
run_make standalone '' test-check-order
[ "$status" -eq 0 ] && [ -e "$FIXTURE/events/done.test-check-order" ] || fail 'standalone test target failed'
echo 'PASS: check-order test dispatch is bounded and non-recursive'
echo 'check-order regression: pass (fixture scheduling only; no production protocol validation)'
