$env:PATH = "C:\iverilog\bin;" + $env:PATH
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Compiling Solution 3: Increased Hamming Distance (d>=2)..." -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
iverilog -g2012 -o sim.vvp design.sv testbench.sv
if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed!"
    exit $LASTEXITCODE
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "Running Simulation and writing to logs.txt..." -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
vvp sim.vvp | Tee-Object -FilePath logs.txt
Write-Host "`nSimulation complete. Output saved to logs.txt and waveform saved to fsm_simulation.vcd" -ForegroundColor Green
