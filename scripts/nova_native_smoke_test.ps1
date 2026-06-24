param(
  [string]$ApiBase = "http://124.221.216.24:6090/api/v1",
  [string]$Phone = "15268642022",
  [string]$Code = "301776",
  [string]$Model = "nova_deepseek"
)

$ErrorActionPreference = "Stop"
function Pass($m) { Write-Host "[PASS] $m" -ForegroundColor Green }
function Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red; exit 1 }
function Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }

Info "1. SMS login $Phone"
$login = Invoke-RestMethod -Uri "$ApiBase/auth/sms/token" -Method POST -Body (@{
  phone = $Phone; code = $Code; channel = "app"
} | ConvertTo-Json) -ContentType "application/json"
if (-not $login.success) { Fail "login: $($login.message)" }
$token = $login.data.token
$userId = $login.data.userId
$headers = @{ Authorization = "Bearer $token" }
Pass "login userId=$userId"

Info "2. GET /me/nova-models"
$models = Invoke-RestMethod -Uri "$ApiBase/me/nova-models" -Headers $headers
$mdata = if ($models.data) { $models.data } else { $models }
$defModel = if ($mdata.defaultModel) { $mdata.defaultModel } else { $Model }
if ($mdata.allowedModels -contains $Model) { $useModel = $Model } else { $useModel = $defModel }
Pass "useModel=$useModel default=$defModel"

Info "3. GET /me/nova-credentials"
$creds = Invoke-RestMethod -Uri "$ApiBase/me/nova-credentials" -Headers $headers
$cdata = if ($creds.data) { $creds.data } else { $creds }
$novaKey = if ($cdata.api_token) { $cdata.api_token } elseif ($cdata.apiKey) { $cdata.apiKey } else { $null }
if (-not $cdata.ready -or -not $novaKey) { Fail "nova not ready" }
$novaUser = $cdata.bizUserId
$novaUrl = if ($cdata.baseUrl) { $cdata.baseUrl.TrimEnd('/') } else { "http://124.221.216.24:3000" }
$sessionId = "profile-$novaUser"
Pass "nova ready base=$novaUrl user=$novaUser"

Info "4. POST sessions/ensure"
$ensure = Invoke-RestMethod -Uri "$ApiBase/ai/conversations/sessions/ensure" -Method POST -Headers $headers -ContentType "application/json" -Body (@{
  kind = "AI_ASSISTANT"; title = "Yunshu"
} | ConvertTo-Json)
$ed = if ($ensure.data) { $ensure.data } else { $ensure }
$convId = [int]($ed.conversationId)
$rowId = [int]($ed.id)
Write-Host ($ensure | ConvertTo-Json -Compress -Depth 6)
if ($convId -le 0 -and $rowId -le 0) { Fail "sessions/ensure no id" }
Pass "ensure conversationId=$convId id=$rowId"

Info "5. probe conversation ids"
foreach ($probeId in @($convId, $rowId) | Where-Object { $_ -gt 0 } | Select-Object -Unique) {
  try {
    $null = Invoke-RestMethod -Uri "$ApiBase/ai/conversations/$probeId" -Headers $headers
    Pass "probe conv=$probeId ok"
  } catch {
    Warn "probe conv=$probeId failed"
  }
}

Info "6. POST /ai/conversations"
try {
  $created = Invoke-RestMethod -Uri "$ApiBase/ai/conversations" -Method POST -Headers $headers -ContentType "application/json" -Body (@{
    kind = "AI_ASSISTANT"; title = "Yunshu new"
  } | ConvertTo-Json)
  $cd = if ($created.data) { $created.data } else { $created }
  Write-Host ($created | ConvertTo-Json -Compress -Depth 6)
  Pass "create conversationId=$($cd.conversationId) id=$($cd.id)"
} catch {
  Warn "create failed: $($_.Exception.Message)"
}

$activeConvId = if ($convId -gt 0) { $convId } else { $rowId }

Info "7. POST messages/local user conv=$activeConvId"
$null = Invoke-RestMethod -Uri "$ApiBase/ai/conversations/$activeConvId/messages/local" -Method POST -Headers $headers -ContentType "application/json" -Body (@{
  role = "user"; content = "smoke test 123"; kind = "TEXT"
} | ConvertTo-Json)
Pass "messages/local user ok"

Info "8. POST Nova SSE chat model=$useModel"
$bodyObj = @{
  model = $useModel
  stream = $true
  user = $novaUser
  messages = @(
    @{ role = "system"; content = "You are Yunshu assistant." }
    @{ role = "user"; content = "smoke test: reply OK only" }
  )
}
$body = $bodyObj | ConvertTo-Json -Depth 5 -Compress
$req = [System.Net.HttpWebRequest]::Create("$novaUrl/v1/chat/completions")
$req.Method = "POST"
$req.ContentType = "application/json"
$req.Accept = "text/event-stream"
$req.Headers.Add("Authorization", "Bearer $novaKey")
$req.Headers.Add("X-Nova-Chat-Session-Id", $sessionId)
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
Pass "chat reply=$acc"

Info "9. POST messages/local assistant"
$null = Invoke-RestMethod -Uri "$ApiBase/ai/conversations/$activeConvId/messages/local" -Method POST -Headers $headers -ContentType "application/json" -Body (@{
  role = "assistant"; content = $acc; kind = "AI_ASSISTANT"
} | ConvertTo-Json)
Pass "messages/local assistant ok"

Info "10. GET history turns"
$turns = Invoke-RestMethod -Uri "$ApiBase/ai/history/turns?size=10" -Headers $headers
$items = if ($turns.data.items) { $turns.data.items } elseif ($turns.data) { $turns.data } else { @() }
$convIds = @($items | ForEach-Object { $_.conversationId } | Select-Object -Unique)
Pass "turns=$($items.Count) convIds=$($convIds -join ',')"

Info "11. GET conversations C1"
$convs = Invoke-RestMethod -Uri "$ApiBase/conversations" -Headers $headers
$aiRow = $convs.data | Where-Object { $_.kind -eq "AI_ASSISTANT" } | Select-Object -First 1
if ($aiRow) { Warn "C1 AI_ASSISTANT inbox id=$($aiRow.id)" }

Pass "ALL DONE activeConvId=$activeConvId"
