// CS203 Fault-Resilient Secure FSM Interactive Hardware Simulator Engine
(function () {
  const DATA = window.DLD_PROJECT_DATA;

  // --- Global Simulator State ---
  const sim = {
    arch: "unified",          // unified | baseline | sol1 | sol2 | sol3 | sol4 | sol5 | sol6
    cycle: 0,
    timeNs: 0,
    authIn: 1,                // Next serial input bit (1 or 0)
    faultMask: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], // Up to 12 bits for TMR
    metastableMode: false,    // Inject 'x' setup/hold violation
    autoPlayTimer: null,

    // Core Registers
    stateA: "0000",           // 4-bit (or 5-bit in sol3)
    stateB: "0000",           // Golden / Secondary core
    stateC: "0000",           // Tertiary core (TMR)
    parityFF: 0,              // Sol 1 running input parity or Sol 2/Unified state parity
    eccFF: "0000",            // 4-bit Hamming parity {p0, p4, p2, p1}
    alarmLatched: false,      // Sticky lockout latch (Sol 1, 2, 4, 5)
    inputHistory: [],         // Bits shifted in since reset

    // Combinational Telemetry Outputs
    telemetry: {
      goldenNext: "0000",
      rawAccess: 0,
      safeAccess: 0,
      parityErr: 0,
      dmrErr: 0,
      tmrErr: 0,
      tmrFaulty: "000",
      votedState: "0000",
      eccSyndrome: "000",
      eccOverall: 0,
      eccErr: 0,
      eccCorr: 0,
      eccUnc: 0,
      eccPos: "0000",
      eccState: "0000",
      trapTriggered: 0,
      metastableDetected: 0,
      attackDetected: 0,
      statusBanner: "SYSTEM IDLE — READY FOR CLOCK EDGE",
      statusType: "neutral" // neutral | ok | warn | breach | rectified
    },

    // Waveform History (last 24 clock edges)
    waveHistory: [],
    // Cycle Log History
    consoleLogs: []
  };

  // --- Helper Bitwise & Encoding Functions ---
  function xorBits(binA, binB) {
    if (binA.includes("x") || binB.includes("x")) return "xxxx".slice(0, binA.length);
    let out = "";
    for (let i = 0; i < binA.length; i++) {
      out += (binA[i] === binB[i]) ? "0" : "1";
    }
    return out;
  }

  function parityOf(binStr) {
    if (binStr.includes("x")) return "x";
    let p = 0;
    for (let i = 0; i < binStr.length; i++) {
      if (binStr[i] === "1") p ^= 1;
    }
    return p;
  }

  function weightOf(binStr) {
    let w = 0;
    for (let i = 0; i < binStr.length; i++) {
      if (binStr[i] === "1") w++;
    }
    return w;
  }

  function encodeHamming84(dStr) {
    if (dStr.includes("x")) return "xxxx";
    const d0 = Number(dStr[3]);
    const d1 = Number(dStr[2]);
    const d2 = Number(dStr[1]);
    const d3 = Number(dStr[0]);
    const p1 = d0 ^ d1 ^ d3;
    const p2 = d0 ^ d2 ^ d3;
    const p4 = d1 ^ d2 ^ d3;
    const p0 = d0 ^ d1 ^ d2 ^ d3 ^ p1 ^ p2 ^ p4;
    return `${p0}${p4}${p2}${p1}`;
  }

  function decodeHamming84(stateStr, eccStr) {
    if (stateStr.includes("x") || eccStr.includes("x")) {
      return {
        syn: "xxx",
        overall: 1,
        eccErr: 1,
        eccCorr: 0,
        eccUnc: 1,
        eccPos: "0000",
        eccState: "xxxx"
      };
    }
    const s0 = Number(stateStr[3]);
    const s1 = Number(stateStr[2]);
    const s2 = Number(stateStr[1]);
    const s3 = Number(stateStr[0]);

    const p1_q = Number(eccStr[3]);
    const p2_q = Number(eccStr[2]);
    const p4_q = Number(eccStr[1]);
    const p0_q = Number(eccStr[0]);

    const cp1 = s0 ^ s1 ^ s3;
    const cp2 = s0 ^ s2 ^ s3;
    const cp4 = s1 ^ s2 ^ s3;

    const syn1 = cp1 ^ p1_q;
    const syn2 = cp2 ^ p2_q;
    const syn4 = cp4 ^ p4_q;
    const synVal = (syn4 << 2) | (syn2 << 1) | syn1;
    const synStr = `${syn4}${syn2}${syn1}`;

    const overall = s3 ^ s2 ^ s1 ^ s0 ^ p0_q ^ p4_q ^ p2_q ^ p1_q;

    let pos = "0000";
    if (synVal === 3) pos = "0001";
    else if (synVal === 5) pos = "0010";
    else if (synVal === 6) pos = "0100";
    else if (synVal === 7) pos = "1000";

    const eccErr = (synVal !== 0 || overall === 1) ? 1 : 0;
    const eccCorr = (overall === 1 && pos !== "0000") ? 1 : 0;
    const eccUnc = (eccErr === 1 && eccCorr === 0) ? 1 : 0;
    const eccPos = eccCorr ? pos : "0000";
    const eccState = xorBits(stateStr, eccPos);

    return { syn: synStr, overall, eccErr, eccCorr, eccUnc, eccPos, eccState };
  }

  function bitwiseMajority4(a, b, c) {
    if (a.includes("x")) return b; // Core B & C golden consensus
    let out = "";
    for (let i = 0; i < 4; i++) {
      const ba = Number(a[i]);
      const bb = Number(b[i]);
      const bc = Number(c[i]);
      const v = (ba & bb) | (ba & bc) | (bb & bc);
      out += String(v);
    }
    return out;
  }

  function nextState4Bit(currState, authBit, defaultToLocked) {
    if (currState.includes("x")) return defaultToLocked ? "0011" : "0000";
    switch (currState) {
      case "0000": return authBit === 1 ? "0100" : "1000";
      case "0100": return authBit === 0 ? "0101" : "1001";
      case "0101": return authBit === 1 ? "0110" : "1010";
      case "0110": return authBit === 0 ? "0111" : "0011";
      case "1000": return "1001";
      case "1001": return "1010";
      case "1010": return "0011";
      case "0111": return "0111";
      case "0011": return "0011";
      default:     return defaultToLocked ? "0011" : "0000";
    }
  }

  function nextState5BitSol3(currState, authBit) {
    if (currState.includes("x")) return { next: "11110", trap: 1 };
    switch (currState) {
      case "00000": return { next: authBit === 1 ? "00011" : "01010", trap: 0 };
      case "00011": return { next: authBit === 0 ? "00101" : "01100", trap: 0 };
      case "00101": return { next: authBit === 1 ? "00110" : "10001", trap: 0 };
      case "00110": return { next: authBit === 0 ? "01001" : "10010", trap: 0 };
      case "01010": return { next: "01100", trap: 0 };
      case "01100": return { next: "10001", trap: 0 };
      case "10001": return { next: "10010", trap: 0 };
      case "01001": return { next: "01001", trap: 0 };
      case "10010": return { next: "10010", trap: 0 };
      case "11110": return { next: "11110", trap: 0 };
      default:      return { next: "11110", trap: 1 };
    }
  }

  function getStateName(code) {
    if (code.includes("x")) return "METASTABLE ('x')";
    if (sim.arch === "sol3") {
      return DATA.states5BitSol3[code] ? DATA.states5BitSol3[code].name : "UNMAPPED_ODD_TRAP";
    }
    return DATA.states4Bit[code] ? DATA.states4Bit[code].name : "CORRUPTED_UNMAPPED";
  }

  function getMaskString(numBits) {
    if (sim.metastableMode) {
      return numBits === 5 ? "000x0" : (numBits === 8 ? "000000x0" : "00x0");
    }
    let s = "";
    for (let i = numBits - 1; i >= 0; i--) {
      s += sim.faultMask[i] ? "1" : "0";
    }
    return s;
  }

  // --- Reset Simulator ---
  function resetSimulator(logMsg) {
    if (sim.autoPlayTimer) {
      clearInterval(sim.autoPlayTimer);
      sim.autoPlayTimer = null;
      updateAutoPlayButton();
    }
    sim.cycle = 0;
    sim.timeNs = 0;
    sim.stateA = (sim.arch === "sol3") ? "00000" : "0000";
    sim.stateB = "0000";
    sim.stateC = "0000";
    sim.parityFF = 0;
    sim.eccFF = "0000";
    sim.alarmLatched = false;
    sim.inputHistory = [];
    sim.metastableMode = false;

    sim.telemetry = {
      goldenNext: (sim.arch === "sol3") ? "00000" : "0000",
      rawAccess: 0,
      safeAccess: 0,
      parityErr: 0,
      dmrErr: 0,
      tmrErr: 0,
      tmrFaulty: "000",
      votedState: "0000",
      eccSyndrome: "000",
      eccOverall: 0,
      eccErr: 0,
      eccCorr: 0,
      eccUnc: 0,
      eccPos: "0000",
      eccState: "0000",
      trapTriggered: 0,
      metastableDetected: 0,
      attackDetected: 0,
      statusBanner: "RESET ASSERTED (rst_n = 0 -> 1) — FSM IN IDLE STATE",
      statusType: "neutral"
    };

    sim.waveHistory = [{
      cycle: 0,
      timeNs: 0,
      authIn: sim.authIn,
      mask: (sim.arch === "sol3") ? "00000" : "0000",
      stateA: sim.stateA,
      goldenState: sim.stateB,
      votedState: "0000",
      eccState: "0000",
      rawAccess: 0,
      safeAccess: 0,
      parityErr: 0,
      dmrErr: 0,
      tmrErr: 0,
      eccErr: 0,
      eccCorr: 0,
      eccUnc: 0,
      alarm: 0
    }];

    if (logMsg !== false) {
      appendConsoleLog(`[t=0ns] RESET (rst_n=0): FSM initialized to IDLE (${sim.stateA}). Ready for serial PIN '1010'.`, "info");
    }
    renderAll();
  }

  // --- Execute One Rising Clock Edge (posedge clk) ---
  function stepClock(overrideBit, overrideMaskStr, keepMaskAfterStep) {
    const bit = (overrideBit !== undefined && overrideBit !== null) ? Number(overrideBit) : sim.authIn;
    sim.authIn = bit;
    sim.cycle += 1;
    sim.timeNs = sim.cycle * 10;
    sim.inputHistory.push(bit);

    const archObj = DATA.architectures.find(a => a.id === sim.arch) || DATA.architectures[0];
    const maskBitsCount = archObj.maskBits;
    const maskStr = overrideMaskStr || getMaskString(maskBitsCount);
    const mask4 = maskStr.slice(-4);
    const hasFault = maskStr.includes("1") || maskStr.includes("x");

    if (sim.arch === "sol3") {
      // 5-bit Even-Weight Hamming Distance >= 2
      const resCurr = nextState5BitSol3(sim.stateA, bit);
      const goldenNext5 = resCurr.next;
      const mask5 = maskStr.padStart(5, "0").slice(-5);
      const injected5 = mask5.includes("x") ? "xxxxx" : xorBits(goldenNext5, mask5);
      sim.stateA = injected5;

      const checkAfter = nextState5BitSol3(sim.stateA, 0);
      const isTrapped = checkAfter.trap === 1 || sim.stateA === "11110" || sim.stateA.includes("x");
      const access = (sim.stateA === "01001") ? 1 : 0;

      sim.telemetry.goldenNext = goldenNext5;
      sim.telemetry.rawAccess = access;
      sim.telemetry.safeAccess = access;
      sim.telemetry.trapTriggered = isTrapped ? 1 : 0;
      sim.telemetry.attackDetected = isTrapped ? 1 : 0;
      sim.telemetry.votedState = goldenNext5;
      sim.telemetry.eccState = sim.stateA;

      if (isTrapped) {
        sim.telemetry.statusBanner = `SOL 3 TRAP TRIGGERED! Odd-Weight/Unmapped State (${sim.stateA}) -> Redirecting to TRAP_LOCKED (11110)`;
        sim.telemetry.statusType = "rectified";
      } else if (access === 1) {
        sim.telemetry.statusBanner = `AUTHENTICATED (SUCCESS = 01001) — Access Granted`;
        sim.telemetry.statusType = "ok";
      } else {
        sim.telemetry.statusBanner = `Cycle ${sim.cycle}: State = ${getStateName(sim.stateA)} (${sim.stateA})`;
        sim.telemetry.statusType = "neutral";
      }
    } else {
      // 4-bit based architectures (Unified, Baseline, Sol 1, Sol 2, Sol 4, Sol 5, Sol 6)
      // In Sol 4 standalone, next_state is computed from corrected_state!
      const effectiveCurrStateA = (sim.arch === "sol4" && !sim.stateA.includes("x"))
        ? sim.telemetry.eccState || sim.stateA
        : sim.stateA;

      const defaultLocked = ["sol1", "sol4", "sol5", "sol6"].includes(sim.arch);
      let nextA = nextState4Bit(effectiveCurrStateA, bit, defaultLocked);
      if (sim.alarmLatched && ["sol1", "sol2", "sol4"].includes(sim.arch)) {
        nextA = "0011"; // Alarm forces LOCKED
      }

      const nextB = nextState4Bit(sim.stateB, bit, defaultLocked);
      const nextC = nextState4Bit(sim.stateC, bit, defaultLocked);

      const nextParityPred = parityOf(nextA);
      const nextEccPred = encodeHamming84(nextA);

      // Apply Fault Masks per architecture
      let injectedA = mask4.includes("x") ? "xxxx" : xorBits(nextA, mask4);
      let injectedB = nextB;
      let injectedC = nextC;

      if (sim.arch === "sol5" && maskStr.length >= 8) {
        const maskCore2 = maskStr.slice(0, 4);
        injectedB = xorBits(nextB, maskCore2);
      } else if (sim.arch === "sol6" && maskStr.length >= 12) {
        const maskC = maskStr.slice(0, 4);
        const maskB = maskStr.slice(4, 8);
        injectedB = xorBits(nextB, maskB);
        injectedC = xorBits(nextC, maskC);
      }

      // Update Parity & ECC Registers
      if (sim.arch === "sol1") {
        const pFlip = maskStr.length >= 5 ? Number(maskStr[0] === "1") : 0;
        if (maskStr.includes("x")) {
          sim.parityFF = "x";
        } else {
          sim.parityFF = (Number(sim.parityFF) ^ bit) ^ pFlip;
        }
      } else if (sim.arch === "sol2") {
        const pFlip = maskStr.length >= 5 ? Number(maskStr[0] === "1") : 0;
        sim.parityFF = maskStr.includes("x") ? "x" : (nextParityPred ^ pFlip);
      } else {
        sim.parityFF = nextParityPred;
      }

      if (sim.arch === "sol4" && maskStr.length >= 8) {
        const eccMask = maskStr.slice(0, 4);
        sim.eccFF = maskStr.includes("x") ? "xxxx" : xorBits(nextEccPred, eccMask);
      } else {
        sim.eccFF = nextEccPred;
      }

      sim.stateA = injectedA;
      sim.stateB = injectedB;
      sim.stateC = injectedC;

      // Evaluate Detectors
      const isMeta = sim.stateA.includes("x") || String(sim.parityFF).includes("x") || sim.eccFF.includes("x");
      const actualParityA = parityOf(sim.stateA);

      let parityErr = 0;
      if (isMeta) {
        parityErr = 1;
      } else if (sim.arch === "sol1") {
        // In Sol 1, expected running parity at SUCCESS (after 1,0,1,0) is 0
        parityErr = (sim.stateA === "0111" && sim.parityFF !== 0) ? 1 : 0;
      } else {
        parityErr = (actualParityA !== sim.parityFF) ? 1 : 0;
      }

      const dmrErr = (isMeta || sim.stateA !== sim.stateB) ? 1 : 0;
      const voted = bitwiseMajority4(sim.stateA, sim.stateB, sim.stateC);
      const tmrErr = (isMeta || sim.stateA !== sim.stateB || sim.stateA !== sim.stateC || sim.stateB !== sim.stateC) ? 1 : 0;
      const faultyA = (sim.stateA !== voted) ? "1" : "0";
      const faultyB = (sim.stateB !== voted) ? "1" : "0";
      const faultyC = (sim.stateC !== voted) ? "1" : "0";
      const tmrFaulty = `${faultyC}${faultyB}${faultyA}`;

      const eccDec = decodeHamming84(sim.stateA, sim.eccFF);
      const unmappedAfterEcc = !DATA.states4Bit[eccDec.eccState];

      if (isMeta || (sim.arch === "sol2" && parityErr) || (sim.arch === "sol4" && (eccDec.eccUnc || unmappedAfterEcc)) || (sim.arch === "sol5" && dmrErr)) {
        sim.alarmLatched = true;
      }

      const rawAccess = (sim.stateA === "0111") ? 1 : 0;
      let safeAccess = rawAccess;
      if (sim.arch === "sol1") {
        safeAccess = (!sim.alarmLatched && !isMeta && sim.stateA === "0111" && sim.parityFF === 0) ? 1 : 0;
      } else if (sim.arch === "sol2") {
        safeAccess = (!sim.alarmLatched && !isMeta && !parityErr && sim.stateA === "0111") ? 1 : 0;
      } else if (sim.arch === "sol4") {
        safeAccess = (!sim.alarmLatched && !isMeta && !eccDec.eccUnc && !unmappedAfterEcc && eccDec.eccState === "0111") ? 1 : 0;
      } else if (sim.arch === "sol5") {
        safeAccess = (!sim.alarmLatched && !isMeta && !dmrErr && sim.stateA === "0111" && sim.stateB === "0111") ? 1 : 0;
      } else if (sim.arch === "sol6") {
        const aA = sim.stateA === "0111" ? 1 : 0;
        const aB = sim.stateB === "0111" ? 1 : 0;
        const aC = sim.stateC === "0111" ? 1 : 0;
        safeAccess = (aA & aB) | (aB & aC) | (aA & aC);
      } else if (sim.arch === "unified") {
        safeAccess = (voted === "0111" && !dmrErr) ? 1 : 0;
      }

      const attackDetected = (parityErr | dmrErr | tmrErr | eccDec.eccErr | (isMeta ? 1 : 0)) ? 1 : 0;

      sim.telemetry = {
        goldenNext: nextB,
        rawAccess,
        safeAccess,
        parityErr,
        dmrErr,
        tmrErr,
        tmrFaulty,
        votedState: voted,
        eccSyndrome: eccDec.syn,
        eccOverall: eccDec.overall,
        eccErr: eccDec.eccErr,
        eccCorr: eccDec.eccCorr,
        eccUnc: eccDec.eccUnc,
        eccPos: eccDec.eccPos,
        eccState: eccDec.eccState,
        trapTriggered: 0,
        metastableDetected: isMeta ? 1 : 0,
        attackDetected,
        statusBanner: "",
        statusType: "neutral"
      };

      // Determine Status Banner & Console Log
      const isBypassBreach = (rawAccess === 1 && nextB !== "0111");
      if (isMeta) {
        sim.telemetry.statusBanner = `METASTABLE GLITCH ('x') DETECTED! Setup/Hold Violation Caught -> Alarm Latched & Access Blocked`;
        sim.telemetry.statusType = "rectified";
        appendConsoleLog(`[t=${sim.timeNs}ns] METASTABILITY ATTACK (mask=${maskStr}): state=xxxx caught by $isunknown detector! Alarm=1.`, "warn");
      } else if (hasFault) {
        if (isBypassBreach && sim.arch === "baseline") {
          sim.telemetry.statusBanner = `CRITICAL AUTHENTICATION BYPASS! Baseline FSM forced from ${getStateName(nextB)} (${nextB}) to SUCCESS (0111)!`;
          sim.telemetry.statusType = "breach";
          appendConsoleLog(`[t=${sim.timeNs}ns] BREACH! Mask ${maskStr} flipped ${nextB} -> 0111 (SUCCESS). Baseline access_granted=1!`, "danger");
        } else if (isBypassBreach) {
          const parMsg = parityErr ? "Parity=CAUGHT" : "Parity=BLIND(Even-Wt)";
          const eccMsg = eccDec.eccCorr ? `SECDED=RECTIFIED(${eccDec.eccState})` : `SECDED=UNCORRECTABLE_LOCKOUT`;
          sim.telemetry.statusBanner = `BYPASS THWARTED! Raw Core A hit 0111, but defenses blocked unauthorized access (${parMsg}, DMR=1, TMR=${voted}, ${eccMsg})`;
          sim.telemetry.statusType = "rectified";
          appendConsoleLog(`[t=${sim.timeNs}ns] BYPASS THWARTED (mask=${maskStr}): Raw=0111 | ${parMsg} | DMR=1 | TMR_Vote=${voted} | ${eccMsg}`, "success");
        } else if (eccDec.eccCorr) {
          sim.telemetry.statusBanner = `1-BIT FAULT RECTIFIED ON-THE-FLY! Mask ${maskStr} flipped bit (${eccDec.eccPos}); SECDED Syndrome=${eccDec.syn} & TMR healed state to ${eccDec.eccState} (${getStateName(eccDec.eccState)})`;
          sim.telemetry.statusType = "rectified";
          appendConsoleLog(`[t=${sim.timeNs}ns] 1-BIT FIXED (mask=${maskStr}): Corrupted=${sim.stateA} -> SECDED Syndrome=${eccDec.syn} located bit ${eccDec.eccPos} -> Rectified=${eccDec.eccState}`, "success");
        } else {
          const parNote = parityErr ? "Parity=1" : "Parity=0 (BLIND)";
          sim.telemetry.statusBanner = `MULTI-BIT FAULT DETECTED (Weight=${weightOf(mask4)})! ${parNote} | DMR=1 | TMR Masked->${voted} | SECDED=Uncorrectable Lockout`;
          sim.telemetry.statusType = "warn";
          appendConsoleLog(`[t=${sim.timeNs}ns] MULTI-BIT ATTACK (mask=${maskStr}, wt=${weightOf(mask4)}): Corrupted=${sim.stateA} | ${parNote} | DMR=1 | TMR_Voted=${voted} | ECC_Unc=1`, "warn");
        }
      } else {
        if (safeAccess === 1) {
          sim.telemetry.statusBanner = `VALID PIN '1010' AUTHENTICATED! FSM reached SUCCESS (0111) — access_granted = 1`;
          sim.telemetry.statusType = "ok";
          appendConsoleLog(`[t=${sim.timeNs}ns] AUTHENTICATION SUCCESS: State=0111 (SUCCESS), access_granted=1, zero faults.`, "success");
        } else if (sim.stateA === "0011") {
          sim.telemetry.statusBanner = `TERMINAL LOCKOUT (LOCKED = 0011) — Constant-time rejection complete; reset required`;
          sim.telemetry.statusType = "warn";
          appendConsoleLog(`[t=${sim.timeNs}ns] LOCKED (0011): Invalid sequence rejected in constant 4-cycle pipeline. access_granted=0.`, "info");
        } else {
          sim.telemetry.statusBanner = `Clock Cycle ${sim.cycle} (t=${sim.timeNs}ns): Input auth_in=${bit} -> State ${getStateName(sim.stateA)} (${sim.stateA})`;
          sim.telemetry.statusType = "neutral";
          appendConsoleLog(`[t=${sim.timeNs}ns] STEP auth_in=${bit}, mask=${maskStr} -> state=${sim.stateA} (${getStateName(sim.stateA)})`, "info");
        }
      }
    }

    // Record Waveform Snapshot
    sim.waveHistory.push({
      cycle: sim.cycle,
      timeNs: sim.timeNs,
      authIn: bit,
      mask: maskStr,
      stateA: sim.stateA,
      goldenState: sim.stateB,
      votedState: sim.telemetry.votedState,
      eccState: sim.telemetry.eccState,
      rawAccess: sim.telemetry.rawAccess,
      safeAccess: sim.telemetry.safeAccess,
      parityErr: sim.telemetry.parityErr,
      dmrErr: sim.telemetry.dmrErr,
      tmrErr: sim.telemetry.tmrErr,
      eccErr: sim.telemetry.eccErr,
      eccCorr: sim.telemetry.eccCorr,
      eccUnc: sim.telemetry.eccUnc,
      alarm: sim.telemetry.attackDetected
    });
    if (sim.waveHistory.length > 22) {
      sim.waveHistory.shift();
    }

    // Clear one-shot fault mask after clock edge (matches testbench `step` task)
    if (!keepMaskAfterStep) {
      sim.faultMask = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      sim.metastableMode = false;
    }

    renderAll();
  }

  // --- Preset Test Scenarios (TC-01 to TC-06) ---
  function runPresetScenario(presetId) {
    resetSimulator(false);
    if (presetId === "tc01") {
      appendConsoleLog("=== Running TC-01: Normal Pass (Valid PIN 1 -> 0 -> 1 -> 0, Fault-Free) ===", "info");
      const seq = [1, 0, 1, 0];
      seq.forEach(b => stepClock(b, "0000", false));
      showToast("TC-01 Executed: Valid PIN 1010 -> SUCCESS (0111)");
    } else if (presetId === "tc02") {
      appendConsoleLog("=== Running TC-02: Normal Fail (Wrong PIN 0 -> 0 -> 0 -> 0, Constant-Time Pipeline) ===", "info");
      const seq = [0, 0, 0, 0];
      seq.forEach(b => stepClock(b, "0000", false));
      showToast("TC-02 Executed: Wrong PIN 0000 -> Constant-Time LOCKED (0011)");
    } else if (presetId === "tc03") {
      appendConsoleLog("=== Running TC-03: Targeted Single-Bit Bypass (LOCKED 0011 ^ mask 0100 -> SUCCESS 0111) ===", "warn");
      [0, 0, 0, 0].forEach(b => stepClock(b, "0000", false));
      stepClock(0, "0100", false);
      showToast("TC-03 Executed: LOCKED (0011) + Mask 0100 -> 1-Bit Bypass Attempt!");
    } else if (presetId === "tc04") {
      appendConsoleLog("=== Running TC-04: Mid-Sequence 1-Bit Laser Glitch on GOT_10 (Rectified On-the-Fly!) ===", "info");
      stepClock(1, "0000", false); // GOT_1 (0100)
      stepClock(0, "0001", false); // Expects GOT_10 (0101), mask 0001 flips to 0100, SECDED/TMR heals to 0101!
      if (sim.arch === "sol4") {
        stepClock(1, "0000", false); // Continues to GOT_101
        stepClock(0, "0000", false); // Reaches SUCCESS!
      }
      showToast("TC-04 Executed: Single-Bit Transient Glitch Injected & Analyzed");
    } else if (presetId === "tc05") {
      appendConsoleLog("=== Running TC-05: Even-Weight Multi-Bit Bypass (IDLE -> ERR_1 1000 ^ mask 1111 -> SUCCESS 0111) ===", "danger");
      stepClock(0, "1111", false);
      showToast("TC-05 Executed: Even-Weight Mask 1111 Blinds Parity (PAR=0), Caught by DMR/TMR/SECDED!");
    } else if (presetId === "tc06") {
      appendConsoleLog("=== Running TC-06: Setup/Hold Violation Metastable Glitch (mask = 4'b00x0) ===", "warn");
      stepClock(1, "0000", false);
      sim.metastableMode = true;
      stepClock(0, "00x0", false);
      showToast("TC-06 Executed: Metastable 'x' State Injected & Trapped!");
    }
  }

  // --- Load any of the 202 CSV Test Cases directly into Live Simulator ---
  function replayCsvRowInSimulator(rowId) {
    const row = DATA.exhaustiveCsv.find(r => r.id === Number(rowId));
    if (!row) return;

    sim.arch = "unified";
    const archSelect = document.getElementById("archSelect");
    if (archSelect) archSelect.value = "unified";

    resetSimulator(false);
    appendConsoleLog(`=== Replaying Exhaustive Test #${row.id} (${row.sec}): Origin=${row.origin}, Mask=${row.mask} (Weight=${row.wt}) ===`, "info");

    // Step to Origin_State cleanly (matches testbench goto_state)
    const statePaths = {
      "IDLE": [],
      "GOT_1": [1],
      "GOT_10": [1, 0],
      "GOT_101": [1, 0, 1],
      "SUCCESS": [1, 0, 1, 0],
      "ERR_1": [0],
      "ERR_2": [0, 0],
      "ERR_3": [0, 0, 0],
      "LOCKED": [0, 0, 0, 0]
    };
    const preSteps = statePaths[row.origin] || [];
    preSteps.forEach(b => stepClock(b, "0000", false));

    // Determine the input bit used during the injection so golden state matches row.golden
    const cand1 = nextState4Bit(sim.stateB, 1, false);
    const injBit = (cand1 === row.golden) ? 1 : 0;
    stepClock(injBit, row.mask, false);

    // Switch to Simulator Tab
    switchTab("simulator");
    showToast(`Replayed Test #${row.id}: ${row.origin} + Mask ${row.mask} -> Corrupted ${row.corrupted}`);
  }

  // --- Console Logger ---
  function appendConsoleLog(msg, level) {
    sim.consoleLogs.unshift({ msg, level, id: Date.now() + Math.random() });
    if (sim.consoleLogs.length > 60) sim.consoleLogs.pop();
    renderConsoleLogs();
  }

  function renderConsoleLogs() {
    const el = document.getElementById("simConsoleLog");
    if (!el) return;
    el.innerHTML = sim.consoleLogs.map(item => {
      let color = "text-slate-300";
      if (item.level === "danger") color = "text-rose-400 font-semibold";
      else if (item.level === "warn") color = "text-amber-300";
      else if (item.level === "success") color = "text-emerald-400";
      return `<div class="py-1 border-b border-slate-800/80 ${color}">${escapeHtml(item.msg)}</div>`;
    }).join("");
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  // --- Toast Notification (No alert/confirm/prompt) ---
  let toastTimeout = null;
  function showToast(message) {
    const t = document.getElementById("appToast");
    const msgEl = document.getElementById("appToastMsg");
    if (!t || !msgEl) return;
    msgEl.textContent = message;
    t.classList.remove("hidden", "opacity-0", "translate-y-4");
    t.classList.add("opacity-100", "translate-y-0");
    if (toastTimeout) clearTimeout(toastTimeout);
    toastTimeout = setTimeout(() => {
      t.classList.add("opacity-0", "translate-y-4");
      setTimeout(() => t.classList.add("hidden"), 250);
    }, 3400);
  }

  // --- Render Interactive SVG State Machine Diagram ---
  function renderFsmDiagram() {
    const svg = document.getElementById("fsmStateSvg");
    if (!svg) return;

    const isSol3 = (sim.arch === "sol3");
    const nodes = [
      { key: isSol3 ? "00000" : "0000", label: "IDLE", x: 75, y: 150 },
      { key: isSol3 ? "00011" : "0100", label: "GOT_1", x: 215, y: 75 },
      { key: isSol3 ? "00101" : "0101", label: "GOT_10", x: 370, y: 75 },
      { key: isSol3 ? "00110" : "0110", label: "GOT_101", x: 525, y: 75 },
      { key: isSol3 ? "01001" : "0111", label: "SUCCESS", x: 685, y: 75 },
      { key: isSol3 ? "01010" : "1000", label: "ERR_1", x: 215, y: 225 },
      { key: isSol3 ? "01100" : "1001", label: "ERR_2", x: 370, y: 225 },
      { key: isSol3 ? "10001" : "1010", label: "ERR_3", x: 525, y: 225 },
      { key: isSol3 ? "10010" : "0011", label: "LOCKED", x: 685, y: 225 }
    ];

    const edges = [
      { from: 0, to: 1, bit: "1", color: "#10b981" },
      { from: 1, to: 2, bit: "0", color: "#10b981" },
      { from: 2, to: 3, bit: "1", color: "#10b981" },
      { from: 3, to: 4, bit: "0", color: "#10b981" },
      { from: 0, to: 5, bit: "0", color: "#f43f5e" },
      { from: 1, to: 6, bit: "1", color: "#f43f5e" },
      { from: 2, to: 7, bit: "0", color: "#f43f5e" },
      { from: 3, to: 8, bit: "1", color: "#f43f5e" },
      { from: 5, to: 6, bit: "0/1", color: "#64748b" },
      { from: 6, to: 7, bit: "0/1", color: "#64748b" },
      { from: 7, to: 8, bit: "0/1", color: "#64748b" }
    ];

    let html = `
      <defs>
        <marker id="arrow-green" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 1 L 10 5 L 0 9 z" fill="#10b981"></path>
        </marker>
        <marker id="arrow-red" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 1 L 10 5 L 0 9 z" fill="#f43f5e"></path>
        </marker>
        <marker id="arrow-slate" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
          <path d="M 0 1 L 10 5 L 0 9 z" fill="#64748b"></path>
        </marker>
      </defs>
    `;

    // Draw Edges
    edges.forEach(e => {
      const n1 = nodes[e.from];
      const n2 = nodes[e.to];
      const dx = n2.x - n1.x;
      const dy = n2.y - n1.y;
      const len = Math.hypot(dx, dy);
      const r = 36;
      const x1 = n1.x + (dx / len) * r;
      const y1 = n1.y + (dy / len) * r;
      const x2 = n2.x - (dx / len) * (r + 4);
      const y2 = n2.y - (dy / len) * (r + 4);
      const marker = e.color === "#10b981" ? "url(#arrow-green)" : (e.color === "#f43f5e" ? "url(#arrow-red)" : "url(#arrow-slate)");
      const mx = (x1 + x2) / 2;
      const my = (y1 + y2) / 2 - 6;

      html += `
        <line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}"
              stroke="${e.color}" stroke-width="2" stroke-opacity="0.7" marker-end="${marker}" />
        <text x="${mx.toFixed(1)}" y="${my.toFixed(1)}" text-anchor="middle" fill="${e.color}" font-size="11" font-family="JetBrains Mono, monospace" font-weight="600">${e.bit}</text>
      `;
    });

    // Draw Nodes
    nodes.forEach((n, idx) => {
      const isCurrA = (sim.stateA === n.key);
      const isGolden = (!isSol3 && sim.stateB === n.key && sim.stateA !== sim.stateB);
      let stroke = "#334155";
      let fill = "#0f172a";
      let extraClass = "";

      if (isCurrA) {
        if (n.label === "SUCCESS" && sim.stateB !== "0111" && !isSol3) {
          stroke = "#f43f5e";
          fill = "#4c0519";
          extraClass = "fsm-node-breach";
        } else if (n.label === "SUCCESS") {
          stroke = "#10b981";
          fill = "#064e3b";
          extraClass = "fsm-node-success";
        } else {
          stroke = "#38bdf8";
          fill = "#0c4a6e";
          extraClass = "fsm-node-active";
        }
      } else if (isGolden) {
        stroke = "#f59e0b";
        fill = "#451a03";
      }

      html += `
        <g class="fsm-node ${extraClass}" data-state-idx="${idx}" onclick="window.DLD_SIM.jumpToStateIndex(${idx})">
          <circle cx="${n.x}" cy="${n.y}" r="34" fill="${fill}" stroke="${stroke}" stroke-width="${isCurrA || isGolden ? 3 : 1.75}" />
          <text x="${n.x}" y="${n.y - 4}" text-anchor="middle" fill="#f8fafc" font-size="11" font-weight="700">${n.label}</text>
          <text x="${n.x}" y="${n.y + 13}" text-anchor="middle" fill="#94a3b8" font-size="10.5" font-family="JetBrains Mono, monospace">${n.key}</text>
          ${isCurrA ? `<rect x="${n.x - 28}" y="${n.y - 50}" width="56" height="15" rx="4" fill="${stroke}" /><text x="${n.x}" y="${n.y - 39}" text-anchor="middle" fill="#090d16" font-size="9" font-weight="800">CORE A</text>` : ""}
          ${isGolden ? `<rect x="${n.x - 32}" y="${n.y + 38}" width="64" height="15" rx="4" fill="#f59e0b" /><text x="${n.x}" y="${n.y + 49}" text-anchor="middle" fill="#090d16" font-size="9" font-weight="800">GOLDEN</text>` : ""}
        </g>
      `;
    });

    // If State A is an unmapped corrupted state or Sol 3 TRAP_LOCKED, show a floating fault callout node
    const mappedKeys = nodes.map(n => n.key);
    if (!mappedKeys.includes(sim.stateA)) {
      html += `
        <g class="fsm-node fsm-node-breach">
          <rect x="275" y="130" width="210" height="44" rx="8" fill="#4c0519" stroke="#f43f5e" stroke-width="2.5" />
          <text x="380" y="149" text-anchor="middle" fill="#fda4af" font-size="11" font-weight="800">FAULT / UNMAPPED STATE</text>
          <text x="380" y="165" text-anchor="middle" fill="#ffffff" font-size="11" font-family="JetBrains Mono, monospace">state_out = ${sim.stateA} (${getStateName(sim.stateA)})</text>
        </g>
      `;
    }

    svg.innerHTML = html;
  }

  // --- Render GTKWave-Style Digital Timing Waveform Canvas ---
  function renderWaveformCanvas() {
    const canvas = document.getElementById("waveformCanvas");
    if (!canvas) return;
    const parent = canvas.parentElement;
    const width = Math.max(parent ? parent.clientWidth : 720, 640);
    const signals = [
      { name: "clk", type: "clk", color: "#38bdf8" },
      { name: "auth_in", key: "authIn", type: "bit", color: "#a855f7" },
      { name: "fault_mask", key: "mask", type: "bus", color: "#f43f5e" },
      { name: "state_out[A]", key: "stateA", type: "bus", color: "#38bdf8" },
      { name: "voted_state", key: "votedState", type: "bus", color: "#10b981" },
      { name: "ecc_state", key: "eccState", type: "bus", color: "#2dd4bf" },
      { name: "access_raw", key: "rawAccess", type: "bit", color: "#f59e0b" },
      { name: "parity_err", key: "parityErr", type: "bit", color: "#eab308" },
      { name: "dmr_err", key: "dmrErr", type: "bit", color: "#f97316" },
      { name: "tmr_err", key: "tmrErr", type: "bit", color: "#ec4899" },
      { name: "ecc_corr", key: "eccCorr", type: "bit", color: "#10b981" },
      { name: "attack_det", key: "alarm", type: "bit", color: "#f43f5e" }
    ];

    const rowH = 28;
    const headerH = 26;
    const height = headerH + signals.length * rowH + 10;
    canvas.width = width;
    canvas.height = height;

    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#090d16";
    ctx.fillRect(0, 0, width, height);

    const labelColW = 118;
    const plotW = width - labelColW - 16;
    const steps = Math.max(sim.waveHistory.length, 1);
    const stepW = Math.max(Math.min(plotW / Math.max(steps, 8), 85), 36);

    // Header ruler
    ctx.fillStyle = "#111827";
    ctx.fillRect(0, 0, width, headerH);
    ctx.strokeStyle = "#1e293b";
    ctx.beginPath();
    ctx.moveTo(0, headerH);
    ctx.lineTo(width, headerH);
    ctx.stroke();

    ctx.fillStyle = "#94a3b8";
    ctx.font = "600 11px JetBrains Mono, monospace";
    ctx.fillText("SIGNAL", 10, 17);

    sim.waveHistory.forEach((snap, idx) => {
      const x = labelColW + idx * stepW;
      ctx.fillStyle = "#64748b";
      ctx.font = "10px JetBrains Mono, monospace";
      ctx.fillText(`${snap.timeNs}ns`, x + 4, 17);
      ctx.strokeStyle = "#1e293b";
      ctx.beginPath();
      ctx.moveTo(x, headerH);
      ctx.lineTo(x, height);
      ctx.stroke();
    });

    // Draw each signal lane
    signals.forEach((sig, sIdx) => {
      const yTop = headerH + sIdx * rowH;
      const yHigh = yTop + 6;
      const yLow = yTop + rowH - 6;
      const yMid = (yHigh + yLow) / 2;

      // Alternating lane background
      if (sIdx % 2 === 1) {
        ctx.fillStyle = "rgba(30, 41, 59, 0.25)";
        ctx.fillRect(0, yTop, width, rowH);
      }

      // Label
      ctx.fillStyle = sig.color;
      ctx.font = "600 11px JetBrains Mono, monospace";
      ctx.fillText(sig.name, 10, yMid + 4);

      ctx.strokeStyle = sig.color;
      ctx.lineWidth = 1.8;

      sim.waveHistory.forEach((snap, idx) => {
        const x0 = labelColW + idx * stepW;
        const x1 = x0 + stepW;
        const xHalf = x0 + stepW / 2;

        if (sig.type === "clk") {
          ctx.beginPath();
          ctx.moveTo(x0, yLow);
          ctx.lineTo(x0, yHigh);
          ctx.lineTo(xHalf, yHigh);
          ctx.lineTo(xHalf, yLow);
          ctx.lineTo(x1, yLow);
          ctx.stroke();
        } else if (sig.type === "bit") {
          const val = Number(snap[sig.key]) ? 1 : 0;
          const prevVal = idx > 0 ? (Number(sim.waveHistory[idx - 1][sig.key]) ? 1 : 0) : val;
          const yCurr = val ? yHigh : yLow;
          const yPrev = prevVal ? yHigh : yLow;

          ctx.beginPath();
          if (idx > 0 && yCurr !== yPrev) {
            ctx.moveTo(x0, yPrev);
            ctx.lineTo(x0, yCurr);
          } else {
            ctx.moveTo(x0, yCurr);
          }
          ctx.lineTo(x1, yCurr);
          ctx.stroke();

          if (val === 1) {
            ctx.fillStyle = sig.color + "22";
            ctx.fillRect(x0, yHigh, stepW, yLow - yHigh);
          }
        } else if (sig.type === "bus") {
          const valStr = String(snap[sig.key]);
          const isAlertBus = (sig.key === "mask" && (valStr.includes("1") || valStr.includes("x"))) || valStr.includes("x");
          ctx.strokeStyle = isAlertBus ? "#f43f5e" : sig.color;
          ctx.fillStyle = isAlertBus ? "rgba(244, 63, 94, 0.22)" : "rgba(15, 23, 42, 0.85)";
          ctx.fillRect(x0 + 2, yHigh, stepW - 4, yLow - yHigh);
          ctx.strokeRect(x0 + 2, yHigh, stepW - 4, yLow - yHigh);

          ctx.fillStyle = "#f8fafc";
          ctx.font = "10px JetBrains Mono, monospace";
          ctx.fillText(valStr, x0 + 5, yMid + 3.5);
        }
      });
    });
  }

  // --- Render Bit-Flip Fault Mask Switches ---
  function renderFaultMaskControls() {
    const container = document.getElementById("faultMaskBitsContainer");
    if (!container) return;
    const archObj = DATA.architectures.find(a => a.id === sim.arch) || DATA.architectures[0];
    const numBits = archObj.maskBits;

    let html = "";
    for (let i = numBits - 1; i >= 0; i--) {
      const active = sim.faultMask[i] === 1;
      let bitLabel = `s[${i}]`;
      if (sim.arch === "sol1" && i === 4) bitLabel = "par";
      else if (sim.arch === "sol2" && i === 4) bitLabel = "par";
      else if (sim.arch === "sol4" && i >= 4) bitLabel = `p[${i - 4}]`;
      else if (sim.arch === "sol5" && i >= 4) bitLabel = `c2[${i - 4}]`;
      else if (sim.arch === "sol6" && i >= 8) bitLabel = `cC[${i - 8}]`;
      else if (sim.arch === "sol6" && i >= 4) bitLabel = `cB[${i - 4}]`;

      html += `
        <button type="button" onclick="window.DLD_SIM.toggleFaultBit(${i})"
          class="bit-btn flex flex-col items-center justify-center px-2.5 py-1.5 rounded-lg border text-xs font-mono-code ${
            active
              ? "bg-rose-600/30 border-rose-500 text-rose-200 font-bold shadow-sm shadow-rose-500/30"
              : "bg-slate-800/90 border-slate-700 text-slate-300 hover:border-slate-500"
          }">
          <span class="text-[10px] text-slate-400">${bitLabel}</span>
          <span class="text-sm">${active ? "1" : "0"}</span>
        </button>
      `;
    }
    container.innerHTML = html;

    const maskPreview = document.getElementById("currentMaskBinary");
    if (maskPreview) {
      maskPreview.textContent = `${numBits}'b${getMaskString(numBits)}`;
    }
  }

  // --- Update All Simulator UI Panels ---
  function renderAll() {
    const archObj = DATA.architectures.find(a => a.id === sim.arch) || DATA.architectures[0];

    // Header Badges
    const elArchTitle = document.getElementById("activeArchTitle");
    const elArchDesc = document.getElementById("activeArchDesc");
    const elArchFFs = document.getElementById("activeArchFFs");
    const elArchSoei = document.getElementById("activeArchSoei");
    if (elArchTitle) elArchTitle.textContent = archObj.name;
    if (elArchDesc) elArchDesc.textContent = archObj.summary;
    if (elArchFFs) elArchFFs.textContent = `${archObj.ffs} Flip-Flops`;
    if (elArchSoei) elArchSoei.textContent = `SOEI: ${archObj.soei}`;

    // Status Banner
    const banner = document.getElementById("simStatusBanner");
    if (banner) {
      banner.textContent = sim.telemetry.statusBanner;
      banner.className = "px-4 py-2.5 rounded-xl border text-xs sm:text-sm font-medium transition-all ";
      if (sim.telemetry.statusType === "breach") {
        banner.className += "bg-rose-950/70 border-rose-500 text-rose-200 alarm-pulse";
      } else if (sim.telemetry.statusType === "rectified") {
        banner.className += "bg-emerald-950/70 border-emerald-500 text-emerald-200 safe-pulse";
      } else if (sim.telemetry.statusType === "warn") {
        banner.className += "bg-amber-950/70 border-amber-500 text-amber-200";
      } else if (sim.telemetry.statusType === "ok") {
        banner.className += "bg-emerald-900/50 border-emerald-500/80 text-emerald-100";
      } else {
        banner.className += "bg-slate-800/80 border-slate-700 text-slate-200";
      }
    }

    // Core Telemetry Readouts
    setText("telCycle", `${sim.cycle} (${sim.timeNs} ns)`);
    setText("telPinSeq", sim.inputHistory.length ? sim.inputHistory.join("") : "None (IDLE)");
    setText("telStateA", `${sim.stateA} (${getStateName(sim.stateA)})`);
    setText("telStateGolden", `${sim.telemetry.goldenNext} (${getStateName(sim.telemetry.goldenNext)})`);

    const rawEl = document.getElementById("telRawAccess");
    if (rawEl) {
      rawEl.textContent = sim.telemetry.rawAccess ? "1 (GRANTED)" : "0 (DENIED)";
      rawEl.className = "font-mono-code text-sm font-bold " + (
        sim.telemetry.rawAccess && sim.telemetry.goldenNext !== "0111" && sim.arch !== "sol3"
          ? "text-rose-400"
          : (sim.telemetry.rawAccess ? "text-emerald-400" : "text-slate-300")
      );
    }

    const safeEl = document.getElementById("telSafeAccess");
    if (safeEl) {
      safeEl.textContent = sim.telemetry.safeAccess ? "1 (AUTHORIZED)" : "0 (PROTECTED / LOCKED)";
      safeEl.className = "font-mono-code text-sm font-bold " + (
        sim.telemetry.safeAccess ? "text-emerald-400" : "text-sky-300"
      );
    }

    // Defense Module Cards
    setBadge("badgeParity", sim.telemetry.parityErr ? "FAULT DETECTED (1)" : "OK / QUIET (0)", sim.telemetry.parityErr ? "warn" : "neutral");
    setText("detailParity", `Stored parity_q=${sim.parityFF} vs ^state=${parityOf(sim.stateA)}`);

    setBadge("badgeDmr", sim.telemetry.dmrErr ? "MISMATCH CAUGHT (1)" : "CONSENSUS (0)", sim.telemetry.dmrErr ? "warn" : "neutral");
    setText("detailDmr", `Core A (${sim.stateA}) vs Core B (${sim.stateB}) | Latch=${sim.alarmLatched ? 1 : 0}`);

    setBadge("badgeTmr", sim.telemetry.tmrErr ? `MASKED CORRUPTION (${sim.telemetry.votedState})` : `UNANIMOUS (${sim.telemetry.votedState})`, sim.telemetry.tmrErr ? "ok" : "neutral");
    setText("detailTmr", `Voted=${sim.telemetry.votedState} | Faulty Core Bitmap=${sim.telemetry.tmrFaulty}`);

    let eccStatus = "CLEAN (0)";
    let eccTone = "neutral";
    if (sim.telemetry.eccCorr) {
      eccStatus = `1-BIT FIXED -> ${sim.telemetry.eccState}`;
      eccTone = "ok";
    } else if (sim.telemetry.eccUnc) {
      eccStatus = "MULTI-BIT UNCORRECTABLE!";
      eccTone = "danger";
    }
    setBadge("badgeEcc", eccStatus, eccTone);
    setText("detailEcc", `Syndrome=${sim.telemetry.eccSyndrome}, P_all=${sim.telemetry.eccOverall}, Pos=${sim.telemetry.eccPos}, Out=${sim.telemetry.eccState}`);

    renderFaultMaskControls();
    renderFsmDiagram();
    renderWaveformCanvas();
  }

  function setText(id, val) {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
  }

  function setBadge(id, text, tone) {
    const el = document.getElementById(id);
    if (!el) return;
    el.textContent = text;
    el.className = "px-2 py-0.5 rounded text-[11px] font-mono-code font-bold ";
    if (tone === "ok") el.className += "bg-emerald-500/20 text-emerald-300 border border-emerald-500/40";
    else if (tone === "warn") el.className += "bg-amber-500/20 text-amber-300 border border-amber-500/40";
    else if (tone === "danger") el.className += "bg-rose-500/20 text-rose-300 border border-rose-500/40";
    else el.className += "bg-slate-700/70 text-slate-300 border border-slate-600";
  }

  // --- Exhaustive 202-Fault Table Filtering & Rendering ---
  function renderExhaustiveTable() {
    const tbody = document.getElementById("exhaustiveTableBody");
    const countEl = document.getElementById("csvFilteredCount");
    if (!tbody) return;

    const secFilter = (document.getElementById("filterSection") || {}).value || "ALL";
    const stateFilter = (document.getElementById("filterState") || {}).value || "ALL";
    const wtFilter = (document.getElementById("filterWeight") || {}).value || "ALL";
    const outcomeFilter = (document.getElementById("filterOutcome") || {}).value || "ALL";
    const searchVal = ((document.getElementById("filterSearch") || {}).value || "").trim().toLowerCase();

    const filtered = DATA.exhaustiveCsv.filter(r => {
      if (secFilter !== "ALL" && r.sec !== secFilter) return false;
      if (stateFilter !== "ALL" && r.origin !== stateFilter) return false;
      if (wtFilter !== "ALL" && String(r.wt) !== wtFilter) return false;
      if (outcomeFilter === "BREACH" && !r.breach) return false;
      if (outcomeFilter === "PARITY_BLIND" && r.par) return false;
      if (outcomeFilter === "ECC_FIXED" && !r.eccCorr) return false;
      if (outcomeFilter === "ECC_UNC" && !r.eccUnc) return false;
      if (searchVal) {
        const hay = `${r.id} ${r.origin} ${r.mask} ${r.golden} ${r.corrupted} ${r.cls}`.toLowerCase();
        if (!hay.includes(searchVal)) return false;
      }
      return true;
    });

    if (countEl) {
      countEl.textContent = `Showing ${filtered.length} of ${DATA.exhaustiveCsv.length} verified fault injections`;
    }

    tbody.innerHTML = filtered.map(r => `
      <tr class="border-b border-slate-800/80 hover:bg-slate-800/50 transition-colors text-xs">
        <td class="py-2 px-2.5 font-mono-code text-slate-400">#${r.id}</td>
        <td class="py-2 px-2.5 text-slate-300">${r.sec}</td>
        <td class="py-2 px-2.5 font-mono-code font-semibold text-sky-300">${r.origin}</td>
        <td class="py-2 px-2.5 font-mono-code text-rose-300 font-bold">${r.mask} <span class="text-slate-500 font-normal">(w=${r.wt})</span></td>
        <td class="py-2 px-2.5 font-mono-code text-slate-300">${r.golden} &rarr; <span class="${r.breach ? "text-rose-400 font-bold" : "text-amber-300"}">${r.corrupted}</span></td>
        <td class="py-2 px-2.5">
          ${r.breach
            ? `<span class="px-2 py-0.5 rounded bg-rose-500/20 border border-rose-500/40 text-rose-300 font-bold">YES (BREACH)</span>`
            : `<span class="text-slate-400">NO</span>`}
        </td>
        <td class="py-2 px-2.5">
          ${r.par
            ? `<span class="text-emerald-400 font-semibold">YES</span>`
            : `<span class="px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-300 font-semibold">BLIND (Even)</span>`}
        </td>
        <td class="py-2 px-2.5 text-emerald-400 font-semibold">YES</td>
        <td class="py-2 px-2.5 font-mono-code text-emerald-300">Voted ${r.tmrVoted}</td>
        <td class="py-2 px-2.5 font-mono-code">
          ${r.eccCorr
            ? `<span class="text-emerald-400 font-semibold">FIXED (${r.eccState})</span>`
            : `<span class="text-amber-300">UNC_LOCKOUT</span>`}
        </td>
        <td class="py-2 px-2.5 text-right">
          <button type="button" onclick="window.DLD_SIM.replayCsvRow(${r.id})"
            class="px-2.5 py-1 rounded-md bg-sky-600/30 hover:bg-sky-600/50 border border-sky-500/50 text-sky-200 font-medium transition">
            Simulate &rarr;
          </button>
        </td>
      </tr>
    `).join("");
  }

  // --- Render RTL & Log Code Viewer ---
  let currentRepoFileId = "combined_design";
  function renderRepoViewer() {
    const listEl = document.getElementById("repoFileList");
    const codeEl = document.getElementById("repoCodeContent");
    const titleEl = document.getElementById("repoCodeTitle");
    const descEl = document.getElementById("repoCodeDesc");
    const pathEl = document.getElementById("repoCodePath");
    if (!listEl || !codeEl) return;

    listEl.innerHTML = DATA.repoFiles.map(f => {
      const active = f.id === currentRepoFileId;
      return `
        <button type="button" onclick="window.DLD_SIM.selectRepoFile('${f.id}')"
          class="w-full text-left px-3 py-2 rounded-lg text-xs transition flex flex-col gap-0.5 border ${
            active
              ? "bg-sky-500/20 border-sky-500/60 text-white font-semibold"
              : "bg-slate-900/60 border-slate-800 text-slate-300 hover:bg-slate-800/70"
          }">
          <span class="text-[10px] uppercase tracking-wider text-sky-400">${escapeHtml(f.category)}</span>
          <span class="truncate font-mono-code">${escapeHtml(f.title)}</span>
        </button>
      `;
    }).join("");

    const curr = DATA.repoFiles.find(f => f.id === currentRepoFileId) || DATA.repoFiles[0];
    if (titleEl) titleEl.textContent = curr.title;
    if (descEl) descEl.textContent = curr.desc;
    if (pathEl) pathEl.textContent = curr.path;
    codeEl.textContent = curr.content;
  }

  // --- Initialize Chart.js Benchmark Charts ---
  let chartsInitialized = false;
  function initBenchmarkCharts() {
    if (chartsInitialized || typeof window.Chart === "undefined") return;
    const ctx1 = document.getElementById("chartDefenseRates");
    const ctx2 = document.getElementById("chartSoeiTradeoff");
    if (!ctx1 || !ctx2) return;

    chartsInitialized = true;
    new window.Chart(ctx1, {
      type: "bar",
      data: {
        labels: ["Baseline FSM", "Parity (Sol 2)", "DMR (Sol 5)", "TMR (Sol 6)", "SECDED (Sol 4)"],
        datasets: [
          {
            label: "Fault Detection Rate (FDR %)",
            data: [0.0, 51.49, 100.0, 100.0, 100.0],
            backgroundColor: "rgba(56, 189, 248, 0.8)",
            borderRadius: 6
          },
          {
            label: "1-Bit Fault Masking/Rectification (%)",
            data: [0.0, 0.0, 0.0, 100.0, 100.0],
            backgroundColor: "rgba(16, 185, 129, 0.8)",
            borderRadius: 6
          },
          {
            label: "Attack Success / Bypass Rate (ASR %)",
            data: [14.85, 0.0, 0.0, 0.0, 0.0],
            backgroundColor: "rgba(244, 63, 94, 0.85)",
            borderRadius: 6
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { labels: { color: "#cbd5e1", font: { size: 11 } } }
        },
        scales: {
          x: { ticks: { color: "#94a3b8" }, grid: { color: "rgba(51,65,85,0.3)" } },
          y: { min: 0, max: 105, ticks: { color: "#94a3b8" }, grid: { color: "rgba(51,65,85,0.3)" } }
        }
      }
    });

    new window.Chart(ctx2, {
      type: "bar",
      data: {
        labels: ["Baseline (4 FFs)", "Parity Sol 2 (6 FFs)", "TMR Sol 6 (12 FFs)", "DMR Sol 5 (9 FFs)", "SECDED Sol 4 (9 FFs)"],
        datasets: [
          {
            label: "Security-Overhead Efficiency Index (SOEI Score)",
            data: [0.00, 1.47, 1.56, 1.92, 2.42],
            backgroundColor: [
              "rgba(100, 116, 139, 0.7)",
              "rgba(245, 158, 11, 0.8)",
              "rgba(168, 85, 247, 0.8)",
              "rgba(56, 189, 248, 0.8)",
              "rgba(16, 185, 129, 0.9)"
            ],
            borderRadius: 6
          },
          {
            label: "Relative Hardware Area (x Baseline)",
            data: [1.00, 1.35, 3.20, 2.10, 1.65],
            backgroundColor: "rgba(148, 163, 184, 0.45)",
            borderRadius: 6
          }
        ]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { labels: { color: "#cbd5e1", font: { size: 11 } } }
        },
        scales: {
          x: { ticks: { color: "#94a3b8" }, grid: { color: "rgba(51,65,85,0.3)" } },
          y: { beginAtZero: true, ticks: { color: "#94a3b8" }, grid: { color: "rgba(51,65,85,0.3)" } }
        }
      }
    });
  }

  // --- Navigation Tab Switcher ---
  function switchTab(tabId) {
    const tabs = ["simulator", "matrix", "benchmarks", "codehub"];
    tabs.forEach(t => {
      const sec = document.getElementById(`tab-panel-${t}`);
      const btn = document.getElementById(`tab-btn-${t}`);
      if (sec) {
        if (t === tabId) sec.classList.remove("hidden");
        else sec.classList.add("hidden");
      }
      if (btn) {
        if (t === tabId) {
          btn.className = "px-3.5 py-2 rounded-lg text-xs sm:text-sm font-semibold bg-sky-500 text-slate-950 shadow-sm transition";
        } else {
          btn.className = "px-3.5 py-2 rounded-lg text-xs sm:text-sm font-medium text-slate-300 hover:text-white hover:bg-slate-800/80 transition";
        }
      }
    });

    if (tabId === "simulator") {
      renderWaveformCanvas();
    } else if (tabId === "benchmarks") {
      initBenchmarkCharts();
    }
  }

  function updateAutoPlayButton() {
    const btn = document.getElementById("btnAutoClock");
    if (!btn) return;
    if (sim.autoPlayTimer) {
      btn.textContent = "Pause Clock";
      btn.className = "px-3 py-2 rounded-lg bg-amber-500 hover:bg-amber-400 text-slate-950 font-semibold text-xs transition";
    } else {
      btn.textContent = "Auto-Clock (1 Hz)";
      btn.className = "px-3 py-2 rounded-lg bg-slate-800 hover:bg-slate-700 border border-slate-600 text-slate-200 font-medium text-xs transition";
    }
  }

  // --- Copy & Download Helpers ---
  function copyTextSafe(text, label) {
    try {
      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
      showToast(`Copied ${label} to clipboard!`);
    } catch (e) {
      showToast("Copy failed in this browser context.");
    }
  }

  function downloadTextFile(filename, content, mime) {
    const blob = new Blob([content], { type: mime || "text/plain;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    showToast(`Downloaded ${filename}`);
  }

  function exportVcdTrace() {
    let vcd = `$date\n  Nov 2026\n$end\n$version\n  CS203 Fault-Resilient Secure FSM Web Simulator\n$end\n$timescale\n  1ns\n$end\n`;
    vcd += `$scope module secure_fsm_top $end\n`;
    vcd += `$var wire 1 ! auth_in $end\n$var wire 4 " state_out $end\n$var wire 4 # voted_state $end\n$var wire 1 $ attack_detected $end\n`;
    vcd += `$upscope $end\n$enddefinitions $end\n`;
    sim.waveHistory.forEach(w => {
      vcd += `#${w.timeNs}\n${w.authIn}!\nb${w.stateA} "\nb${w.votedState} #\n${w.alarm}$\n`;
    });
    downloadTextFile("detect_web_sim.vcd", vcd, "text/plain");
  }

  // --- Expose Public Controller API ---
  window.DLD_SIM = {
    switchTab,
    setArch(archId) {
      sim.arch = archId;
      resetSimulator(true);
      showToast(`Switched Architecture: ${archId.toUpperCase()}`);
    },
    stepWithBit(bitVal) {
      sim.authIn = Number(bitVal);
      stepClock(Number(bitVal));
    },
    stepCurrent() {
      stepClock(sim.authIn);
    },
    toggleInputBit() {
      sim.authIn = sim.authIn === 1 ? 0 : 1;
    },
    toggleFaultBit(bitIdx) {
      sim.metastableMode = false;
      sim.faultMask[bitIdx] = sim.faultMask[bitIdx] ? 0 : 1;
      renderFaultMaskControls();
    },
    setQuickMask(mask4Str) {
      sim.metastableMode = false;
      sim.faultMask = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      for (let i = 0; i < mask4Str.length; i++) {
        const bitPos = mask4Str.length - 1 - i;
        sim.faultMask[bitPos] = mask4Str[i] === "1" ? 1 : 0;
      }
      renderFaultMaskControls();
      showToast(`Armed Fault Mask: ${mask4Str} (will inject on next clock edge)`);
    },
    armMetastable() {
      sim.metastableMode = !sim.metastableMode;
      renderFaultMaskControls();
      showToast(sim.metastableMode ? "Armed Metastable 'x' Glitch for next clock edge" : "Cleared Metastable Mode");
    },
    reset() {
      resetSimulator(true);
      showToast("FSM Reset (rst_n = 0 -> 1)");
    },
    toggleAutoClock() {
      if (sim.autoPlayTimer) {
        clearInterval(sim.autoPlayTimer);
        sim.autoPlayTimer = null;
      } else {
        const pinBits = [1, 0, 1, 0];
        sim.autoPlayTimer = setInterval(() => {
          const nextBit = pinBits[sim.cycle % 4];
          stepClock(nextBit);
        }, 900);
      }
      updateAutoPlayButton();
    },
    runPreset: runPresetScenario,
    replayCsvRow: replayCsvRowInSimulator,
    jumpToStateIndex(idx) {
      resetSimulator(false);
      const paths = [
        [], [1], [1, 0], [1, 0, 1], [1, 0, 1, 0],
        [0], [0, 0], [0, 0, 0], [0, 0, 0, 0]
      ];
      const seq = paths[idx] || [];
      seq.forEach(b => stepClock(b, "0000", false));
      showToast(`Jumped to state #${idx} via clean input sequence`);
    },
    filterCsv: renderExhaustiveTable,
    selectRepoFile(fileId) {
      currentRepoFileId = fileId;
      renderRepoViewer();
    },
    copyCurrentRepoFile() {
      const curr = DATA.repoFiles.find(f => f.id === currentRepoFileId) || DATA.repoFiles[0];
      copyTextSafe(curr.content, curr.title);
    },
    downloadCurrentRepoFile() {
      const curr = DATA.repoFiles.find(f => f.id === currentRepoFileId) || DATA.repoFiles[0];
      const base = curr.path.split("/").pop();
      downloadTextFile(base, curr.content);
    },
    exportVcd: exportVcdTrace,
    copyGitCommands() {
      const cmds = document.getElementById("gitCommitCommands").textContent;
      copyTextSafe(cmds, "Git Commit Commands");
    }
  };

  window.addEventListener("DOMContentLoaded", () => {
    resetSimulator(true);
    renderExhaustiveTable();
    renderRepoViewer();
    window.addEventListener("resize", () => {
      renderWaveformCanvas();
    });
  });
})();
