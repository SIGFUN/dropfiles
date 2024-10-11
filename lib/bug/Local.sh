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
# comment in Local.init.
. "${libdir}/Lib.sh"
. "${libdir}/Module.sh"

assert_available CLI
assert_available Plist

# MARK: Module State
LOCAL_DB=
LOCAL_PROJECT=
LOCAL_NUMBER=
LOCAL_UPDATE_FIELDS=()
LOCAL_QUERY_FIELDS=()

# MARK: Internal
function Local._translate_field()
{
	local f="$1"

	case "$f" in
	Title)
		echo "Title"
		;;
	State)
		echo "State"
		;;
	Branch)
		echo "Branch"
		;;
	Component)
		echo "Component"
		;;
	esac
}

# MARK: Public
function Local.init()
{
	local p="$1"
	local username="$2"
	local secrets="$3"

	LOCAL_DB=$(CLI.get_boot_state_path "db")
	LOCAL_PROJECT="$p"

	Module.config 0 "local bug database"
	Module.config 1 "db path" "$LOCAL_DB"
	Module.config 1 "project" "$LOCAL_PROJECT"
	Module.config 1 "username" "$username"
	Module.config 1 "secrets store" "$secrets"
}

function Local.init_problem()
{
	local n="$1"

	LOCAL_NUMBER="$n"

	Module.config 0 "local bug database [number]"
	Module.config 1 "number" "$LOCAL_NUMBER"
}

function Local.query_tracker_property()
{
	local f="$1"

	case "$f" in
	Key)
		echo "BUG"
		;;
	BugPrefix)
		echo "BUG-"
		;;
	esac
}

function Local.add_comment()
{
	return
}

function Local.update_field()
{
	local f="$1"
	local v="$2"
	local t="$3"
	local ft=

	ft=$(Local._translate_field "$f")
	CLI.die_ifz "$ft" "no translation for field: $f"

	LOCAL_UPDATE_FIELDS+=("$ft" "$v" "$t")
}

function Local.query_field()
{
	local f="$1"
	local ft=

	ft=$(Local._translate_field "$f")
	CLI.die_ifz "$ft" "no translation for field: $f"

	LOCAL_QUERY_FIELDS+=("$ft")
}

function Local.update()
{
	# plutil is awful -- if we just give it a string of digits as the key path,
	# e.g. "1234", it will try and interpret that as an integer and the
	# resulting object won't be useable as a key. Property lists don't support
	# non-string keys, so it's a wonder why they'd do anything but interpret it
	# as a string, but whatever. We just make it look like a URL to appease
	# plutil.
	local k="bug://${LOCAL_NUMBER}"

	Plist.init_with_file "$LOCAL_DB"
	Plist.init_collection "$k" "dictionary"

	for (( i = 0; i < "${#LOCAL_UPDATE_FIELDS[@]}"; i += 3 )); do
		local f="${LOCAL_UPDATE_FIELDS[$(( $i + 0 ))]}"
		local v="${LOCAL_UPDATE_FIELDS[$(( $i + 1 ))]}"
		local s="${LOCAL_UPDATE_FIELDS[$(( $i + 2 ))]}"
		local kp="$k.$f"

		if [[ $v == *$'\n'* ]]; then
			CLI.die "value cannot contain new line character"
		fi

		Plist.set_value "$kp" "$t" "$v"
		CLI.die_check $? "set field: $kp = $v"
	done

	Plist.write "$LOCAL_DB" "xml1"
	CLI.die_check $? "write bug database"
}

function Local.query()
{
	local k="bug://${LOCAL_NUMBER}"
	local js='{}'

	Plist.init_with_file "$LOCAL_DB"
	Plist.init_collection "$k" "dictionary"

	for f in "${LOCAL_QUERY_FIELDS[@]}"; do
		local kp="$k.$f"
		local v=

		v=$(Plist.get_value_raw "$kp")

		Plist.init_with_raw "json" "$js"
		Plist.set_value "$f" "string" "$v"
		js=$(Plist.get)

		Plist.init_with_file "$LOCAL_DB"
	done

	Plist.init_with_raw "json" "$js"
	Plist.get "json"
}
