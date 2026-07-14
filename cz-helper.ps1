# CHZ helper: local proxy between scanner-kiz.html and True API (Chestny Znak)
# Listens on http://localhost:8787 and forwards code-status requests to markirovka.crpt.ru

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8787/")
try { $listener.Start() } catch {
    Write-Host "ERROR: cannot start on port 8787. Maybe helper is already running." -ForegroundColor Red
    Write-Host $_.Exception.Message
    Read-Host "Press Enter to close"
    exit 1
}

Write-Host ""
Write-Host "=================================================" -ForegroundColor Green
Write-Host "  CHZ HELPER ZAPUSHCHEN  -  http://localhost:8787" -ForegroundColor Green
Write-Host "  NE ZAKRYVAYTE ETO OKNO poka idet skanirovanie" -ForegroundColor Yellow
Write-Host "=================================================" -ForegroundColor Green
Write-Host ""

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    $res.Headers.Add("Access-Control-Allow-Origin", "*")
    $res.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    $res.Headers.Add("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
    $res.Headers.Add("Access-Control-Allow-Private-Network", "true")
    $res.Headers.Add("Access-Control-Max-Age", "600")
    $out = ""
    try {
        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 204
        }
        elseif ($req.Url.AbsolutePath -eq "/ping") {
            $out = '{"ok":true}'
        }
        elseif ($req.Url.AbsolutePath -eq "/check" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $data = $body | ConvertFrom-Json
            $token = ($data.token -replace '^\s*Bearer\s+', '').Trim()
            $codes = @($data.codes)
            if (-not $token) {
                $res.StatusCode = 400
                $out = '{"error":"no_token"}'
            } elseif ($codes.Count -eq 0) {
                $res.StatusCode = 400
                $out = '{"error":"no_codes"}'
            } else {
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
        }
        else {
            $res.StatusCode = 404
            $out = '{"error":"not_found"}'
        }
    } catch {
        $res.StatusCode = 500
        $msg = $_.Exception.Message -replace '"', "'"
        $out = ('{{"error":"helper_error","message":"{0}"}}' -f $msg)
    }
    if ($out -ne "") {
        $bytes = [Text.Encoding]::UTF8.GetBytes($out)
        $res.ContentType = "application/json; charset=utf-8"
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    $res.OutputStream.Close()
}
