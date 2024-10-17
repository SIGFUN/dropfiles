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

# sysexits(7)
EX_OK=0
EX_USAGE=64
EX_DATAERR=65
EX_NOINPUT=66
EX_NOUSER=67
EX_NOHOST=68
EX_UNAVAILABLE=69
EX_SOFTWARE=70
EX_OSERR=71
EX_OSFILE=72
EX_CANTCREAT=73
EX_IOERR=74
EX_TEMPFAIL=75
EX_PROTOCOL=76
EX_NOPERM=77
EX_CONFIG=78

# MARK: Globals
G_CLI_PARSEOPT_FRAGMENT="\
 Common command line options
v,verbose!    turn on verbose logging; may be specified multiple times, in \
which case the level of verbosity will increase
d,debug!      turn on debug logging and tracing

 Git subcommand options
G,git-dir=GIT-DIR-PATH         uses GIT-DIR-PATH as the git repository state \
directory
W,git-work-tree=WORK-TREE-PATH uses WORK-TREE-PATH as the git worktree
R,remote=REMOTE                uses REMOTE as the git remote; if unspecified, \
the default is \"origin\"
"

G_CLI_DEBUG_TOKEN="  debug"
G_CLI_STATUS_TOKEN=" status"
G_CLI_WARN_TOKEN="   warn"
G_CLI_ERROR_TOKEN="  error"

# MARK: Object Fields
F_CLI_NAME=
F_CLI_RUN_STATE_DIRECTORY=
F_CLI_BOOT_STATE_DIRECTORY=
F_CLI_VERBOSE_LEVEL=0
F_CLI_DEBUG_LEVEL=0
F_CLI_GIT_DIR=default
F_CLI_GIT_WORKTREE=default
F_CLI_GIT_REMOTE=default

# MARK: Meta
function CLI.available()
{
	return 0
}

function CLI.get_stuckopt_blurb()
{
	echo "\
Optional arguments and stuck-long
Any option which takes an optional argument is parsed with git-rev-parse(1)'s \
--stuck-long option. Whnen using the short form of option, this requires that \
the argument be stuck to the option in order to be properly recognized. For \
example, for the option '-f, --foo[=ARGUMENT]', passing '-fbar' would \
recognize 'bar' as the argument to the '--foo' option, even if '-b' is another \
valid option switch.
"
}

function CLI.get_global_blurb()
{
	echo "$G_CLI_PARSEOPT_FRAGMENT"
}

function CLI.init_cleanup()
{
	local cleanup="$1"
	trap "$cleanup" 0 1 2 3 15
}

function CLI.parse_argument()
{
	local opt_stuck="$1"
	local optarg=

	echo "${opt_stuck#*=}"
}

function CLI.parse_option_argument()
{
	local opt_stuck="$1"
	local opt=
	local arg=

	opt="${opt_stuck%%=*}"
	if [[ "$opt_stuck" =~ '=' ]]; then
		arg="${opt_stuck#*=}"
	fi

	echo "$opt $arg"
}

function CLI.get_config_path()
{
	local what="$1"
	local slash=""

	if [ -n "$what" ]; then
		slash="/"
	fi

	echo "$HOME/.config${slash}$what"
}

# MARK: Public
function CLI.init()
{
	local name="$1"
	local cmd_spec="$2"
	local tmpdir=$(getconf DARWIN_USER_TEMP_DIR)
	local run_state_dir=
	local boot_state_dir=
	local old_pwd=$(pwd)

	# Initialize these from the environment and allow the command line options
	# to override them.
	F_CLI_VERBOSE_LEVEL=0
	if [ -n "$VERBOSE" ]; then
		F_CLI_VERBOSE_LEVEL="$VERBOSE"
	fi

	F_CLI_DEBUG_LEVEL=0
	if [ -n "$DEBUG" ]; then
		F_CLI_DEBUG_LEVEL="$DEBUG"
	fi

	shift 2
	eval "$(echo "$cmd_spec" |
		git rev-parse --parseopt --keep-dashdash --stuck-long -- "$@" \
				|| echo exit $?
	)"

	while [ $# -ne 0 ]; do
		CLI.parse_opt "$1"
		shift
	done

	cd "$tmpdir"
	run_state_dir=$(mktemp -d "$name.XXXXXX")
	run_state_dir="${tmpdir}${run_state_dir}"
	cd "$old_pwd"

	boot_state_dir="${tmpdir}$name"
	mkdir -p "$boot_state_dir"

	F_CLI_NAME="$name"
	F_CLI_RUN_STATE_DIRECTORY="$run_state_dir"
	F_CLI_BOOT_STATE_DIRECTORY="$boot_state_dir"

	Module.config 0 "CLI"
	Module.config 1 "name" "$F_CLI_NAME"
	Module.config 1 "run state" "$F_CLI_RUN_STATE_DIRECTORY"
	Module.config 1 "boot state" "$F_CLI_BOOT_STATE_DIRECTORY"
	Module.config 1 "verbosity" "$F_CLI_VERBOSE_LEVEL"
	Module.config 1 "debug" "$F_CLI_DEBUG_LEVEL"
	Module.config 1 "working directory" "$(pwd)"
}

