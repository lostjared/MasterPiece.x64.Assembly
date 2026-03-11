#!/usr/bin/env python3

import re
import sys
from pathlib import Path

REG_64 = {
    "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp",
    "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "rip"
}
REG_32 = {
    "eax", "ebx", "ecx", "edx", "esi", "edi", "ebp", "esp",
    "r8d", "r9d", "r10d", "r11d", "r12d", "r13d", "r14d", "r15d"
}
REG_16 = {
    "ax", "bx", "cx", "dx", "si", "di", "bp", "sp",
    "r8w", "r9w", "r10w", "r11w", "r12w", "r13w", "r14w", "r15w"
}
REG_8 = {
    "al", "bl", "cl", "dl", "sil", "dil", "bpl", "spl",
    "ah", "bh", "ch", "dh",
    "r8b", "r9b", "r10b", "r11b", "r12b", "r13b", "r14b", "r15b"
}
ALL_REGS = REG_64 | REG_32 | REG_16 | REG_8

# x87 registers
FP_REGS = {f"st({i})" for i in range(8)} | {"st"}

# SSE/AVX registers
XMM_REGS = {f"xmm{i}" for i in range(32)}
YMM_REGS = {f"ymm{i}" for i in range(32)}
ZMM_REGS = {f"zmm{i}" for i in range(32)}
SIMD_REGS = XMM_REGS | YMM_REGS | ZMM_REGS

# Segment registers
SEG_REGS = {"cs", "ds", "es", "fs", "gs", "ss"}

ALL_REGS_FULL = ALL_REGS | FP_REGS | SIMD_REGS | SEG_REGS

# Instructions that never take a size suffix (even if they end in b/w/l/q)
NO_SUFFIX_OPS = {
    # jumps and branches
    "jmp", "je", "jne", "jz", "jnz", "jg", "jge", "jl", "jle",
    "ja", "jae", "jb", "jbe", "jc", "jnc", "jo", "jno", "js", "jns",
    "jp", "jnp", "jpe", "jpo",
    "jcxz", "jecxz", "jrcxz",
    "loop", "loope", "loopne", "loopz", "loopnz",
    # call/ret
    "call", "ret", "retq", "retl",
    "syscall", "sysret", "sysenter", "sysexit",
    # string ops (handled separately)
    "rep", "repe", "repz", "repne", "repnz",
    # other control
    "int", "into", "iret", "iretd", "iretq",
    "leave", "hlt", "nop", "ud2",
    "endbr64", "endbr32",
    # flag ops
    "clc", "stc", "cmc", "cld", "std", "cli", "sti",
    "lahf", "sahf", "pushf", "pushfq", "popf", "popfq",
    # sign extension (no operands)
    "cbw", "cwde", "cdqe", "cwd", "cdq", "cqo",
    "cbtw", "cwtl", "cltq", "cwtd", "cltd", "cqto",
    # prefixes
    "lock",
    # sse/avx scalar moves (suffix is part of name, not size)
    "movss", "movsd", "movaps", "movups", "movapd", "movupd",
    "movdqa", "movdqu", "movlps", "movhps", "movlpd", "movhpd",
    # cpuid/rdtsc
    "cpuid", "rdtsc", "rdtscp", "rdpmc",
    "lfence", "sfence", "mfence",
    "pause",
    "xgetbv", "xsetbv",
}

# AT&T sign-extension mnemonics → Intel
SIGN_EXT_MAP = {
    "cbtw": "cbw", "cwtl": "cwde", "cltq": "cdqe",
    "cwtd": "cwd", "cltd": "cdq", "cqto": "cqo",
}

# AT&T movs/movz → Intel movsx/movzx
MOVEXT_RE = re.compile(r'^(movs|movz)(b)(l|w|q)$|^(movs|movz)(w)(l|q)$|^(movs|movz)(l)(q)$')

def strip_comment(line):
    in_string = False
    escaped = False
    for i, ch in enumerate(line):
        if ch == '"' and not escaped:
            in_string = not in_string
        elif ch == '#' and not in_string:
            return line[:i].rstrip(), line[i:]
        escaped = (ch == '\\' and not escaped)
        if ch != '\\':
            escaped = False
    return line.rstrip('\n'), ''

def _is_numeric(s):
    """Check if a string is a numeric literal (decimal, hex, or negative)."""
    s = s.strip()
    if not s:
        return False
    if s.startswith('-'):
        s = s[1:]
    if not s:
        return False
    if s.startswith('0x') or s.startswith('0X'):
        return len(s) > 2 and all(c in '0123456789abcdefABCDEF' for c in s[2:])
    return s.isdigit()

# Map from AT&T suffix → size directive
SUFFIX_TO_PTR = {'b': 'BYTE PTR', 'w': 'WORD PTR', 'l': 'DWORD PTR', 'q': 'QWORD PTR'}

