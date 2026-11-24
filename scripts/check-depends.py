#!/usr/bin/env python3
"""check-depends.py - does each of our packages declare what it needs?

A package that needs something only because another package happens to pull it in works until
that other package goes. That is how removing the unused mkinitcpio took cmp away from the kernel
installer (diffutils was only there for mkinitcpio), and how the base snapshot lost plasma-mobile's
volume control (nothing declared plasma-pa, so no image installed it and the snapshot left it out).

For every package named on the command line this works out what its files need:
  lib     shared libraries its arm64 ELF files link (DT_NEEDED)
  cmd     commands its shell and Python scripts run, and the programs its systemd units,
          .desktop files and udev rules start
  qml     QML modules its .qml files import
  python  Python modules its Python files import
and checks each one is met inside the package's own dependency closure (depends and provides,
followed through every --repo). What the `base` package's closure ships counts as met everywhere:
every image installs it explicitly. A command a script tests for first (command -v, -x
/usr/bin/..., shutil.which) is optional and not checked.

--missing also reports libraries and QML modules that nothing in the repos ships at all, which is
what a new base snapshot looks like when it stops carrying something we use.

Usage:
  check-depends.py --repo base.db:base.files [--repo shared.db:shared.files ...]
                   [--ok config/packages/depends-ok.list] [--missing] <pkg.tar.zst | dir>...
Exceptions: `<pkgname> <need>  # why` per line in the --ok file. --pending names depends a package
is known to lack, `<pkgname> <version> <depends...>`: they count as declared while the package is
at that version (scripts/check.sh makes sure they are added when it moves on). Exit 1 on any finding.
"""
import argparse
import os
import re
import struct
import subprocess
import sys
import tarfile

# --- repo dbs -------------------------------------------------------------------------------


def parse_desc(text):
    out, key = {}, None
    for line in text.split("\n"):
        if line.startswith("%") and line.endswith("%"):
            key = line.strip("%")
            out[key] = []
        elif line and key:
            out[key].append(line)
    return out


def strip_ver(dep):
    return re.split(r"[<>=:]", dep, maxsplit=1)[0].strip()


class Universe:
    def __init__(self):
        self.depends = {}   # pkg -> [dep names]
        self.provides = {}  # name -> {pkg}
        self.files = {}     # pkg -> [paths]

    def add(self, name, depends, provides, files):
        if name in self.depends:  # a later copy (the package being checked) replaces the repo's
            for p in list(self.provides):
                self.provides[p].discard(name)
        self.depends[name] = [strip_ver(d) for d in depends]
        self.provides.setdefault(name, set()).add(name)
        for p in provides:
            self.provides.setdefault(strip_ver(p), set()).add(name)
        self.files[name] = files

    def closure(self, roots):
        seen, todo = set(), list(roots)
        while todo:
            for pkg in self.provides.get(todo.pop(), ()):
                if pkg not in seen:
                    seen.add(pkg)
                    todo.extend(self.depends.get(pkg, ()))
        return seen


def load_repo(u, db_path, files_path):
    files = {}
    if files_path:
        with tarfile.open(files_path) as t:
            for m in t:
                if m.name.endswith("/files"):
                    d = parse_desc(t.extractfile(m).read().decode("utf-8", "replace"))
                    files[m.name.split("/")[0]] = ["/" + f for f in d.get("FILES", [])]
    with tarfile.open(db_path) as t:
        for m in t:
            if m.name.endswith("/desc"):
                d = parse_desc(t.extractfile(m).read().decode("utf-8", "replace"))
                u.add(d["NAME"][0], d.get("DEPENDS", []), d.get("PROVIDES", []),
                      files.get(m.name.split("/")[0], []))


# --- reading a package ----------------------------------------------------------------------

ELF_MAGIC = b"\x7fELF"
EM_AARCH64 = 183


