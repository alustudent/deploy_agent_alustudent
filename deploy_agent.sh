#!/usr/bin/env bash
# Deploys, runs and archives the Student Attendance Tracker.
# Usage: ./deploy_agent.sh [deploy | run <name> | archive <name>]   (no argument shows a menu)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPLATES_DIR="$SCRIPT_DIR/templates"
APP=attendance_checker.py
MAX_ATTEMPTS=3
OPTION_B_MAX=100

# Option B roster names. Emails get a numeric suffix once the list wraps, so they stay unique.
SAMPLE_STUDENTS=(
	"Amara Okafor" "Kwame Asante" "Lina Haddad" "Mateo Silva" "Nia Mwangi"
	"Omar Farouk" "Priya Nair" "Ravi Patel" "Sofia Rossi" "Tariq Bello"
)

PROJECT_DIR=""
# Set only once this run creates PROJECT_DIR, so cleanup never touches a directory it didn't make
CREATED_DIR=""
ANSWER=""

info() { printf '[deploy_agent] %s\n' "$*"; }
warn() { printf '[deploy_agent] %s\n' "$*" >&2; }

remove_partial_project() {
	[ -n "$CREATED_DIR" ] && [ -d "$CREATED_DIR" ] || return 0
	# DANGEROUS DANGEROUS DANGEROUS IF YOU CHANGE THIS THEN A FINISHED OR USER-OWNED DIRECTORY CAN BE DELETED
	rm -rf -- "$CREATED_DIR"
	warn "Removed the incomplete $(basename "$CREATED_DIR")/"
	CREATED_DIR=""
}

fail() {
	warn "ERROR: $*"
	remove_partial_project
	exit 1
}

# ask PROMPT VALIDATOR [ARGS...]: stores the answer in ANSWER, giving up after MAX_ATTEMPTS invalid ones.
# VALIDATOR is called as VALIDATOR ANSWER ARGS... and prints why it rejected an answer.
ask() {
	local prompt=$1 validator=$2 answer attempt left
	shift 2
	for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
		answer=""
		read -r -p "$prompt" answer || [ -n "$answer" ] || fail "No input received."
		if "$validator" "$answer" "$@"; then
			ANSWER=$answer
			return 0
		fi
		left=$((MAX_ATTEMPTS - attempt))
		[ "$left" -gt 0 ] && warn "$left attempt(s) left."
	done
	fail "Too many invalid answers ($MAX_ATTEMPTS)."
}

