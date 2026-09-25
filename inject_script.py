#!/usr/bin/env python3
"""Inject script content into nixos-test-vm.nix for writeTextFile"""

import sys

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <script_file> <nix_file>")
        sys.exit(1)
    
    script_file = sys.argv[1]
    nix_file = sys.argv[2]
    
    with open(script_file, 'r') as f:
        content = f.read()
    
    # For writeTextFile, no escaping needed - raw content is written as-is
    # Just ensure no NUL bytes
    content = content.replace('\x00', '')
    
    with open(nix_file, 'r') as f:
        nix_content = f.read()
    
    nix_content = nix_content.replace('SCRIPT_CONTENT_PLACEHOLDER', content)
    
    with open(nix_file, 'w') as f:
        f.write(nix_content)

if __name__ == '__main__':
    main()