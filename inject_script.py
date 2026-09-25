#!/usr/bin/env python3
"""Inject script content into nixos-test-vm.nix"""

import sys

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <script_file> <nix_file>")
        sys.exit(1)
    
    script_file = sys.argv[1]
    nix_file = sys.argv[2]
    
    with open(script_file, 'r') as f:
        content = f.read()
    
    # Escape for Nix string: escape backslashes, quotes, and newlines
    content = content.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    
    with open(nix_file, 'r') as f:
        nix_content = f.read()
    
    nix_content = nix_content.replace('SCRIPT_CONTENT_PLACEHOLDER', content)
    
    with open(nix_file, 'w') as f:
        f.write(nix_content)

if __name__ == '__main__':
    main()