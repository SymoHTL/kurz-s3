#!/bin/sh
# awscli.sh [ENDPOINT]: aws-cli v2's calls, in AWS's aws-cli image, signed by the key and secret in KURZ_S3_ACCESS_KEY and
# KURZ_S3_SECRET_KEY, against a server started with the same two variables. The image runs on the host's network, or on
# the network that NETWORK names (`container:NAME` reaches a server inside the container NAME). Each step prints PASS or
# FAIL, and the script exits with 1 when one failed.
set -u
E=${1:-http://127.0.0.1:9000}
: "${KURZ_S3_ACCESS_KEY:?set KURZ_S3_ACCESS_KEY}" "${KURZ_S3_SECRET_KEY:?set KURZ_S3_SECRET_KEY}"
IMAGE=amazon/aws-cli:2.24.0@sha256:c3e9c88d22f9bea0e7b2195c7407b364db83d32d094ea8b936ad258592f66510
docker run --rm --network "${NETWORK:-host}" -e AWS_ACCESS_KEY_ID="$KURZ_S3_ACCESS_KEY" \
    -e AWS_SECRET_ACCESS_KEY="$KURZ_S3_SECRET_KEY" -e AWS_DEFAULT_REGION=us-east-1 -e E="$E" --entrypoint sh "$IMAGE" -c '
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
        tail -n 6 /tmp/step.out /tmp/step.err
        fails=$((fails + 1))
    fi
}
s3() { aws --endpoint-url "$E" s3 "$@"; }
s3api() { aws --endpoint-url "$E" s3api "$@"; }
printf "hello from aws-cli\n" > /tmp/small.txt
head -c 9000000 /dev/urandom > /tmp/big.bin
step "make bucket" s3 mb s3://cli
step "list buckets" s3 ls
step "copy a small file up" s3 cp /tmp/small.txt s3://cli/small.txt
step "copy a 9 MB file up, in parts" s3 cp /tmp/big.bin s3://cli/big.bin
step "list the bucket" s3 ls s3://cli/
step "the list holds both" sh -c "grep -q small.txt /tmp/step.out && grep -q big.bin /tmp/step.out"
step "copy the small file down" s3 cp s3://cli/small.txt /tmp/small.back
step "the small file has its bytes" cmp /tmp/small.txt /tmp/small.back
step "get a range" s3api get-object --bucket cli --key small.txt --range bytes=0-4 /tmp/part.txt
step "the range has its bytes" test "$(cat /tmp/part.txt)" = hello
step "head" s3api head-object --bucket cli --key small.txt
step "remove the small file" s3 rm s3://cli/small.txt
step "copy the 9 MB file down" s3 cp s3://cli/big.bin /tmp/big.back
step "the 9 MB file has its bytes" cmp /tmp/big.bin /tmp/big.back
step "remove the bucket and what it holds" s3 rb s3://cli --force
echo "$fails failed"
[ "$fails" -eq 0 ]
'