# valid_int VALUE MIN MAX
valid_int() {
	if [[ $1 =~ ^[0-9]{1,6}$ ]] && ((10#$1 >= $2 && 10#$1 <= $3)); then return 0; fi
	warn "Enter a whole number from $2 to $3."
	return 1
}

valid_name() {
	[[ $1 =~ ^[A-Za-z0-9_-]+$ ]] && return 0
	warn "Use letters, digits, '-' or '_' only."
	return 1
}

# Empty means no
valid_yes_no() {
	[[ ${1,,} =~ ^(y|yes|n|no)?$ ]] && return 0
	warn "Answer y or n."
	return 1
}

is_yes() { [[ ${1,,} =~ ^y(es)?$ ]]; }

valid_roster_option() {
	[[ ${1^^} =~ ^[AB]$ ]] && return 0
	warn "Choose A or B."
	return 1
}

# valid_threshold VALUE CURRENT MIN MAX: empty keeps CURRENT
valid_threshold() { valid_int "${1:-$2}" "$3" "$4"; }

config_number() { grep -oE "\"$2\": *[0-9]+" "$1" | grep -oE '[0-9]+$'; }

# Replaces only the number after "KEY":, keeping the key, spacing and key order
set_config_number() { sed -i -E "s/(\"$2\": *)[0-9]+/\\1$3/" "$1"; }

preflight() {
	info "Running pre-flight checks..."
	local tool file missing=0
	for tool in python3 zip; do
		if ! command -v "$tool" > /dev/null; then
			warn "ERROR: $tool is not installed. Install it (Ubuntu: sudo apt install $tool) and try again."
			missing=1
		fi
	done
	[ "$missing" -eq 0 ] || exit 1
	info "Found $(python3 --version 2>&1)"
	for file in "$APP" config.json assets.csv; do
		[ -f "$TEMPLATES_DIR/$file" ] || fail "Missing template: templates/$file"
	done
}

ask_project_name() {
	ask "Project name (creates attendance_tracker_<name>): " valid_name
	PROJECT_DIR="$SCRIPT_DIR/attendance_tracker_$ANSWER"
	[ -e "$PROJECT_DIR" ] || return 0
	ask "$(basename "$PROJECT_DIR")/ already exists. Overwrite it? [y/N]: " valid_yes_no
	if ! is_yes "$ANSWER"; then
		info "Aborted. $(basename "$PROJECT_DIR")/ was left untouched."
		exit 1
	fi
	# DANGEROUS DANGEROUS DANGEROUS IF YOU CHANGE THIS THEN AN UNCONFIRMED OR UNRELATED DIRECTORY CAN BE DELETED
	rm -rf -- "$PROJECT_DIR" || fail "Could not remove the existing $(basename "$PROJECT_DIR")/"
	info "Removed the existing $(basename "$PROJECT_DIR")/"
}

build_structure() {
	CREATED_DIR=$PROJECT_DIR
	mkdir -p "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports" &&
		cp "$TEMPLATES_DIR/$APP" "$PROJECT_DIR/" &&
		cp "$TEMPLATES_DIR/config.json" "$PROJECT_DIR/Helpers/" ||
		fail "Could not build the project structure."
	info "Created $(basename "$PROJECT_DIR")/ with Helpers/ and reports/"
}

roster_from_template() {
	local available
	available=$(awk 'NR > 1 && NF' "$TEMPLATES_DIR/assets.csv" | wc -l)
	ask "How many students to copy (1-$available)? " valid_int 1 "$available"
	# awk 1 adds the newline the template's last line lacks
	head -n $((10#$ANSWER + 1)) "$TEMPLATES_DIR/assets.csv" | awk 1 > "$PROJECT_DIR/Helpers/assets.csv" ||
		fail "Could not write Helpers/assets.csv"
	info "Copied the header and the first $((10#$ANSWER)) students into Helpers/assets.csv"
}

roster_generated() {
	local count i name first last suffix
	local samples=${#SAMPLE_STUDENTS[@]}
	ask "How many students to generate (1-$OPTION_B_MAX)? " valid_int 1 "$OPTION_B_MAX"
	count=$((10#$ANSWER))
	{
		head -n 1 "$TEMPLATES_DIR/assets.csv"
		for ((i = 0; i < count; i++)); do
			name=${SAMPLE_STUDENTS[i % samples]}
			first=${name%% *}
			last=${name##* }
			suffix=""
			((i >= samples)) && suffix=$((i / samples + 1))
			echo "${first,,}.${last,,}$suffix@example.com,$name,0,0"
		done
	} > "$PROJECT_DIR/Helpers/assets.csv" || fail "Could not write Helpers/assets.csv"
	# A fresh roster has no prior sessions, so today is session 1
	set_config_number "$PROJECT_DIR/Helpers/config.json" total_sessions 1 || fail "Could not update total_sessions."
	info "Generated $count students in Helpers/assets.csv and set total_sessions to 1"
}

build_roster() {
	ask "Roster: [A] copy students from the template, [B] generate a fresh roster: " valid_roster_option
	if [ "${ANSWER^^}" = A ]; then roster_from_template; else roster_generated; fi
}

set_permissions() {
	chmod +x "$PROJECT_DIR/$APP" && chmod 600 "$PROJECT_DIR/Helpers/config.json" ||
		fail "Could not set permissions."
	info "Permissions set:"
	(cd "$PROJECT_DIR" && ls -l "$APP" Helpers/config.json) | sed 's/^/  /'
}

update_thresholds() {
	local config="$PROJECT_DIR/Helpers/config.json" warning failure
	ask "Update the attendance thresholds? [y/N]: " valid_yes_no
	if ! is_yes "$ANSWER"; then
		info "Keeping the default thresholds."
		return 0
	fi
	warning=$(config_number "$config" warning)
	failure=$(config_number "$config" failure)
	ask "Warning threshold % (1-100, Enter keeps $warning): " valid_threshold "$warning" 1 100
	warning=$((10#${ANSWER:-$warning}))
	ask "Failure threshold % (0-$((warning - 1)), Enter keeps $failure): " valid_threshold "$failure" 0 $((warning - 1))
	failure=$((10#${ANSWER:-$failure}))
	set_config_number "$config" warning "$warning" &&
		set_config_number "$config" failure "$failure" &&
		python3 -m json.tool "$config" > /dev/null ||
		fail "Could not update the thresholds in Helpers/config.json"
	info "Thresholds set: warning=$warning, failure=$failure"
}

# Zips whatever exists of the project, removes the incomplete directory and exits non-zero
on_interrupt() {
	local signal=$1 code=$2 parent base
	trap - INT TSTP
	echo >&2
	warn "Deployment interrupted by SIG$signal."
	if [ -z "$CREATED_DIR" ] || [ ! -d "$CREATED_DIR" ]; then
		warn "No project directory was created yet, so there is nothing to archive."
		exit "$code"
	fi
	parent=$(dirname "$CREATED_DIR")
	base=$(basename "$CREATED_DIR")
	cd "$parent" || exit "$code"
	if [ -e "${base}_archive.zip" ]; then
		warn "Replacing the previous ${base}_archive.zip"
		rm -f -- "${base}_archive.zip"
	fi
	if ! zip -rq "${base}_archive.zip" "$base"; then
		warn "ERROR: Could not zip $base/, so it was left in place."
		exit "$code"
	fi
	# DANGEROUS DANGEROUS DANGEROUS IF YOU CHANGE THIS THEN A FINISHED OR USER-OWNED DIRECTORY CAN BE DELETED
	rm -rf -- "$base"
	warn "Archived the partial project to $parent/${base}_archive.zip and removed $base/"
	exit "$code"
}

run_app() {
	info "Starting the attendance session in $(basename "$1")/"
	(cd "$1" && python3 "$APP")
}

valid_existing_project() {
	valid_name "$1" || return 1
	[ -d "$SCRIPT_DIR/attendance_tracker_$1" ] && return 0
	warn "No project attendance_tracker_$1/ next to $(basename "$0"). Deploy it first."
	return 1
}

# resolve_project [NAME]: sets PROJECT_DIR from NAME, or asks for it when NAME is empty
resolve_project() {
	if [ -z "$1" ]; then
		ask "Project name (attendance_tracker_<name>): " valid_existing_project
	else
		valid_existing_project "$1" || exit 1
		ANSWER=$1
	fi
	PROJECT_DIR="$SCRIPT_DIR/attendance_tracker_$ANSWER"
}

run_project() {
	resolve_project "$1"
	run_app "$PROJECT_DIR"
}

# Moves each existing log to archives/<log>/<log>_<timestamp>.log; a missing log is skipped
archive_logs() {
	resolve_project "$1"
	local timestamp log source target archived=0
	timestamp=$(date +%Y%m%d_%H%M%S)
	for log in attendance absent; do
		source="$PROJECT_DIR/reports/$log.log"
		if [ ! -f "$source" ]; then
			info "No reports/$log.log found, skipping it."
			continue
		fi
		target="$PROJECT_DIR/archives/$log/${log}_$timestamp.log"
		[ -e "$target" ] && fail "$target already exists. Wait a second and archive again."
		mkdir -p "$PROJECT_DIR/archives/$log" && mv "$source" "$target" ||
			fail "Could not archive reports/$log.log"
		info "Archived reports/$log.log to $target"
		archived=$((archived + 1))
	done
	[ "$archived" -gt 0 ] || info "No logs to archive. Run a session first."
}

deploy() {
	preflight
	# The trap covers deployment only, never the marking session
	trap 'on_interrupt INT 130' INT
	trap 'on_interrupt TSTP 148' TSTP
	ask_project_name
	build_structure
	build_roster
	set_permissions
	update_thresholds
	# From here the project is complete, so neither the trap nor a failure may delete it
	trap - INT TSTP
	CREATED_DIR=""
	info "Deployed $(basename "$PROJECT_DIR")/. Verifying by running the app."
	run_app "$PROJECT_DIR"
}

usage() {
	cat <<-EOF
		Usage: $(basename "$0") [command]

		Commands:
		  deploy            build a new attendance_tracker_<name>/ project and run it
		  run [name]        run the marking session of an existing project
		  archive [name]    move the project's logs into archives/ with a timestamp
		  -h                show this help

		With no command, a menu is shown. Without a name, run and archive ask for it.
	EOF
}

valid_menu_choice() {
	[[ $1 =~ ^[123q]$ ]] && return 0
	warn "Choose 1, 2, 3 or q."
	return 1
}

menu() {
	echo "Student Attendance Tracker - deploy agent"
	echo "  1) Deploy a new project"
	echo "  2) Run an attendance session"
	echo "  3) Archive logs"
	echo "  q) Quit"
	ask "Choose an option: " valid_menu_choice
	case $ANSWER in
		1) deploy ;;
		2) run_project "" ;;
		3) archive_logs "" ;;
		q) exit 0 ;;
	esac
}

main() {
	case ${1:-} in
		"") menu ;;
		deploy) deploy ;;
		run) run_project "${2:-}" ;;
		archive) archive_logs "${2:-}" ;;
		-h | --help) usage ;;
		*)
			usage >&2
			exit 2
			;;
	esac
}

main "$@"
