"""Builds the release zip from the last commit (HEAD), leaving out uncommitted changes.

Calls make_release.py with HEAD; extra arguments (such as -o <folder>) are passed on.

Usage: python tools/make_release_head.py [-o output folder, default: dist]
"""
import os
import subprocess
import sys

script = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'make_release.py')
sys.exit(subprocess.call([sys.executable, script, 'HEAD', *sys.argv[1:]]))
