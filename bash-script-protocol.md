BASH SCRIPT ENGINEERING PROTOCOL — v1.0

Canonical location: ~/icr/.config/zed/bash-script-protocol.mdLoaded by: the dispatcher in ~/.config/opencode/AGENTS.md (automatic), or the/bash-script command (explicit). When you load this file, announce:"Bash protocol loaded — starting Phase 1 research." Then begin Phase 1.

0. Scope, activation, precedence

Activates ONLY for shell-script tasks: creating or significantly refactoring anythingthat is/becomes a .sh file, starts with #!/bin/sh or #!/usr/bin/env bash, or isdescribed as a shell/bash script. If you were not directed here by such a request,stop and say so. If you cannot read this file in full, do NOT work from memory —ask the user to paste it.

    Precedence: this file > repo docs/bash-harness.md (if present) > repo AGENTS.md

        your defaults. If docs/bash-harness.md exists, read it before Phase 3 and treatit as the detailed spec.

    Priority order (never trade downward):correctness/robustness > debuggability/observability > readability > portability >performance. PERFORMANCE IS LAST: never remove a robustness or debugging featurefor speed. Extra processes, temp files, and verbose logging are always acceptable.
    "Always" means always: even a 10-line script gets the full workflow.

1. Mandatory four-phase workflow

Phase 1 RESEARCH → Phase 2 SELECTION CONTRACT → [USER GATE] → Phase 3 BUILD →Phase 4 VERIFY. Announce each transition explicitly (e.g. "→ Phase 2: Selection Contract").

You MUST NOT write final script code before the user has explicitly picked featuresfrom your Phase 1 list. In plan mode, execute Phases 1–2 only.If the user says "just write it", still present the Phase 1 list with a recommendedbaseline pre-marked, and ask ONCE for confirmation before building.

2. Phase 1 — Deep-dive research (ALWAYS, even for trivial requests)

Do all of the following before answering anything:

a. Restate the task
One line: inputs, outputs, side effects, invocation context.

b. CONSULT RESOURCES

Use web-search / doc-fetch tools when available; otherwise reason explicitly fromthese authorities and state what you could NOT verify (mark ⚠):

    POSIX (Issue 7/8) Shell Command Language
    Bash Reference Manual (if bash mode is a candidate)
    ShellCheck wiki (rule IDs, especially SC2xxx/SC3xxx)
    MAN PAGE OF EVERY EXTERNAL TOOL the script will call — actively hunt forsafety/atomicity/retry/checksum flags worth proposing (e.g. rsync --partial,gzip --rsyncable, cp --preserve, find -exec ... +)

c. REAL-WORLD MINING

Beyond official docs, mine existing shell scripts from public git — but ONLY qualityexemplars. GitHub's median script is actively harmful as a reference; the gates beloware mandatory, not advisory.

SOURCE TIERS — work top-down, prefer fewer/better:  T1  Curated idiom collections (highest signal, zero noise):      dylanaraps/pure-sh-bible · dylanaraps/bash-bible · Greg's Wiki (BashFAQ +      BashPitfalls) · ShellCheck wiki · Google shell styleguide  T2  Battle-tested public projects (wide deployment, real-world hardened):      acme.sh (pure sh) · nvm · k3s install.sh · rustup-init.sh · Docker      official-image entrypoints · pi-hole · asdf-vm · tj/n · bat-extras  T3  Distro/vendor scripts (portability + policy gold):      Debian maintainer scripts (sources.debian.org) · dracut/mkinitcpio ·      busybox scripts · OpenWrt · autoconf archive  T4  Raw search — LAST RESORT: GitHub search language:Shell stars:>500, then      inspect. Discard unless ALL of: recent commits · CI linting shell      (shellcheck/shfmt/bats visible) · dogfoods strict mode + traps + mktemp.

d. once research is completed cite source types checked and cite main sources selected for current script

QUALITY GATES — T2/T4 sources qualify with any 3; everything else is discarded:  deployed at scale | maintained 2+ yrs or org-owned (Docker/Debian/kernel.org) |  passes shellcheck -S style or uses deliberate directives | visible CI for shell |  dogfoods: strict mode, traps, mktemp, quoted expansions | in awesome-shell/awesome-bash

EXTRACT — mine patterns, NEVER code:

    robustness idioms: retry/backoff, flock, arg parsing, signal handling, atomic writes
    compatibility workarounds (dash/busybox/macOS-3.2) → WORKAROUND candidates withthe removal condition stated
    anti-patterns seen in the wild → negative ledger ("common failure mode"candidates, esp. BashPitfalls entries observed in real repos)
    feature ideas missing from the seed taxonomy → add as new candidates
    doc-vs-practice conflicts → report explicitly; DOCS WIN unless the user overrides