def elf_needed(data):
    """DT_NEEDED of a 64-bit little-endian arm64 ELF; None for anything else (x86 trees in
    Proton and the FEX rootfs carry their own libraries)."""
    if len(data) < 64 or data[:4] != ELF_MAGIC or data[4] != 2 or data[5] != 1:
        return None
    try:
        if struct.unpack_from("<H", data, 0x12)[0] != EM_AARCH64:
            return None
        e_shoff, = struct.unpack_from("<Q", data, 0x28)
        e_shentsize, e_shnum = struct.unpack_from("<HH", data, 0x3A)
        secs = []
        for i in range(e_shnum):
            off = e_shoff + i * e_shentsize
            sh_type, = struct.unpack_from("<I", data, off + 4)
            sh_offset, sh_size = struct.unpack_from("<QQ", data, off + 0x18)
            sh_link, = struct.unpack_from("<I", data, off + 0x28)
            secs.append((sh_type, sh_offset, sh_size, sh_link))
        out = []
        for sh_type, off, size, link in secs:
            if sh_type != 6:  # SHT_DYNAMIC
                continue
            stroff = secs[link][1]
            for j in range(0, size, 16):
                tag, val = struct.unpack_from("<qQ", data, off + j)
                if tag == 0:
                    break
                if tag == 1:  # DT_NEEDED
                    end = data.index(b"\0", stroff + val)
                    out.append(data[stroff + val:end].decode())
        return out
    except (struct.error, IndexError, ValueError):
        return None


SHELL_RE = re.compile(rb"^#!\s*(/usr)?/bin/(env\s+)?(ba|da|z)?sh\b")
PY_RE = re.compile(rb"^#!\s*(/usr)?/bin/(env\s+)?python3?\b")


def read_pkg(path):
    """Streams the package: (pkginfo, every path, {path: needed sonames}, {path: (kind, text)})."""
    proc = subprocess.Popen(["zstd", "-dcq", path], stdout=subprocess.PIPE)
    info, allp, elfs, texts = {}, [], {}, {}
    with tarfile.open(fileobj=proc.stdout, mode="r|") as t:
        for m in t:
            name = m.name[2:] if m.name.startswith("./") else m.name
            if name == ".PKGINFO":
                for line in t.extractfile(m).read().decode().splitlines():
                    if " = " in line:
                        k, v = line.split(" = ", 1)
                        info.setdefault(k, []).append(v)
                continue
            if name.startswith("."):
                continue
            p = "/" + name
            allp.append(p + ("/" if m.isdir() else ""))
            if not m.isfile():
                continue
            f = t.extractfile(m)
            head = f.read(64)
            if head[:4] == ELF_MAGIC:
                needed = elf_needed(head + f.read())
                if needed:
                    elfs[p] = needed
            elif SHELL_RE.match(head):
                texts[p] = ("sh", (head + f.read()).decode("utf-8", "replace"))
            elif PY_RE.match(head) or p.endswith(".py"):
                texts[p] = ("py", (head + f.read()).decode("utf-8", "replace"))
            elif p.endswith(".qml"):
                texts[p] = ("qml", (head + f.read()).decode("utf-8", "replace"))
            elif p.endswith((".service", ".socket", ".desktop", ".rules")) and m.size < 1024 * 1024:
                texts[p] = ("exec", (head + f.read()).decode("utf-8", "replace"))
    proc.wait()
    return info, allp, elfs, texts


# --- what a script runs ---------------------------------------------------------------------


def shell_code(text):
    """The script with comments, heredoc bodies and quoted strings blanked out. Command
    substitutions inside double quotes are kept, as commands of their own."""
    out, i, n = [], 0, len(text)
    heredocs = []

    def dq_end(j):  # past the closing quote of a "..." that opened at j-1, and its $(...)s
        subs, depth, start = [], 0, None
        while j < n:
            c = text[j]
            if c == "\\":
                j += 2
                continue
            if depth == 0 and c == '"':
                return j + 1, subs
            if c == "$" and j + 1 < n and text[j + 1] == "(":
                if depth == 0:
                    start = j + 2
                depth += 1
                j += 2
                continue
            if c == ")" and depth:
                depth -= 1
                if depth == 0:
                    subs.append(text[start:j])
            j += 1
        return n, subs

    while i < n:
        c = text[i]
        if c == "\n":
            out.append(c)
            i += 1
            for tag in heredocs:  # skip each heredoc body that starts here
                while i < n:
                    e = text.find("\n", i)
                    e = n if e < 0 else e
                    line, i = text[i:e], e + 1
                    if line.strip() == tag:
                        break
            heredocs = []
            continue
        if c == "\\":
            out.append(" ")
            i += 2
            continue
        if c == "#" and (i == 0 or text[i - 1] in " \t\n;"):
            e = text.find("\n", i)
            i = n if e < 0 else e
            continue
        if c == "<" and text.startswith("<<", i) and not text.startswith("<<<", i):
            m = re.match(r"<<-?\s*['\"]?(\w+)['\"]?", text[i:])
            if m:
                heredocs.append(m.group(1))
                i += m.end()
                continue
        if c == "'":
            e = text.find("'", i + 1)
            i = n if e < 0 else e + 1
            out.append(" '' ")
            continue
        if c == '"':
            i, subs = dq_end(i + 1)
            out.append(' "" ')
            for sub in subs:
                out.append(" ; " + shell_code(sub) + " ; ")
            continue
        out.append(c)
        i += 1
    return "".join(out)


