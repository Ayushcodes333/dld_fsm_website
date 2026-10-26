@echo off
set PATH=C:\iverilog\bin;%PATH%
echo ========================================================
echo Compiling Solution 3: Increased Hamming Distance (d>=2)...
echo ========================================================
iverilog -g2012 -o sim.vvp design.sv testbench.sv
if %ERRORLEVEL% NEQ 0 (
    echo Compilation failed!
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