The 10 commandments (if you remember nothing else):

    Quote every expansion: "$var", "$(cmd)", "${arr[@]}".
    Start every script with set -Eeuo pipefail + an ERR trap.
    Run shellcheck in CI with zero warnings; format with shfmt.
    Use arrays for lists of anything — never space-joined strings.
    Never parse ls output. Use globs or find -print0.
    Temp files: only mktemp + trap cleanup. Atomic writes via temp+mv.
    -- before untrusted filenames; validate untrusted input with regexes.
    Never eval, sh -c, or build command strings dynamically — use arrays.
    printf, not echo; command -v, not which; know your GNUisms.
    Test on the oldest bash you claim to support (macOS ships 3.2).
 
 These tools catch 80% of bugs before runtime. Non-negotiable for anything committed to a repo.
 
 shellcheck -x script.sh          # static analysis (-x follows source directives)
bash -n script.sh                # syntax check only
shfmt -d -i 2 -ci script.sh      # formatting diff (2-space indent, indent case)

 Add # shellcheck shell=bash, # shellcheck disable=SC2086 # reason directives where needed — always with a reason.
 Wire both into CI and pre-commit hooks.
 Key ShellCheck codes to recognize on sight: SC2086 (unquoted var), SC2046 (unquoted command substitution → word splitting), SC2068 (unquoted $@), SC2115 (rm -rf "$var/" on empty var), SC2155 (declare masks return value), SC2015 (a && b || c is not if/else), SC2166 ([ a -a b ]), SC2044 (for over find output), SC2312 (command substitution masks exit status under set -e).   
 
 1. Interpreter & invocation

Shebang:

#!/usr/bin/env bash     # normal scripts: finds bash on PATH (allows Homebrew/newer bash)
#!/bin/bash             # privileged/root scripts: absolute path, so PATH can't control your interpreter
#!/bin/sh               # POSIX mode: only when you truly need max portability (see §14)

 #!/usr/bin/env bash is the default choice; for scripts running as root or in hardened contexts, hardcode /bin/bash so a manipulated PATH can't substitute a fake interpreter.
 The shebang kernel line takes exactly one argument. #!/usr/bin/env bash -eu does not work portably; #!/usr/bin/env -S bash -euo pipefail works on recent GNU coreutils (8.30+) and BSDs.
 Resolve your own location safely:
 
 readonly PROG=${0##*/}
readonly SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)

 Use ${BASH_SOURCE[0]} (not $0) — $0 breaks when the script is sourced.
 pwd -P resolves symlinks; add realpath/readlink -f only if you accept the portability cost (§14).
 
Version guard when you use newer features:

if (( BASH_VERSINFO[0] < 4 )); then
    printf '%s: requires bash >= 4.0 (found %s)\n' "$PROG" "$BASH_VERSION" >&2
    exit 1
fi

Library vs. script pattern (run main only when executed, not sourced):

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi

2. Strict mode & error handling
2.1 The header


#!/usr/bin/env bash
set -Eeuo pipefail


Flag
	
Meaning
	
Notes
-e (errexit)	Exit on any command failure	Unreliable alone — know the pitfalls below
-u (nounset)	Error on unset variables	Catches typos; use ${1:-} for optional args
-o pipefail	Pipeline fails if any component fails	Without it, only the last command's status counts
-E (errtrace)	ERR trap inherited by functions/subshells	Without it, your ERR trap silently doesn't fire in functions

Optional additions:

shopt -s inherit_errexit   # bash 4.4+: failures inside $( ) propagate with set -e
shopt -s nullglob          # empty glob expands to nothing instead of literal pattern (§7)

Do not globally set IFS=$'\n\t' (the "unofficial strict mode"). It changes behavior of $*, read, and any code expecting default splitting. Instead, scope IFS explicitly where needed (§7).

2.2 Where set -e does NOT trigger — memorize these

# 1. Commands in a condition context never trigger it:
if failing_cmd; then ...; fi            # failure just means "false"
failing_cmd && next                     # failure short-circuits, script continues
failing_cmd || fallback                 # expected

# 2. Negation:
! failing_cmd                           # script continues

# 3. Arithmetic that evaluates to 0 returns status 1:
count=0
((count++))                             # post-increment evaluates to 0 → status 1 → with set -e, script DIES
count=$((count + 1))                    # SAFE idiom
((count += 1))                          # evaluates to 1 → safe (but fragile; prefer $(( )))

# 4. `a && b || c` is NOT if/else:
failing_cmd && echo ok || echo fallback # runs fallback even when echo ok fails

# 5. `local`/`declare`/`export` mask the status of command substitution:
local x=$(failing_cmd)                  # SC2155: failure silently ignored
local x
x=$(failing_cmd)                        # correct: assignment propagates the failure

# 6. Pipelines: without pipefail only the last command matters (why we set pipefail).

Conclusion: set -e is a safety net, not a strategy. Check explicitly for anything you care about:

