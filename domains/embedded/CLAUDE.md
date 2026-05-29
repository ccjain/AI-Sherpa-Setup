# AI Sherpa — Embedded Software Rules

These rules apply to all embedded software projects (C/C++, firmware, RTOS).
They extend the global rules in core/CLAUDE.md — do not remove global rules.

---

## Architecture Check (Before Every Embedded Task)

Before writing any code, ask the developer if not already documented:
1. Which toolchain is in use? (GCC ARM / IAR / Keil / MPLAB / other)
2. Which RTOS or bare-metal framework? (FreeRTOS / Zephyr / bare-metal / other)
3. Target hardware constraints — RAM, flash size, CPU clock speed
4. Any MISRA-C compliance requirement?

Do not assume or guess hardware context. Proceed only once confirmed.

---

## Toolchain & Flasher Paths

When the developer asks to **build, flash, or debug**, look up the actual paths
from two files in this order — per-project override first, global fallback second.

### Lookup order

1. **`<project-root>/.embedded-override.json`** — pinned per repo. Use when a
   board requires a specific toolchain version (e.g. an old Zephyr SDK), a
   non-default flasher, or a vendor-specific GDB server. Only contains the keys
   that need to override the global default.
2. **`~/.claude/embedded-toolchain.json`** — auto-detected at AI Sherpa setup,
   one per machine. Holds every tool the detection script found, plus any
   user-entered fallbacks. In WSL+Windows hybrid, this lives at the Windows
   user's `.claude\embedded-toolchain.json`.

**Merge rule:** for any tool key, if the per-project file has a non-null value,
use it. Otherwise fall back to the global file's value. If both are null/missing,
ask the developer for the path and update the appropriate file (per-project for
repo-specific tooling, global for machine-wide installs).

### Schema (same for both files)

```jsonc
{
  "toolchains": {
    "arm-gcc":    "<absolute path to bin/>",
    "zephyr-sdk": "<absolute path to sdk root>",
    "iar":        "<absolute path>",
    "keil-mdk":   "<absolute path>",
    "mplab-x":    "<absolute path>",
    "xc8":  "...", "xc16": "...", "xc32": "..."
  },
  "flashers": {
    "jlink":         "<full path to JLink.exe / JLinkExe.exe>",
    "stm32cubeprog": "<full path to STM32_Programmer_CLI.exe>",
    "nrfjprog":      "<full path>",
    "pyocd":         "<full path>",
    "openocd":       "<full path to openocd.exe>"
  },
  "debuggers": {
    "arm-gdb":         "<full path to arm-none-eabi-gdb.exe>",
    "jlink-gdbserver": "<full path to JLinkGDBServerCL.exe>"
  }
}
```

### Example per-project override (`.embedded-override.json`)

A project that requires an older Zephyr SDK pinned for compatibility:

```json
{
  "toolchains": {
    "zephyr-sdk": "C:/zephyr-sdk-0.13.2"
  }
}
```

Everything else falls back to the global config.

### How to use it

Prefer the absolute path over a bare command name. Avoids PATH surprises
across shells.

| Developer asks | What to look up |
|---|---|
| "Build this Zephyr app for nrf5340dk" | `toolchains.zephyr-sdk` + `toolchains.arm-gcc` |
| "Flash this .hex to my STM32H7 dev board" | `flashers.stm32cubeprog` or `flashers.jlink` |
| "Start a GDB debug session" | `debuggers.arm-gdb` + `debuggers.jlink-gdbserver` |
| "Run pyocd to list connected probes" | `flashers.pyocd` |

Example commands you'd issue with the JSON resolved:

```
& "C:\Program Files\STMicroelectronics\STM32CubeProgrammer\bin\STM32_Programmer_CLI.exe" -c port=SWD -d build/firmware.hex -v -rst
& "C:\zephyr-sdk-0.16.1\openocd\bin\openocd.exe" -f boards/arm/nrf5340dk_nrf5340/support/nrf5340_cpuapp.cfg
```

### If a needed tool is null in both files

Ask the developer for its install path, then:
- If it's repo-specific (e.g. an old Zephyr SDK pinned for this board) → write
  it to `<project-root>/.embedded-override.json`.
- If it's machine-wide (a new flasher they just installed) → update
  `~/.claude/embedded-toolchain.json`.

### If neither file exists

The developer hasn't run AI Sherpa setup for embedded. Tell them to run
`setup.bat` or `bash setup.sh` from the AI Sherpa repo and pick domain `1`.

---

## Hardware-Critical Code — Human Approval Required

Flag ANY suggestion that touches the following with: `⚠ HUMAN REVIEW REQUIRED — hardware-critical change`

Do not proceed until the developer explicitly approves:
- Interrupt service routines (ISRs)
- Memory-mapped hardware register access
- Real-time scheduling or timing logic
- Boot/startup code
- Safety-critical control loops
- DMA configuration
- Power management sequences

---

## Always Do (Embedded)

1. Annotate ISRs with their timing constraints and expected execution time
2. Prefer iterative over recursive — always consider stack depth impact
3. Reference the project's datasheet or HAL before suggesting register access
4. State explicitly: "This suggestion requires hardware-in-the-loop testing to verify"

---

## Never Do (Embedded)

1. Use dynamic memory allocation (malloc/free) unless developer explicitly approves
2. Suggest hardware register access without a datasheet/HAL reference
3. Claim code correctness without hardware-in-the-loop testing
4. Apply MISRA-C suggestions to non-safety-critical modules without asking first

---

## AI Effectiveness Boundaries

Effective: logic bugs, unit tests, code style, test coverage gaps, static analysis
Not suitable as final authority: timing analysis, hardware-specific optimisation, real-time behaviour, physical signal integrity

---

## Plugin & Skill Invocation Contract — Domain (embedded)

These plugins ship for the embedded domain. Reach for them by default; the rules
below override any defaults from their `SKILL.md` descriptions.

### MANDATORY — invoke without asking

| When the user…                                                              | Invoke                  | Why                                                |
|-----------------------------------------------------------------------------|-------------------------|----------------------------------------------------|
| asks about Zephyr device-tree, kernel threads, `BIT`/`CONTAINER_OF`         | `zephyr-foundations`    | Reach for Zephyr-specific patterns first           |
| asks to set up or bring up a new custom board                               | `board-bringup`         | Hardware-aware skill; reads `board.yml` correctly  |
| asks about West workspace, manifest, or Sysbuild                            | `build-system`          | Zephyr-specific build-system knowledge             |
| asks about BLE GATT services / characteristics or `Send-When-Idle`          | `connectivity-ble`      | Embedded BLE patterns, including power-aware design |
| asks about sensors, GPIO, pinctrl, or peripheral fetch/get                  | `hardware-io`           | Sensor subsystem + Devicetree integration          |

### Self-described — auto-fires for its listed use cases, no override needed

- `antigravity-bundle-systems-programming` — systems-programming skills (C/C++/Rust focused) that auto-activate alongside `fullstack-dev-skills`.
- `beriberikix/zephyr-agent-skills` — 44 Zephyr RTOS skills (BLE, IP networking, USB/CAN, kernel basics + services, hardware I/O, multicore, native simulation, power/performance, security/updates, storage, testing/debugging, industrial protocols, IoT, board bringup, build system, devicetree, modules, specialized, Zephyr foundations) that auto-activate when their context matches.

The C/C++ and Rust skills from the globally-installed `fullstack-dev-skills` plugin also auto-activate in this domain.
