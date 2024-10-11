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

# MARK: Availability
function check_available()
{
	local mod="$1"
	q type "${mod}.available"
}

function assert_available()
{
	local mod="$1"

	check_available "$mod"
	if [ $? -ne 0 ]; then
		echo "module $mod must be imported by sourcer" >&2
		exit 1
	fi
}

# MARK: Output Suppression
function q2()
{
	"$@" 2> /dev/null
	return ${PIPESTATUS[0]}
}

function q1()
{
	"$@" > /dev/null
	return ${PIPESTATUS[0]}
}

function q()
{
	"$@" &> /dev/null
	return ${PIPESTATUS[0]}
}

# MARK: Simple Wrappers
function find_first()
{
	local what="$1"
	find . -name "$what" | head -n 1 | sed "s|^\./||" | tr -d '\n'
}

function find_latest()
{
	local what="$1"
	find . -name "$what" -print0 | xargs -0 ls -tU | sort -r | head -n 1
}

function find_cwd()
{
	local what="$1"
	find . -maxdepth 1 -name "$what" | head -n 1 | sed "s|^\./||" | tr -d '\n'
}

function find_nolinks()
{
	local where="$1"
	local what="$2"
	local results=()

	results=($(find "$where" -name "$what"))
	for r in "${results[@]}"; do
		local ls_out=

		ls_out=$(ls -ld "$r")
		if [[ ! "$ls_out" =~ ^l ]]; then
			echo "$r"
		fi
	done
}

function cp_clone()
{
	local cp_out=

	cp_out=$(cp -c "$@" 2>&1)
	if [[ "$cp_out" =~ "Cross-device link" ]]; then
		cp "$@"
	elif [ -n "$o" ]; then
		echo "$cp_out" >&2
	fi
}

# MARK: Generally Useful
function toupper()
{
	local s="$1"
	echo "$(tr '[:lower:]' '[:upper:]' <<< "$s")"
}

function tolower()
{
	local s="$1"
	echo "$(tr '[:upper:]' '[:lower:]' <<< "$s")"
}

function capitalize()
{
	local s="$1"
	echo "$(tr '[:lower:]' '[:upper:]' <<< ${s:0:1})${s:1}"
}

function initdefault()
{
	local v="$1"
	local d="$2"

	if [ -z "$v" ]; then
		echo "$d"
		return
	fi

	echo "$v"
}

function strsmash()
{
	local delim="$1"

	IFS="$delim"

	shift
	echo "$*"
}

function strclean()
{
	local s="$1"

	s="$(sed -E 's/^[[:space:]]?//;' <<< "$s")"
	s="$(sed -E 's/[[:space:]]?$//;' <<< "$s")"

	echo "$s"
}

function joinby()
{
	local d=${1-}
	local f=${2-}

	if shift 2; then
		printf '%s' "$f" "${@/#/$d}"
	fi
}

function toshellsafe()
{
	local s="$1"
	local n=

	# Normalize the string to something that should be useable in a shell
	# without escape sequences.
	n=$(tr -s '[:blank:]' <<< "$s")
	n=$(tr '[:blank:]' '-' <<< "$n")
	n=$(sed -E 's/[[:space:]]*$//' <<< "$n")
	n=$(tr -dc '[:alnum:]-' <<< "$n")

	echo -n "$n"
}

function verscmp()
{
	local lhs="$1"
	local rhs="$2"
	local sort_str=
	local sorted=()

	if [ "$lhs" = "$rhs" ]; then
		return 0
	fi

	sort_str+="$lhs"
	sort_str+=$'\n'
	sort_str+="$rhs"

	sorted=($(sort -V <<< "$sort_str"))
	if [ "${sorted[0]}" = "$lhs" ]; then
		return -1
	fi

	return 1
}

function date_file()
{
	date "+%Y.%m.%d_%H.%M.%S"
}

function uuidgen_unformatted()
{
	uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-'
}

function strip_prefix()
{
	local s="$1"
	local p="$2"

	echo "${s#"$p"}"
}

function strip_suffix()
{
	local s="$1"
	local sf="$2"

	echo "${s%"$sf"}"
}

function rand()
{
	local l="$1"
	local f=$(initdefault "$2" "x")
	
	od -An -t${f}${l} -N${l} /dev/urandom | tr -d ' '
}