def _base_and_suffix(op):
    """Return (base_opcode, ptr_string_or_None) for a possibly-suffixed AT&T op."""
    low = op.lower()

    # If the whole opcode is in the no-suffix set, return as-is
    if low in NO_SUFFIX_OPS:
        return low, None

    # Sign-extension mnemonics
    if low in SIGN_EXT_MAP:
        return SIGN_EXT_MAP[low], None

    # movs/movz with double suffix → movsx/movsxd/movzx
    m = MOVEXT_RE.match(low)
    if m:
        # figure out which group matched
        for g in range(1, 8, 3):
            if m.group(g):
                kind = m.group(g)       # movs or movz
                src_s = m.group(g + 1)  # source size suffix
                dst_s = m.group(g + 2)  # dest size suffix
                if kind == 'movs' and src_s == 'l' and dst_s == 'q':
                    return 'movsxd', SUFFIX_TO_PTR.get(src_s)
                elif kind == 'movs':
                    return 'movsx', SUFFIX_TO_PTR.get(src_s)
                else:
                    return 'movzx', SUFFIX_TO_PTR.get(src_s)
        return low, None

    # setcc instructions: setCC → setCC (suffix is condition, not size)
    if low.startswith('set'):
        return low, None

    # cmovcc instructions: cmovCCl/q → cmovCC
    cmov_m = re.match(r'^(cmov\w+?)(b|w|l|q)$', low)
    if cmov_m:
        return cmov_m.group(1), SUFFIX_TO_PTR.get(cmov_m.group(2))

    # Explicit mapping for common suffixed instructions
    SUFFIX_MAP = {}
    for base in [
        'mov', 'cmp', 'add', 'sub', 'xor', 'and', 'or', 'test',
        'lea', 'imul', 'idiv', 'div', 'mul', 'neg', 'not',
        'inc', 'dec', 'shl', 'shr', 'sar', 'sal', 'rol', 'ror', 'rcl', 'rcr',
        'push', 'pop',
        'adc', 'sbb',
        'bt', 'bts', 'btr', 'btc', 'bsf', 'bsr',
        'xchg', 'xadd', 'cmpxchg',
        'bswap',
        'movabs',
        'lzcnt', 'tzcnt', 'popcnt',
        'in', 'out',
    ]:
        for sfx, ptr in SUFFIX_TO_PTR.items():
            SUFFIX_MAP[base + sfx] = (base, ptr)

    if low in SUFFIX_MAP:
        return SUFFIX_MAP[low]

    # rep/repne string ops: e.g. movsb, stosb, lodsb, scasb, cmpsb, insb, outsb
    for sop in ['movs', 'stos', 'lods', 'scas', 'cmps', 'ins', 'outs']:
        for sfx in ['b', 'w', 'l', 'q']:
            if low == sop + sfx:
                return low, None  # keep as-is, suffix is part of the mnemonic

    # retq/retl → ret
    if low in ('retq', 'retl'):
        return 'ret', None

    return op, None


