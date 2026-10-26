# Fault-Resilient Secure Finite State Machine (FSM)

[![Language: Verilog / SystemVerilog](https://img.shields.io/badge/Language-Verilog%20%2F%20SystemVerilog-blue.svg)](https://en.wikipedia.org/wiki/Verilog)
[![Toolchain: Icarus Verilog](https://img.shields.io/badge/Simulation-Icarus%20Verilog%2014.0-yellow.svg)](http://iverilog.icarus.com/)
[![Waveform: GTKWave](https://img.shields.io/badge/Waveform-GTKWave-orange.svg)](http://gtkwave.sourceforge.net/)
[![Test Status: 348 / 348 Passing](https://img.shields.io/badge/Tests-348%20%2F%20348%20Passing-brightgreen.svg)]()

A hardware security research and implementation project evaluating physical **Fault Injection Attacks (FIA)** (such as localized laser strikes and clock/voltage glitching) on serial authentication Finite State Machines, developed for **CS203: Digital Logic Design**.

---

## 📌 Project Overview

Authentication FSMs controlling secure hardware access are vulnerable to physical transient state register corruption ($S_{\text{injected}} = S_{\text{raw}} \oplus M_{\text{fault}}$), enabling unauthorized bypass (e.g. flipping `LOCKED` directly into `SUCCESS`). 

This repository implements, simulates, and benchmarks **six hardware countermeasure architectures** against an unprotected baseline, ranging from lightweight parity checks to active Extended Hamming SECDED rectification and Triple Modular Redundancy (TMR).

---

## 🏗️ Hardware Countermeasures Implemented

| Architecture | Folder | Mechanism | Primary Asset Protected | Hardware Overhead | Security Philosophy |
| :--- | :--- | :--- | :--- | :---: | :--- |
| **Baseline FSM** | [`FSM/`](./FSM) | Constant-time 4-cycle sequence detector (`1010`) | None (Reference) | 4 FFs | Vulnerable (0% FDR) |
| **Solution 1** | [`Solution 1.../`](./Solution%201%20-%20Simple%201%20bit%20parity%20check) | Input-Stream Running XOR Parity Accumulator | Input Serial Line | 5 FFs | Wire Integrity |
| **Solution 2** | [`Solution 2.../`](./Solution%202%20-%20Parity%20Protected%20State%20Register) | Self-Checking Invariant Parity (`^state == parity`) + Sticky Alarm | State Flip-Flops | 6 FFs | **Fail-Secure** (Minimal Area) |
| **Solution 3** | [`Solution 3.../`](./Solution%203%20-%20Increased%20Hamming%20Distance) | Even-Weight 5-bit State Codebook ($d_{\min} \ge 2$) + Trap States | State Space Boundary | 5 FFs | Fail-Secure (Trapped) |
| **Solution 4** | [`Solution 4.../`](./Solution%204%20-%20Extended%20Hamming%20SECDED) | Extended Hamming $(8, 4)$ SECDED on State Register | State Integrity | 9 FFs | **Active Rectification** (Freddin) |
| **Solution 5** | [`Solution 5.../`](./Solution%205%20-%20Dual%20Modular%20Redundancy) | Dual Modular Redundancy (DMR) + Dual Consensus AND Gate | Single-Core Faults | 9 FFs | **Strict Dual Consensus** |
| **Solution 6** | [`Solution 6.../`](./Solution%206%20-%20Triple%20Modular%20Redundancy) | Triple Modular Redundancy (TMR) + Majority Voter ($AB+BC+AC$) | Single-Core Faults | 12 FFs | **High Availability Masking** |
| **Unified Top**| [`Combined Testbench/`](./Combined%20Testbench) | Multi-Defense Benchmark Harness (`secure_fsm_top`) | Entire System | $\sim 19$ FFs | Diagnostic Benchmark |

---

## 📐 Architecture Block Diagrams

### 1. Baseline Architecture (Unprotected FSM)
```mermaid
flowchart LR
    subgraph Inputs
        CLK["clk"]
        RST["rst_n"]
        IN["auth_in"]
        FM["fault_mask[3:0]"]
    end

    subgraph Core_FSM ["Baseline FSM"]
        NSL["Next-State Logic<br/>(Combinational)"]
        XOR["XOR Fault Injection<br/>(next_state ^ fault_mask)"]
        DFF["4-bit State Register<br/>(state[3:0])"]
        OUT_LOGIC["Output Decoder<br/>(state == SUCCESS)"]
    end

    IN --> NSL
    NSL --> XOR
    FM --> XOR
    XOR --> DFF
    DFF -->|Feedback| NSL
    DFF --> OUT_LOGIC
    DFF --> S_OUT["state_out[3:0]"]
    OUT_LOGIC --> AG["access_granted"]
```

---

### 2. Solution 1: Input-Stream Running Parity Accumulator
```mermaid
flowchart LR
    subgraph Inputs
        IN["auth_in"]
        FM_S["fault_mask[3:0]"]
        FM_P["fault_mask[4]"]
    end

    subgraph FSM_Core ["FSM Core"]
        NSL["Next-State Logic"]
        XOR_S["XOR Gate"]
        DFF_S["State Register<br/>state[3:0]"]
    end

    subgraph Input_Parity_Engine ["Input-Stream Parity Engine"]
        XOR_IN["Running XOR<br/>parity ^ auth_in"]
        XOR_P["XOR Gate"]
        DFF_P["1-bit Parity Register<br/>(parity)"]
    end

    subgraph Auth_Decision ["Authorization Logic"]
        CMP_P{"parity == EXPECTED_PARITY?"}
        CMP_S{"state == SUCCESS?"}
        AND_GATE["Final Gate (AND)"]
    end

    IN --> NSL
    NSL --> XOR_S
    FM_S --> XOR_S
    XOR_S --> DFF_S
    DFF_S -->|Feedback| NSL
    DFF_S --> CMP_S

    IN --> XOR_IN
    DFF_P -->|Feedback| XOR_IN
    XOR_IN --> XOR_P
    FM_P --> XOR_P
    XOR_P --> DFF_P
    DFF_P --> CMP_P

    CMP_P --> AND_GATE
    CMP_S --> AND_GATE
    AND_GATE --> AG["access_granted"]
```

---

### 3. Solution 2: Self-Checking State-Register Invariant Parity Protection
```mermaid
flowchart LR
    subgraph Inputs
        IN["auth_in"]
        FM_S["fault_mask[3:0]"]
        FM_P["fault_mask[4]"]
    end

    subgraph State_Parity_Engine ["State & Invariant Generation"]
        NSL["Next-State Logic"]
        PAR_PRED["Parity Predictor Tree<br/>^next_state"]
        XOR_S["XOR Gate"]
        XOR_P["XOR Gate"]
        DFF_S["4-bit State Register<br/>state[3:0]"]
        DFF_P["1-bit Parity Register<br/>state_parity"]
    end

    subgraph Invariant_Monitor ["Continuous Invariant Checker"]
        PAR_ACT["Actual Parity Tree<br/>^state"]
        INV_CMP{"^state === state_parity?"}
        META_DET["Metastability Detector<br/>$isunknown({parity, state})"]
        ALARM["Sticky Alarm Latch<br/>(alarm <= 1'b1)"]
    end

    subgraph Gate ["Authorization Gate"]
        DEC["state == SUCCESS"]
        FINAL_AND["Security AND Gate"]
    end

    IN --> NSL
    NSL --> XOR_S
    NSL --> PAR_PRED
    PAR_PRED --> XOR_P

    FM_S --> XOR_S
    FM_P --> XOR_P

    XOR_S --> DFF_S
    XOR_P --> DFF_P

    DFF_S -->|Feedback| NSL
    DFF_S --> PAR_ACT
    DFF_S --> META_DET
    DFF_P --> META_DET
    DFF_P --> INV_CMP
    PAR_ACT --> INV_CMP

    INV_CMP -->|Mismatch| ALARM
    META_DET -->|Metastable 'x'| ALARM

    ALARM -->|Trip / Lockout| NSL
    ALARM -->|Block| FINAL_AND
    DEC --> FINAL_AND
    FINAL_AND --> AG["access_granted"]
```

---

### 4. Solution 3: Increased Minimum Hamming Distance ($d_{\min} \ge 2$) & Trap States
```mermaid
flowchart LR
    subgraph Inputs
        IN["auth_in"]
        FM["fault_mask[4:0]"]
    end

    subgraph Hamming_FSM ["5-bit Even-Weight FSM (d >= 2)"]
        DEC_NS["Next-State Decoder<br/>Even-Weight Codebook"]
        XOR_F["XOR Fault Mask"]
        REG_5B["5-bit State Register<br/>state[4:0]"]
        TRAP_CHK{"State in Even Codebook?"}
        TRAP_LOCK["Trap Action:<br/>next_state = TRAP_LOCKED (5'b11110)"]
    end

    subgraph Output_Logic ["Authentication Logic"]
        AUTH_CHK{"state == SUCCESS (5'b01001)?"}
    end

    IN --> DEC_NS
    DEC_NS --> XOR_F
    FM --> XOR_F
    XOR_F --> REG_5B
    REG_5B -->|Feedback| TRAP_CHK

    TRAP_CHK -->|Legitimate Even-Weight| DEC_NS
    TRAP_CHK -->|Odd-Weight Bit-Flip / Unmapped| TRAP_LOCK
    TRAP_LOCK --> XOR_F

    REG_5B --> AUTH_CHK
    AUTH_CHK --> AG["access_granted"]
    TRAP_CHK -->|In-Between Detected| TRAP_OUT["in_between_trap_out"]
```

---

### 5. Solution 4: Extended Hamming SECDED (8,4) On-the-Fly Rectification
```mermaid
flowchart LR
    subgraph Inputs
        IN["auth_in"]
        FM_S["fault_mask[3:0]"]
        FM_P["fault_mask[7:4]"]
    end

    subgraph Next_Gen ["Next State & Parity Prediction"]
        NSL["Next-State Logic"]
        HAM_ENC["SECDED Generator<br/>p1, p2, p4, p0"]
        XOR_S["XOR Gate"]
        XOR_P["XOR Gate"]
        DFF_S["State Register<br/>state[3:0]"]
        DFF_P["ECC Register<br/>hamming_parity[3:0]"]
    end

    subgraph SECDED_Decoder ["SECDED Syndrome & Rectifier"]
        SYN_DEC["Syndrome & Overall Parity<br/>S = {s3, s2, s1}, P_all"]
        ERR_CLASS{"Error Classification"}
        CORR_MUX["Correction Multiplexer<br/>Inverts error bit"]
        ALARM["Sticky Alarm Latch<br/>(alarm)"]
    end

    subgraph Final_Gate ["Access Decision"]
        AUTH_DEC{"corrected_state == SUCCESS?"}
        AND_GATE["Security AND Gate"]
    end

    IN --> NSL
    NSL --> HAM_ENC
    NSL --> XOR_S
    HAM_ENC --> XOR_P
    FM_S --> XOR_S
    FM_P --> XOR_P
    XOR_S --> DFF_S
    XOR_P --> DFF_P

    DFF_S --> SYN_DEC
    DFF_P --> SYN_DEC

    SYN_DEC --> ERR_CLASS
    ERR_CLASS -->|Single-Bit Error: P_all=1| CORR_MUX
    ERR_CLASS -->|Double-Bit Error: S!=0, P_all=0| ALARM
    ERR_CLASS -->|Unmapped Corrupted State| ALARM

    DFF_S --> CORR_MUX
    CORR_MUX -->|Corrected State Feedback| NSL
    CORR_MUX --> AUTH_DEC

    AUTH_DEC --> AND_GATE
    ALARM -->|Block Access| AND_GATE
    AND_GATE --> AG["access_granted"]
```

---

### 6. Solution 5: Dual Modular Redundancy (DMR / Dual Consensus)
```mermaid
flowchart LR
    subgraph Inputs
        IN["auth_in"]
        CLK["clk"]
        RST["rst_n"]
        FM_1["fault_mask[3:0]"]
        FM_2["fault_mask[7:4]"]
    end

    subgraph Redundant_Cores ["Dual Redundant Cores"]
        subgraph Core_1 ["Primary FSM (Core 1)"]
            NSL_1["Next-State Logic 1"]
            REG_1["State Register 1<br/>state_1[3:0]"]
            DEC_1["Auth Decoder 1<br/>(state_1 == SUCCESS)"]
        end

        subgraph Core_2 ["Secondary FSM (Core 2)"]
            NSL_2["Next-State Logic 2"]
            REG_2["State Register 2<br/>state_2[3:0]"]
            DEC_2["Auth Decoder 2<br/>(state_2 == SUCCESS)"]
        end
    end

    subgraph Consensus_Security ["Consensus & Comparison"]
        CMP{"Comparator<br/>state_1 != state_2?"}
        ALARM["Sticky Alarm Latch<br/>(alarm)"]
        AND_AUTH["Dual Consensus AND Gate<br/>auth_1 & auth_2"]
        GATE["Final Gate"]
    end

    IN --> NSL_1
    IN --> NSL_2
    FM_1 --> REG_1
    FM_2 --> REG_2
    NSL_1 --> REG_1
    NSL_2 --> REG_2

    REG_1 -->|Feedback| NSL_1
    REG_2 -->|Feedback| NSL_2

    REG_1 --> DEC_1
    REG_2 --> DEC_2

    REG_1 --> CMP
    REG_2 --> CMP

    CMP -->|Mismatch Detected| ALARM
    ALARM -->|Force Lockout| GATE

    DEC_1 --> AND_AUTH
    DEC_2 --> AND_AUTH
    AND_AUTH --> GATE

    GATE --> AG["access_granted"]
```

---

### 7. Solution 6: Triple Modular Redundancy (TMR / Majority Voting)
```mermaid
flowchart LR
    subgraph Inputs
        IN["auth_in"]
        FM_A["fault_mask[3:0]"]
        FM_B["fault_mask[7:4]"]
        FM_C["fault_mask[11:8]"]
    end

    subgraph TMR_Cores ["Triplicated FSM Cores"]
        subgraph Core_A ["FSM Core A"]
            REG_A["State Register A<br/>sA[3:0]"]
            AUTH_A["Auth Flag A<br/>(sA == SUCCESS)"]
        end

        subgraph Core_B ["FSM Core B"]
            REG_B["State Register B<br/>sB[3:0]"]
            AUTH_B["Auth Flag B<br/>(sB == SUCCESS)"]
        end

        subgraph Core_C ["FSM Core C"]
            REG_C["State Register C<br/>sC[3:0]"]
            AUTH_C["Auth Flag C<br/>(sC == SUCCESS)"]
        end
    end

    subgraph Voter_Block ["Majority Consensus Voting Logic"]
        VOTER_STATE["Bitwise State Voter<br/>(A & B) | (B & C) | (A & C)"]
        VOTER_AUTH["Majority Authorization Voter<br/>(aA & aB) | (aB & aC) | (aA & aC)"]
        DISAG_CHK{"Disagreement Detector<br/>!(sA==sB && sB==sC)"}
    end

    IN --> REG_A
    IN --> REG_B
    IN --> REG_C

    FM_A --> REG_A
    FM_B --> REG_B
    FM_C --> REG_C

    REG_A --> AUTH_A
    REG_B --> AUTH_B
    REG_C --> AUTH_C

    REG_A --> VOTER_STATE
    REG_B --> VOTER_STATE
    REG_C --> VOTER_STATE

    REG_A --> DISAG_CHK
    REG_B --> DISAG_CHK
    REG_C --> DISAG_CHK

    AUTH_A --> VOTER_AUTH
    AUTH_B --> VOTER_AUTH
    AUTH_C --> VOTER_AUTH

    VOTER_STATE --> S_OUT["state_out[3:0] (Voted)"]
    VOTER_AUTH --> AG["access_granted"]
    DISAG_CHK --> DISAG_OUT["disagreement_detected"]
```

---

### 8. Combined Top-Level Architecture (`secure_fsm_top`)
```mermaid
flowchart TD
    subgraph Stimulus ["System Stimulus"]
        IN["Serial auth_in"]
        CLK["clk"]
        RST["rst_n"]
        FM["fault_mask[3:0] (Targeted on Core A)"]
    end

    subgraph Cores ["Triplicated Core Hierarchy"]
        FSM_A["auth_fsm (Core A - Attacked)<br/>fault_mask = FM"]
        FSM_B["auth_fsm (Core B - Golden)<br/>fault_mask = 0000"]
        FSM_C["auth_fsm (Core C - Golden)<br/>fault_mask = 0000"]
    end

    subgraph Detectors ["Unified Multi-Defense Detectors"]
        PAR_DET["parity_detector<br/>(^state_out) ^ parity_a"]
        DMR_DET["dmr_detector<br/>state_a != state_b"]
        TMR_VOT["tmr_voter<br/>Majority State & Faulty Core"]
        ECC_DET["ecc_detector (SECDED 8,4)<br/>Syndrome, Correction, Uncorrectable"]
    end

    subgraph Outputs ["Unified Telemetry & Access"]
        P_ERR["parity_err"]
        D_ERR["dmr_err"]
        T_ERR["tmr_err & tmr_faulty[2:0]"]
        V_STATE["voted_state[3:0]"]
        E_FLAGS["ecc_err, ecc_corr, ecc_unc"]
        E_STATE["ecc_state[3:0] & ecc_pos"]
        COMB_ALARM["attack_detected (OR-Reduction)"]
        RAW_AG["access_granted (Core A raw)"]
    end

    IN --> FSM_A
    IN --> FSM_B
    IN --> FSM_C
    FM --> FSM_A

    FSM_A -->|state_out, parity_a, ecc_a| PAR_DET
    FSM_A -->|state_out| DMR_DET
    FSM_B -->|state_b| DMR_DET

    FSM_A -->|state_out| TMR_VOT
    FSM_B -->|state_b| TMR_VOT
    FSM_C -->|state_c| TMR_VOT

    FSM_A -->|state_out, ecc_a| ECC_DET
    FSM_A --> RAW_AG

    PAR_DET --> P_ERR
    DMR_DET --> D_ERR
    TMR_VOT --> T_ERR
    TMR_VOT --> V_STATE
    ECC_DET --> E_FLAGS
    ECC_DET --> E_STATE

    P_ERR --> COMB_ALARM
    D_ERR --> COMB_ALARM
    T_ERR --> COMB_ALARM
    E_FLAGS --> COMB_ALARM
```

---

## 📊 Benchmark & Experimental Results

The unified verification suite evaluated **202 distinct fault injections** across all 9 operating states (`IDLE`, `GOT_1`, `GOT_10`, `GOT_101`, `SUCCESS`, `ERR_1`, `ERR_2`, `ERR_3`, `LOCKED`):

| Countermeasure | Faults Injected | Fault Detection Rate (FDR) | Fault Masking Rate (FMR) | Attack Success Rate (ASR) | Key Finding |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **Baseline FSM** | 202 | 0.0% (0 / 202) | 0.0% | **14.85% Bypass** | Raw bypass occurs whenever bit-flips hit `0111`. |
| **Parity Check** | 202 | **51.49%** (104 / 202) | N/A | **48.51% Undetected** | **Blind to even-weight masks** (`0011`, `1111`). |
| **DMR Consensus** | 202 | **100.0%** (202 / 202) | N/A | **0.0% Bypass** | 100% deauth lock on any single-core divergence. |
| **TMR Voter** | 202 | **100.0%** (202 / 202) | **100.0%** (202 / 202) | **0.0% Bypass** | 100% transparent on-the-fly masking of single-core errors. |
| **SECDED (8,4)** | 202 | **100.0%** (202 / 202) | **100.0% of 1-bit** (52/52)| **0.0% Bypass** | Dynamically rectifies single-bit faults; locks out multi-bit attacks. |

> **Comprehensive Reports:** Full datasets and graphical dashboards are available in [`Combined Testbench/CS203_Fault_Resilience_Benchmark_Report.xlsx`](./Combined%20Testbench/CS203_Fault_Resilience_Benchmark_Report.xlsx) and [`Combined Testbench/attack_results_exhaustive.csv`](./Combined%20Testbench/attack_results_exhaustive.csv).

---

## 📁 Repository Structure

```text
DLD Project/
├── README.md                                   # Project documentation & architecture diagrams
├── CS203_Fault_Resilience_Benchmark_Report.xlsx# Multi-sheet Excel benchmark workbook
│
├── Combined Testbench/                         # Unified multi-defense top module & testbench
│   ├── design.sv                               # secure_fsm_top RTL wrapper
│   ├── testbench.sv                            # 202-injection verification suite (TC-01 to TC-05)
│   ├── attack_results_exhaustive.csv           # Tabular export of all 202 fault outcomes
│   ├── detect.vcd                              # GTKWave simulation trace dump
│   ├── logs.txt                                # Raw compiler & simulator output
│   └── run_sim.ps1 / run_sim.bat               # One-click automated simulation scripts
│
├── FSM/                                        # Baseline unprotected 4-bit FSM
├── Solution 1 - Simple 1 bit parity check/     # Input-stream XOR accumulator
├── Solution 2 - Parity Protected State Register/# Invariant state parity & sticky alarm
├── Solution 3 - Increased Hamming Distance/    # Even-weight d_min >= 2 encoding
├── Solution 4 - Extended Hamming SECDED/       # SECDED (8,4) dynamic rectification FSM
├── Solution 5 - Dual Modular Redundancy/       # Dual consensus FSM with comparator
└── Solution 6 - Triple Modular Redundancy/     # Triplicated FSM with majority voter
```

---

## 🚀 Quickstart & Simulation

### Prerequisites
* [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog`, `vvp`)
* [GTKWave](http://gtkwave.sourceforge.net/) (for `.vcd` waveform inspection)

### Run the Unified Benchmark Suite
```powershell
cd "Combined Testbench"
.\run_sim.ps1
# or on CMD: run_sim.bat
```

### Run Any Discrete Standalone Solution
```powershell
# Example: Run Solution 4 (Extended Hamming SECDED)
cd "Solution 4 - Extended Hamming SECDED"
.\run_sim.ps1

# View waveforms in GTKWave
gtkwave fsm_simulation.vcd
```

---

## 👥 Team & Individual Contributions (CS203)

* **Instructor:** Dr. Geeta — *Department of Computer Science & Engineering*
* **Team Members & Responsibilities:**
  * **Freddin (2025CSB1416) [Lead]:**
    * Designed and implemented **Solutions 1 through 4** in Verilog RTL and C++:
      * Solution 1: Input-Stream Running Parity Accumulator
      * Solution 2: Parity Protected State Register with Sticky Alarm
      * Solution 3: Increased Hamming Distance ($d_{\min} \ge 2$) Even-Weight State Encoding
      * Solution 4: Extended Hamming $(8, 4)$ SECDED with Dynamic Error Rectification
  * **Uttkarsh Goyal (2025CSB1394):**
    * Designed and implemented **Solutions 5 and 6** in Verilog RTL and C++:
      * Solution 5: Dual Modular Redundancy (DMR) with Fail-Secure Comparator
      * Solution 6: Triple Modular Redundancy (TMR) with Majority Voting Logic
  * **Tanmay Kumar Jayant (2025CSB1263):**
    * Baseline FSM architecture and state transition pipeline.
    * Designed the top-level integration wrapper [`Combined Testbench/design.sv`](./Combined%20Testbench/design.sv) (`secure_fsm_top`) orchestrating all countermeasure modules.
  * **Ayush Awasthi (2025CSB1311):**
    * Developed the 202-fault exhaustive testbench suite in [`Combined Testbench/testbench.sv`](./Combined%20Testbench/testbench.sv).
    * Executed the **Attack Analysis** (evaluating FDR, FMR, and ASR across all 9 operating states).
    * Co-authored the multi-sheet benchmark Excel workbook (`CS203_Fault_Resilience_Benchmark_Report.xlsx`).
  * **Dane Prince Daniel (2025CSB1548):**
    * Conducted the **Time and Hardware Area Analysis** (evaluating flip-flop overhead, gate complexities, and critical path timings).
    * Co-authored the multi-sheet benchmark Excel workbook (`CS203_Fault_Resilience_Benchmark_Report.xlsx`).
    * Timing verification and waveform hazard inspection.