function CLI.init_git()
{
	Module.config 0 "CLI [git]"
	Module.config 1 "directory" "$F_CLI_GIT_DIR"
	Module.config 1 "worktree" "$F_CLI_GIT_WORKTREE"
	Module.config 1 "remote" "$F_CLI_GIT_REMOTE"

	Git.init "$F_CLI_GIT_DIR" "$F_CLI_GIT_WORKTREE" "$F_CLI_GIT_REMOTE"
}

function CLI.parse_opt()
{
	local opt="$1"
	local arg="$(CLI.parse_argument "$opt")"

	case "$opt" in
	-v | --verbose)
		F_CLI_VERBOSE_LEVEL=$(( $F_CLI_VERBOSE_LEVEL + 1 ))
		;;
	-d | --debug)
		F_CLI_DEBUG_LEVEL=$(( $F_CLI_DEBUG_LEVEL + 1 ))
		;;
	-G | --git-dir=*)
		F_CLI_GIT_DIR="$arg"
		;;
	-W | --git-work-tree=*)
		F_CLI_GIT_WORKTREE="$arg"
		;;
	-R | --git-remote=*)
		F_CLI_GIT_REMOTE="$arg"
		;;
	esac
}

function CLI.get_verbosity_opt()
{
	local opt="$1"
	local v_threshold=1
	local look_4threshold=t
	local dash_cnt=0
	local which_switch=
	local caps=
	local long=
	local dashes=
	local switch=
	local sep=
	local level=

	for (( i = 0; i < ${#opt}; i++ )); do
		local char="${opt:$i:1}"

		case "$char" in
		d)
			(( dash_cnt++ ))
			;;
		l)
			long=1
			;;
		q | Q)
			if [ "$F_CLI_VERBOSE_LEVEL" -lt $v_threshold ]; then
				which_switch="$char"
			fi
			;;
		s | S)
			if [ "$F_CLI_VERBOSE_LEVEL" -lt $v_threshold ]; then
				which_switch="$char"
			fi
			;;
		v | V)
			if [ "$F_CLI_VERBOSE_LEVEL" -ge $v_threshold ]; then
				which_switch="$char"
			fi
			;;
		b | B | D)
			if [ "$F_CLI_DEBUG_LEVEL" -ge $v_threshold ]; then
				if [ "$char" = "D" ]; then
					which_switch="d"
				else
					which_switch="$char"
				fi
			fi
			;;
		=)
			sep='='
			;;
		[0-9])
			if [ -n "$look_4threshold" ]; then
				v_threshold="$char"
			else
				level="$char"
			fi
			;;
		esac

		look_4threshold=
	done

	if [ -z "$which_switch" ]; then
		return 0
	fi

	if [[ "$which_switch" =~ [[:upper:]] ]]; then
		caps=t
	fi

	if [ -n "$long" ]; then
		which_switch=$(tolower "$which_switch")

		case "$which_switch" in
		v)
			which_switch="verbose"
			;;
		s)
			which_switch="silent"
			;;
		b | d)
			which_switch="debug"
			;;
		*)
			which_switch="quiet"
			;;
		esac
	fi

	if [ -n "$caps" ]; then
		which_switch=$(toupper "$which_switch")
	fi

	if [ -n "$level" ]; then
		if [ -n "$sep" ]; then
			level="$sep$level"
		else
			level=" $level"
		fi
	fi

	for (( i = 0; i < $dash_cnt; i++ )); do
		dashes+="-"
	done

	echo -n "$dashes$which_switch$level"
	return 0
}

function CLI.split_specifier_nospace()
{
	local delim="$1"
	local specifier="$2"
	local ifs_old=$IFS
	local arr=()

	IFS="$delim"
	arr=($specifier)
	IFS="$ifs_old"

	echo "${arr[@]}"
}

