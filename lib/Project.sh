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
. "${libdir}/Plist.sh"

# MARK: Object Fields
F_PROJECT_NAME=
F_PROJECT_JS=
F_PROJECT_VMAP=()

# MARK: Meta
function Project.available()
{
	return 0
}

# MARK: Public
function Project.init()
{
	local name="$1"
	local js="$2"
	local imgs=

	shift 2
	F_PROJECT_NAME="$name"
	F_PROJECT_JS="$js"
	F_PROJECT_VMAP=("$@")

	imgs=($(Project.get_image_types))
	if [ ${#imgs[@]} -gt 0 ]; then
		local build_dir=

		# If there are no images, then there doesn't need to be a build
		# directory.
		build_dir=$(Project.query_string "BuildDirectory")
		CLI.die_ifz "$build_dir" "no BuildDirectory in project spec: $j"

		# The build directory is set on a per-project basis, so we synthesize
		# the variable for each individual project. If the caller provided their
		# own BUILD_DIR, then that one will win, since it will be encountered
		# first during variable expansion.
		F_PROJECT_VMAP+=("BUILD_DIR" "$build_dir")
	fi
}

function Project.get_name()
{
	echo "$F_PROJECT_NAME"
}

function Project.query_string()
{
	local what="$1"
	local s=
	local i=0

	Plist.init_with_raw "json" "$F_PROJECT_JS"
	s=$(Plist.get_value "$what" "string" "")
	if [ -z "$s" ]; then
		return
	fi

	for (( i = 0; i < ${#F_PROJECT_VMAP[@]}; i += 2 )); do
		local v="${F_PROJECT_VMAP[$(( i + 0 ))]}"
		local vv="${F_PROJECT_VMAP[$(( i + 1 ))]}"
		local v_wxforms=$(grep -oE "\%$v:[A-Z:]+\%" <<< "$s")

		# There are transformations in the variable expansion, so apply them.
		# Each transform is indicated by a ':'.
		if [ -n "$v_wxforms" ]; then
			local xfs="${v_wxforms#*:}"
			local xf_arr=

			xfs=$(tr -d '%' <<< "$xfs")
			xf_arr=($(CLI.split_specifier_nospace ":" "$xfs"))
			for xf in "${xf_arr[@]}"; do
				case "$xf" in
				LOWER)
					vv=$(tolower "$vv")
					;;
				UPPER)
					vv=$(toupper "$vv")
					;;
				*)
					CLI.die "unsupported transform: $xf"
					;;
				esac
			done

			# Now we need to replace the fully-qualified variable in the value
			# string with just the variable name.
			s="${s/"$v_wxforms"/%$v%}"
		fi

		vv=$(sed 's/\//\\\//g' <<< "$vv")
		s=$(sed -E "s/\%$v\%/$vv/g" <<< "$s")
	done

	echo "$s"
}

function Project.get_image_predicate()
{
	local flavor="$1"

	Plist.init_with_raw "json" "$F_PROJECT_JS"
	if [ "$flavor" = "default" ]; then
		flavor=$(Project.query_string "Images.default")
		CLI.die_ifz "$flavor" "no default image in project spec"
	fi

	Project.query_string "Images.$flavor" "string" ""
}

function Project.get_image_types()
{
	local keys=()

	Plist.init_with_raw "json" "$F_PROJECT_JS"
	keys=($(Plist.get_keys "Images"))
	echo "${keys[@]}"
}

function Project.get_dependencies()
{
	local deps=()
	local cnt=
	local i=0

	Plist.init_with_raw "json" "$F_PROJECT_JS"
	cnt=$(Plist.get_count "Dependencies")
	for (( i = 0; i < cnt; i++ )); do
		local d=

		d=$(Plist.get_value "Dependencies.$i" "string")
		CLI.die_ifz "$d" "invalid dependency at index $i"

		deps+=("$d")
	done

	echo "${deps[@]}"
}

function Project.get_export()
{
	local what="$1"
	Project.query_string "Exports.$what"
}

function Project.get_exports()
{
	local keys=()

	Plist.init_with_raw "json" "$F_PROJECT_JS"
	keys=($(Plist.get_keys "Exports"))
	echo "${keys[@]}"
}
