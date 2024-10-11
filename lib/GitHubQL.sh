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
. "${libdir}/Plist.sh"

# MARK: Module Globals
G_GITHUBQL_GRAPHQL_API="https://api.github.com/graphql"
G_GITHUBQL_JS_NULL_HACK="__js_null_hack"

# MARK: Object Fields
F_GITHUBQL_Q=
F_GITHUBQL_PAGINATE=
F_GITHUBQL_PAGE_NODE=
F_GITHUBQL_CURSOR_NAME=
F_GITHUBQL_VARIABLES=()

function GitHubQL._api()
{
	local verb="$1"
	local q="$2"
	local auth=
	local rq=
	local r=
	local error_cnt=0
	local msg=

	q=$(tr '"' '\"' <<< "$q")
	q=$(tr -d $'\t' <<< "$q")
	q=$(tr $'\n' ' ' <<< "$q")
	CLI.status "performing query: $q"

	Plist.init_with_raw "json" '{}'
	Plist.set_value "query" "string" "$q"

	if [ "${#F_GITHUBQL_VARIABLES[@]}" -ne 0 ]; then
		local i=0

		Plist.init_collection "variables" "dictionary"
		for (( i = 0; i < ${#F_GITHUBQL_VARIABLES[@]}; i++ )); do
			local n="${F_GITHUBQL_VARIABLES[$(( i + 0 ))]}"
			local t="${F_GITHUBQL_VARIABLES[$(( i + 1 ))]}"
			local v="${F_GITHUBQL_VARIABLES[$(( i + 2 ))]}"
			local k="variables.$n"

			Plist.set_value "$k" "$t" "$v"
		done
	fi

	# XML plists cannot represent the null type, while JSON can, and the Plist
	# module deals with XML internally. So hack it so that we can do a simple
	# string replacement.
	rq=$(Plist.get "json")
	rq=$(sed -E "s/\"$G_GITHUBQL_JS_NULL_HACK\"/null/;" <<< "$rq")

	auth="Authorization: bearer $F_GITHUBQL_PAT"
	r=$(CLI.command curl -s -X "$verb" \
			-d "$rq" \
			-K- \
			"$G_GITHUBQL_GRAPHQL_API" <<< "--header \"$auth\"")
	CLI.status "response: $r"

	Plist.init_with_raw "json" "$r"
	error_cnt=$(Plist.get_count "errors" "0")
	msg=$(Plist.get_value "message" "string")
	if [ $error_cnt -gt 0 ]; then
		local i=0

		CLI.err "query failed: $q"
		for (( i = 0; i < $error_cnt; i++ )); do
			local k="errors.$i.message"
			local msg=

			msg=$(Plist.get_value "$k" "string")
			CLI.die_ifz "$msg" "failed to get error message: $k"
			CLI.err "error querying GitHub: $msg"
		done

		r=''
	elif [ -n "$msg" ]; then
		CLI.err "server rejected request: $msg"
		r=''
	else
		local d=

		if [ -n "$F_GITHUBQL_CURSOR_NAME" ]; then
			local cursor=

			cursor=$(Plist.get_value "string" "$F_GITHUBQL_CURSOR_NAME")
			CLI.die_ifz "$cursor" "cursor not returned: $F_GITHUBQL_CURSOR_NAME"

			GITHUB_CURSOR_POS="$cursor"
		fi

		d=$(Plist.get_value_xml "data" "dictionary")
		CLI.die_ifz "$d" "query data not returned"

		Plist.init_with_raw "xml1" "$d"
		r=$(Plist.get "json")
	fi

	echo "$r"
}

# MARK: Meta
function GitHubQL.available()
{
	return 0
}

# MARK: Public
function GitHubQL.init()
{
	local pat="$1"
	local q="$2"

	F_GITHUBQL_PAT="$pat"
	F_GITHUBQL_Q="$q"
	F_GITHUBQL_PAGINATE=
	F_GITHUBQL_PAGE_NODE=
	F_GITHUBQL_CURSOR_NAME=
	F_GITHUBQL_VARIABLES=()

	F_GITHUBQL_ORG=
	F_GITHUBQL_USER=
}

function GitHubQL.set_variable()
{
	local n="$1"
	local t="$2"
	local v="$3"

	F_GITHUBQL_VARIABLES+=("$n" "$t" "$v")
}

function GitHubQL.paginate()
{
	local object="$1"
	local page_node="$2"
	local cursor_name="$3"

	F_GITHUBQL_PAGINATE="$object"
	F_GITHUBQL_PAGE_NODE="$page_node"
	F_GITHUBQL_CURSOR_NAME="$cursor_name"
}

function GitHubQL.query()
{
	local next="true"
	local cursor_idx=
	local js_result='[]'

	# If there's a cursor, we initialize it to null.
	if [ -n "$F_GITHUBQL_CURSOR_NAME" ]; then
		GitHubQL.set_variable \
				"$F_GITHUBQL_CURSOR_NAME" \
				"string" \
				"$G_GITHUBQL_JS_NULL_HACK"
	fi

	while [ "$next" = "true" ]; do
		local q="$F_GITHUBQL_Q"

		CLI.status "js result = $js_result"

		r=$(GitHubQL._api "POST" "$q")
		CLI.die_ifz "$r" "api call failed"
		CLI.status "response = $r"

		Plist.init_with_raw "json" "$r"
		if [ -n "$F_GITHUBQL_PAGINATE" ]; then
			local d_xml=
			local var_cnt=${#F_GITHUBQL_VARIABLES[@]}
			local k_node="${F_GITHUBQL_PAGINATE}.${F_GITHUBQL_PAGE_NODE}"
			local k_cursor="${F_GITHUBQL_PAGINATE}.pageInfo.endCursor"
			local k_next="${F_GITHUBQL_PAGINATE}.pageInfo.hasNextPage"

			d_xml=$(Plist.get_value_xml "$k_node" "array")
			CLI.die_ifz "$d_xml" "no response data found at path: $k_node"
			CLI.status "response data = $d_xml"

			cursor=$(Plist.get_value "$k_cursor" "string")
			CLI.die_ifz "$cursor" "no cursor in response"
			CLI.status "cursor = $cursor"

			next=$(Plist.get_value "$k_next" "bool" "false")

			Plist.init_with_raw "json" "$js_result"
			Plist.merge_arrays "" "$d_xml"
			js_result=$(Plist.get "json")

			# Update the cursor.
			unset F_GITHUBQL_VARIABLES[$(( var_cnt - 1 ))]
			unset F_GITHUBQL_VARIABLES[$(( var_cnt - 2 ))]
			unset F_GITHUBQL_VARIABLES[$(( var_cnt - 3 ))]
			GitHubQL.set_variable "$F_GITHUBQL_CURSOR_NAME" "string" "$cursor"
		else
			js_result="$r"
			next="false"
		fi
	done

	echo "$js_result"
}
