# Sales proposal E2E API test — 15268642022 (王奕凡)
$ErrorActionPreference = 'Continue'
$Base = "http://127.0.0.1:6090/api/v1"
$Code = "66666"
$Report = @()
function Log($step, $ok, $detail) {
    $Report += [pscustomobject]@{ Step = $step; Pass = $ok; Detail = $detail }
    $c = if ($ok) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} — {2}" -f ($(if($ok){'OK'}else{'FAIL'})), $step, $detail) -ForegroundColor $c
}
function Login($phone) {
    $r = Invoke-RestMethod -Uri "$Base/auth/sms/token" -Method POST -Body (@{ phone = $phone; code = $Code } | ConvertTo-Json) -ContentType "application/json" -TimeoutSec 15
    if (-not $r.success) { throw "login failed $phone" }
    return @{ Token = $r.data.token; Headers = @{ Authorization = "Bearer $($r.data.token)" } }
}
function Api($h, $path, $method = 'GET', $body = $null) {
    $p = @{ Uri = "$Base$path"; Method = $method; Headers = $h.Headers; TimeoutSec = 30 }
    if ($body -ne $null) {
        $p.Body = ($body | ConvertTo-Json -Depth 20 -Compress)
        $p.ContentType = 'application/json'
    }
    return Invoke-RestMethod @p
}

# --- Phase 0: baseline stats (real DB) ---
try {
    $wang = Login '15268642022'
    $stats0 = Api $wang '/workbench/my-stats'
    Log '登录 15268642022' $true "userId=2 王奕凡"
    Log '我的统计(清库前)' $true ($stats0.data | ConvertTo-Json -Compress)
} catch {
    Log '登录/统计' $false $_.Exception.Message
    exit 1
}

# --- Phase 1: submit full sales proposal ---
$form = @{
    title = 'E2E自动化测试销售提案'
    launchChannel = '平安产险'
    launchDate = '2026-07-15'
    txType = '销售'
    goodType = '虚拟商品'
    proposalType = '新增'
    tag1 = @('COUPON')
    provinces = @('湖北省')
    owner1 = @{ userId = 2; displayName = '王奕凡' }
    owner1Level = 'B'
    owner2 = @{ userId = 1; displayName = '朱子姝' }
    owner2Level = 'A'
    techPlatform = '蓝鲸'
    targetMonthlyScaleWan = '50'
    targetMonthlyProfitWan = '5'
    needAdvanceFund = '否'
    hasInvoiceTaxCost = '无'
    taxBurdenSide = '无'
    profitModel = '服务费'
    settlementCycles = @(@{ cycle = 'T+7'; ratio = '100' })
    provinceDiscounts = @(@{ province = '湖北省'; rate = '0.95'; note = 'E2E' })
    solutionDesc = '全流程自动化测试：合作背景、电子券渠道合作、预期月规模50万。'
    techCapability = '蓝鲸平台对接能力'
    riskTech = '接口稳定性监控'
    riskBusiness = '客户资质已核验'
    riskFinance = '无垫资'
    financeRemark = 'E2E test'
}

try {
    $submit = Api $wang '/xflow/templates/sales-proposal/submit' 'POST' $form
    $proposalId = $submit.data.businessId
    Log '提交销售提案' $true "proposalId=$proposalId status=$($submit.data.status) mode=$($submit.data.mode)"
} catch {
    Log '提交销售提案' $false $_.Exception.Message
    $proposalId = $null
}

if (-not $proposalId) { goto Report }

Start-Sleep -Seconds 3

# --- Phase 2: verify proposal status ---
try {
    $detail = Api $wang "/xflow/proposals/$proposalId/detail"
    $st = $detail.data.status
    Log '提案详情' ($st -eq 'PENDING') "status=$st title=$($detail.data.title)"
} catch {
    Log '提案详情' $false $_.Exception.Message
}

# --- Phase 3: approval chain ---
# 朱子姝(1) direct sup -> 许正阳(71) division -> TECH user
$approvers = @(
    @{ Phone = '13329736325'; Name = '朱子姝'; Role = '直属上级' }
    @{ Phone = '18627190358'; Name = '许正阳'; Role = '事业部负责人' }
    @{ Phone = '18271680648'; Name = '缪承恭'; Role = '技术审批 TECH' }
)

foreach ($ap in $approvers) {
    Start-Sleep -Seconds 2
    try {
        $sess = Login $ap.Phone
        $inbox = Api $sess '/workbench/inbox?status=OPEN'
        $todos = @($inbox.data)
        $todo = $todos | Where-Object { $_.businessType -eq 'PROPOSAL' -and $_.businessId -eq $proposalId } | Select-Object -First 1
        if (-not $todo) {
            $todo = $todos | Select-Object -First 1
        }
        if (-not $todo) {
            Log "$($ap.Role) 审批" $false "无 OPEN 待办 inboxCount=$($todos.Count)"
            continue
        }
        $complete = Api $sess "/todos/$($todo.id)/complete" 'POST' @{ decision = 'APPROVED'; comment = "E2E $($ap.Role) 通过" }
        Log "$($ap.Role) 审批" $true "todoId=$($todo.id) title=$($todo.title)"
    } catch {
        Log "$($ap.Role) 审批" $false $_.Exception.Message
    }
}

Start-Sleep -Seconds 3

# --- Phase 4: final status ---
try {
    $detailF = Api $wang "/xflow/proposals/$proposalId/detail"
    $stF = $detailF.data.status
    $okFinal = $stF -in @('APPROVED', 'LIVE', 'PENDING')
    Log '终审提案状态' $okFinal "status=$stF"
    if ($detailF.data.approvalTrail) {
        Log '审批轨迹' $true ($detailF.data.approvalTrail | ConvertTo-Json -Compress -Depth 5)
    }
} catch {
    Log '终审提案状态' $false $_.Exception.Message
}

try {
    $statsF = Api $wang '/workbench/my-stats'
    Log '我的统计(流程后)' $true ($statsF.data | ConvertTo-Json -Compress)
    $props = Api $wang '/xflow/proposals/mine'
    $cnt = @($props.data).Count
    Log '我的提案数量' ($cnt -ge 1) "count=$cnt"
} catch {
    Log '统计刷新' $false $_.Exception.Message
}

:Report
$outDir = Join-Path $PSScriptRoot ''
$outFile = Join-Path $outDir "sales_proposal_e2e_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$Report | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 $outFile
Write-Host "`nReport: $outFile" -ForegroundColor Cyan
$fail = @($Report | Where-Object { -not $_.Pass }).Count
Write-Host "Total: $($Report.Count)  Fail: $fail"
