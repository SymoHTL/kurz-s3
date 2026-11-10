#!/bin/sh
# curl.sh [ENDPOINT]: the server's calls and errors, signed with curl's SigV4 by the key and secret in KURZ_S3_ACCESS_KEY
# and KURZ_S3_SECRET_KEY, against a server started with the same two variables and an empty root. Each check prints
# PASS or FAIL, and the script exits with 1 when one failed. It needs curl 7.75 or newer, GNU date and sha256sum.
set -u
B=${1:-http://127.0.0.1:9000}
: "${KURZ_S3_ACCESS_KEY:?set KURZ_S3_ACCESS_KEY}" "${KURZ_S3_SECRET_KEY:?set KURZ_S3_SECRET_KEY}"
SIGV4='aws:amz:us-east-1:s3'
KEYS="$KURZ_S3_ACCESS_KEY:$KURZ_S3_SECRET_KEY"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fails=0

# check NAME STATUS EXPECT CURL-ARGS...: the response has STATUS, and its body is the rest of EXPECT where EXPECT starts
# with `=`, or holds EXPECT where EXPECT is not empty.
check() {
    name=$1 want=$2 expect=$3
    shift 3
    got=$(curl -s -D "$work/head" -o "$work/body" -w '%{http_code}' "$@")
    ok=yes
    [ "$got" = "$want" ] || ok=no
    case $expect in
        '') ;;
        =*) [ "$(cat "$work/body")" = "${expect#=}" ] || ok=no ;;
        *) grep -qF -- "$expect" "$work/body" || ok=no ;;
    esac
    if [ $ok = yes ]; then
        echo "PASS $name"
    else
        echo "FAIL $name: status $got, expected $want${expect:+ and body $expect}"
        head -c 300 "$work/body"
        echo
        fails=$((fails + 1))
    fi
}

# signed NAME STATUS EXPECT CURL-ARGS...: check, with the request signed by the key and secret.
signed() {
    name=$1 want=$2 expect=$3
    shift 3
    check "$name" "$want" "$expect" --aws-sigv4 "$SIGV4" --user "$KEYS" "$@"
}

# header NAME LINE: the last response's head holds LINE, in any case.
header() {
    if tr -d '\r' < "$work/head" | grep -qixF -- "$2"; then
        echo "PASS $1"
    else
        echo "FAIL $1: no header line '$2'"
        fails=$((fails + 1))
    fi
}

check "unsigned list" 403 AccessDenied "$B/"
check "wrong secret" 403 SignatureDoesNotMatch --aws-sigv4 "$SIGV4" --user "$KURZ_S3_ACCESS_KEY:wrong" "$B/"
check "wrong key" 403 InvalidAccessKeyId --aws-sigv4 "$SIGV4" --user "OTHERKEY:$KURZ_S3_SECRET_KEY" "$B/"
signed "date in 2020" 403 RequestTimeTooSkewed -H 'x-amz-date: 20200101T000000Z' "$B/"
signed "date 10 minutes old" 200 '' -H "x-amz-date: $(date -u -d '-10 min' +%Y%m%dT%H%M%SZ)" "$B/"
signed "date 20 minutes ahead" 403 RequestTimeTooSkewed -H "x-amz-date: $(date -u -d '+20 min' +%Y%m%dT%H%M%SZ)" "$B/"

signed "get, missing bucket" 404 NoSuchBucket "$B/photos/a.txt"
signed "delete, missing bucket" 404 NoSuchBucket -X DELETE "$B/photos/a.txt"
signed "create bucket" 200 '' -X PUT "$B/photos"
signed "list buckets" 200 '<Name>photos</Name>' "$B/"
signed "missing key" 404 NoSuchKey "$B/photos/a.txt"
signed "put, unsigned payload" 200 '' -H 'x-amz-content-sha256: UNSIGNED-PAYLOAD' -X PUT --data-binary 'hello world' \
    "$B/photos/a/b.txt"
H=$(printf 'second object' | sha256sum | cut -d' ' -f1)
signed "put, signed payload, a space in the key" 200 '' -H "x-amz-content-sha256: $H" -X PUT --data-binary 'second object' \
    "$B/photos/z%20key.txt"
signed "put, payload not its hash" 400 XAmzContentSHA256Mismatch -H "x-amz-content-sha256: $H" -X PUT \
    --data-binary 'other bytes' "$B/photos/c.txt"
signed "get" 200 '=hello world' "$B/photos/a/b.txt"
signed "get, a space in the key" 200 '=second object' "$B/photos/z%20key.txt"
signed "head" 200 '' -I "$B/photos/a/b.txt"
header "head's length" 'Content-Length: 11'
signed "range 0-4" 206 '=hello' -H 'Range: bytes=0-4' "$B/photos/a/b.txt"
signed "range 6-" 206 '=world' -H 'Range: bytes=6-' "$B/photos/a/b.txt"
header "range 6-, its Content-Range" 'Content-Range: bytes 6-10/11'
header "range 6-, its length" 'Content-Length: 5'
signed "range -3" 206 '=rld' -H 'Range: bytes=-3' "$B/photos/a/b.txt"
signed "range 4-100" 206 '=o world' -H 'Range: bytes=4-100' "$B/photos/a/b.txt"
signed "range 50-" 416 InvalidRange -H 'Range: bytes=50-' "$B/photos/a/b.txt"
signed "list, prefix a/" 200 '<Key>a/b.txt</Key>' "$B/photos?list-type=2&prefix=a%2F"
signed "list, delimiter /" 200 '<Prefix>a/</Prefix>' "$B/photos?list-type=2&delimiter=%2F"
signed "delete a bucket with objects" 409 BucketNotEmpty -X DELETE "$B/photos"
signed "delete" 204 '' -X DELETE "$B/photos/a/b.txt"
signed "delete, a space in the key" 204 '' -X DELETE "$B/photos/z%20key.txt"
signed "get a deleted key" 404 NoSuchKey "$B/photos/a/b.txt"
signed "delete bucket" 204 '' -X DELETE "$B/photos"
signed "list buckets, none" 200 '' "$B/"
if grep -qF '<Name>photos</Name>' "$work/body"; then
    echo "FAIL list buckets, none: photos is listed"
    fails=$((fails + 1))
fi

echo "$fails failed"
[ "$fails" -eq 0 ]
