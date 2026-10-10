# Assemble the ISA test program and compute the expected final state with a
# small Python RV32I model. Writes tb/isa_prog.svh (included by tb_isa.sv).
#   python scripts/gen_isa_test.py
import pathlib

PROG = """
    lui   x1, 0x12345
    addi  x1, x1, 0x678
    auipc x2, 0
    addi  x3, x0, -1
    addi  x4, x0, 5
    addi  x5, x0, -7
    add   x6, x4, x5
    sub   x7, x4, x5
    sll   x8, x1, x4
    slt   x9, x5, x4
    sltu  x10, x5, x4
    xor   x11, x1, x3
    srl   x12, x3, x4
    sra   x13, x5, x4
    or    x14, x1, x4
    and   x15, x1, x3
    slti  x16, x5, -6
    sltiu x17, x4, -1
    xori  x18, x1, -1
    ori   x19, x4, 0x700
    andi  x20, x1, 0x0f0
    slli  x21, x1, 4
    srli  x22, x3, 28
    srai  x23, x5, 1
    sw    x1, 0(x0)
    sh    x5, 4(x0)
    sb    x3, 6(x0)
    sb    x4, 7(x0)
    lw    x24, 4(x0)
    lb    x25, 6(x0)
    lbu   x26, 6(x0)
    lh    x27, 4(x0)
    lhu   x28, 4(x0)
    lb    x29, 1(x0)
    addi  x30, x0, 0
    beq   x4, x5, L1
    addi  x30, x30, 1
L1: bne   x4, x5, L2
    addi  x30, x30, 2
L2: blt   x5, x4, L3
    addi  x30, x30, 4
L3: bge   x5, x4, L4
    addi  x30, x30, 8
L4: bltu  x5, x4, L5
    addi  x30, x30, 16
L5: bgeu  x5, x4, L6
    addi  x30, x30, 32
L6: jal   x31, F
    addi  x30, x30, 64
    jal   x0, END
F:  addi  x30, x30, 128
    jalr  x0, 0(x31)
END: sw   x30, 8(x0)
    sw    x9, 12(x0)
    lui   x9, 0xABCDE
    ecall
"""

R = {"add": (0, 0), "sub": (0x20, 0), "sll": (0, 1), "slt": (0, 2), "sltu": (0, 3),
     "xor": (0, 4), "srl": (0, 5), "sra": (0x20, 5), "or": (0, 6), "and": (0, 7)}
I = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SH = {"slli": (0, 1), "srli": (0, 5), "srai": (0x20, 5)}
LD = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
ST = {"sb": 0, "sh": 1, "sw": 2}
BR = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}


def reg(s):
    return int(s.strip().lstrip("x"))


def num(s):
    return int(s.strip(), 0)


def memop(s):                       # "8(x0)" -> (8, 0)
    off, r = s.strip().rstrip(")").split("(")
    return num(off), reg(r)


def parse():
    lines, labels = [], {}
    for raw in PROG.strip().splitlines():
        s = raw.split("#")[0].strip()
        if ":" in s:
            lab, s = s.split(":", 1)
            labels[lab.strip()] = len(lines)
            s = s.strip()
        if s:
            op, _, rest = s.partition(" ")
            lines.append((op, [a.strip() for a in rest.split(",")] if rest else []))
    return lines, labels


