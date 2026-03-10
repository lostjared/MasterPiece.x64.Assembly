import re
import sys
import zipfile
import tarfile
import shutil
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
    "r8b", "r9b", "r10b", "r11b", "r12b", "r13b", "r14b", "r15b"
}

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

def size_from_suffix(op):
    if op.endswith('b'):
        return 'BYTE PTR'
    if op.endswith('w'):
        return 'WORD PTR'
    if op.endswith('l'):
        return 'DWORD PTR'
    if op.endswith('q'):
        return 'QWORD PTR'
    return None

def normalize_opcode(op):
    mapping = {
        'movl': 'mov', 'movq': 'mov', 'movb': 'mov', 'movw': 'mov',
        'cmpl': 'cmp', 'cmpq': 'cmp', 'cmpb': 'cmp', 'cmpw': 'cmp',
        'addl': 'add', 'addq': 'add', 'addb': 'add', 'addw': 'add',
        'subl': 'sub', 'subq': 'sub', 'subb': 'sub', 'subw': 'sub',
        'xorl': 'xor', 'xorq': 'xor', 'xorb': 'xor', 'xorw': 'xor',
        'andl': 'and', 'andq': 'and', 'andb': 'and', 'andw': 'and',
        'orl': 'or', 'orq': 'or', 'orb': 'or', 'orw': 'or',
        'testl': 'test', 'testq': 'test', 'testb': 'test', 'testw': 'test',
        'leaq': 'lea', 'leal': 'lea',
        'imulq': 'imul', 'imull': 'imul',
        'idivq': 'idiv', 'idivl': 'idiv',
        'divq': 'div', 'divl': 'div',
        'incq': 'inc', 'incl': 'inc', 'incw': 'inc', 'incb': 'inc',
        'decq': 'dec', 'decl': 'dec', 'decw': 'dec', 'decb': 'dec',
        'shlq': 'shl', 'shll': 'shl',
        'shrq': 'shr', 'shrl': 'shr',
        'sarq': 'sar', 'sarl': 'sar',
        'pushq': 'push', 'pushl': 'push',
        'popq': 'pop', 'popl': 'pop',
    }
    return mapping.get(op, op)

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

    operand = operand.replace('%', '')

    if operand.startswith('$'):
        val = operand[1:]
        if _is_numeric(val):
            return val
        return f'OFFSET {val}'

    m = re.match(r'^(.*)\(([^)]*)\)$', operand)
    if m:
        disp = m.group(1).strip()
        inside = [x.strip().replace('%', '') for x in m.group(2).split(',')]
        while len(inside) < 3:
            inside.append('')
        base, index, scale = inside[:3]

        parts = []
        if base:
            parts.append(base)
        if index:
            parts.append(index + (f'*{scale}' if scale else ''))
        if disp:
            if base == 'rip':
                return f'[{base} + {disp}]'
            if parts:
                parts.append(disp)
            else:
                parts = [disp]
        if not parts:
            return '[]'
        return '[' + ' + '.join(parts) + ']'

    return operand

def operand_needs_ptr(op):
    return '[' in op and ' PTR ' not in op

def is_register(op):
    return op in REG_64 or op in REG_32 or op in REG_16 or op in REG_8

def convert_line(line):
    raw, comment = strip_comment(line)

    if not raw.strip():
        return raw + (' ' + comment if comment else '')

    stripped = raw.lstrip()

    if stripped.startswith('.'):
        return raw + (' ' + comment if comment else '')

    if raw.rstrip().endswith(':'):
        return raw + (' ' + comment if comment else '')

    if re.match(r'^\s*[A-Za-z_.$][\w.$]*:\s+\.', raw):
        return raw + (' ' + comment if comment else '')

    indent = re.match(r'^\s*', raw).group(0)
    body = raw[len(indent):].strip()

    if not body:
        return raw + (' ' + comment if comment else '')

    parts = body.split(None, 1)
    op = parts[0]
    args = parts[1] if len(parts) > 1 else ''
    ptr = size_from_suffix(op)
    op2 = normalize_opcode(op)

    if not args:
        return indent + op2 + (' ' + comment if comment else '')

    if op.startswith('imul'):
        ops = [convert_operand(x) for x in split_operands(args)]
        if len(ops) == 3:
            src1, src2, dst = ops
            out = f'{op2} {dst}, {src2}, {src1}'
        elif len(ops) == 2:
            src, dst = ops
            out = f'{op2} {dst}, {src}'
        else:
            out = f'{op2} ' + ', '.join(ops)
        return indent + out + (' ' + comment if comment else '')

    ops = [convert_operand(x) for x in split_operands(args)]

    if len(ops) == 2:
        src, dst = ops
        if ptr and operand_needs_ptr(dst) and not is_register(src):
            dst = f'{ptr} {dst}'
        elif ptr and operand_needs_ptr(src):
            src = f'{ptr} {src}'
        out = f'{op2} {dst}, {src}'
    elif len(ops) == 1:
        one = ops[0]
        if ptr and operand_needs_ptr(one):
            one = f'{ptr} {one}'
        out = f'{op2} {one}'
    else:
        out = f'{op2} ' + ', '.join(ops)

    return indent + out + (' ' + comment if comment else '')

def convert_text(text):
    lines = text.splitlines()
    out = ['.intel_syntax noprefix']
    for line in lines:
        out.append(convert_line(line))
    return '\n'.join(out) + '\n'

def main():
    if len(sys.argv) < 2:
        print("usage: python3 att_to_gas_intel.py code.zip [output_dir]")
        sys.exit(1)

    src_zip = Path(sys.argv[1])
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("code_intel_gas")
    extract_dir = Path("_att_unpack")

    if extract_dir.exists():
        shutil.rmtree(extract_dir)
    if out_dir.exists():
        shutil.rmtree(out_dir)

    extract_dir.mkdir(parents=True)
    out_dir.mkdir(parents=True)

    with zipfile.ZipFile(src_zip, "r") as zf:
        zf.extractall(extract_dir)

    asm_files = list(extract_dir.rglob("*.s"))

    for src in asm_files:
        dst = out_dir / src.name
        text = src.read_text(encoding="utf-8")
        dst.write_text(convert_text(text), encoding="utf-8")
        print(f"converted {src} -> {dst}")

    tar_path = out_dir.with_suffix(".tar.gz")
    with tarfile.open(tar_path, "w:gz") as tf:
        for f in out_dir.glob("*.s"):
            tf.add(f, arcname=f.name)

    print(f"wrote {tar_path}")

if __name__ == "__main__":
    main()