cd "$dir" || die "cannot cd into $dir"
if ! command -v jq >/dev/null 2>&1; then die "jq is required"; fi

2.3 ERR trap for diagnostics

trap 'printf "%s: FAILED: line %d: %s\n" "$PROG" "$LINENO" "$BASH_COMMAND"' ERR

$BASH_COMMAND shows the exact failing command. Works in functions/subshells only with set -E.

2.4 Exit codes

0	success
1	generic failure
2	usage error (convention — distinguish it)
126	found but not executable
127	command not found
128+N	killed by signal N (141 = SIGPIPE, 130 = SIGINT, 143 = SIGTERM)

die helper:

die() { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }

3. Quoting & expansion — the #1 bug source

3.1 The rules

Quote by default: "$var", "$(cmd)", "${arr[@]}". Unquoted expansions undergo word splitting and globbing.
"$@" is the one "always correct" form: each positional stays a separate word. "$*" joins into one string (separator = first char of IFS) — use only when you want joining. Never unquoted $@/$*/$var.
Quoting is unnecessary (and harmless) inside: assignments (x=$y), case words, arithmetic (( ))/$(( )), heredoc bodies, [[ ]] (mostly). Quoting there anyway is fine and ShellCheck-friendly.

# BAD
rm $file                 # "my file.txt" → two args: "my" and "file.txt"
cp $src $dst
for x in $list; do ...   # list was "a b c" or maybe "a*b c" — glob!

# GOOD
rm -- "$file"
cp -- "$src" "$dst"

3.2 Dangerous quoting contexts

# [[ ]] RHS: quoted = LITERAL string, unquoted = PATTERN
[[ $file == *.txt ]]        # glob match
[[ $file == "*.txt" ]]      # literal comparison against the 6 chars *.txt

# =~ : regex must be in a VARIABLE, unquoted
re='^[0-9]{1,5}$'
[[ $port =~ $re ]]          # correct
[[ $port =~ ^[0-9]+$ ]]     # also fine
[[ $port =~ "$re" ]]        # WRONG — quotes make it a literal string

# Building commands: use ARRAYS, never strings
# BAD:  cmd="grep $pattern $file"; bash -c "$cmd"   ← injection
args=(grep -e "$pattern" -- "$file")
"${args[@]}"

3.3 When you must produce a shell-quoted string

quoted=$(printf '%q ' "$@")   # safely shell-escapes each arg for later re-use

4. Variables, arrays, scoping, arithmetic

