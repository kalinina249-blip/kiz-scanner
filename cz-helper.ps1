# CHZ helper: local server for the KIZ scanner
# - serves the scanner page at http://localhost:8787/ (no browser blocks: same origin)
# - proxies code-status requests to True API (Chestny Znak)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$siteBase = "https://kalinina249-blip.github.io/kiz-scanner"
$pageCache = Join-Path $env:TEMP "kiz-index.html"
$favCache = Join-Path $env:TEMP "kiz-favicon.svg"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8787/")
try { $listener.Start() } catch {
    try {
        $null = Invoke-RestMethod "http://localhost:8787/ping" -TimeoutSec 3
        Write-Host ""
        Write-Host "===============================================" -ForegroundColor Green
        Write-Host "  POMOSHCHNIK UZHE ZAPUSHCHEN v drugom okne." -ForegroundColor Green
        Write-Host "  Vsyo rabotaet! Eto okno mozhno zakryt." -ForegroundColor Green
        Write-Host "===============================================" -ForegroundColor Green
        Start-Process "http://localhost:8787/"
    } catch {
        Write-Host "ERROR: port 8787 zanyat drugoy programmoy." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    Read-Host "Nazhmite Enter chtoby zakryt"
    exit 0
}

# refresh the page from the site (fallback: cached copy in TEMP)
try {
    Invoke-WebRequest "$siteBase/index.html?v=$(Get-Random)" -OutFile $pageCache -UseBasicParsing -TimeoutSec 20
    Invoke-WebRequest "$siteBase/favicon.svg?v=$(Get-Random)" -OutFile $favCache -UseBasicParsing -TimeoutSec 20
    Write-Host "Stranica programmy obnovlena iz interneta." -ForegroundColor Gray
} catch {
    if (Test-Path $pageCache) { Write-Host "Net interneta - ispolzuyu sohranennuyu kopiyu stranicy." -ForegroundColor Yellow }
    else { Write-Host "WARNING: net interneta i net sohranennoy kopii - stranica nedostupna." -ForegroundColor Red }
}

Write-Host ""
Write-Host "=================================================" -ForegroundColor Green
Write-Host "  CHZ HELPER ZAPUSHCHEN" -ForegroundColor Green
Write-Host "  PROGRAMMA-SKANER:  http://localhost:8787" -ForegroundColor Cyan
Write-Host "  NE ZAKRYVAYTE ETO OKNO poka idet skanirovanie" -ForegroundColor Yellow
Write-Host "=================================================" -ForegroundColor Green
Write-Host ""

# open the scanner in the default browser
try { Start-Process "http://localhost:8787/" } catch {}

function Send-Bytes($res, $bytes, $type) {
    $res.ContentType = $type
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
}

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    $res.Headers.Add("Access-Control-Allow-Origin", "*")
    $res.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    $res.Headers.Add("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
    $res.Headers.Add("Access-Control-Allow-Private-Network", "true")
    $res.Headers.Add("Access-Control-Max-Age", "600")
    try {
        $path = $req.Url.AbsolutePath
        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 204
        }
        elseif ($path -eq "/" -or $path -eq "/index.html") {
            if (Test-Path $pageCache) {
                Send-Bytes $res ([IO.File]::ReadAllBytes($pageCache)) "text/html; charset=utf-8"
            } else {
                $res.StatusCode = 503
                Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes("Net kopii stranicy. Podklyuchite internet i perezapustite pomoshchnik.")) "text/plain; charset=utf-8"
            }
        }
        elseif ($path -eq "/favicon.svg" -and (Test-Path $favCache)) {
            Send-Bytes $res ([IO.File]::ReadAllBytes($favCache)) "image/svg+xml"
        }
        elseif ($path -eq "/ping") {
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes('{"ok":true}')) "application/json; charset=utf-8"
        }
        elseif ($path -eq "/check" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $data = $body | ConvertFrom-Json
            $token = ($data.token -replace '^\s*Bearer\s+', '').Trim()
            $codes = @($data.codes)
            $out = ""
            if (-not $token) { $res.StatusCode = 400; $out = '{"error":"no_token"}' }
            elseif ($codes.Count -eq 0) { $res.StatusCode = 400; $out = '{"error":"no_codes"}' }
            else {
                $jsonBody = ConvertTo-Json -InputObject $codes -Compress
                try {
                    $apiRes = Invoke-WebRequest -Uri "https://markirovka.crpt.ru/api/v3/true-api/cises/info" `
                        -Method Post -UseBasicParsing -TimeoutSec 25 `
                        -Headers @{ Authorization = "Bearer $token" } `
                        -ContentType "application/json; charset=utf-8" `
                        -Body ([Text.Encoding]::UTF8.GetBytes($jsonBody)) -ErrorAction Stop
                    $out = $apiRes.Content
                    Write-Host ("{0}  checked {1} code(s)  OK" -f (Get-Date -Format "HH:mm:ss"), $codes.Count)
                } catch {
                    $http = 0
                    if ($_.Exception.Response) { $http = [int]$_.Exception.Response.StatusCode }
                    $msg = $_.Exception.Message -replace '"', "'"
                    $out = ('{{"error":"api_error","http":{0},"message":"{1}"}}' -f $http, $msg)
                    Write-Host ("{0}  API error http={1}" -f (Get-Date -Format "HH:mm:ss"), $http) -ForegroundColor Red
                }
            }
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes($out)) "application/json; charset=utf-8"
        }
        else {
            $res.StatusCode = 404
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes('{"error":"not_found"}')) "application/json; charset=utf-8"
        }
    } catch {
        try {
            $res.StatusCode = 500
            $msg = $_.Exception.Message -replace '"', "'"
            Send-Bytes $res ([Text.Encoding]::UTF8.GetBytes(('{{"error":"helper_error","message":"{0}"}}' -f $msg))) "application/json; charset=utf-8"
        } catch {}
    }
    try { $res.OutputStream.Close() } catch {}
}
