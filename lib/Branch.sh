#!/bin/bash -O extglob

# Module preamble
if [[ "${BASH_SOURCE[0]}" = "${0}" ]]; then
	echo "library modules cannot be executed directly" >&2
	exit 1
fi

if [ -z "$libdir" ]; then
	echo "library modules must be initialized by sourcer" >&2
	exit 1
fi

# Imports
. "${libdir}/Lib.sh"
. "${libdir}/Module.sh"
. "${libdir}/CLI.sh"
. "${libdir}/Git.sh"

# MARK: Object Fields
F_BRANCH_BUG=
F_BRANCH_NAMESPACE=
F_BRANCH_BUG_NUMBER_PREFIX=
F_BRANCH_COMPONENT=
F_BRANCH_TITLE=
F_BRANCH_WORD_CAP=5
F_BRANCH_BASE=
F_BRANCH_USERNAME=

# MARK: Internal
function Branch._derive_title_fragment()
{
	local n="$F_BRANCH_WORD_CAP"
	local title=
	local i=
	local fragment=
	local words=
	local delim=""

	# Remove shell-inconvenient characters. Spaces will be replaced with a '-',
	# so below we set the delimiter to '-'.
	title=$(toshellsafe "$F_BRANCH_TITLE")

	IFS='-' read -ra words <<< "$title"
	if [ ${#words[@]} -lt $n ]; then
		n=${#words[@]}
	fi

	for (( i = 0; i < $n; i++ )); do
		local w=${words[$i]}

		fragment+="${delim}$(tolower "$w")"
		delim="-"
	done

	echo "$fragment"
}

function Branch._derive_component_fragment()
{
	local comp=

	# Collapse the component into a single, all-caps word.
	comp=$(toshellsafe "$F_BRANCH_COMPONENT")
	comp=$(tr -d '-' <<< "$comp")
	comp=$(toupper "$comp")

	# Allow for up to 9 characters in the component.
	echo "${comp:0:9}"
}

function Branch._derive_name()
{
	local ns_prefix=
	local bug_prefix="$F_BRANCH_BUG_NUMBER_PREFIX"
	local username="$F_BRANCH_USERNAME"
	local problem="$F_BRANCH_BUG"
	local title=
	local component=
	local trailer=

	if [ -n "$F_BRANCH_TITLE" ]; then
		title=$(Branch._derive_title_fragment)
		trailer="-$title"
	fi

	if [ -n "$F_BRANCH_COMPONENT" ]; then
		component=$(Branch._derive_component_fragment)
		trailer="-${component}${trailer}"
	fi

	case "$F_BRANCH_NAMESPACE" in
	wip)
		ns_prefix="$(Git.run config fix.wip.namespace)/"
		branch_name="${ns_prefix}${username}/${bug_prefix}${problem}${trailer}"
		;;
	pr)
		ns_prefix="$(Git.run config fix.pr.namespace)/"
		username=$(toupper "$username")
		branch_name="${ns_prefix}${bug_prefix}${problem}-${username}${trailer}"
		;;
	esac

	echo "$branch_name"
}

# MARK: Meta
function Branch.available()
{
	return 0
}

function Branch.has_title()
{
	local branch_name=$(Git.get_current_branch)
	local username="$(toupper "$F_BRANCH_USERNAME")"
	local regex=$(Git.run config fix.bug.regex)

	if [[ "$branch_name" =~ ${regex}-${username}-[A-Z]+- ]]; then
		# PR branch that includes a component.
		return 0
	fi

	if [[ "$branch_name" =~ ${regex}-${username}- ]]; then
		# PR branch that does not include a component.
		return 0
	fi

	if [[ "$branch_name" =~ ${regex}-[A-Z]+- ]]; then
		# WIP branch that includes a component.
		return 0
	fi

	if [[ "$branch_name" =~ ${regex}- ]]; then
		# WIP branch that does not include a component.
		return 0
	fi

	return 1
}

function Branch.get_namespace()
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
		echo "wip"
		;;
	${pr_space}/*)
		echo "pr"
		;;
	esac
}

function Branch.find_problems()
{
	local parent=
	local p=$(Git.run config fix.bug.trailer)

	parent=$(Git.get_branch_base)

	# If a single commit has multiple problem trailer properties, they'll be
	# displayed on a single line, separated by a ','. So we have to tease that
	# apart.
	Git.run log --pretty=format:"%(trailers:key=$p,valueonly,separator=%x2C)" \
			${parent}..HEAD | tr ',' '\n' | sort | uniq
}

function Branch.guess_primary_problem()
{
	local problems=()
	local branch_name=$(Git.get_current_branch)
	local regex=$(Git.run config fix.bug.regex)

	problems=($(Branch.find_problems))
	case "${#problems[@]}" in
	0)
		local bug=

		bug=$(grep -oE "$regex" <<< "$branch_name")
		if [ -n "$bug" ]; then
			echo "$bug"
		fi
		;;
	1)
		echo "${problems[0]}"
		return
		;;
	*)
		local i=
		local cnt=${#problems[@]}

		for (( i = 0; i < $cnt; i++ )); do
			local p=${problems[$i]}

			if [[ "$branch_name" =~ $p ]]; then
				echo "$p"
				return
			fi
		done
	esac
}

# MARK: Public
function Branch.init()
{
	local bug="$1"
	local namespace="$2"

	case "$namespace" in
	wip|pr)
		;;
	*)
		CLI.die "invalid branch namespace: $namespace"
		;;
	esac

	F_BRANCH_BUG="$bug"
	F_BRANCH_NAMESPACE="$namespace"
	F_BRANCH_USERNAME="$(Git.run config fix.username)"
}

function Branch.set_base_ref()
{
	local b="$1"
	F_BRANCH_BASE="$b"
}

function Branch.set_bug_number_prefix()
{
	local pfx="$1"
	F_BRANCH_BUG_NUMBER_PREFIX="$pfx"
}

function Branch.set_component()
{
	local c="$1"
	F_BRANCH_COMPONENT="$c"
}

function Branch.set_title()
{
	local t="$1"
	F_BRANCH_TITLE="$t"
}

function Branch.set_title_word_count()
{
	local n="$1"
	F_BRANCH_WORD_CAP="$n"
}

function Branch.get_name()
{
	echo "$(Branch._derive_name)"
}

function Branch.get_base_ref()
{
	local branch_base=

	case "$F_BRANCH_BASE" in
	latest)
		branch_base="$(Git.get_default_branch)"
		;;
	tags/*)
		branch_base=$(strip_prefix "$F_BRANCH_BASE" "tags/")
		;;
	current)
		branch_base=
		;;
	*)
		branch_base="$F_BRANCH_BASE"
		;;
	esac

	echo "$branch_base"
}

function Branch.get_title()
{
	echo "$F_BRANCH_TITLE"
}

function Branch.create_and_checkout()
{
	local branch_name=
	local branch_base=
	local update_refs=

	branch_name=$(Branch._derive_name)
	CLI.die_ifz "$branch_name" "failed to derive branch name"

	Module.config 0 "branch create"
	Module.config 1 "branch name" "$branch_name"
	Module.config 1 "bug" "$F_BRANCH_BUG"
	Module.config 1 "namespace" "$F_BRANCH_NAMESPACE"
	Module.config 1 "component" "$F_BRANCH_COMPONENT"
	Module.config 1 "title" "$F_BRANCH_TITLE"
	Module.config 1 "title word cap" "$F_BRANCH_WORD_CAP"
	Module.config 1 "base ref" "$F_BRANCH_BASE"
	Module.config 1 "username" "$F_BRANCH_USERNAME"

	branch_base=$(Branch.get_base_ref)
	if [ -n "$branch_base" ]; then
		Git.check_tag "$branch_base"
		if [ $? -eq 0 ]; then
			Git.run fetch '%REMOTE%' refs/$base:refs/$base
			CLI.die_check $? "fetch base tag: $branch_base"
		else
			update_refs=t
		fi

		Git.run_quiet checkout "$branch_base"
		CLI.die_check $? "check out base branch or tag"

		# If we fetched a tag, we don't need to update our remote refs or pull
		# commits before creating the branch; we'll just be good to go.
		if [ -n "$update_refs" ]; then
			q Git.update_remote_refs_and_pull
			CLI.die_check $? "update base branch or tag"
		fi
	fi

	Git.run_quiet checkout -b "$branch_name"
	CLI.die_check $? "create fix branch: $branch_name"

	echo "$branch_name"
}
