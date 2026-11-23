#!/bin/bash
set -euo pipefail

for bucket in ecoraee-evidencias ecoraee-contenidos; do
  if ! awslocal s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    awslocal s3api create-bucket --bucket "$bucket" >/dev/null
  fi
  awslocal s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration \
    'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
  awslocal s3api put-bucket-cors --bucket "$bucket" --cors-configuration \
    '{"CORSRules":[{"AllowedOrigins":["http://localhost:8090"],"AllowedMethods":["PUT","GET","HEAD"],"AllowedHeaders":["Content-Type"],"ExposeHeaders":["ETag"],"MaxAgeSeconds":300}]}'
done
