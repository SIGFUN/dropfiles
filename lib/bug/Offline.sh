#!/bin/bash -O extglob

# MARK: Module preamble
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
	echo "library modules cannot be executed directly" >&2
	exit 1
fi

if [ -z "$libdir" ]; then
	echo "library modules must be initialized by sourcer" >&2
	exit 1
fi

# MARK: Imports
# Note that we can only safely import modules that don't have any state. See the
# comment in Offline.init.
. "${libdir}/Lib.sh"
. "${libdir}/Module.sh"

assert_available CLI
assert_available Git
assert_available Plist

# MARK: Module State
OFFLINE_PROJECT=
OFFLINE_NUMBER=
OFFLINE_STATE_GUESS=
OFFLINE_BRANCH_GUESS=
OFFLINE_QUERY_FIELDS=()

# MARK: Internal
function Offline._guess_state()
{
	local branch_name=$(Git.get_current_branch)
	local wip_space="$(Git.run config fix.wip.namespace)"
	local pr_space="$(Git.run config fix.pr.namespace)"

	# We need the repository to provide some clue about branch conventions in
	# order to guess anything.
	if [ -z "$wip_space" ]; then
		return
	fi

	if [ -z "$pr_space" ]; then
		return
	fi

	case "$branch_name" in
	${wip_space}/*)
		echo "active"
		;;
	${pr_space}/*)
		echo "review"
		;;
	*)
		# If the current branch does not correspond to any known convention,
		# then we assume that work is not currently in progress.
		echo "scheduled"
		;;
	esac
}

function Offline._guess_branch()
{
	local pattern=
	local candidates=()
	local wip_space="$(Git.run config fix.wip.namespace)"
	local pr_space="$(Git.run config fix.pr.namespace)"
	local hints=()
	local branch=

	# We need the repository to provide some clue about branch conventions in
	# order to guess anything.
	if [ -z "$wip_space" ]; then
		return
	fi

	if [ -z "$pr_space" ]; then
		return
	fi

	hints=("$pr_space" "$wip_space")
	pattern+='*'
	pattern+="$OFFLINE_NUMBER"
	pattern+='*'

	candidates=($(Git.run branch --format='%(refname:short)' -l "$pattern"))
	for h in "${hints[@]}"; do
		for c in "${candidates[@]}"; do
			if [[ "$c" =~ ^${h}/ ]]; then
				echo "$c"
				return
			fi
		done
	done
}

# MARK: Public
function Offline.init()
{
	local p="$1"
	local username="$3"
	local secret="$4"

	OFFLINE_PROJECT="$p"
	OFFLINE_STATE_GUESS=$(Offline._guess_state)
	OFFLINE_BRANCH_GUESS=$(Offline._guess_branch)

	Module.config 0 "offline bug tracker"
	Module.config 1 "project" "$OFFLINE_PROJECT"
	Module.config 1 "state guess" "$OFFLINE_STATE_GUESS"
	Module.config 1 "branch guess" "$OFFLINE_BRANCH_GUESS"
	Module.config 1 "username" "$username"
	Module.config 1 "secrets store" "$secrets"
}

function Offline.init_problem()
{
	local n="$1"

	OFFLINE_NUMBER="$n"

	Module.config 0 "offline bug tracker [number]"
	Module.config 1 "number" "$OFFLINE_NUMBER"
}

function Offline.query_tracker_property()
{
	return
}

function Offline.add_comment()
{
	return
}

function Offline.update_field()
{
	local f="$1"
	local v="$2"
	local t="$3"
	local ft=

	return
}

function Offline.query_field()
{
	local f="$1"

	case "$f" in
	Title|Component)
		;;
	State)
		CLI.die_ifz "$OFFLINE_STATE_GUESS" "failed to guess bug state"
		;;
	Branch)
		CLI.die_ifz "$OFFLINE_BRANCH_GUESS" "failed to guess branch"
		;;
	esac

	OFFLINE_QUERY_FIELDS+=("$f")
}

function Offline.update()
{
	return
}

function Offline.query()
{
	local r='{}'

	Plist.init_with_raw "json" "$r"
	for f in "${OFFLINE_QUERY_FIELDS[@]}"; do
		local v=

		case "$f" in
		State)
			v="$OFFLINE_STATE_GUESS"
			;;
		Branch)
			v="$OFFLINE_BRANCH_GUESS"
			;;
		Component|Title)
			v=""
			;;
		*)
			CLI.die "unsupported field: $f"
		esac

		Plist.set_value "$f" "string" "$v"
	done

	Plist.get "json"
}
