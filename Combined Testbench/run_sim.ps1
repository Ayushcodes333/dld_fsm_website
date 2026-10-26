Set-Location $PSScriptRoot
$env:PATH = "C:\iverilog\bin;" + $env:PATH
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Compiling Combined Multi-Defense Security System..." -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
& "C:\iverilog\bin\iverilog.exe" -g2012 -o sim.vvp design.sv testbench.sv
if ($LASTEXITCODE -ne 0) {
    Write-Host "Compilation failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "Running Simulation and writing to logs.txt..." -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
& "C:\iverilog\bin\vvp.exe" sim.vvp | Tee-Object -FilePath "logs.txt"
Write-Host "`nSimulation complete. Output saved to logs.txt and waveform saved to detect.vcd" -ForegroundColor Green
