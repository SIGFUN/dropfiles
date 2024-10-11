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

# MARK: Object Fields
F_PLIST_FILE=
F_PLIST_RAW=
F_PLIST_FMT=

# MARK: Internal
function Plist._sanitize_json()
{
	local js="$1"

	# JSON null values cannot be represented in whatever normalized form that
	# plutil(1) uses internally to muck around. So strip them out, since we are
	# fine just treating them as not being present.
	js=$(sed -E 's/"[a-zA-Z0-9_]+"[[:space:]]*:[[:space:]]*null,?//g' <<< "$js")
	echo "$js"
}

function Plist._unwrap_xml()
{
	local xml="$1"
	local type="$2"
	local stripped=$(tr -d '\n' <<< "$xml")

	stripped=$(sed -E "s/<\?.*\?>//;" <<< "$stripped")
	stripped=$(sed -E "s/<\!.*.dtd\">//;" <<< "$stripped")
	stripped=$(sed -E "s/<plist version=\".*\">//;" <<< "$stripped")
	stripped=$(sed -E "s/<\/plist>//;" <<< "$stripped")

	if [ -n "$type" ]; then
		stripped=$(sed -E "s/^[[:space:]]*<$type>//;" <<< "$stripped")
		stripped=$(sed -E "s/<\/$type>[[:space:]]*$//;" <<< "$stripped")
	fi

	# If the type is an empty collection, then we just return nothing. The point
	# of this method is to return something that can be used for dumb text
	# concatenation when it's not possible/practical to do it via plutil.
	if [[ "$stripped" =~ ^\s*\<$type\/\> ]]; then
		stripped=''
	fi

	echo "$stripped"
}

function Plist._wrap_xml()
{
	local raw="$1"
	local type="$2"
	local hdr=
	local tlr=

	hdr+='<?xml version="1.0" encoding="UTF-8"?>'
	hdr+='<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
	hdr+='"http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
	hdr+='<plist version="1.0">'
	tlr='</plist>'

	# Note that it's completely fine for an empty collection to be represented
	# as e.g. <array></array>. The <array/> form is just a parsing convenience I
	# guess, but fortunately it's not the mandatory representation of an empty
	# collection.
	if [ -n "$type" ]; then
		hdr+="<$type>"
		tlr="</$type>$tlr"
	fi

	echo "${hdr}${raw}${tlr}"
}

function Plist._plutil_read()
{
	if [ -n "$F_PLIST_FILE" ]; then
		CLI.command plutil "$@" -o - "$F_PLIST_FILE"
	else
		CLI.command plutil "$@" -o - - <<< "$F_PLIST_RAW"
	fi
}

function Plist._plutil_write()
{
	local sarg=$(CLI.get_verbosity_opt "ds")

	if [ -n "$F_PLIST_FILE" ]; then
		CLI.command plutil "$@" $sarg "$F_PLIST_FILE"
	else
		local d=
		local ret=

		d=$(CLI.command plutil "$@" $sarg -o - - <<< "$F_PLIST_RAW")
		ret=$?

		case "$d" in
		*'No value to remove at key path'*)
			# Not an error, so just eat it and don't update the plist.
			F_PLIST_RAW="$d"
			;;
		*)
			if [ $ret -eq 0 ]; then
				F_PLIST_RAW="$d"
			else
				return $ret
			fi
			;;
		esac
	fi
}

# This is stupid, but it is what it is. plutil cannot directly address the root
# object because that doesn't appear to be something KVC can do. So we take the
# plist, wrap it in an array, and then query the first element of the array.
function Plist._get_root()
{
	local t="$1"
	local fmt="$2"
	local xml=$(Plist.get "xml1")
	local xml_unwrapped=
	local xml_hacked=

	xml_unwrapped=$(Plist._unwrap_xml "$xml")
	xml_hacked=$(Plist._wrap_xml "$xml_unwrapped" "array")
	CLI.command plutil -extract "0" "$fmt" -expect "$t" -o - - <<< "$xml_hacked"
}

# MARK: Meta
function Plist.available()
{
	return 0
}

# MARK: Public
function Plist.init_with_file()
{
	local f="$1"
	local f_name=$(basename "$f")
	local stash=$(CLI.get_run_state_path "$f_name")

	# Stash the plist as xml1 so we can work on it. This also catches any
	# syntactic issues with it early so we don't have to worry about parsing
	# as many failures out of plutil, which can be infuriating since it prints
	# error information to stdout. If there is no plist, we'll just create an
	# empty one.
	if [ -f "$f" ]; then
		cp_clone "$f" "$stash"
	else
		CLI.command plutil -create xml1 "$stash"
	fi

	CLI.command plutil -convert xml1 "$stash"
	CLI.die_check $? "convert plist to xml1"

	F_PLIST_FILE="$stash"
	F_PLIST_RAW=
	F_PLIST_FMT=
}

