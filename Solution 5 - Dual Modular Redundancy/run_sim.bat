@echo off
pushd "%~dp0"
set PATH=C:\iverilog\bin;%PATH%
echo ========================================================
echo Compiling Solution 5: Dual Modular Redundancy (DMR)...
echo ========================================================
iverilog -g2012 -o sim.vvp design.sv testbench.sv
if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
    popd
    exit /b %ERRORLEVEL%
)

echo.
echo ========================================================
echo Running Simulation and writing to logs.txt...
echo ========================================================
vvp sim.vvp > logs.txt
type logs.txt
echo.
echo Simulation complete. Output saved to logs.txt and waveform saved to fsm_simulation.vcd
popd
