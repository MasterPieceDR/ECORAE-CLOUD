$ErrorActionPreference = 'Stop'
$destino = Join-Path (Split-Path $PSScriptRoot -Parent) '.env.produccion'
foreach ($ruta in @($destino, "$destino.db", "$destino.api")) { if (Test-Path -LiteralPath $ruta) { throw "Ya existe $ruta; no se sobrescribirá." } }
function New-Secret { $bytes = New-Object byte[] 32; $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create(); try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }; return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant() }
$db=New-Secret; $api=New-Secret; $mcp=New-Secret; $jwt=New-Secret; $admin=New-Secret
$contenido = @"
POSTGRES_PASSWORD=$db
API_DB_PASS=$api
MCP_DB_PASS=$mcp
DB_CLAVE_API=$api
DB_CLAVE_MCP=$mcp
JWT_SECRETO=$jwt
ADMIN_CORREO=admin@ecoraee.local
ADMIN_ALIAS=admin.produccion
ADMIN_CLAVE=$admin
CLAVE_DEMO=
"@
$archivo = [System.IO.File]::Open($destino, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
try { $escritor = [System.IO.StreamWriter]::new($archivo, [System.Text.UTF8Encoding]::new($false)); try { $escritor.Write($contenido) } finally { $escritor.Dispose() } } finally { $archivo.Dispose() }
[System.IO.File]::WriteAllText("$destino.db", "POSTGRES_PASSWORD=$db`nAPI_DB_PASS=$api`nMCP_DB_PASS=$mcp`n", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText("$destino.api", "DB_CLAVE_API=$api`nDB_CLAVE_MCP=$mcp`nJWT_SECRETO=$jwt`n", [System.Text.UTF8Encoding]::new($false))
Write-Host 'Creado .env.produccion; conserve sus secretos.'