function Plist.init_with_raw()
{
	local fmt="$1"
	local d="$2"

	case "$fmt" in
	xml1|binary1)
		;;
	json)
		d=$(Plist._sanitize_json "$d")
		;;
	*)
		CLI.die "invalid plist format: $fmt"
		;;
	esac

	# We normalize raw data to xml1 while working with it, but when the final
	# plist gets written, we preserve the original format by default.
	d=$(CLI.command plutil -convert xml1 -o - - <<< "$d")
	CLI.die_check $? "convert plist to xml1"

	F_PLIST_FILE=
	F_PLIST_RAW="$d"
	F_PLIST_FMT="$fmt"
}

function Plist.get_value()
{
	local k="$1"
	local t="$2"
	local d="$3"
	local v=

	v=$(Plist._plutil_read -extract "$k" raw -expect "$t")
	if [ $? -ne 0 ]; then
		# plutil sometimes prints error information to stdout, so we have to
		# catch this and nix the output we captured.
		v="$d"
	fi

	echo "$v"
}

function Plist.get_value_raw()
{
	local k="$1"
	local v=

	v=$(Plist._plutil_read -extract "$k" raw)
	if [ $? -ne 0 ]; then
		# plutil sometimes prints error information to stdout, so we have to
		# catch this and nix the output we captured.
		v=""
	fi

	echo "$v"
}

function Plist.get_value_xml()
{
	local k="$1"
	local t="$2"
	local v=

	v=$(Plist._plutil_read -extract "$k" xml1 -expect "$t")
	if [ $? -ne 0 ]; then
		v=
	fi

	echo "$v"
}

function Plist.get_value_json()
{
	local k="$1"
	local t="$2"
	local v=

	v=$(Plist._plutil_read -extract "$k" json -expect "$t")
	if [ $? -ne 0 ]; then
		v=
	fi

	echo "$v"
}

function Plist.get_count()
{
	local k="$1"
	local d="$2"
	local cnt=

	cnt=$(Plist._plutil_read -extract "$k.@count" raw)
	if [ $? -ne 0 ]; then
		cnt="$d"
	fi

	echo "$cnt"
}

function Plist.get_keys()
{
	local k="$1"
	local xml=
	local keys=

	xml=$(Plist.get_value_xml "$k" "dictionary")
	if [ -z "$xml" ]; then
		return
	fi

	keys=$(grep -oE '^\t<key>.*</key>' <<< "$xml")
	keys=$(sed -E 's/<key>(.*)<\/key>/\1/;' <<< "$keys")

	# Set the delimiter to the newline since keys are allowed to have spaces in
	# them.
	IFS=$'\n' ; keys=($keys)
	echo "${keys[@]}"
}

function Plist.init_collection()
{
	local k="$1"
	local t="$2"
	local v=

	case "$t" in
	array)
		v='[]'
		;;
	dictionary)
		v='{}'
		;;
	*)
		CLI.die "invalid collection type: $t"
	esac

	q1 Plist._plutil_read -type "$k" -expect "$t"
	if [ $? -ne 0 ]; then
		Plist._plutil_write -replace "$k" -json "$v"
	fi
}

function Plist.set_value()
{
	local k="$1"
	local t="$2"
	local v="$3"

	Plist._plutil_write -replace "$k" -$t "$v"
}

function Plist.remove_value()
{
	local k="$1"
	Plist._plutil_write -remove "$k"
}

function Plist.append_value()
{
	local k="$1"
	local t="$2"
	local v="$3"

	Plist._plutil_write -insert "$k" -$t "$v" -append
}

function Plist.merge_arrays()
{
	local k="$1"
	local rhs="$2"
	local lhs=
	local lhs_unwrapped=
	local rhs_unwrapped=
	local concat_unwrapped=
	local concat=

	if [ -n "$k" ]; then
		lhs=$(Plist.get_value_xml "$k" "array")
	else
		lhs=$(Plist._get_root "array" "xml1")
	fi

	lhs_unwrapped=$(Plist._unwrap_xml "$lhs" "array")
	rhs_unwrapped=$(Plist._unwrap_xml "$rhs" "array")

	concat_unwrapped="${lhs_unwrapped}${rhs_unwrapped}"
	concat=$(Plist._wrap_xml "$concat_unwrapped" "array")

	if [ -n "$k" ]; then
		Plist._plutil_write -replace "$k" -array "$concat"
	else
		# We're dealing with the root object, so just convert the whole plist to
		# our internal representation.
		Plist.init_with_raw "xml1" "$concat"
	fi
}

function Plist.get()
{
	local fmt="$(initdefault "$1" "$F_PLIST_FMT")"
	local pretty_arg=

	if [ -n "$F_PLIST_FILE" ]; then
		CLI.command plutil -convert "$fmt" -o - "$F_PLIST_FILE"
		return $?
	fi

	if [ "$fmt" = "json-human" ]; then
		fmt="json"
		pretty_arg="-r"
	fi

	CLI.command plutil -convert "$fmt" $pretty_arg -o - - <<< "$F_PLIST_RAW"
}

function Plist.write()
{
	local f="$1"
	local fmt="$(initdefault "$2" "$F_PLIST_FMT")"

	if [ -n "$F_PLIST_FILE" ]; then
		cp_clone "$F_PLIST_FILE" "$f"
		return $?
	fi

	CLI.command plutil -convert "$fmt" -o "$f" - <<< "$F_PLIST_RAW"
}