SEP_RE = re.compile(r"\$\(|`|&&|\|\||[;|&()\n]")
KEYWORDS = {"if", "then", "else", "elif", "fi", "do", "done", "while", "until", "esac", "in",
            "!", "{", "}", "function", "return", "time"}
WRAPPERS = {"exec", "sudo", "pkexec", "env", "nohup", "command", "builtin", "nice", "ionice",
            "chrt", "taskset", "setsid", "stdbuf", "xargs", "timeout", "flock", "runuser",
            "unshare", "chroot"}
NOT_COMMANDS = {"local", "export", "readonly", "declare", "typeset", "unset", "echo", "printf"}
# A command the script tests for before running it is optional: the script copes without it.
GUARD_RE = re.compile(r"(?:command\s+-v|type\s+-[pP]|hash|which)\s+[\"']?(?:/usr/s?bin/)?([A-Za-z0-9_][\w.+-]*)"
                      r"|-[xef]\s+[\"']?/usr/s?bin/([A-Za-z0-9_][\w.+-]*)")
WORD_RE = re.compile(r"^[A-Za-z0-9_][\w.+-]*$")


def shell_commands(text):
    """The first word of each simple command, past variable assignments and wrappers."""
    s = shell_code(text)
    s = re.sub(r"\b\w+\+?=\([^()]*\)", " ", s)                                # array literals
    s = re.sub(r"(?m)(^|;;)\s*\(?[\w*.|\[\]\"'-]+\)(?=\s|$)", r"\1 ", s)         # case labels
    out = set()
    for seg in SEP_RE.split(s):
        words = seg.split()
        if not words or words[0] in NOT_COMMANDS:
            continue
        i = 0
        while i < len(words):
            w = words[i]
            if w in ("for", "select", "case"):  # a loop variable or the case word, not a command
                i = len(words)
                break
            if w in KEYWORDS or re.match(r"^\w+=", w):
                i += 1
                continue
            if w in WRAPPERS:
                out.add(w)
                i += 1
                while i < len(words) and (words[i].startswith("-") or re.match(r"^\w+=", words[i])
                                          or re.match(r"^\d", words[i])):
                    i += 1
                continue
            break
        if i < len(words):
            w = re.sub(r"^(/usr)?/s?bin/", "", words[i].strip("\"'"))
            if WORD_RE.match(w):
                out.add(w)
    return out


PY_CALL_RE = re.compile(r"""(?:\brun|Popen|check_output|check_call|\bcall|exec[lv]p?e?)\(\s*\[?\s*["']([^"'\s]+)["']""")


EXEC_RE = re.compile(r"^\s*(?:Exec(?:Start|StartPre|StartPost|Stop|StopPost|Reload|Condition)?|TryExec)=[-+!@:|]*\s*(\S+)", re.M)
UDEV_RE = re.compile(r"""(?:RUN(?:\{program\})?\+?=|PROGRAM=)"([^"\s]+)""")


def script_commands(kind, text):
    if kind == "exec":  # systemd units, .desktop files, udev rules: the program each line starts
        # A .desktop entry with TryExec= is hidden when that program is missing: optional.
        tried = {os.path.basename(c) for c in re.findall(r"^\s*TryExec=\s*(\S+)", text, re.M)}
        return {os.path.basename(c) for c in EXEC_RE.findall(text) + UDEV_RE.findall(text)
                if not c.startswith(("%", "$"))} - tried
    guarded = {a or b for a, b in GUARD_RE.findall(text)}
    guarded |= set(re.findall(r"shutil\.which\(\s*[\"']([\w.+-]+)", text))
    if kind == "py":
        code = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
        found = {os.path.basename(c) for c in PY_CALL_RE.findall(code)}
    else:
        found = shell_commands(text)
    return found - guarded


QML_IMPORT = re.compile(r"^\s*import\s+([A-Za-z][\w.]*)", re.M)
PY_IMPORT = re.compile(r"^\s*(?:from\s+([A-Za-z_]\w*)|import\s+([A-Za-z_]\w*))", re.M)

