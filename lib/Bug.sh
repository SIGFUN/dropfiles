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
. "${libdir}/Lib.sh"
. "${libdir}/Module.sh"
. "${libdir}/CLI.sh"
. "${libdir}/Git.sh"
. "${libdir}/TmpFS.sh"

# MARK: Object Fields
F_BUG_TRACKER=
F_BUG_PROJECT=
F_BUG_NUMBER=
F_BUG_USERNAME=
F_BUG_SECRETS=

# MARK: Internal
function Bug._do()
{
	local what="$1"

	shift
	${F_BUG_TRACKER}.$what "$@"
}

# MARK: Meta
function Bug.set_project()
{
	local p="$1"
	Git.run config --local fix.bug.project "$p"
}

function Bug.get_project_name()
{
	Git.run config fix.bug.project
}

function Bug.get_id_regex()
{
	Git.run config fix.bug.regex
}

function Bug.get_commit_trailer()
{
	Git.run config fix.bug.trailer
}

function Bug.find_bug_id()
{
	local s="$1"
	local r=

	r=$(Bug.get_id_regex)
	CLI.die_ifz "$r" "no bug regex configured for repository"

	grep -oE "$r" <<< "$s"
}

# MARK: Public
function Bug.init()
{
	F_BUG_TRACKER="$(Git.run config fix.bug.tracker)"
	CLI.die_ifz "$F_BUG_TRACKER" "no bug tracker configured"

	F_BUG_PROJECT="$(Git.run config fix.bug.project)"
	CLI.die_ifz "$F_BUG_PROJECT" "no bug tracker project name configured"

	F_BUG_USERNAME="$(Git.run config fix.bug.account)"
	CLI.die_ifz "$F_BUG_USERNAME" "no bug tracker account configured"

	F_BUG_SECRETS="$(CLI.get_run_state_path "secrets")"
	CLI.command mkdir -p "$F_BUG_SECRETS"
	TmpFS.init "$F_BUG_SECRETS"

	TmpFS.mount
	CLI.die_check $? "mount secrets tmpfs"

	Module.load_lazy "bug/$F_BUG_TRACKER"
	CLI.die_check "$?" "find library for: $F_BUG_TRACKER"

	Module.config 0 "bug"
	Module.config 1 "tracker" "$F_BUG_TRACKER"
	Module.config 1 "project" "$F_BUG_PROJECT"
	Module.config 1 "username" "$F_BUG_USERNAME"
	Module.config 1 "secrets" "$F_BUG_SECRETS"

	Bug._do "init" "$F_BUG_PROJECT" "$F_BUG_USERNAME" "$F_BUG_SECRETS"
}

function Bug.init_problem()
{
	local n="$1"

	F_BUG_NUMBER="$n"
	Bug._do "init_problem" "$F_BUG_NUMBER"
}

function Bug.cleanup()
{
	TmpFS.unmount
}

function Bug.query_tracker_property()
{
	Bug._do "query_tracker_property" "$@"
}

function Bug.add_comment()
{
	Bug._do "add_comment" "$@"
}

function Bug.update_field()
{
	Bug._do "update_field" "$@"
}

function Bug.query_field()
{
	Bug._do "query_field" "$@"
}

function Bug.update()
{
	Bug._do "update" "$@"
}

function Bug.update_field_oneshot()
{
	local f="$1"
	local v="$2"

	Bug.update_field "$f" "$v"
	Bug.update
}

function Bug.query()
{
	Bug._do "query" "$@"
}

function Bug.query_field_oneshot()
{
	local f="$1"
	local js=

	Bug.query_field "$f"
	js=$(Bug.query)
	CLI.die_ifz "$js" "failed to query field: $f"

	Plist.init_with_raw "json" "$js"
	Plist.get_value "$f" "string"
}
