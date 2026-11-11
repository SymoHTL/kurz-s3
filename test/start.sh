#!/bin/sh
# start.sh: the starts of ./s3 that fail end with the exit code 1, write nothing on standard output and their line on
# standard error. The case of an address in use needs a server of the same build listening on 127.0.0.1:9000, as the
# job starts it. Each case prints PASS or FAIL, and the script exits with 1 when one failed.
set -u
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

# expect NAME TEXT ENV...: ./s3, run by env with ENV, ends with 1, writes nothing on standard output and a line that holds
# TEXT on standard error.
expect() {
    name=$1 text=$2
    shift 2
    rc=0
    env "$@" ./s3 > "$work/out" 2> "$work/err" || rc=$?
    if [ "$rc" = 1 ] && [ ! -s "$work/out" ] && grep -qF -- "$text" "$work/err"; then
        echo "PASS $name"
    else
        echo "FAIL $name: exit $rc; standard output: $(cat "$work/out"); standard error: $(cat "$work/err")"
        fails=$((fails + 1))
    fi
}

expect "no root" "the server does not start: not present: KURZ_S3_ROOT" -u KURZ_S3_ROOT
expect "an empty root" "the server does not start: not present: KURZ_S3_ROOT" KURZ_S3_ROOT=
expect "no access key" "the server does not start: not present: KURZ_S3_ACCESS_KEY" -u KURZ_S3_ACCESS_KEY KURZ_S3_ROOT="$work/root"
expect "an address in use" "address in use: 127.0.0.1:9000" KURZ_S3_ROOT="$work/root" KURZ_S3_ADDRESS=127.0.0.1:9000

[ "$fails" = 0 ]
