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
