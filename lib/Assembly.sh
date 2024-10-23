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
. "${libdir}/Project.sh"

# MARK: Globals
G_BUILD_CYCLE_SKIP=0
G_BUILD_CYCLE_ITER=1
G_BUILD_CYCLE_FULL=2

# MARK: Object Fields
F_ASSEMBLY_TARGET=
F_ASSEMBLY_TAG_COLLECTION=
F_ASSEMBLY_PROJECT_DIRECTORY=
F_ASSEMBLY_CALLBACK=
F_ASSEMBLY_IMAGES=()
F_ASSEMBLY_BUILD_CYCLE=full
F_ASSEMBLY_CFLAGS=()
F_ASSEMBLY_BUILD_STYLES=()
F_ASSEMBLY_BRANCHES=()
F_ASSEMBLY_WORKSPACE=
F_ASSEMBLY_IMGROOT=
F_ASSEMBLY_VMAP=()

# MARK: Internal
function Assembly.null_callback()
{
	return
}

function Assembly._get_ncpu()
{
	local ncpu=

	ncpu=$(CLI.command sysctl -n hw.ncpu)
	if [ -z "$ncpu" ]; then
		ncpu=2
	fi

	echo "$ncpu"
}

function Assembly._cycle_from_string()
{
	local cys="$1"

	case "$cys" in
	Skip|skip)
		echo $G_BUILD_CYCLE_SKIP
		return
		;;
	Iter*|iterative)
		echo $G_BUILD_CYCLE_ITER
		return
		;;
	Full|full)
		echo $G_BUILD_CYCLE_FULL
		return
		;;
	esac

	echo $G_BUILD_CYCLE_FULL
}

function Assembly._cycle_to_string()
{
	local cy="$1"

	case "$cy" in
	$G_BUILD_CYCLE_SKIP)
		echo "skip"
		return
		;;
	$G_BUILD_CYCLE_ITER)
		echo "iterative"
		return
		;;
	$G_BUILD_CYCLE_FULL)
		echo "full"
		return
		;;
	esac

	CLI.die "invalid build cycle: $cy"
}

function Assembly._compute_build_cycle()
{
	local p=$(Project.get_name)
	local min=$(Project.query_string "MinimumBuildCycle")
	local asm="$F_ASSEMBLY_BUILD_CYCLE"
	local cy=

	if [ -z "$min" ]; then
		min="skip"
	fi

	CLI.status "choosing build cycle: project = $p, min = $min, assembly = $asm"
	min=$(Assembly._cycle_from_string "$min")
	asm=$(Assembly._cycle_from_string "$asm")

	# If the project specifies a minimum build cycle that is greater than what
	# the assembly is doing, then go with the project's.
	cy="$asm"
	if [ "$min" -gt "$asm" ]; then
		cy="$min"
	fi

	cy=$(Assembly._cycle_to_string "$cy")
	CLI.status "chose build cycle: $cy"

	echo "$cy"
}

function Assembly._find_project_spec()
{
	local p="$1"
	local rez=

	rez=$(Module.find_resource "$F_ASSEMBLY_PROJECT_DIRECTORY/$p.json")
	if [ -n "$rez" ]; then
		cat "$rez"
	fi
}