def split_operands(args):
    out = []
    cur = []
    depth = 0
    for ch in args:
        if ch in '([':
            depth += 1
        elif ch in ')]' and depth > 0:
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(''.join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    if cur:
        out.append(''.join(cur).strip())
    return out

def convert_operand(operand):
    operand = operand.strip()
    if not operand:
        return operand

    # Handle indirect call/jmp: *%rax or *symbol or *(%rax) etc
    if operand.startswith('*'):
        inner = operand[1:]
        return convert_operand(inner)

    # Handle segment override: %fs:disp(%base) → fs:[base + disp]
    seg_m = re.match(r'^(%\w\w):(.*)$', operand)
    if seg_m:
        seg = seg_m.group(1).replace('%', '')
        rest = convert_operand(seg_m.group(2))
        if rest.startswith('['):
            return f'{seg}:{rest}'
        return f'{seg}:[{rest}]'

    # Strip all % prefixes from registers
    operand = operand.replace('%', '')

    # Immediate
    if operand.startswith('$'):
        val = operand[1:]
        if _is_numeric(val):
            return val
        return f'OFFSET {val}'

    # Memory operand: disp(base, index, scale)
    m = re.match(r'^(.*)\(([^)]*)\)$', operand)
    if m:
        disp = m.group(1).strip()
        inside = [x.strip().replace('%', '') for x in m.group(2).split(',')]
        while len(inside) < 3:
            inside.append('')
        base, index, scale = inside[:3]

        bracket_parts = []
        if base:
            bracket_parts.append(base)
        if index:
            if scale and scale != '1':
                bracket_parts.append(f'{index}*{scale}')
            elif scale == '1':
                bracket_parts.append(index)
            else:
                bracket_parts.append(index)
        if disp:
            # For rip-relative, always use "rip + symbol"
            if base == 'rip':
                return f'[rip + {disp}]'
            # Numeric displacement
            if _is_numeric(disp):
                num = int(disp, 0)
                if num < 0:
                    if bracket_parts:
                        return '[' + ' + '.join(bracket_parts) + f' - {-num}]'
                    else:
                        return f'[{num}]'
                elif num > 0:
                    if bracket_parts:
                        return '[' + ' + '.join(bracket_parts) + f' + {num}]'
                    else:
                        return f'[{num}]'
                # disp == 0, skip it
            else:
                # Symbol displacement
                if bracket_parts:
                    bracket_parts.append(disp)
                else:
                    bracket_parts = [disp]
        if not bracket_parts:
            return '[0]'
        return '[' + ' + '.join(bracket_parts) + ']'

    # x87 register: %st(N) → st(N)  (already stripped %)
    if operand.startswith('st(') or operand == 'st':
        return operand

    return operand

def operand_needs_ptr(op):
    return '[' in op and ' PTR ' not in op

def is_register(op):
    low = op.lower()
    return low in ALL_REGS_FULL

def convert_line(line):
    raw, comment = strip_comment(line)

    if not raw.strip():
        return raw + (' ' + comment if comment else '')

    stripped = raw.lstrip()

    # Assembler directives
    if stripped.startswith('.'):
        return raw + (' ' + comment if comment else '')

    # Labels (possibly with code after colon handled below)
    if raw.rstrip().endswith(':'):
        return raw + (' ' + comment if comment else '')

    # Label followed by directive: "label: .long 42"
    if re.match(r'^\s*[A-Za-z_.$][\w.$]*:\s+\.', raw):
        return raw + (' ' + comment if comment else '')

    indent = re.match(r'^\s*', raw).group(0)
    body = raw[len(indent):].strip()

    if not body:
        return raw + (' ' + comment if comment else '')

    # Handle lock prefix: "lock cmpxchg ..."
    prefix = ''
    if body.startswith('lock ') or body.startswith('lock\t'):
        prefix = 'lock '
        body = body[5:].strip()

    # Handle rep/repe/repne/repz/repnz prefix
    rep_m = re.match(r'^(rep[enz]*)\s+', body, re.IGNORECASE)
    if rep_m:
        prefix += rep_m.group(1) + ' '
        body = body[rep_m.end():].strip()

    parts = body.split(None, 1)
    op = parts[0]
    args = parts[1] if len(parts) > 1 else ''

    # Get base opcode and size info
    op2, ptr = _base_and_suffix(op)

    # movq/movd: if any operand is an xmm/mmx register, keep as movq/movd
    # otherwise it's a GP mov with q/d suffix
    if op.lower() in ('movq', 'movd'):
        raw_args = args.replace('%', '').lower()
        has_simd = any(r in raw_args for r in ('xmm', 'ymm', 'zmm', 'mm'))
        if has_simd:
            op2 = op.lower()  # keep as movq / movd
            ptr = None

    # No operands
    if not args:
        return indent + prefix + op2 + (' ' + comment if comment else '')

    # movabs → mov (AT&T movabsq $imm, %reg)
    if op2 == 'movabs':
        op2 = 'mov'

    # imul special: AT&T has reversed 3-operand form
    if op2 == 'imul':
        ops = [convert_operand(x) for x in split_operands(args)]
        if len(ops) == 3:
            src1, src2, dst = ops
            out = f'{op2} {dst}, {src2}, {src1}'
        elif len(ops) == 2:
            src, dst = ops
            out = f'{op2} {dst}, {src}'
        else:
            one = ops[0]
            if ptr and operand_needs_ptr(one):
                one = f'{ptr} {one}'
            out = f'{op2} {one}'
        return indent + prefix + out + (' ' + comment if comment else '')

    ops = [convert_operand(x) for x in split_operands(args)]

    if len(ops) == 2:
        src, dst = ops
        # Add PTR if memory operand and size would be ambiguous
        if ptr and operand_needs_ptr(dst) and not is_register(src):
            dst = f'{ptr} {dst}'
        elif ptr and operand_needs_ptr(src) and not is_register(dst):
            src = f'{ptr} {src}'
        out = f'{op2} {dst}, {src}'
    elif len(ops) == 1:
        one = ops[0]
        if ptr and operand_needs_ptr(one):
            one = f'{ptr} {one}'
        out = f'{op2} {one}'
    elif len(ops) == 3:
        # 3-operand forms other than imul (e.g. shld, shrd, etc.)
        # AT&T: src1, src2, dst → Intel: dst, src2, src1
        src1, src2, dst = ops
        out = f'{op2} {dst}, {src2}, {src1}'
    else:
        out = f'{op2} ' + ', '.join(reversed(ops))

    return indent + prefix + out + (' ' + comment if comment else '')

def convert_text(text):
    lines = text.splitlines()
    out = ['.intel_syntax noprefix']
    for line in lines:
        out.append(convert_line(line))
    return '\n'.join(out) + '\n'

def main():
    if len(sys.argv) < 2:
        print("usage: python3 convert.py <src_dir> [output_dir]")
        sys.exit(1)

    src_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("code_intel_gas")

    if not src_path.is_dir():
        print(f"error: {src_path} is not a directory")
        sys.exit(1)

    out_dir.mkdir(parents=True, exist_ok=True)

    asm_files = list(src_path.rglob("*.s"))
    if not asm_files:
        print(f"no .s files found in {src_path}")
        sys.exit(1)

    for src in asm_files:
        dst = out_dir / src.name
        text = src.read_text(encoding="utf-8")
        dst.write_text(convert_text(text), encoding="utf-8")
        print(f"converted {src} -> {dst}")

if __name__ == "__main__":
    main()
