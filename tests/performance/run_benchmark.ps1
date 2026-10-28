param(
    [string]$ConfigFile = "tests/performance/bench_config.json",
    [string]$OutputFile = "tests/performance/results/run_optimized.json"
)

$ErrorActionPreference = "Stop"

$engineExe = "C:\Users\trufa\AppData\Local\Programs\Beyond-All-Reason\data\engine\recoil_2026.07.04\spring-headless.exe"
$writeDataDir = "C:\Users\trufa\AppData\Local\Programs\Beyond-All-Reason\data"
$scriptTxt = "C:\Users\trufa\Documents\BAR\Beyond-All-Reason\tests\performance\run_bench_script.txt"
$infologPath = "$writeDataDir\infolog.txt"
$stdoutPath = "$writeDataDir\stdout_bench.log"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "       LAUNCHING DETERMINISTIC HEADLESS BENCHMARK      " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " Config  : $ConfigFile"
Write-Host " Output  : $OutputFile"

if (Test-Path $stdoutPath) { Remove-Item $stdoutPath -Force }

$proc = Start-Process -FilePath $engineExe -ArgumentList @("--write-dir", $writeDataDir, $scriptTxt) -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError "$writeDataDir\stderr_bench.log"
Write-Host " Process started with PID $($proc.Id). Waiting for completion..."

$timeoutSec = 300
$sw = [System.Diagnostics.Stopwatch]::StartNew()

while (-not $proc.HasExited) {
    Start-Sleep -Seconds 2
    if ($sw.Elapsed.TotalSeconds -gt $timeoutSec) {
        Write-Warning "Benchmark timed out after $timeoutSec seconds. Terminating process."
        Stop-Process -Id $proc.Id -Force
        break
    }
}

Write-Host " Benchmark process exited with code $($proc.ExitCode). Total wallclock: $($sw.Elapsed.TotalSeconds.ToString('F1'))s"

# Extract JSON from stdoutPath or infologPath
$sourceLog = $null
if (Test-Path $stdoutPath) {
    $sourceLog = $stdoutPath
} elseif (Test-Path $infologPath) {
    $sourceLog = $infologPath
}

if ($sourceLog) {
    $raw = Get-Content $sourceLog
    $start = $false
    $jsonLines = @()
    foreach ($line in $raw) {
        if ($line -match "JSON_REPORT_START") { $start = $true; continue }
        if ($line -match "JSON_REPORT_END") { $start = $false; break }
        if ($start) {
            $clean = $line -replace "^\[t=.*?\]\[f=.*?\]\s*", ""
            $jsonLines += $clean
        }
    }

    if ($jsonLines.Count -gt 0) {
        $jsonStr = $jsonLines -join "`n"
        $outDir = Split-Path -Parent $OutputFile
        if (-not (Test-Path $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($OutputFile, $jsonStr)
        Write-Host " [SUCCESS] Benchmark report saved to: $OutputFile" -ForegroundColor Green

        $data = $jsonStr | ConvertFrom-Json
        Write-Host "-------------------------------------------------------" -ForegroundColor Yellow
        Write-Host " Tag                : $($data.tag)"
        Write-Host " Total Frames       : $($data.total_frames)"
        Write-Host " Sim Duration       : $($data.wallclock_sec) s"
        Write-Host " Sim Speed          : $($data.sim_fps) FPS ($($data.sim_speedup)x real-time)"
        Write-Host " Avg Frame Time     : $($data.frame_time_avg_ms) ms"
        Write-Host " P50 Frame Time     : $($data.frame_time_p50_ms) ms"
        Write-Host " P95 Frame Time     : $($data.frame_time_p95_ms) ms"
        Write-Host " P99 Frame Time     : $($data.frame_time_p99_ms) ms"
        Write-Host " Max Frame Time     : $($data.frame_time_max_ms) ms"
        Write-Host " Spikes (>33ms)     : $($data.spikes_over_33ms) ($($data.spikes_percent)%)"
        Write-Host " Lua RAM Range      : $([math]::Round($data.lua_mem_min_kb / 1024, 2)) MB -> $([math]::Round($data.lua_mem_max_kb / 1024, 2)) MB"
        Write-Host " Checkpoints Count  : $($data.checkpoints.Count)"
        Write-Host " Final Checksum     : $($data.checkpoints[-1].checksum)"
        Write-Host "-------------------------------------------------------" -ForegroundColor Yellow
    } else {
        Write-Warning "Could not find JSON_REPORT markers in $sourceLog"
    }
} else {
    Write-Error "No log file found."
}
