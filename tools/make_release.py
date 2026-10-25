"""Builds the release zip of the addon.

By default the zip is built from the working directory: tracked files as they are now, plus new
files that git does not ignore. With a commit (a hash, tag, branch or HEAD) it is built from that
commit instead, and uncommitted changes are left out.

The zip holds a single CombatTracking folder, ready to be unpacked into Interface/AddOns.
Development files (tools, CLAUDE.md, dot files) are left out. The version in the file name comes
from the "## Version" line of CombatTracking.toc in the same source.

Usage: python tools/make_release.py [commit] [-o output folder, default: dist]
"""
import argparse
import os
import re
import subprocess
import sys
import time
import zipfile

ADDON = 'CombatTracking'
EXCLUDE = {'tools', 'CLAUDE.md', 'dist'}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def git(*args, binary=False):
    out = subprocess.run(['git', *args], cwd=ROOT, check=True, capture_output=True).stdout
    return out if binary else out.decode('utf-8')


def packed(path):
    parts = path.split('/')
    return parts[0] not in EXCLUDE and not any(p.startswith('.') for p in parts)


def working_files():
    """(path, read, date) of the files in the working directory."""
    names = git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split('\0')
    for name in sorted(set(names)):
        full = os.path.join(ROOT, name)
        if name and packed(name) and os.path.isfile(full):  # skips deleted tracked files
            yield name, lambda f=full: open(f, 'rb').read(), time.localtime(os.path.getmtime(full))[:6]


def commit_files(commit):
    """(path, read, date) of the files in a commit."""
    date = time.localtime(int(git('show', '-s', '--format=%ct', commit)))[:6]
    for name in git('ls-tree', '-r', '-z', '--name-only', commit).split('\0'):
        if name and packed(name):
            yield name, lambda n=name: git('show', '%s:%s' % (commit, n), binary=True), date


def main(commit, out_dir):
    files = list(commit_files(commit) if commit else working_files())
    toc = next(read for name, read, _ in files if name == ADDON + '.toc')().decode('utf-8')
    version = re.search(r'^## Version:\s*(\S+)', toc, re.M).group(1)

    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, '%s-%s.zip' % (ADDON, version))
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as zip_file:
        for name, read, date in files:
            zip_file.writestr(zipfile.ZipInfo('%s/%s' % (ADDON, name), date), read(), zipfile.ZIP_DEFLATED)
    print('%s (%d files, from %s)' % (path, len(files), commit or 'the working directory'))


def started_from_explorer():
    """True when the script was double-clicked: its console closes as soon as it ends."""
    if os.name != 'nt':
        return False
    import ctypes
    from ctypes import wintypes

    class ProcessEntry(ctypes.Structure):
        _fields_ = [('dwSize', wintypes.DWORD), ('cntUsage', wintypes.DWORD), ('th32ProcessID', wintypes.DWORD),
                    ('th32DefaultHeapID', ctypes.c_void_p), ('th32ModuleID', wintypes.DWORD),
                    ('cntThreads', wintypes.DWORD), ('th32ParentProcessID', wintypes.DWORD),
                    ('pcPriClassBase', ctypes.c_long), ('dwFlags', wintypes.DWORD),
                    ('szExeFile', ctypes.c_wchar * 260)]

    kernel32 = ctypes.windll.kernel32
    kernel32.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    snapshot = kernel32.CreateToolhelp32Snapshot(2, 0)  # TH32CS_SNAPPROCESS
    entry = ProcessEntry(dwSize=ctypes.sizeof(ProcessEntry))
    processes = {}
    ok = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
    while ok:
        processes[entry.th32ProcessID] = (entry.th32ParentProcessID, entry.szExeFile.lower())
        ok = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    kernel32.CloseHandle(snapshot)

    # Skip the Python processes (py.exe launcher, python.exe, a calling script) to reach whatever started them.
    pid = os.getpid()
    while pid in processes and processes[pid][1].startswith('py'):
        pid = processes[pid][0]
    return processes.get(pid, (0, ''))[1] == 'explorer.exe'


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Builds the release zip of the addon.')
    parser.add_argument('commit', nargs='?', help='commit to build from (default: the working directory)')
    parser.add_argument('-o', '--out', default=os.path.join(ROOT, 'dist'), help='output folder (default: dist)')
    args = parser.parse_args()

    exit_code = 0
    try:
        main(args.commit, args.out)
    except Exception as e:
        error = e.stderr.decode('utf-8', 'replace').strip() if isinstance(e, subprocess.CalledProcessError) else e
        print('Error: %s' % error, file=sys.stderr)
        exit_code = 1
    if started_from_explorer():
        input('Press Enter to close...')
    sys.exit(exit_code)