function CLI.print_field()
{
	local lvl="$1"
	local name="$2"
	local width=30
	local indent=""

	shift 2
	for (( l = 0; l < $lvl; l++ )); do
		indent+=" "
	done

	name="$indent$name"
	if [ $# -eq 0 ]; then
		printf '%s\n' "$name"
	else
		printf '%-*s: %s\n' $width "$name" "$@"
	fi
}

function CLI.status()
{
	local msg="$@"

	if [ $F_CLI_VERBOSE_LEVEL -gt 0 ]; then
		echo "$F_CLI_NAME:$G_CLI_STATUS_TOKEN: ${msg[@]}" >&2
	fi
}

function CLI.debug()
{
	local msg="$@"

	if [ $F_CLI_DEBUG_LEVEL -gt 0 ]; then
		echo "$F_CLI_NAME:$G_CLI_DEBUG_TOKEN: ${msg[@]}" >&2
	fi
}

function CLI.warn()
{
	local msg="$@"
	echo "$F_CLI_NAME:$G_CLI_WARN_TOKEN: ${msg[@]}" >&2
}

function CLI.err()
{
	local msg="$@"
	echo "$F_CLI_NAME:$G_CLI_ERROR_TOKEN: ${msg[@]}" >&2
}

function CLI.warn_check()
{
	local code="$1"
	local what="$2"

	if [ $code -ne 0 ]; then
		CLI.warn "failed to $what: $code"
	fi
}

function CLI.warn_ifz()
{
	local str="$1"
	local what="$2"

	if [ -z "$str" ]; then
		CLI.warn "$what"
	fi
}

function CLI.die()
{
	CLI.err "$@"
	exit $EX_SOFTWARE
}

function CLI.die_noopt()
{
	local param="$1"
	local a_an="a"

	if [[ "$param" =~ ^[AEIOUaeiou] ]]; then
		a_an="an"
	fi

	CLI.err "must provide $a_an $param"
	exit $EX_USAGE
}

function CLI.die_badopt()
{
	local param="$1"
	local val="$2"

	CLI.err "invalid or missing $param: $val"
	exit $EX_USAGE
}

function CLI.die_check()
{
	local code="$1"
	local what="$2"

	if [ $code -ne 0 ]; then
		CLI.err "failed to $what: $code"
		exit $EX_SOFTWARE
	fi
}

function CLI.die_advise()
{
	local code="$1"
	local what="$2"

	if [ $code -ne 0 ]; then
		CLI.err "$what: $code"
		exit $EX_SOFTWARE
	fi
}

function CLI.die_ifz()
{
	local str="$1"
	local what="$2"

	if [ -z "$str" ]; then
		CLI.err "$what"
		exit $EX_SOFTWARE
	fi
}

function CLI.die_fcheck()
{
	local p="$1"
	local what="$2"

	if [ ! -f "$p" ]; then
		CLI.err "$what not found: $p"
		exit $EX_NOINPUT
	fi
}

function CLI.die_dcheck()
{
	local p="$1"
	local what="$2"

	if [ ! -d "$p" ]; then
		CLI.err "$what not found: $p"
		exit $EX_NOINPUT
	fi
}

function CLI.get_run_state_path()
{
	local subpath="$1"
	local sep="/"

	if [ -z "$subpath" ]; then
		sep=""
	fi

	echo -n "$F_CLI_RUN_STATE_DIRECTORY$sep$subpath"
}

function CLI.get_boot_state_path()
{
	local subpath="$1"
	local sep="/"

	if [ -z "$subpath" ]; then
		sep=""
	fi

	echo -n "$F_CLI_BOOT_STATE_DIRECTORY$sep$subpath"
}

function CLI.get_verbosity()
{
	echo "$F_CLI_VERBOSE_LEVEL"
}

function CLI.start_debug()
{
	if [ "$F_CLI_DEBUG_LEVEL" -ge 2 ]; then
		set -x
	fi
}

function CLI.pushdir()
{
	local d="$1"

	CLI.die_ifz "$d" "no directory to push"

	if [ $(CLI.get_verbosity) -gt 1 ]; then
		echo "+ pushd $d"
		pushd "$d" >&2
	else
		pushd "$d" > /dev/null
	fi
}

function CLI.popdir()
{
	if [ $(CLI.get_verbosity) -gt 1 ]; then
		echo "+ popd"
		popd
	else
		popd > /dev/null
	fi
}

function CLI.command()
{
	local ret=

	if [ $(CLI.get_verbosity) -gt 1 ]; then
		( set -x; "$@" )
		ret=$?
		return $ret
	fi

	( "$@" )
	return $?
}

function CLI.command_noerr()
{
	CLI.command "$@" 2>/dev/null
}
