$ErrorActionPreference = "Stop"

$port = 8080
$root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "public"))
$rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)

$contentTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".csv"  = "text/csv; charset=utf-8"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".svg"  = "image/svg+xml"
    ".ico"  = "image/x-icon"
}

function Write-Response {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$StatusCode,
        [string]$StatusText,
        [byte[]]$Body,
        [string]$ContentType = "text/plain; charset=utf-8"
    )

    $headers = "HTTP/1.1 $StatusCode $StatusText`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
}

try {
    $listener.Start()
    Write-Host ""
    Write-Host "Inventario disponible en:" -ForegroundColor Green
    Write-Host "  En esta computadora: http://localhost:$port"

    $addresses = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
        Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork }

    foreach ($address in $addresses) {
        Write-Host "  En el telefono:       http://$($address.IPAddressToString):$port" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "Deja esta ventana abierta mientras uses el inventario."
    Write-Host "Para detener el servidor, presiona Ctrl+C o cierra la ventana."
    Write-Host ""

    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
            $requestLine = $reader.ReadLine()

            while ($reader.ReadLine()) {
                # Consume the remaining HTTP headers.
            }

            if (-not $requestLine) {
                continue
            }

            $parts = $requestLine.Split(" ")
            $method = $parts[0]
            $urlPath = [System.Uri]::UnescapeDataString($parts[1].Split("?")[0])

            if ($method -ne "GET") {
                Write-Response $stream 405 "Method Not Allowed" ([System.Text.Encoding]::UTF8.GetBytes("Metodo no permitido"))
                continue
            }

            if ($urlPath -eq "/") {
                $urlPath = "/index.html"
            }

            $relativePath = $urlPath.TrimStart("/").Replace("/", [System.IO.Path]::DirectorySeparatorChar)
            $filePath = [System.IO.Path]::GetFullPath((Join-Path $root $relativePath))

            if (-not $filePath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                Write-Response $stream 404 "Not Found" ([System.Text.Encoding]::UTF8.GetBytes("Archivo no encontrado"))
                continue
            }

            $extension = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
            $contentType = if ($contentTypes.ContainsKey($extension)) { $contentTypes[$extension] } else { "application/octet-stream" }
            Write-Response $stream 200 "OK" ([System.IO.File]::ReadAllBytes($filePath)) $contentType
        }
        catch {
            Write-Host "No se pudo responder una solicitud: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        finally {
            if ($stream) {
                $stream.Dispose()
            }
            $client.Dispose()
        }
    }
}
finally {
    $listener.Stop()
}
