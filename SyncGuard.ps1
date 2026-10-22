# SyncGuard - keeps cloud-sync clients (Google Drive for desktop, OneDrive, iCloud Photos) from eating the CPU.
# Every N seconds it kills processes on the kill list and pins processes on the throttle list to a few cores
# at a lower priority. Create a file named STOP next to this script to restore normal priority/affinity and exit.
# Works in Windows PowerShell 5.1 and PowerShell 7. Settings: syncguard.json next to this script (optional).
param([string]$Config = '')

$ErrorActionPreference = 'Continue'
$Root  = $PSScriptRoot
$Log   = Join-Path $Root 'guard.log'
$StopF = Join-Path $Root 'STOP'

# Built-in defaults, used when no config file exists
$Interval = 20
$KillList = @('iCloudPhotos','ApplePhotoStreams')
$Throttle = @(
  @{ Procs=@('GoogleDriveFS');                         Affinity=0x003; Prio='Idle' },
  @{ Procs=@('OneDrive','OneDrive.Sync.Service');      Affinity=0x007; Prio='BelowNormal' }
)

function Say($m){ Add-Content -LiteralPath $Log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) }
function To-Mask($v){
  if($v -is [string]){ $s = $v.Trim(); if($s -match '^0x'){ return [Convert]::ToInt64($s.Substring(2),16) } return [int64]$s }
  return [int64]$v
}

if(-not $Config){ $Config = Join-Path $Root 'syncguard.json' }
if(Test-Path -LiteralPath $Config){
  try {
    $c = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
    if($c.intervalSec){ $Interval = [int]$c.intervalSec }
    if($null -ne $c.kill){ $KillList = @($c.kill) }
    if($null -ne $c.throttle){
      $Throttle = @($c.throttle | ForEach-Object { @{ Procs=@($_.procs); Affinity=(To-Mask $_.affinity); Prio=[string]$_.priority } })
    }
  } catch { Say "config error ($Config): $($_.Exception.Message) - using built-in defaults" }
}

if((Test-Path $Log) -and (Get-Item $Log).Length -gt 300KB){ Set-Content -LiteralPath $Log -Value '' }
Say "=== guard start (pid $PID) ==="

$seen = @{}
while($true){
  if(Test-Path $StopF){
    Say "STOP requested - restoring and exiting"
    foreach($g in $Throttle){ foreach($n in $g.Procs){ Get-Process $n -EA SilentlyContinue | ForEach-Object {
      try { $_.ProcessorAffinity=[IntPtr]([int64][Math]::Pow(2,[Environment]::ProcessorCount)-1); $_.PriorityClass='Normal' } catch {} } } }
    Remove-Item -LiteralPath $StopF -Force -EA SilentlyContinue
    Say "=== guard end ==="
    exit
  }

  foreach($n in $KillList){
    Get-Process $n -EA SilentlyContinue | ForEach-Object {
      Say "kill $n pid=$($_.Id) cpuSec=$([int]$_.CPU)"
      Stop-Process -Id $_.Id -Force -EA SilentlyContinue
    }
  }

  foreach($g in $Throttle){
    foreach($n in $g.Procs){
      Get-Process $n -EA SilentlyContinue | ForEach-Object {
        $p = $_
        if(-not $seen.ContainsKey($p.Id)){
          try {
            $p.PriorityClass = $g.Prio
            $p.ProcessorAffinity = [IntPtr]$g.Affinity
            $seen[$p.Id] = $true
            Say ("throttle {0} pid={1} -> {2} / affinity 0x{3:X}" -f $n,$p.Id,$g.Prio,$g.Affinity)
          } catch { Say "throttle $n pid=$($p.Id) FAILED: $($_.Exception.Message)" }
        }
      }
    }
  }

  # forget pids that are gone so restarts get re-throttled
  foreach($k in @($seen.Keys)){ if(-not (Get-Process -Id $k -EA SilentlyContinue)){ $seen.Remove($k) } }
  Start-Sleep -Seconds $Interval
}
