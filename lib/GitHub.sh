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

assert_available CLI
assert_available Plist
assert_available Keychain

# MARK: Module Globals
G_GITHUB_API="https://api.github.com"
G_GITHUB_API_VERSION="2022-11-28"

# MARK: Object Fields
F_GITHUB_PROJECT=
F_GITHUB_ORG=
F_GITHUB_ACCOUNT=
F_GITHUB_PR_BRANCH=
F_GITHUB_PR_TARGET=
F_GITHUB_PR_TITLE=
F_GITHUB_PR_BODY=

# MARK: Internal
function GitHub._get_access_token()
{
	local server="$G_GITHUB_API"
	local account="$F_GITHUB_ACCOUNT"

	Keychain.init_account "$server" "$account"
	Keychain.get_password_or_prompt "GitHub personal access token"
}

function GitHub._api()
{
	local verb="$1"
	local call="$2"
	local rq="$3"
	local rp=
	local pat=
	local auth=
	local status=
	local message=
	local url="$G_GITHUB_API/$call"

	pat=$(GitHub._get_access_token)
	CLI.die_ifz "$pat" "failed to get personal access token from Keychain"

	CLI.status "sending request: $rq"

	auth="Authorization: bearer $pat"
	rp=$(CLI.command curl -s -X "$verb" \
			-H "Accept: application/vnd.github+json" \
			-H "X-GitHub-Api-Version: $G_GITHUB_API_VERSION" \
			-d "$rq" \
			-K- \
			"$url" <<< "--header \"$auth\"")
	CLI.status "response: $rp"

	Plist.init_with_raw "json" "$rp"
	status=$(Plist.get_value "status" "string" "201")
	case "$status" in
	201)
		CLI.status "api call succeeded"
		echo "$rp"
		;;
	422)
		CLI.status "validation failure"
		echo "$rp"
		;;
	*)
		message=$(Plist.get_value "message" "string" "no message")
		CLI.err "api call failed: $status: $message:  $rq"
		;;
	esac
}

# MARK: Public
function GitHub.init()
{
	local org="$1"
	local proj="$2"
	local account="$3"

	F_GITHUB_ORG="$org"
	F_GITHUB_PROJECT="$proj"
	F_GITHUB_ACCOUNT="$account"
}

function GitHub.call()
{
	local verb="$1"
	local call="$2"
	local data="$3"

	GitHub._api "$verb" "$call" "$data"
}

# MARK: Pull Request Protocol
function GitHub.PR.init()
{
	local branch="$1"
	local target="$2"
	local title="$3"

	F_GITHUB_PR_BRANCH="$branch"
	F_GITHUB_PR_TARGET="$target"
	F_GITHUB_PR_TITLE="$title"
	F_GITHUB_PR_BODY="$F_GITHUB_ACCOUNT: $target ← $branch"
}

function GitHub.PR.set_body()
{
	local body="$1"
	F_GITHUB_PR_BODY="$body"
}

function GitHub.PR.create()
{
	local call="repos/$F_GITHUB_ORG/$F_GITHUB_PROJECT/pulls"
	local rq=
	local rp=
	local message=

	Plist.init_with_raw "json" '{}'
	Plist.set_value "head" "string" "$F_GITHUB_PR_BRANCH"
	Plist.set_value "base" "string" "$F_GITHUB_PR_TARGET"
	Plist.set_value "title" "string" "$F_GITHUB_PR_TITLE"
	Plist.set_value "body" "string" "$F_GITHUB_PR_BODY"

	rq=$(Plist.get "json")
	rp=$(GitHub.call "POST" "$call" "$rq")

	Plist.init_with_raw "json" "$rp"

	message=$(Plist.get_value "errors.0.message" "string")
	if [ -n "$message" ]; then
		case "$message" in
		'A pull request already exists for'*)
			# Hack, but GitHub doesn't tell you the URL of the existing pull
			# request, and I don't feel like making this path do the query to
			# figure out the existing URL.
			Plist.set_value "html_url" "string" "$message"
			;;
		*)
			CLI.die "failed to create pull request: $message"
			;;
		esac
	fi

	Plist.get_value "html_url" "string"
}
