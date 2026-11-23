#!/usr/bin/env bash
set -euo pipefail
: "${BUCKET_FRONTEND:?}" "${DISTRIBUCION_ID:?}"
raiz=$(cd "$(dirname "$0")/../.." && pwd)
(cd "$raiz/frontend" && npm ci && npm run build)
aws s3 sync "$raiz/frontend/dist/" "s3://$BUCKET_FRONTEND/" --delete --cache-control 'no-cache'
aws cloudfront create-invalidation --distribution-id "$DISTRIBUCION_ID" --paths '/*'