# --- main -----------------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--repo", action="append", default=[], metavar="DB[:FILES]",
                    help="a pacman repo's .db (and .files, for what it ships); repeatable")
    ap.add_argument("--ok", help="exceptions: <pkgname> <need>  # why")
    ap.add_argument("--pending", help="known gaps: <pkgname> <version> <depends...>")
    ap.add_argument("--missing", action="store_true",
                    help="also report libraries and QML modules nothing ships at all")
    ap.add_argument("pkgs", nargs="+")
    a = ap.parse_args()

    u = Universe()
    for r in a.repo:
        db, _, files = r.partition(":")
        load_repo(u, db, files or None)

    paths = []
    for p in a.pkgs:
        if os.path.isdir(p):
            paths += [os.path.join(p, f) for f in sorted(os.listdir(p)) if re.search(r"\.pkg\.tar\.zst$", f)]
        else:
            paths.append(p)

    pending = {}
    if a.pending and os.path.exists(a.pending):
        for line in open(a.pending):
            f = line.split("#", 1)[0].split()
            if len(f) >= 3:
                pending[(f[0], f[1])] = f[2:]

    checked = []
    for p in paths:
        info, allp, elfs, texts = read_pkg(p)
        name = info["pkgname"][0]
        deps = info.get("depend", []) + pending.get((name, info["pkgver"][0]), [])
        u.add(name, deps, info.get("provides", []), allp)
        checked.append((name, allp, elfs, texts))

    ok = set()
    if a.ok and os.path.exists(a.ok):
        for line in open(a.ok):
            f = line.split("#", 1)[0].split()
            if len(f) >= 2:
                ok.add((f[0], f[1]))

    # who ships what
    soname, command, qml, pymod = {}, {}, {}, {}
    for pkg, files in u.files.items():
        for f in files:
            if f.endswith("/"):
                d = f.rstrip("/")
                if d.startswith("/usr/lib/qt6/qml/"):
                    qml.setdefault(d[len("/usr/lib/qt6/qml/"):].replace("/", "."), set()).add(pkg)
                m = re.match(r"^/usr/lib/python3[^/]*/site-packages/([A-Za-z_]\w*)$", d)
                if m:
                    pymod.setdefault(m.group(1), set()).add(pkg)
                continue
            base, dirn = os.path.basename(f), os.path.dirname(f)
            if dirn in ("/usr/lib", "/usr/lib64", "/lib") and ".so" in base:
                soname.setdefault(base, set()).add(pkg)
            elif dirn in ("/usr/bin", "/usr/sbin", "/bin", "/sbin"):
                command.setdefault(base, set()).add(pkg)
            m = re.match(r"^/usr/lib/python3[^/]*/site-packages/([A-Za-z_]\w*)\.(py|.*\.so)$", f)
            if m:
                pymod.setdefault(m.group(1), set()).add(pkg)

    always = u.closure(["base"]) if "base" in u.depends else set()

    findings = []
    for name, allp, elfs, texts in checked:
        clos = u.closure([name]) | always
        own = {os.path.basename(q.rstrip("/")) for q in allp}
        miss = {}

        def need(kind, what, owners, path):
            if (name, what) in ok:
                return
            if not owners:
                if a.missing and kind in ("lib", "qml"):
                    miss.setdefault((kind, what), [set(), set()])[1].add(path)
                return
            if owners & clos:
                return
            e = miss.setdefault((kind, what), [set(), set()])
            e[0].update(owners)
            e[1].add(path)

        for path, needed in elfs.items():
            for n in needed:
                if n not in own:  # its own copy, beside it or on its RUNPATH
                    need("lib", n, soname.get(n, set()), path)
        for path, (kind, text) in texts.items():
            if kind == "qml":
                for mod in QML_IMPORT.findall(text):
                    need("qml", mod, qml.get(mod, set()), path)
                continue
            for c in script_commands(kind, text):
                if c in command:
                    need("cmd", c, command[c], path)
            if kind == "py":
                for m in PY_IMPORT.finditer(text):
                    mod = m.group(1) or m.group(2)
                    if mod in pymod:
                        need("python", mod, pymod[mod], path)

        for (kind, what), (owners, files) in sorted(miss.items()):
            files = sorted(files)
            where = ", ".join(files[:3]) + (" ..." if len(files) > 3 else "")
            if owners:
                findings.append(f"{name}: {kind} {what} comes from {' or '.join(sorted(owners))}, "
                                f"which it does not depend on ({where})")
            else:
                findings.append(f"{name}: {kind} {what}: nothing in the repos ships it ({where})")

    for f in findings:
        print(f)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
