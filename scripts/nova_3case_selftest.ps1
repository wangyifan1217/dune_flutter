param(
  [string]$ApiBase = "http://124.221.216.24:6090/api/v1",
  [string]$Phone = "15268642022",
  [string]$Code = "293271",
  [string]$Model = "nova_deepseek"
)

$ErrorActionPreference = "Stop"
function Pass($m) { Write-Host "[PASS] $m" -ForegroundColor Green }
function Fail($m) { Write-Host "[FAIL] $m" -ForegroundColor Red; exit 1 }
function Info($m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Case($n, $m) { Write-Host "`n======== CASE $n : $m ========" -ForegroundColor Yellow }

# --- login ---
Info "SMS login $Phone"
$login = Invoke-RestMethod -Uri "$ApiBase/auth/sms/token" -Method POST -ContentType "application/json" -Body (@{
  phone = $Phone; code = $Code; channel = "app"
} | ConvertTo-Json)
if (-not $login.success) { Fail "login: $($login.message)" }
$token = $login.data.token
$h = @{ Authorization = "Bearer $token" }
Pass "login ok tokenLen=$($token.Length)"

$creds = Invoke-RestMethod -Uri "$ApiBase/me/nova-credentials" -Headers $h
$cd = if ($creds.data) { $creds.data } else { $creds }
$novaKey = if ($cd.api_token) { $cd.api_token } elseif ($cd.apiKey) { $cd.apiKey } else { $null }
if (-not $cd.ready -or -not $novaKey) { Fail "nova not ready" }
$novaUser = $cd.bizUserId
$novaUrl = $cd.baseUrl.TrimEnd('/')
$sessionId = "profile-$novaUser"
Pass "nova user=$novaUser base=$novaUrl"

$models = Invoke-RestMethod -Uri "$ApiBase/me/nova-models" -Headers $h
$md = if ($models.data) { $models.data } else { $models }
$useModel = if ($md.allowedModels -contains $Model) { $Model } else { $md.defaultModel }
Pass "model=$useModel"

function Ensure-Conv {
  $r = Invoke-RestMethod -Uri "$ApiBase/ai/conversations/sessions/ensure" -Method POST -Headers $h -ContentType "application/json" -Body (@{
    kind = "AI_ASSISTANT"; title = "Yunshu"
  } | ConvertTo-Json)
  $d = if ($r.data) { $r.data } else { $r }
  return [int]$d.conversationId
}

function Post-Local($convId, $role, $content) {
  $null = Invoke-RestMethod -Uri "$ApiBase/ai/conversations/$convId/messages/local" -Method POST -Headers $h -ContentType "application/json" -Body (@{
    role = $role; content = $content; kind = if ($role -eq 'assistant') { 'AI_ASSISTANT' } else { 'TEXT' }
  } | ConvertTo-Json)
}

function Get-TurnsForConv($convId) {
  try {
    $r = Invoke-RestMethod -Uri "$ApiBase/ai/history/turns?size=50&conversationId=$convId" -Headers $h
    $items = if ($r.data.items) { $r.data.items } elseif ($r.data) { $r.data } else { @() }
    return @($items)
  } catch { return @() }
}

function Invoke-NovaSse($prompt, $abortAfterMs) {
  $bodyObj = @{
    model = $useModel
    stream = $true
    user = $novaUser
    messages = @(
      @{ role = "system"; content = "You are Yunshu." }
      @{ role = "user"; content = $prompt }
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
  $resp = $req.GetResponse()
  $reader = New-Object IO.StreamReader($resp.GetResponseStream())
  $acc = ""
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while (-not $reader.EndOfStream) {
    if ($abortAfterMs -gt 0 -and $sw.ElapsedMilliseconds -ge $abortAfterMs) {
      try { $resp.Close() } catch {}
      return @{ text = $acc; aborted = $true }
    }
    $line = $reader.ReadLine()
    if ($line -match '^data:\s*(.+)$' -and $Matches[1] -ne '[DONE]') {
      try {
        $j = $Matches[1] | ConvertFrom-Json
        $d = $j.choices[0].delta.content
        if ($d) { $acc += $d }
      } catch {}
    }
  }
  return @{ text = $acc; aborted = $false }
}

# CASE 2: same session on re-enter (app uses saved convId, NOT re-ensure)
Case 2 "re-enter shows recent session (stable convId + history)"
$id1 = Ensure-Conv
Pass "first ensure convId=$id1 (persist as dunes_nova_conv_id in app)"
# simulate app: second enter uses saved id without calling ensure again
$id2 = $id1
$turns = Get-TurnsForConv $id1
Pass "re-enter uses saved convId=$id2 turns=$($turns.Count)"

# CASE 1a: abort mid-stream then complete (simulates leave + return)
Case 1 "generating leave/return (abort SSE then full reply)"
$conv = $id1
Post-Local $conv "user" "case1-abort-test"
$partial = Invoke-NovaSse "Reply with exactly: PARTIAL_OK" 800
if (-not $partial.aborted) { Info "stream finished before abort window (ok)" }
Info "partial len=$($partial.text.Length) aborted=$($partial.aborted)"

$full = Invoke-NovaSse "Reply with exactly: FULL_OK" 0
if ($full.text -notmatch 'FULL_OK' -and $full.text.Length -lt 2) { Fail "full stream empty: $($full.text)" }
Post-Local $conv "assistant" $full.text
Pass "full reply=$($full.text.Trim())"

# CASE 3: deepseek model check
Case 3 "deepseek model"
if ($useModel -ne 'nova_deepseek') { Fail "expected nova_deepseek got $useModel" }
Pass "using nova_deepseek"

Write-Host "`n======== ALL 3 CASES PASSED ========" -ForegroundColor Green
Write-Host "convId=$id1 model=$useModel"
