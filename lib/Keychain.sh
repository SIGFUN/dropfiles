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
F_KEYCHAIN_IDENTIFIER=
F_KEYCHAIN_SERVER=
F_KEYCHAIN_ACCOUNT=

# MARK: Internal
# We just use internet passwords for everything, since I'm not really clear on
# the difference between those and "generic" passwords. Note that the "Kind"
# column in Keychain Access does not correspond to whether the password item is
# "internet" vs. "generic"; it corresponds to the description of the item which
# can be matched with -D.
function Keychain._do()
{
	local what="$1"

	shift
	if [ -n "$F_KEYCHAIN_IDENTIFIER" ]; then
		CLI.command security $what-internet-password \
				-l "$F_KEYCHAIN_IDENTIFIER" \
				"$@"
	else
		CLI.command security $what-internet-password \
				-a "$F_KEYCHAIN_ACCOUNT" \
				-s "$F_KEYCHAIN_SERVER" \
				"$@"
	fi
}

# MARK: Meta
function Keychain.available()
{
	return 0
}

# MARK: Public
function Keychain.init_identifier()
{
	local identifier="$1"

	F_KEYCHAIN_IDENTIFIER="$identifier"
	F_KEYCHAIN_SERVER=
	F_KEYCHAIN_ACCOUNT=

	Module.config 0 "keychain"
	Module.config 1 "identifier" "$F_KEYCHAIN_IDENTIFIER"
}

function Keychain.init_account()
{
	local server="$1"
	local account="$2"

	F_KEYCHAIN_SERVER="$server"
	F_KEYCHAIN_ACCOUNT="$account"
	F_KEYCHAIN_IDENTIFIER=

	Module.config 0 "keychain"
	Module.config 1 "server" "$F_KEYCHAIN_SERVER"
	Module.config 1 "account" "$F_KEYCHAIN_ACCOUNT"
}

function Keychain.get_password_or_prompt()
{
	local what="$1"
	local n=$(initdefault "$2" 3)
	local pw=

	for (( i = 0; i < $n; i++ )); do
		pw=$(Keychain.get_password)
		if [ -n "$pw" ]; then
			break
		fi

		# Even though security(1) prompts for the password, its output does not
		# get reflected to stdout -- it goes straight to the tty. So we can
		# safely do this in this function without disrupting what the caller is
		# trying to capture from stdout.
		echo -n "please enter $what for $F_KEYCHAIN_ACCOUNT" >&2
		Keychain._do "add" -w
	done

	echo "$pw"
}

function Keychain.get_password()
{
	Keychain._do "find" -w
}

function Keychain.delete_password()
{
	local output=
	local ret=

	output=$(Keychain._do "delete" 2>&1)
	ret=$?
	case "$ret" in
	0)
		;;
	44)
		if [[ "$output" =~ 'The specified item could not be found' ]]; then
			ret=0
		fi
		;;
	*)
		echo "$output" >&2
		;;
	esac

	return $?
}
