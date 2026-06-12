#!/usr/bin/env python3
# Tiny generator for a demo program: print a string over the UART, then ECALL.
import sys

UART_BASE = 0x10000000
MSG = "Hello, RV32I 3-stage!\n"

def u(x):  # mask to 32 bits
    return x & 0xFFFFFFFF

def lui(rd, imm20):     return u((imm20 & 0xFFFFF) << 12 | rd << 7 | 0x37)
def addi(rd, rs1, im):  return u((im & 0xFFF) << 20 | rs1 << 15 | 0 << 12 | rd << 7 | 0x13)
def andi(rd, rs1, im):  return u((im & 0xFFF) << 20 | rs1 << 15 | 7 << 12 | rd << 7 | 0x13)
def lw(rd, rs1, im):    return u((im & 0xFFF) << 20 | rs1 << 15 | 2 << 12 | rd << 7 | 0x03)
def sw(rs2, rs1, im):
    im &= 0xFFF
    return u((im >> 5) << 25 | rs2 << 20 | rs1 << 15 | 2 << 12 | (im & 0x1F) << 7 | 0x23)
def bne(rs1, rs2, off):
    o = off & 0x1FFF
    b12 = (o >> 12) & 1; b11 = (o >> 11) & 1; b10_5 = (o >> 5) & 0x3F; b4_1 = (o >> 1) & 0xF
    return u(b12 << 31 | b10_5 << 25 | rs2 << 20 | rs1 << 15 | 1 << 12 | b4_1 << 8 | b11 << 7 | 0x63)
def ecall():            return 0x00000073

prog = []
def emit(w): prog.append(u(w))
def here(): return len(prog) * 4

# x1 = UART_BASE  (0x10000000 = 0x10000 << 12, low 12 bits zero)
emit(lui(1, UART_BASE >> 12))

for ch in MSG:
    poll = here()
    emit(lw(3, 1, 4))           # x3 = STATUS
    emit(andi(3, 3, 1))         # x3 &= TX_BUSY
    emit(bne(3, 0, poll - here()))  # while busy, retry
    emit(addi(4, 0, ord(ch)))   # x4 = char
    emit(sw(4, 1, 0))           # DATA = x4

emit(ecall())

with open(sys.argv[1], "w") as f:
    for w in prog:
        f.write(f"{w:08x}\n")
print(f"emitted {len(prog)} instructions ({len(prog)*4} bytes), msg={MSG!r}")
