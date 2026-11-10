# kurz-s3

A small S3-style object server written in [Kurz](https://github.com/SymoHTL/Kurz), over the HTTP server of Kurz's
standard library.

Kurz commit: `a514840e9d92e14c9a697e4a08b6fa376d7cd388`

The server is built and tested with the Kurz compiler at that commit. The CI job reads the commit from the line above
and fails when the README names none.

## What it does

- Requests are signed with AWS Signature Version 4 in the header form, by one access key and its secret. A request
  dated more than 15 minutes from the server's clock is refused with `RequestTimeTooSkewed`.
- Addressing is path style: `http://host:port/bucket/key`.
- A bucket is a directory under the root. An object is a file in it, named by the hex of its key, with its ETag in a
  file beside it.

The checks in `test/` pass these calls, and only these are claimed:

- `test/curl.sh`, with curl's `--aws-sigv4` (curl 8.5.0): list buckets; create and delete a bucket, and
  `BucketNotEmpty`; put an object with a signed or an unsigned payload, and `XAmzContentSHA256Mismatch`; get, head and
  delete an object, a key with a space among them; ranges `0-4`, `6-`, `-3` and `4-100`, and `InvalidRange`; list
  objects (version 2) by prefix and by delimiter; `NoSuchBucket` and `NoSuchKey`; `AccessDenied`,
  `InvalidAccessKeyId`, `SignatureDoesNotMatch` and `RequestTimeTooSkewed`.
- `test/awscli.sh`, with aws-cli 2.24.0: `s3 mb`, `ls`, `cp` up and down, a 9 MB file in parts among them,
  `s3api get-object` with a range, `s3api head-object`, `s3 rm` and `s3 rb --force`.
- `test/rclone.sh`, with rclone 1.68.2: `mkdir`, `copy` of a tree up, a 12 MB file in 5 MB parts among them, `lsl`,
  `check`, `copy` down, `copyto` on the server, `cat` with an offset and a count, `purge` and `lsd`.

It is not a full implementation of S3's API.

Its limits: it speaks plain HTTP, so requests and object bytes travel in the clear unless a proxy with TLS fronts it;
it knows one key; and it serves one connection at a time, one request per connection.

## Build

The compiler needs the .NET SDK and the clang that the Kurz commit pins. The image Kurz's own CI job runs in holds both:
its digest is the `image:` line of `.github/workflows/gates.yml` at that commit.

```sh
git clone https://github.com/SymoHTL/Kurz kurz
git -C kurz checkout "$(sed -n 's/^Kurz commit: `\([0-9a-f]\{40\}\)`$/\1/p' README.md)"
image=$(sed -n 's/^ *image: \(ghcr\.io\/symohtl\/kurz-ci@sha256:[0-9a-f]\{64\}\)$/\1/p' kurz/.github/workflows/gates.yml)
docker run --rm -v "$PWD:/w" -w /w "$image" sh -c '
  dotnet build kurz/compiler/Kurz/Kurz.csproj -c Release -p:RestoreLockedMode=true &&
  dotnet kurz/compiler/Kurz/bin/Release/net10.0/kurz.dll build --release s3.kz -o s3'
```

The build warns `md5-insecure` twice: S3's ETag of an object put in one request is the MD5 of its bytes, which is a
checksum here and signs nothing.

## Run

The server reads its settings from the environment, so that the secret is on no command line:

| Variable | What it is | Default |
|---|---|---|
| `KURZ_S3_ADDRESS` | the address and port it listens on | `127.0.0.1:9000` |
| `KURZ_S3_ROOT` | the directory that holds the buckets | none |
| `KURZ_S3_ACCESS_KEY` | the access key | none |
| `KURZ_S3_SECRET_KEY` | the key's secret | none |

A variable with no default that is not set, or set to nothing, stops the start with a line that names it, such as
`the server does not start: not present: KURZ_S3_ROOT`. The process then ends with the exit code 0: the compiler at
that commit builds no `Environment.Exit`.

```sh
export KURZ_S3_ROOT=./data KURZ_S3_ACCESS_KEY=AKIDEXAMPLE
read -rs KURZ_S3_SECRET_KEY && export KURZ_S3_SECRET_KEY
./s3
```

## Test

Start the server with an empty root, then run each script with the same two variables of the key:

```sh
sh test/curl.sh http://127.0.0.1:9000
sh test/awscli.sh http://127.0.0.1:9000
sh test/rclone.sh http://127.0.0.1:9000
```

`test/curl.sh` needs curl 7.75 or newer. The two others run their client's image, pinned by its digest, with Docker on
the host's network; `NETWORK=container:NAME` runs it on the network of the container `NAME` instead. The key
`AKIDEXAMPLE` and the secret the CI job uses are the example credentials of AWS's documentation.

## License

Apache License 2.0 with LLVM Exceptions (`Apache-2.0 WITH LLVM-exception`), the license of LLVM. See `LICENSE`.