4.1 Parameter expansion toolkit

 ${var:-default}        # default if unset/empty
 ${var:=default}        # assign default (error-free required vars: use ${var:?} )
 ${var:?message}        # die if unset/empty — great guard: "${REQUIRED:?not set}"
 ${var:+alt}            # alt if set
 ${#var}                # length
 ${var#pat}  ${var##pat}   # strip shortest/longest prefix
 ${var%pat}  ${var%%pat}   # strip shortest/longest suffix
 ${var/a/b}  ${var//a/b}   # replace first/all (bash 4: also ${var/#x/y} anchored, ${var/%x/y})
 ${var^^}    ${var,,}      # upper/lowercase whole string (bash 4.0)
 ${var:2:5}             # substring
 ${var: -4}             # last 4 chars — NOTE THE SPACE (without it: parsing ambiguity)
 ${!var}                # indirection
 
 Filename surgery without forks (beats basename/dirname — but note they differ on edge cases like path/, path//, so use the real tools if inputs may be odd):
 
 file=${path##*/}       # basename
dir=${path%/*}         # dirname
base=${file%.*}        # name without extension
ext=${file##*.}        # extension

4.2 Naming and scoping

 Never name variables like env vars (PATH, HOME, PWD, USER, IFS, LD_LIBRARY_PATH, PS1…) unless you intend to modify the environment. A typo'd overwrite of PATH in a root script is an incident.
 Lowercase locals (verbose, out_file), UPPER for exported env / constants (readonly MAX_RETRIES=5).
 Always local inside functions — bash is dynamically scoped; without local you leak into callers (including their loops' read variables).
 readonly for constants; declare -g (bash 4.2) to declare a global from inside a function; declare -n namerefs (bash 4.3) for out-params (beware self-reference/collision footguns).
 
 4.3 Arrays — use them for anything plural
 
 files=(one.txt "two words.txt" three.txt)
files+=("four.txt")                       # append
files2=("${files[@]}")                    # copy
n=${#files[@]}                            # count
for f in "${files[@]}"; do ...; done      # iterate (ALWAYS quoted)
for i in "${!files[@]}"; do ...; done     # indices (arrays may be sparse)
last=${files[-1]}                         # bash 4.3+
slice=("${files[@]:1:2}")                 # slicing
declare -A m=([key1]=val1 [key2]=val2)    # associative: bash 4.0+
[[ ${m[$key]+x} ]]                        # membership test (portable, safe)
m["$key"]=value                           # quote keys with spaces
printf '%s\n' "${files[@]}"               # one per line
unset 'files[2]'                          # QUOTE the subscript

Gotcha: under set -u, expanding an empty array with "${arr[@]}" is an error on bash < 4.4. Workaround for old bash: "${arr[@]+${arr[@]}"}". Or require bash ≥ 4.4.

Security gotcha — arithmetic/array-index injection: the subscript of an indexed array is evaluated as arithmetic, and arithmetic evaluates $((...))/command substitutions. Untrusted data like x[$(rm -rf ~)] executes. Never let untrusted strings become array subscripts of indexed arrays or enter (( )) / $(( )) — validate first:

[[ $n =~ ^[0-9]+$ ]] || die "not a number: $n"
(( 10#$n ))          # 10# forces base 10 → "08" isn't treated as (invalid) octal

5. Tests & conditionals

5.1 [ vs [[

Feature
	
[ (POSIX)
	
[[ (bash/ksh/zsh)
Word splitting / globbing of operands	yes — must quote	no
&& || inside	no (use -a -o — don't; chain instead)	yes
< > string comparison	no (needs escaping)	yes
Pattern matching (== *.txt)	no	yes
Regex =~	no	yes
-v var (is set)	no	yes (bash 4.2)
  

Rule: use [[ ]] in bash; use [ (properly quoted) in /bin/sh scripts. Inside [, always quote and prefer = over ==:

[ "$a" = "$b" ] || exit 1
[ -f "$file" ] && [ -r "$file" ] || die "not readable: $file"

5.2 Comparison operators

# strings
[[ $a == "$b" ]]        # equality (quote RHS when literal)
[[ $a != $b ]]
[[ $a < $b ]]           # lexicographic

# numbers
(( a == b ))            # or: [ "$a" -eq "$b" ]
(( a < b ))             # -lt -le -gt -ge -ne in [ ]
(( 10#$n > 0 ))         # 10# guards against octal interpretation of "08"

5.3 File tests

-e exists, -f regular file, -d directory, -L symlink, -r readable, -w writable,
-x executable, -s size>0, -p fifo, -S socket, -t fd is a tty
[[ $a -nt $b ]]  newer-than;  -ot older;  -ef same device+inode (hardlink)

TOCTOU warning: [[ -e $f ]] && cmd "$f" races — the file can vanish between test and use. Where possible, act directly and handle failure (cmd "$f" || handle) instead of test-then-act.

5.4 case — underrated, safe, portable

case $arg in                      # no quoting needed on the word
    -h|--help) usage; exit 0 ;;
    *.tar.gz|*.tgz) extract ;;
    *) die "unknown argument: $arg" ;;
esac

6. Strings, printf, command substitution

6.1 printf, not echo

# BAD
echo "$data"           # -n/-e behavior varies; data starting with '-' becomes a flag
echo $data             # unquoted → splitting/globbing
printf "$data"         # INJECTION: %-specifiers in data consume your args / crash

# GOOD
printf '%s\n' "$data"
printf '%s=%s\n' "$key" "$value"
printf '%q\n' "$dangerous"          # shell-escaped output
printf -v result '%s/%s' "$a" "$b"  # build string WITHOUT a subshell fork (fast)

 Use fixed format strings only; variables go in arguments.
 printf '%s\n' "${arr[@]}" prints each element on its own line.
 
 6.2 Command substitution

     $(...), never backticks (nesting/escaping hell).
     Trailing newlines are stripped by $( ) — this is almost always what you want, but know it.
     Splitting output into words (foo $(cmd)) is a bug factory. Capture to an array:
     
     mapfile -t lines < <(some_command)      # bash 4.0+: output → array, one line per element
# or
while IFS= read -r line; do ...; done < <(some_command)

Under set -e, x=$(cmd) propagates failure; inside local/declare/export it does not (§2.2). With bash ≥ 4.4 + inherit_errexit, failures inside nested $( ) also propagate.

7. Iteration & file handling
7.1 Loop over files: globs, never ls

shopt -s nullglob          # unmatched glob → nothing (instead of literal '*.log')
shopt -s dotglob           # include dotfiles when needed
shopt -s globstar          # bash 4.0+: ** recurses

for f in "$dir"/*.conf; do
    [[ -e $f ]] || continue          # only needed WITHOUT nullglob
    process "$f"
done

for f in "$root"/**/*.log; do ...; done   # recursive with globstar

Never for f in $(ls ...) or ls | grep pipelines — it breaks on spaces/newlines, sorts wrong, and is unparseable by definition.

7.2 Reading lines

# The canonical idiom:
while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}          # tolerate CRLF input
    process "$line"
done < "$file"

 IFS= → don't trim leading/trailing whitespace.
 -r → don't interpret backslashes.
 || [[ -n $line ]] → process a final line lacking a trailing newline.
 
 IFS=, read -ra fields <<< "a,b,c"     # simple CSV only (no quoted commas); trailing empty field is dropped
 
 7.3 The pipeline-subshell trap
 
 # BAD: the while loop runs in a SUBSHELL → variables set inside are LOST
cat file | while read -r line; do count=$((count+1)); done
echo "$count"                          # empty!

# GOOD options:
while IFS= read -r line; do count=$((count+1)); done < file
while IFS= read -r line; do count=$((count+1)); done < <(produce_data)   # process substitution
shopt -s lastpipe; produce_data | while ...; done                       # bash 4.2+, no job control

Related trap: commands inside a while read loop consume stdin. while read h; do ssh "$h" cmd; done < hosts — ssh eats the rest of hosts. Fix: ssh -n or redirect cmd < /dev/null.

7.4 find / xargs

# Null-delimited always:
find . -type f -name '*.log' -print0 | xargs -0 -r gzip
find . -type f -name '*.tmp' -delete                      # avoids ARG_MAX on huge dirs
find . -type f -exec cp {} "$dest/" +                     # -exec + = batched (fast)
while IFS= read -r -d '' f; do ...; done < <(find . -type f -print0)

-print0/-0/-d '' handle every legal filename (spaces, newlines, quotes). -r (don't run on empty input) is GNU/busybox. -exec ... {} + and -execdir don't invoke a shell — safe with any filename.

8. Functions

# Return STATUS (0–255) — for success/failure:
is_root() { (( EUID == 0 )); }

# Return DATA via stdout — capture with $():
greeting() {
    printf 'hello, %s\n' "$1"
}
msg=$(greeting "$USER")

# Return DATA via out-param (no fork, can return strings with any content):
compute() {
    local -n out=$1      # nameref, bash 4.3+
    out="result value"
}
compute result_var

Rules:

     local everything; local -r for constants. Define constants before use.
     Split declaration and assignment when using command substitution (SC2155, §2.2).
     Don't shadow builtins/essential commands (test, read, cd…) with function names.
     A usage() function paired with getopts keeps CLI handling in one place.
     Wrap everything in main "$@" — enables sourcing for testing and gives locals a scope.
     
9. Redirection, file descriptors, here-docs

cmd >out 2>&1          # both to file — ORDER MATTERS
cmd 2>&1 >out          # WRONG-ish: stderr goes to old stdout (terminal), stdout to file
cmd &>out              # bash 4.0 shorthand for >out 2>&1
cmd 2>>err.log         # append stderr
cmd |& next            # bash 4.0: stdout+stderr into pipe (same as 2>&1 |)
cmd 3>&1 1>&2 2>&3     # swap stdout/stderr

Custom FDs (cleaner than juggling redirections):

exec 3< "$input"
read -u 3 line
exec 3<&-              # close when done

Logging through tee:

exec > >(tee -a "$logfile") 2>&1

Here-docs and here-strings:

cat <<'EOF'        # QUOTED delimiter → NO expansion inside (use for literal text/code)
  $HOME is literal
EOF

cat <<EOF          # unquoted → variables expand
user=$USER
EOF

grep "$pat" <<< "$string"     # herestring: string → stdin, no temp file, no echo pipe

<<- strips only tabs, not spaces. set -o noclobber prevents > from clobbering existing files (>| to force when intentional).

10. Temp files, cleanup, traps & signals
10.1 Temp files — mktemp only

# BAD — predictable name, symlink/race attacks, collisions:
tmp=/tmp/mytmp.$$;  echo x > "$tmp"

# GOOD
tmpdir=$(mktemp -d) || die "mktemp failed"      # dir: 0700, name unguessable
tmpfile=$(mktemp) || die "mktemp failed"        # file: 0600

10.2 Cleanup that actually runs

tmpdir=
cleanup() {
    if [[ -n ${tmpdir:-} ]]; then
        rm -rf -- "$tmpdir"          # -- guards leading-dash names
    fi
}
trap cleanup EXIT                   # runs on normal exit AND on fatal errors
tmpdir=$(mktemp -d) || die "mktemp failed"

Order matters: define cleanup, install the trap, then create the dir. The ${tmpdir:-} guard handles exits before assignment.

10.3 Signals

trap 'exit 130' INT                 # ensure EXIT trap fires on Ctrl-C
trap 'exit 143' TERM
trap 'exit 129' HUP
# exit codes 128+N follow the signal convention

To kill all background children on exit:

pids=()
worker ... & pids+=("$!")
trap 'kill "${pids[@]}" 2>/dev/null' EXIT

11. Security hardening
11.1 Injection

     Unquoted expansions → word splitting/globbing → argument injection (§3).
     eval, sh -c "$string", bash -c "$string", source-ing anything derived from data = arbitrary code execution. Build arrays and execute "${args[@]}".
     Computed command names are injection too: "$tool" args where $tool comes from config/input — validate against a whitelist (case $tool in grep|sed) ... esac).
     When a shell string is truly unavoidable, quote every component with printf '%q'.

11.2 Untrusted filenames & option injection

     Filenames can start with - and look like options. Always --:
     
rm -- "$file"
grep -e -- "$pattern" "$file"    # -e for patterns that look like flags
cp -- "$src" "$dst"

 Prefix glob-derived names with ./ when no -- exists: for f in ./*; do ....
 Validate everything crossing a trust boundary:
 
 [[ $port =~ ^[0-9]{1,5}$ ]] || die "invalid port"
[[ $name =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid name"

11.3 Privileged (root) scripts

PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH   # hardcoded, FIRST thing
umask 077                                          # private by default; opt-in openness
unset BASH_ENV ENV CDPATH GLOBIGNORE               # env vars that alter behavior (CDPATH breaks `cd`)
IFS=$' \t\n'                                       # defense in depth for odd shells

 Check (( EUID == 0 )), never whoami.
 Don't place root-run scripts in world-writable directories; don't source anything from them.
 sudo -n cmd in non-interactive contexts (fails fast instead of hanging on a password prompt).
 Drop privileges when you don't need them; run the least privileged logic as an unprivileged user.
 Exported functions (BASH_FUNC_...%%) were the Shellshock vector — modern bash sanitizes them, but for paranoid contexts run with env -i bash --noprofile --norc.
 
 11.4 Secrets

     Never on command lines (ps, /proc/*/cmdline, logs): use env vars, FDs, or --password-file/--passphrase-fd 0.
     set -x prints expanded commands — disable xtrace around anything touching secrets.
     Prompt safely: read -rsp 'Password: ' pw; printf '\n' >&2.
     Files with secrets: create via mktemp (0600) or install -m 600; umask 077 for the whole script.
     curl | bash executes unverified code over TLS-optional pipes. Download, verify checksum/signature, then run.

11.5 Races & filesystem attacks

     Prefer operating (open/mv/link) over test-then-act (§5.3 TOCTOU).
     Write to mktemp in the same directory, then mv (atomic on same filesystem).
     noclobber and mktemp's O_EXCL creation prevent classic clobber/symlink attacks.
     find -execdir avoids path races that plain -exec on ./ has.

11.6 Arithmetic injection

Covered in §4.3 — untrusted data must be regex-validated before it touches (( )), $(( )), indexed-array subscripts, or ${!var}.
12. Resiliency patterns
12.1 Pre-flight checks

need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
need jq
need rsync
[[ -r "$input" ]] || die "input not readable: $input"
[[ -d $out_dir ]] || mkdir -p -- "$out_dir" || die "cannot create $out_dir"

12.2 Singleton execution (flock)

readonly lockfile=/tmp/myprog.lock
exec 9>"$lockfile" || die "cannot open $lockfile"
flock -n 9 || die "another instance is already running"

The fd stays open for the process lifetime → the lock is released automatically even on crash. Caveat: flock is unreliable over NFS; there use an atomic mkdir lock with a stale-lock policy:

lockdir=/tmp/myprog.lock
if ! mkdir -- "$lockdir" 2>/dev/null; then die "already running"; fi
trap 'rmdir -- "$lockdir" 2>/dev/null' EXIT     

12.3 Retries with backoff

retry() {  # retry <max_tries> <base_delay_sec> command [args...]
    local tries=$1 delay=$2; shift 2
    local attempt=1
    while true; do
        if "$@"; then return 0; fi
        if (( attempt >= tries )); then return 1; fi
        log "attempt $attempt/$tries failed, retrying in $((delay * attempt))s"
        sleep "$((delay * attempt))"        # linear backoff; use 2**attempt or $RANDOM for jitter
        attempt=$((attempt + 1))
    done
}
retry 5 2 curl -fsSL --max-time 30 -o "$out" "$url"

(Note the if around the arithmetic — the (( )) && return shortcut would die under set -e, §2.2.)

12.4 Timeouts

timeout -k 10 60 rsync ...        # SIGTERM at 60s, SIGKILL 10s later (exit 124 on timeout)
read -t 5 -rsp 'Press a key: '   # read timeout
curl --max-time 30 --connect-timeout 5
(timeout is absent on stock macOS — see §14.)

12.5 Atomic & idempotent writes

# Atomic replace: write temp in SAME dir, then rename
tmp=$(mktemp -- "$dest.tmp.XXXXXX") || return 1
{ do_work > "$tmp"; } && mv -f -- "$tmp" "$dest" || { rm -f -- "$tmp"; return 1; }

# Idempotent operations: safe to re-run after partial failure
install -m 0644 -- "$src" "$dst"      # copies with exact perms
ln -sfn -- "$target" "$link"          # replace symlink atomically-ish
mkdir -p -- "$dir"

Design scripts to be re-runnable: skip existing outputs, use checkpoint/state files, make destructive steps explicit (--force).

12.6 Bounded parallelism

max=8
pids=()
for item in "${items[@]}"; do
    while (( $(jobs -rp | wc -l) >= max )); do
        wait -n || failures=$((failures + 1))     # wait -n: bash 4.3+; collect failures!
    done
    process "$item" &
    pids+=("$!")
done
status=0
for p in "${pids[@]}"; do wait "$p" || status=1; done
exit "$status"

12.7 SIGPIPE, empty input, huge input

 producer | consumer_that_exits_early → exit status 141 (SIGPIPE). With pipefail this is "expected" in some designs; handle deliberately (... || (( $? == 141 ))) rather than blanket-suppressing.
 Empty input: xargs -r, [[ ${#arr[@]} -gt 0 ]], [[ -s $file ]] (non-empty file).
 Huge input: stream (while read), don't mapfile megabytes into memory; use find -delete/-exec + instead of expanding millions of globs (rm ./* → "argument list too long").
 
 13. CLI interface & UX
13.1 Option parsing with getopts (POSIX, safe)

verbose=0 outfile=
usage() {
    cat <<EOF
Usage: $PROG [-v] [-o FILE] FILE...
  -v        verbose
  -o FILE   output file
  -h        this help
EOF
}
while getopts ":hvo:" opt; do
    case $opt in
        v) verbose=1 ;;
        o) outfile=$OPTARG ;;
        h) usage; exit 0 ;;
        :) die "option -$OPTARG requires an argument" ;;
        *) die "unknown option: -$OPTARG" ;;
    esac
done
shift $((OPTIND - 1))
(( $# > 0 )) || { usage >&2; exit 2; }

For long options, pre-scan --name/--name=value with case, or use GNU getopt (util-linux) — but prefer getopts for safety.

13.2 UX rules

     Everything user-facing goes to stderr (log, warn, die); data on stdout only.
     Fail fast with actionable messages; validate all args before doing work.
     Support -h/--help; exit 2 for usage errors.
     Don't prompt in non-interactive contexts: check [[ -t 0 ]] and support -y/--force.
     Offer --dry-run:
     
     run() {
    if (( dry_run )); then
        printf 'dry-run:'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}
14. Compatibility
14.1 Bash version feature matrix
Feature
	
Min bash
+= append, <<< herestrings	3.1 / 2.05b
Associative arrays, globstar (**), &>, |&, ${var^^}, coproc	4.0
mapfile/readarray	4.0
declare -g, lastpipe, [[ -v ]], negative substring offset ${s: -2}	4.2
Namerefs (declare -n), wait -n, negative array index arr[-1]	4.3
inherit_errexit, ${var@Q}, empty-array OK under set -u, mapfile -d	4.4
EPOCHSECONDS, EPOCHREALTIME	5.0
  

macOS ships bash 3.2 (GPLv3 avoidance). Decide deliberately: target 3.2-compatible syntax, or use #!/usr/bin/env bash with Homebrew bash, or guard with a version check. Docker test matrix: docker run --rm -v "$PWD:/s" -w /s bash:4.4 ./script.sh etc.
14.2 If you must run under /bin/sh (POSIX)

You lose: [[ ]], arrays, local (technically), (( )) as a command, ${var//}, ${var^^}, $'...', process substitution, mapfile, function keyword, pipefail. Test with dash script.sh; add # shellcheck shell=sh. Honestly: if the script is nontrivial, require bash.
14.3 Common non-portable tool flags
GNU flag Problem Portable-ish alternative
sed -i	BSD needs -i ''	temp file + mv, or per-OS branch
grep -P	GNU/PCRE only	grep -E, or awk, or ship rg/pcre2grep
xargs -r	GNU/busybox only	guard empty input in shell
readlink -f / realpath	GNU	parameter expansion, or cd ... && pwd -P
stat -c	GNU (BSD: -f)	avoid stat; use -nt/-ot, wc -c <
date -d	GNU (BSD: -j -f)	date +%s arithmetic
seq	not POSIX	for ((i=1;i<=n;i++))
sort -V / -h	GNU	pad/prefix keys, sort -n
timeout	GNU coreutils	read -t tricks, or require coreutils
sha256sum	GNU (macOS: shasum -a 256)	feature-detect
  
14.4 Locale & text

     For byte-stable behavior (sort order, regex ranges, decimal points): export LC_ALL=C. Trade-off: breaks UTF-8 collation/case for user-facing text. Set it for machine-facing sections; leave UTF-8 for display.
     CRLF input: strip with line=${line%$'\r'} (§7.2).

15. Performance

Bash is slow when you fork. Measure first (time, hyperfine), then:

     Prefer builtins/parameter expansion over external tools — especially inside loops:
     
     # BAD: one fork per iteration
for f in *.txt; do base=$(basename "$f"); done
# GOOD: zero forks
for f in *.txt; do base=${f##*/}; done

 Build strings with printf -v var '...' instead of var=$(...) (§6.1).
 One awk pass beats ten grep/cut forks; grep -f patterns.txt beats a loop of greps.
 Glob instead of find when depth allows; find -exec + (batched) instead of \; (one fork per file).
 LC_ALL=C measurably speeds up sort/grep on ASCII.
 Parallelize with bounded jobs (§12.6) or xargs -0 -P "$(nproc)".
 Don't micro-optimize cold paths (one-shot setup scripts) at the cost of clarity.
 
16. Debugging & testing

 bash -n script.sh                 # syntax check
bash -x script.sh                 # trace every command
PS4='+ ${BASH_SOURCE##*/}:$LINENO: ' bash -x script.sh    # trace with locations
set -v                            # print lines as read
declare -p var arr                # inspect variables/arrays precisely (better than echo debugging)

 With set -E + the ERR trap from §2.3, failures self-report line and command.
 BASH_XTRACEFD=3 exec 3>trace.log separates xtrace noise from stderr.
 Unit-test with bats-core; smoke-test with --dry-run; CI runs shellcheck, shfmt -d, bash -n, and the test suite on the oldest supported bash (docker matrix).
 
 17. Annotated template
 
 #!/usr/bin/env bash
#
# prog-name — one-line description.
# Usage: prog-name [options] FILE...

set -Eeuo pipefail

readonly PROG=${0##*/}
readonly VERSION='1.0.0'

# ---------- logging ----------
log()  { printf '%s: %s\n' "$PROG" "$*" >&2; }
warn() { printf '%s: warning: %s\n' "$PROG" "$*" >&2; }
die()  { printf '%s: error: %s\n' "$PROG" "$*" >&2; exit 1; }

trap 'log "FAILED: line $LINENO: $BASH_COMMAND"' ERR

# ---------- preflight ----------
if (( BASH_VERSINFO[0] < 4 )); then die "requires bash >= 4.0"; fi
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }
# need jq

# ---------- cleanup ----------
tmpdir=
cleanup() {
    if [[ -n ${tmpdir:-} ]]; then
        rm -rf -- "$tmpdir"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tmpdir=$(mktemp -d) || die "mktemp failed"

# ---------- cli ----------
usage() {
    cat <<EOF
Usage: $PROG [options] FILE...
  -v        verbose
  -o FILE   output file (default: stdout)
  -n        dry run
  -h        show this help
EOF
}

main() {
    local verbose=0 outfile=- dry_run=0
    while getopts ":hvo:n" opt; do
        case $opt in
            v) verbose=1 ;;
            o) outfile=$OPTARG ;;
            n) dry_run=1 ;;
            h) usage; exit 0 ;;
            :) die "option -$OPTARG requires an argument" ;;
            *) usage >&2; exit 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    (( $# >= 1 )) || { usage >&2; exit 2; }

    local f
    for f in "$@"; do
        [[ -r $f ]] || die "not readable: $f"
        # ... real work, using "$tmpdir" for scratch ...
    done
}

main "$@"

8. Master checklist

Correctness

     set -Eeuo pipefail; every failure either handled or fatal
     All expansions quoted; arrays for lists; "$@" always quoted
     No local x=$(...); no a && b || c as if/else; no ((count++))-style status traps
     while IFS= read -r for lines; read -d ''/-print0 for filenames; no parsing ls
     Loops over globs handle empty matches (nullglob or [[ -e ]] guard)

Security

     No eval/sh -c/source on dynamic strings; command arrays + printf '%q'
     -- before untrusted filenames; input validated by regex
     mktemp only; cleanup trap; atomic mv writes; sensible umask
     Untrusted data never reaches arithmetic/indexed-subscript contexts
     Privileged scripts: hardcoded PATH, absolute interpreter, unset CDPATH etc., secrets never on argv or in xtrace logs

Resiliency

     Dependency pre-flight (command -v); version guard if needed
     flock singleton where re-entry is dangerous
     Retries + timeouts on anything network/remote; bounded parallelism with failure collection
     Idempotent/re-runnable design; SIGPIPE and empty-input edge cases considered

Compatibility

     Target bash version decided and documented; tested on it (macOS 3.2!)
     GNUisms identified (or POSIX mode + dash-tested); locale strategy explicit

Process

     shellcheck + shfmt + bash -n in CI, zero warnings
     usage(), stderr diagnostics, exit code 2 for usage errors, -h/--help, --dry-run
     bats/smoke tests on the oldest supported interpreter




 
 

