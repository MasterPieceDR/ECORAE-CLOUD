$ErrorActionPreference = 'Stop'
if (-not $env:BUCKET_FRONTEND -or -not $env:DISTRIBUCION_ID) { throw 'Defina BUCKET_FRONTEND y DISTRIBUCION_ID' }
$raiz = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location (Join-Path $raiz 'frontend')
try { npm ci; if ($LASTEXITCODE) { throw 'npm ci falló' }; npm run build; if ($LASTEXITCODE) { throw 'build falló' } } finally { Pop-Location }
aws s3 sync (Join-Path $raiz 'frontend/dist') "s3://$env:BUCKET_FRONTEND/" --delete --cache-control 'no-cache'
if ($LASTEXITCODE) { throw 'sync falló' }
aws cloudfront create-invalidation --distribution-id $env:DISTRIBUCION_ID --paths '/*'
if ($LASTEXITCODE) { throw 'invalidación falló' }