function Assembly._get_project_spec()
{
	local p="$1"
	local i=0

	for (( i = 0; i < ${#F_ASSEMBLY_IMAGES[@]}; i += 3 )); do
		local pi="${F_ASSEMBLY_IMAGES[$(( i + 0 ))]}"
		local vi="${F_ASSEMBLY_IMAGES[$(( i + 1 ))]}"
		local ji="${F_ASSEMBLY_IMAGES[$(( i + 2 ))]}"

		if [ "$pi" = "$p" ]; then
			echo "$ji"
			return
		fi
	done
}

function Assembly._get_build_style()
{
	local p="$1"

	for (( i = 0; i < ${#F_ASSEMBLY_BUILD_STYLES[@]}; i += 2 )); do
		local pi="${F_ASSEMBLY_BUILD_STYLES[$(( i + 0 ))]}"
		local si="${F_ASSEMBLY_BUILD_STYLES[$(( i + 1 ))]}"

		if [ "$pi" = "$p" ]; then
			echo "$si"
			return
		fi
	done

	echo "normal"
}

function Assembly._lookup_tag()
{
	local p="$1"

	Plist.init_with_file "$F_ASSEMBLY_TAG_COLLECTION"
	Plist.get_value "$p" "string"
}

function Assembly._invoke_build()
{
	local which="$1"
	local style="$2"
	local p=
	local exports=()
	local v_map=(${F_ASSEMBLY_VMAP[@]})
	local tool=
	local tool_wflags=
	local style_xtra=
	local i=0
	local buildme=

	shift 2
	exports=("$@")

	p=$(Project.get_name)
	buildme=$(Project.query_string "$which")
	if [ -z "$buildme" ]; then
		CLI.status "no $which in project spec; skipping"
		return
	fi

	tool=$(Project.query_string "BuildTool")
	if [ -n "$tool" ]; then
		local v_fmt=
		local q_fmt=
		local v_arg=
		local q_arg=

		tool_wflags="$tool"

		v_fmt=$(Project.query_string "BuildVerbosityFormat")
		if [ -n "$v_fmt" ]; then
			v_arg=$(CLI.get_verbosity_opt "$v_fmt")
			if [ -n "$v_arg" ]; then
				tool_wflags+=" $v_arg"
			fi
		fi

		q_fmt=$(Project.query_string "BuildQuietFormat")
		if [ -n "$q_fmt" ]; then
			q_arg=$(CLI.get_verbosity_opt "$q_fmt")
			if [ -n "$q_arg" ]; then
				tool_wflags+=" $q_arg"
			fi
		fi

		# Insert the quiet/verbosity flags right next to the build tool,
		# since build variables and/or settings tend to follow argument
		# lists for build tools.
		buildme=$(sed -E "s/^$tool/$tool_wflags/;" <<< "$buildme")
	fi

	for (( i = 0; i < ${#exports[@]}; i += 2 )); do
		local ex="${exports[$(( i + 0 ))]}"
		local exv="${exports[$(( i + 1 ))]}"

		buildme="${ex}=${exv} $buildme"
	done

	style_xtra=$(Project.query_string "BuildStyles.$style")
	if [ -n "$style_xtra" ]; then
		buildme+=" $style_xtra"
	fi

	if [ "$which" = "BuildCommand" ]; then
		for (( i = 0; i < ${#F_ASSEMBLY_CFLAGS[@]}; i += 2 )); do
			local pi="${F_ASSEMBLY_CFLAGS[$(( i + 0 ))]}"
			local fi="${F_ASSEMBLY_CFLAGS[$(( i + 1 ))]}"

			if [ "$p" = "$pi" ]; then
				buildme+=" $fi"
				break
			fi
		done
	fi

	CLI.command eval "$buildme"
	CLI.die_check $? "build: '$buildme'"
}

function Assembly._check_project()
{
	local p="$1"

	for (( i = 0; i < ${#F_ASSEMBLY_IMAGES[@]}; i += 3 )); do
		local pi="${F_ASSEMBLY_IMAGES[$(( i + 0 ))]}"
		local vi="${F_ASSEMBLY_IMAGES[$(( i + 1 ))]}"
		local ji="${F_ASSEMBLY_IMAGES[$(( i + 2 ))]}"

		if [ "$p" = "$pi" ]; then
			return 0
		fi
	done

	return 1
}

function Assembly._update_project()
{
	local p="$1"
	local v="$2"

	for (( i = 0; i < ${#F_ASSEMBLY_IMAGES[@]}; i += 3 )); do
		local pi="${F_ASSEMBLY_IMAGES[$(( i + 0 ))]}"
		local vi="${F_ASSEMBLY_IMAGES[$(( i + 1 ))]}"
		local ji="${F_ASSEMBLY_IMAGES[$(( i + 2 ))]}"

		if [ "$p" = "$pi" ]; then
			F_ASSEMBLY_IMAGES[$(( i + 1 ))]="$v"
			return 0
		fi
	done

	return 1
}

function Assembly._add_project()
{
	local p="$1"
	local v="$2"
	local imgdir=$(Assembly.get_image_directory "$p")
	local p_spec=
	local url=
	local tp=
	local build_cmd=
	local default_img=

	# Check to see if the project has already been added to the build list. This
	# can happen if the project was part of the list of project to build, and
	# then later added during dependency resolution.
	Assembly._check_project "$p"
	if [ $? -eq 0 ]; then
		return
	fi

	p_spec=$(Assembly._find_project_spec "$p")
	CLI.die_ifz "$p_spec" "no specification for project: $p"

	Project.init "$p" "$p_spec" "${F_ASSEMBLY_VMAP[@]}"
	url="$(Project.query_string "URL")"
	tp="$(Project.query_string "TagPrefix")"
	build_cmd="$(Project.query_string "BuildCommand")"
	default_img="$(Project.get_image_predicate "default")"

	# When adding dependencies, we always use the tag collection to find out
	# what tags to use.
	deps=($(Project.get_dependencies))
	for d in "${deps[@]}"; do
		Assembly._add_project "$d" "collection"
	done

	F_ASSEMBLY_IMAGES+=("$p" "$v" "$p_spec")
	CLI.command mkdir -p "$imgdir"

	Module.config 1 "$p"
	Module.config 2 "base version" "$v"
	Module.config 2 "url" "$url"
	Module.config 2 "tag prefix" "$tp"
	Module.config 2 "build" "$build_cmd"
	Module.config 2 "default image" "$default_img"
	Module.config 2 "image directory" "$imgdir"
}

function Assembly._create_workspace()
{
	local oldwd=$(pwd)

	cd "$F_ASSEMBLY_WORKSPACE"
	for (( i = 0; i < ${#F_ASSEMBLY_IMAGES[@]}; i += 3 )); do
		local p="${F_ASSEMBLY_IMAGES[$(( i + 0 ))]}"
		local v="${F_ASSEMBLY_IMAGES[$(( i + 1 ))]}"
		local j="${F_ASSEMBLY_IMAGES[$(( i + 2 ))]}"
		local url=
		local tp=
		local cy=
		local base=
		local update_refs=

		Project.init "$p" "$j" "${F_ASSEMBLY_VMAP[@]}"

		url="$(Project.query_string "URL")"
		CLI.die_ifz "$url" "no URL in project spec"

		tp="$(Project.query_string "TagPrefix")"
		CLI.die_ifz "$url" "no TagPrefix in project spec"

		if [ ! -d "$p" ]; then
			Git.run clone "$url" "$p"
			CLI.die_check $? "clone repo: $url"
		fi

		cd "$p"
		Git.init "default" "default" "default"
		Git.run reset --hard '%REMOTE%'
		CLI.die_check $? "reset repo to clean state: $p"

		cy=$(Assembly._compute_build_cycle)
		case "$cy" in
		full|iterative)
			CLI.status "cleaning git repo"

			Git.run clean -fd
			CLI.die_check $? "reset repo to clean state: $p"
			;;
		*)
			;;
		esac

		if [ "$v" = "collection" ]; then
			v=$(Assembly._lookup_tag "$p")
			CLI.die_ifz "$v" "no tag in collection for project: $p"
		fi

		case "$v" in
		latest)
			base=$(Git.get_default_branch)
			update_refs=t
			;;
		${tp}*)
			if [[ "$v" =~ ^$tp ]]; then
				base="${v}"
			else
				base="${tp}${v}"
			fi

			Git.run fetch '%REMOTE%' refs/tags/$base:refs/tags/$base
			CLI.die_check $? "fetch base tag: $base"
			;;
		*)
			base="$v"
			update_refs=t
			;;
		esac

		Git.run checkout "$base"
		CLI.die_check $? "check out base branch or tag: $base"

		if [ -n "$update_refs" ]; then
			q Git.update_remote_refs_and_pull
			CLI.die_check $? "update base branch"
		fi

		cd ..
	done

	for (( i = 0; i < ${#F_ASSEMBLY_BRANCHES[@]}; i += 2 )); do
		local p="${F_ASSEMBLY_BRANCHES[$(( i + 0 ))]}"
		local b="${F_ASSEMBLY_BRANCHES[$(( i + 1 ))]}"
		local r=$(rand 4 "x")
		local mb="merge/$r/$b"

		cd "$p"
		CLI.die_check $? "no repo clone for $p"

		Git.fetch_branch_from_remote "$b"
		CLI.die_check $? "fetch branch from remote: $b"

		Git.run_quiet checkout -b "$mb"
		CLI.die_check $? "create merge branch: $mb"

		CLI.status "merging: $mb <= $b"
		Git.run merge --no-edit "$b"
		CLI.die_check $? "merge branch: $b"

		cd ..
	done

	cd "$oldwd"
}

function Assembly._build()
{
	local exports=()
	local i=0

	CLI.pushdir "$F_ASSEMBLY_WORKSPACE"
	for (( i = 0; i < ${#F_ASSEMBLY_IMAGES[@]}; i += 3 )); do
		local pi="${F_ASSEMBLY_IMAGES[$(( i + 0 ))]}"
		local vi="${F_ASSEMBLY_IMAGES[$(( i + 1 ))]}"
		local ji="${F_ASSEMBLY_IMAGES[$(( i + 2 ))]}"
		local imgdir="$(Assembly.get_image_directory "$pi")"
		local style=
		local v_map=(${F_ASSEMBLY_VMAP[@]})
		local cy=
		local build_dir=
		local imgs=
		local p_exports=

		# We'll always publish a build style, even if one was not explicitly
		# set. In that case we're building the "normal" style.
		style=$(Assembly._get_build_style "$pi")
		v_map+=("STYLE" "$style")

		Project.init "$pi" "$ji" "${v_map[@]}"
		CLI.pushdir "$pi"

		cy=$(Assembly._compute_build_cycle)
		case "$cy" in
		full|iterative)
			if [ "$cy" = "full" ]; then
				Assembly._invoke_build "CleanCommand" "" "${exports[@]}"
				CLI.die_check $? "clean failed: $pi"
			fi

			Assembly._invoke_build "BuildCommand" "$style" "${exports[@]}"
			CLI.die_check $? "build failed: $pi"
			;;
		*)
			;;
		esac

		imgs=($(Project.get_image_types))
		build_dir=$(Project.query_string "BuildDirectory")
		for img_type in "${imgs[@]}"; do
			local prd="$(Project.get_image_predicate "$img_type")"
			local img=

			CLI.pushdir "$build_dir"
			img=$(find_cwd "$prd")
			CLI.die_ifz "$img" "no image found: type = $img_type, pred = $prd"

			cp_clone "$img" "$imgdir/"
			CLI.command ln -sF "$img" "$imgdir/$img_type"
			$F_ASSEMBLY_CALLBACK "image" "$pi" "$img_type" "$imgdir/$img_type"
			CLI.popdir
		done

		p_exports=($(Project.get_exports))
		for ex in "${p_exports[@]}"; do
			local exv=$(Project.get_export "$ex")
			exports+=("$ex" "$exv")
		done

		CLI.popdir
	done

	CLI.popdir
}

# MARK: Meta
function Assembly.available()
{
	return 0
}

# MARK: Public
function Assembly.init()
{
	local target="$1"
	local tags="$2"
	local projdir="$3"
	local cb="$4"
	local images=()
	local ws=$(CLI.get_boot_state_path "workspace")
	local imgroot=$(CLI.get_run_state_path "img")
	local i=0

	F_ASSEMBLY_TARGET="$target"
	F_ASSEMBLY_TAG_COLLECTION="$tags"
	F_ASSEMBLY_PROJECT_DIRECTORY="$projdir"
	F_ASSEMBLY_CALLBACK="$cb"
	F_ASSEMBLY_WORKSPACE="$ws"
	F_ASSEMBLY_IMGROOT="$imgroot"
	F_ASSEMBLY_VMAP=(
		"NCPU" "$(Assembly._get_ncpu)"
		"TARGET" "$target"
		"WORKSPACE" "$ws"
		"INSTANCE" "$(rand 8 "x")"
	)

	if [ -z "$F_ASSEMBLY_CALLBACK" ]; then
		F_ASSEMBLY_CALLBACK="Assembly.null_callback"
	fi

	Module.config 0 "Assembly"
	Module.config 1 "target" "$target"
	Module.config 1 "tag collection" "$tags"
	Module.config 1 "workspace" "$ws"
	Module.config 1 "instance" "$instance"
	Module.config 1 "image root" "$imgroot"

	CLI.command mkdir -p "$ws"
	CLI.command mkdir -p "$imgroot"

	shift 4
	images=("$@")
	for (( i = 0; i < ${#images[@]}; i += 2 )); do
		local p="${images[$(( $i + 0 ))]}"
		local v="${images[$(( $i + 1 ))]}"

		# If the project was already in the list, we just update its version to
		# be what was explicitly specified. This can happen if the project in
		# question was a dependency of a project that we already added. In this
		# case, we want to use the version which was explicitly given over the
		# one from the collection.
		Assembly._update_project "$p" "$v"
		if [ $? -ne 0 ]; then
			Assembly._add_project "$p" "$v"
		fi
	done
}

function Assembly.set_variable()
{
	local v="$1"
	local vv="$2"

	F_ASSEMBLY_VMAP+=("$v" "$vv")
}

function Assembly.add_cflags()
{
	local p="$1"
	local f="$2"
	local i=0

	f="$(strclean "$f")"
	for (( i = 0; i < ${#F_ASSEMBLY_CFLAGS[@]}; i += 2 )); do
		local pi="${F_ASSEMBLY_CFLAGS[$(( i + 0 ))]}"
		local fi="${F_ASSEMBLY_CFLAGS[$(( i + 1 ))]}"

		if [ "$p" = "$pi" ]; then
			F_ASSEMBLY_CFLAGS[$(( i + 1 ))]="$fi $f"
			return
		fi
	done

	F_ASSEMBLY_CFLAGS+=("$p" "$f")
}

function Assembly.set_build_style()
{
	local p="$1"
	local s="$2"

	F_ASSEMBLY_BUILD_STYLES=("$p" "$s")
}

function Assembly.merge_branch()
{
	local p="$1"
	local b="$2"

	F_ASSEMBLY_BRANCHES+=("$p" "$b")
}

function Assembly.set_build_cycle()
{
	local cy="$1"
	F_ASSEMBLY_BUILD_CYCLE="$cy"
}

function Assembly.check_tool()
{
	local p="$1"
	local what="$2"
	local where="$F_ASSEMBLY_WORKSPACE/$p/$what"

	if [ -f "$where" ]; then
		return 0
	fi
	return 1
}

function Assembly.run_tool()
{
	local p="$1"
	local what="$2"
	local where="$F_ASSEMBLY_WORKSPACE/$p/$what"

	CLI.die_fcheck "$where" "assembly tool"

	shift 2
	CLI.command "$where" "$@"
}

function Assembly.assemble()
{
	Assembly._create_workspace
	Assembly._build
}

function Assembly.get_image_root()
{
	echo "$F_ASSEMBLY_IMGROOT"
}

function Assembly.get_image_directory()
{
	local p="$1"
	echo "$F_ASSEMBLY_IMGROOT/$p"
}

function Assembly.get_image()
{
	local p="$1"
	local flavor="$2"
	local img="$(Assembly.get_image_directory "$p")/$flavor"

	if [ -f "$img" ]; then
		echo "$img"
	fi
}
