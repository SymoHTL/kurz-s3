#!/bin/sh
# rclone.sh [ENDPOINT]: rclone's calls, in rclone's image, signed by the key and secret in KURZ_S3_ACCESS_KEY and
# KURZ_S3_SECRET_KEY, against a server started with the same two variables. The image runs on the host's network, or on
# the network that NETWORK names (`container:NAME` reaches a server inside the container NAME). Each step prints PASS or
# FAIL, and the script exits with 1 when one failed.
set -u
E=${1:-http://127.0.0.1:9000}
: "${KURZ_S3_ACCESS_KEY:?set KURZ_S3_ACCESS_KEY}" "${KURZ_S3_SECRET_KEY:?set KURZ_S3_SECRET_KEY}"
IMAGE=rclone/rclone:1.68.2@sha256:74c51b8817e5431bd6d7ed27cb2a50d8ee78d77f6807b72a41ef6f898845942b
docker run --rm --network "${NETWORK:-host}" -e RCLONE_CONFIG_K_TYPE=s3 -e RCLONE_CONFIG_K_PROVIDER=Other \
    -e RCLONE_CONFIG_K_ACCESS_KEY_ID="$KURZ_S3_ACCESS_KEY" -e RCLONE_CONFIG_K_SECRET_ACCESS_KEY="$KURZ_S3_SECRET_KEY" \
    -e RCLONE_CONFIG_K_REGION=us-east-1 -e RCLONE_CONFIG_K_ENDPOINT="$E" -e RCLONE_CONFIG_K_FORCE_PATH_STYLE=true \
    --entrypoint sh "$IMAGE" -c '
fails=0
# step NAME COMMAND...: the command exits with 0.
# Its output goes to /tmp/step.out once it ended, so that a step can read the output of the step before; what it
# writes to stderr goes to /tmp/step.err.
step() {
    name=$1
    shift
    "$@" > /tmp/run.out 2> /tmp/step.err
    rc=$?
    mv /tmp/run.out /tmp/step.out
    if [ $rc -eq 0 ]; then
        echo "PASS $name"
    else
        echo "FAIL $name: exit $rc"
        tail -n 8 /tmp/step.out /tmp/step.err
        fails=$((fails + 1))
    fi
}
mkdir -p /tmp/tree/sub
printf one > /tmp/tree/a.txt
printf two > /tmp/tree/sub/b.txt
head -c 12000000 /dev/urandom > /tmp/tree/big.bin
step "make bucket" rclone mkdir k:rcl
step "copy a tree up, the 12 MB file in 5 MB parts" rclone copy /tmp/tree k:rcl/tree --s3-upload-cutoff 5M --s3-chunk-size 5M
step "list" rclone lsl k:rcl
step "check the tree against the bucket" rclone check /tmp/tree k:rcl/tree
step "copy the tree down" rclone copy k:rcl/tree /tmp/back
step "the tree has its bytes" diff -r /tmp/tree /tmp/back
step "copy on the server" rclone copyto k:rcl/tree/a.txt k:rcl/c/a.txt
step "read the copy" rclone cat k:rcl/c/a.txt
step "the copy has its bytes" test "$(cat /tmp/step.out)" = one
step "read a range" rclone cat k:rcl/tree/sub/b.txt --offset 1 --count 1
step "the range has its bytes" test "$(cat /tmp/step.out)" = w
step "purge the bucket" rclone purge k:rcl
step "list buckets" rclone lsd k:
step "the bucket is gone" sh -c "! grep -q rcl /tmp/step.out"
echo "$fails failed"
[ "$fails" -eq 0 ]
'
