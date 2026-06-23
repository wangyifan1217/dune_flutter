param(
  [string]$ApiBase = "http://124.221.216.24:6090/api/v1",
  [string]$NovaBase = "http://124.221.216.24:3000",
  [string]$Phone = "15268642022",
  [string]$Code = "66666"
)

$ErrorActionPreference = "Stop"
function Pass($m) { Write-Host "[PASS] $m" -ForegroundColor Green }
function Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red; exit 1 }
function Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }

Info "1. SMS login"
$login = Invoke-RestMethod -Uri "$ApiBase/auth/sms/token" -Method POST -Body (@{ phone = $Phone; code = $Code } | ConvertTo-Json) -ContentType "application/json"
if (-not $login.success) { Fail "login failed" }
$token = $login.data.token
Pass "login userId=$($login.data.userId)"

Info "2. GET /me/nova-models"
$models = Invoke-RestMethod -Uri "$ApiBase/me/nova-models" -Headers @{ Authorization = "Bearer $token" }
$mdata = if ($models.data) { $models.data } else { $models }
$defModel = $mdata.defaultModel
Pass "defaultModel=$defModel"

Info "3. GET /me/nova-credentials"
$creds = Invoke-RestMethod -Uri "$ApiBase/me/nova-credentials" -Headers @{ Authorization = "Bearer $token" }
$cdata = if ($creds.data) { $creds.data } else { $creds }
$novaKey = if ($cdata.api_token) { $cdata.api_token } elseif ($cdata.apiKey) { $cdata.apiKey } else { $null }
if (-not $cdata.ready -or -not $novaKey) { Fail "nova not ready" }
$novaUser = $cdata.bizUserId
$novaUrl = if ($cdata.baseUrl) { $cdata.baseUrl.TrimEnd('/') } else { $NovaBase.TrimEnd('/') }
Pass "nova ready base=$novaUrl user=$novaUser"

Info "4. POST Nova /v1/chat/completions text SSE"
$bodyObj = @{
  model = $defModel
  stream = $true
  messages = @(@{ role = "user"; content = "reply OK only" })
}
if ($novaUser) { $bodyObj.user = $novaUser }
$body = $bodyObj | ConvertTo-Json -Depth 5 -Compress
$req = [System.Net.HttpWebRequest]::Create("$novaUrl/v1/chat/completions")
$req.Method = "POST"
$req.ContentType = "application/json"
$req.Accept = "text/event-stream"
$req.Headers.Add("Authorization", "Bearer $novaKey")
$req.Headers.Add("X-Nova-Chat-Session-Id", "selftest-" + [guid]::NewGuid().ToString("N"))
$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
$req.ContentLength = $bytes.Length
$ws = $req.GetRequestStream(); $ws.Write($bytes, 0, $bytes.Length); $ws.Close()
try { $resp = $req.GetResponse() } catch [System.Net.WebException] {
  $r = $_.Exception.Response
  if ($r) { $sr = New-Object IO.StreamReader($r.GetResponseStream()); Fail "chat HTTP $($r.StatusCode): $($sr.ReadToEnd())" }
  Fail "chat: $($_.Exception.Message)"
}
$reader = New-Object IO.StreamReader($resp.GetResponseStream())
$acc = ""
while (-not $reader.EndOfStream) {
  $line = $reader.ReadLine()
  if ($line -match '^data:\s*(.+)$' -and $Matches[1] -ne '[DONE]') {
    try {
      $j = $Matches[1] | ConvertFrom-Json
      $d = $j.choices[0].delta.content
      if ($d) { $acc += $d }
    } catch {}
  }
}
if ($acc.Length -lt 1) { Fail "chat empty response" }
Pass "chat reply len=$($acc.Length)"

Info "5. POST Nova multimodal (1x1 png) model=nova_gpt5.5"
$mmModel = if ($mdata.allowedModels -contains "nova_gpt5.5") { "nova_gpt5.5" } else { $defModel }
$pngB64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
$dataUrl = "data:image/png;base64,$pngB64"
$mbodyObj = @{
  model = $mmModel
  stream = $false
  messages = @(@{
    role = "user"
    content = @(
      @{ type = "text"; text = "What color is this image? One word only." }
      @{ type = "image_url"; image_url = @{ url = $dataUrl } }
    )
  })
}
if ($novaUser) { $mbodyObj.user = $novaUser }
$mbody = $mbodyObj | ConvertTo-Json -Depth 8 -Compress
try {
  $mr = Invoke-RestMethod -Uri "$novaUrl/v1/chat/completions" -Method POST -Headers @{
    Authorization = "Bearer $novaKey"
    "Content-Type" = "application/json"
  } -Body $mbody
  $txt = $mr.choices[0].message.content
  if (-not $txt) { Fail "multimodal empty" }
  Pass "multimodal reply=$txt"
} catch { Fail "multimodal: $($_.Exception.Message)" }

Info "6. GET Nova /v1/app/kb/status"
try {
  $null = Invoke-RestMethod -Uri "$novaUrl/v1/app/kb/status" -Headers @{ Authorization = "Bearer $novaKey" }
  Pass "kb status ok"
} catch {
  Info "kb/status pending: $($_.Exception.Message)"
}

Pass "ALL CHECKS DONE"
