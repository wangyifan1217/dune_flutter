<#
  从 linux_about/.env 与 android/local.properties 解析 --dart-define 参数。
  用法: . .\scripts\resolve-dart-defines.ps1; $args = Get-DunesDartDefines
#>

function Read-DunesEnvFile {
  param([string]$Path)
  $vars = @{}
  if (-not (Test-Path $Path)) { return $vars }
  foreach ($line in Get-Content $Path) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    if ($line -match '^\s*([^=]+)=(.*)$') {
      $key = $matches[1].Trim()
      $val = $matches[2].Trim()
      if ($val.StartsWith('"') -and $val.EndsWith('"')) {
        $val = $val.Substring(1, $val.Length - 2)
      }
      $vars[$key] = $val
    }
  }
  return $vars
}

function Get-DunesDartDefines {
  param([string]$FlutterRoot = (Split-Path $PSScriptRoot -Parent))

  $defines = @()
  $envVars = @{}

  $linuxAboutEnv = Join-Path $FlutterRoot "..\..\new_dune\linux_about\.env"
  $linuxAboutEnv = [System.IO.Path]::GetFullPath($linuxAboutEnv)
  foreach ($entry in (Read-DunesEnvFile $linuxAboutEnv).GetEnumerator()) {
    $envVars[$entry.Key] = $entry.Value
  }

  $localProps = Join-Path $FlutterRoot "android\local.properties"
  foreach ($line in (Get-Content $localProps -ErrorAction SilentlyContinue)) {
    if ($line -match '^\s*tpns\.accessId=(.+)$') {
      $envVars['TPNS_ACCESS_ID'] = $matches[1].Trim()
    }
    if ($line -match '^\s*tpns\.accessKey=(.+)$') {
      $envVars['TPNS_ACCESS_KEY'] = $matches[1].Trim()
    }
    if ($line -match '^\s*tpns\.miAppId=(.+)$') {
      $envVars['TPNS_MI_APP_ID'] = $matches[1].Trim()
    }
    if ($line -match '^\s*tpns\.miAppKey=(.+)$') {
      $envVars['TPNS_MI_APP_KEY'] = $matches[1].Trim()
    }
    if ($line -match '^\s*tpns\.cluster=(.+)$') {
      $envVars['TPNS_CLUSTER'] = $matches[1].Trim()
    }
    if ($line -match '^\s*dunes\.apiHost=(.+)$') {
      $envVars['DUNES_API_HOST'] = $matches[1].Trim()
    }
    if ($line -match '^\s*nova\.baseUrl=(.+)$') {
      $envVars['NOVA_BASE_URL'] = $matches[1].Trim()
    }
  }

  $map = @{
    'TPNS_ACCESS_ID' = 'TPNS_ACCESS_ID'
    'TPNS_ACCESS_KEY' = 'TPNS_ACCESS_KEY'
    'TPNS_MI_APP_ID' = 'TPNS_MI_APP_ID'
    'TPNS_MI_APP_KEY' = 'TPNS_MI_APP_KEY'
    'TPNS_CLUSTER' = 'TPNS_CLUSTER'
    'DUNES_API_HOST' = 'DUNES_API_HOST'
    'NOVA_BASE_URL' = 'NOVA_BASE_URL'
  }

  foreach ($entry in $map.GetEnumerator()) {
    $sourceKey = $entry.Key
    $dartKey = $entry.Value
    if ($envVars.ContainsKey($sourceKey) -and $envVars[$sourceKey]) {
      $defines += "--dart-define=${dartKey}=$($envVars[$sourceKey])"
    }
  }

  return ,$defines
}