def encode(op, a, pc, labels):
    if op in R:
        f7, f3 = R[op]
        return f7 << 25 | reg(a[2]) << 20 | reg(a[1]) << 15 | f3 << 12 | reg(a[0]) << 7 | 0x33
    if op in I:
        return (num(a[2]) & 0xFFF) << 20 | reg(a[1]) << 15 | I[op] << 12 | reg(a[0]) << 7 | 0x13
    if op in SH:
        f7, f3 = SH[op]
        return f7 << 25 | num(a[2]) << 20 | reg(a[1]) << 15 | f3 << 12 | reg(a[0]) << 7 | 0x13
    if op in LD:
        off, rs1 = memop(a[1])
        return (off & 0xFFF) << 20 | rs1 << 15 | LD[op] << 12 | reg(a[0]) << 7 | 0x03
    if op in ST:
        off, rs1 = memop(a[1])
        return ((off >> 5) & 0x7F) << 25 | reg(a[0]) << 20 | rs1 << 15 | ST[op] << 12 | (off & 0x1F) << 7 | 0x23
    if op in BR:
        imm = (labels[a[2]] * 4 - pc) & 0x1FFF
        return ((imm >> 12) & 1) << 31 | ((imm >> 5) & 0x3F) << 25 | reg(a[1]) << 20 | reg(a[0]) << 15 \
            | BR[op] << 12 | ((imm >> 1) & 0xF) << 8 | ((imm >> 11) & 1) << 7 | 0x63
    if op == "lui":
        return (num(a[1]) & 0xFFFFF) << 12 | reg(a[0]) << 7 | 0x37
    if op == "auipc":
        return (num(a[1]) & 0xFFFFF) << 12 | reg(a[0]) << 7 | 0x17
    if op == "jal":
        imm = (labels[a[1]] * 4 - pc) & 0x1FFFFF
        return ((imm >> 20) & 1) << 31 | ((imm >> 1) & 0x3FF) << 21 | ((imm >> 11) & 1) << 20 \
            | ((imm >> 12) & 0xFF) << 12 | reg(a[0]) << 7 | 0x6F
    if op == "jalr":
        off, rs1 = memop(a[1])
        return (off & 0xFFF) << 20 | rs1 << 15 | reg(a[0]) << 7 | 0x67
    if op == "ecall":
        return 0x73
    raise ValueError(op)


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def simulate(lines, labels):
    x = [0] * 32
    mem = bytearray(1024)
    pc = 0
    M = 0xFFFFFFFF
    while True:
        op, a = lines[pc // 4]
        nxt = pc + 4
        s = lambda r: sx(x[reg(r)], 32)
        u = lambda r: x[reg(r)]
        def wr(r, v):
            if reg(r):
                x[reg(r)] = v & M
        if op in R:
            v1, v2 = u(a[1]), u(a[2]); sh = v2 & 31
            wr(a[0], {"add": v1 + v2, "sub": v1 - v2, "sll": v1 << sh, "slt": int(s(a[1]) < s(a[2])),
                      "sltu": int(v1 < v2), "xor": v1 ^ v2, "srl": v1 >> sh, "sra": s(a[1]) >> sh,
                      "or": v1 | v2, "and": v1 & v2}[op])
        elif op in I:
            imm = sx(num(a[2]), 12)
            wr(a[0], {"addi": u(a[1]) + imm, "slti": int(s(a[1]) < imm), "sltiu": int(u(a[1]) < (imm & M)),
                      "xori": u(a[1]) ^ (imm & M), "ori": u(a[1]) | (imm & M), "andi": u(a[1]) & (imm & M)}[op])
        elif op in SH:
            sh = num(a[2])
            wr(a[0], {"slli": u(a[1]) << sh, "srli": u(a[1]) >> sh, "srai": s(a[1]) >> sh}[op])
        elif op in LD:
            off, rs1 = memop(a[1]); ad = (x[rs1] + off) & M
            n = {"lb": 1, "lbu": 1, "lh": 2, "lhu": 2, "lw": 4}[op]
            v = int.from_bytes(mem[ad:ad + n], "little")
            wr(a[0], sx(v, 8 * n) if op in ("lb", "lh") else v)
        elif op in ST:
            off, rs1 = memop(a[1]); ad = (x[rs1] + off) & M
            n = {"sb": 1, "sh": 2, "sw": 4}[op]
            mem[ad:ad + n] = (u(a[0]) & ((1 << 8 * n) - 1)).to_bytes(n, "little")
        elif op in BR:
            v1, v2 = u(a[0]), u(a[1])
            take = {"beq": v1 == v2, "bne": v1 != v2, "blt": s(a[0]) < s(a[1]), "bge": s(a[0]) >= s(a[1]),
                    "bltu": v1 < v2, "bgeu": v1 >= v2}[op]
            if take:
                nxt = labels[a[2]] * 4
        elif op == "lui":
            wr(a[0], num(a[1]) << 12)
        elif op == "auipc":
            wr(a[0], pc + (num(a[1]) << 12))
        elif op == "jal":
            wr(a[0], pc + 4); nxt = labels[a[1]] * 4
        elif op == "jalr":
            off, rs1 = memop(a[1]); t = (x[rs1] + off) & ~1 & M
            wr(a[0], pc + 4); nxt = t
        elif op == "ecall":
            return x, mem
        pc = nxt


lines, labels = parse()
code = [encode(op, a, 4 * i, labels) for i, (op, a) in enumerate(lines)]
regs, mem = simulate(lines, labels)

out = ["// generated by scripts/gen_isa_test.py, do not edit", f"localparam int ISA_LEN = {len(code)};",
       "logic [31:0] prog [64];", "logic [31:0] exp_r [32];", "logic [31:0] exp_m [4];", "",
       "task automatic isa_program;"]
for i, (w, (op, a)) in enumerate(zip(code, lines)):
    out.append(f"    prog[{i}] = 32'h{w:08X};  // {op} {', '.join(a)}")
out += ["endtask", "", "task automatic isa_expected;"]
out += [f"    exp_r[{i}] = 32'h{v:08X};" for i, v in enumerate(regs)]
out += [f"    exp_m[{i}] = 32'h{int.from_bytes(mem[4*i:4*i+4], 'little'):08X};" for i in range(4)]
out += ["endtask", ""]
pathlib.Path(__file__).resolve().parent.parent.joinpath("tb", "isa_prog.svh").write_text("\n".join(out))
print(f"{len(code)} instructions, x30 = {regs[30]}, mem[2] = {int.from_bytes(mem[8:12], 'little')}")
