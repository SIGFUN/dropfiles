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
F_GIT_REMOTE=origin
F_GIT_DIR=
F_GIT_WORKTREE=
F_GIT_DEFAULT_BRANCH=

# MARK: Internal
function Git._status_plusplus()
{
	local remote="$(Git.get_remote)"
	local branch="$(Git.get_current_branch)"
	local remote_restore=
	local ret=

	shift 2

	# git-status(1) doesn't let you specify an arbitrary remote; it always uses
	# the current remote tracking branch. This is a bit annoying, but it's
	# understandable since there is no rule saying that a branch has to track an
	# identically named branch in a given remote. So git-status(1) goes with the
	# canonical tracking information on the current branch. Still, given that
	# the config field refers to a remote and not a remote ref, it seems like
	# this functionality wouldn't break a whole lot by checking the named remote
	# for a ref of the same name as the current branch.
	remote_restore=$(Git.run config branch.$branch.remote)
	ret=$?
	if [ -z "$remote_restore" ]; then
		# This just means that no remote was configured.
		return $ret
	fi

	# Temporarily change the remote to the one we want to check.
	Git.run config branch.$branch.remote "$remote"
	Git.run status "$@"
	ret=$?
	Git.run config branch.$branch.remote "$remote_restore"

	return $?
}

# MARK: Meta
function Git.available()
{
	return 0
}

function Git.check_repo()
{
	q2 Git.run rev-parse --git-dir
}

# MARK: Public
function Git.init()
{
	local gitdir="$1"
	local worktree="$2"
	local remote="$3"
	local default_branch=
	local gitbin="$libdir/../bin"

	F_GIT_DIR=
	F_GIT_WORKTREE=
	F_GIT_REMOTE=origin

	if [ "$gitdir" != "default" ]; then
		F_GIT_DIR="$gitdir"
	fi

	if [ "$worktree" != "default" ]; then
		F_GIT_WORKTREE="$worktree"
	fi

	if [ "$remote" != "default" ]; then
		F_GIT_REMOTE="$remote"
	fi

	gitdir=$(Git.check_repo)
	CLI.die_ifz "$gitdir" "not a git repository"

	# If we're not able to connect to the remote, then we'll just guess at a
	# default branch name of "main".
	default_branch=$(Git.get_default_branch_online)
	if [ -z "$default_branch" ]; then
		default_branch="main"
	fi

	F_GIT_DEFAULT_BRANCH="$default_branch"

	# We want to find this repository's git subcommands first.
	gitbin=$(realpath "$gitbin")
	export PATH="$gitbin:$PATH"

	Module.config 0 "git"
	Module.config 1 "gitdir" "$F_GIT_DIR"
	Module.config 1 "work tree" "$F_GIT_WORKTREE"
	Module.config 1 "remote" "$F_GIT_REMOTE"
	Module.config 1 "default branch" "$F_GIT_DEFAULT_BRANCH"
	Module.config 1 "path" "$PATH"
}

function Git.init_dotfiles()
{
	local gd="$HOME/.dotfiles"
	local wt="$dotfiles"
	local varg=$(CLI.get_verbosity_opt "dv")

	if [ "$wt" != "$HOME" ]; then
		gd="$dotfiles/.git"
	fi

	Git.init "$gd" "$wt" "default"
}

function Git.get_directory()
{
	if [ -z "$F_GIT_DIR" ]; then
		echo ".git"
		return
	fi

	echo "$F_GIT_DIR"
}

function Git.get_worktree()
{
	if [ -z "$F_GIT_WORKTREE" ]; then
		echo "."
		return
	fi

	echo "$F_GIT_WORKTREE"
}

function Git.set_remote()
{
	local r="$1"
	F_GIT_REMOTE="$r"
}

function Git.get_remote()
{
	echo "$F_GIT_REMOTE"
}

function Git.get_name()
{
	local url=$(Git.run remote get-url "$F_GIT_REMOTE")
	echo "$(basename -s ".git" "$url")"
}

function Git.get_default_branch()
{
	echo "$F_GIT_DEFAULT_BRANCH"
}

function Git.get_current_branch()
{
	local b=

	b=$(Git.run branch --show-current)
	if [ -z "$b" ]; then
		b=$(Git.run describe --exact-match --tags)
	fi

	CLI.die_ifz "$b" "failed to get current branch or tag"
	echo "$b"
}

function Git.get_default_branch_online()
{
	local head_line=

	head_line=$(Git.run_timeout remote show "$F_GIT_REMOTE")
	head_line=$(grep "HEAD branch" <<< "$head_line")
	head_line=${head_line#*: }

	echo -n "$head_line"
}

function Git.get_head_hash()
{
	local which="$1"
	local h=

	if [ "$which" = "short" ]; then
		Git.run_quiet rev-parse --short HEAD
	else
		Git.run_quiet rev-parse HEAD
	fi
}

function Git.get_ancestors()
{
	local ancestors=()

	ancestors=($(Git.run --no-pager log --simplify-by-decoration \
			--format="format:%D%n" -n1 --decorate-refs-exclude=refs/remotes \
			HEAD~1 | sed -e 's/, / /g' | sed -e 's/tag: //g'))
	echo "${ancestors[@]}"
}

function Git.get_branch_base()
{
	local ancestors=()

	ancestors=($(Git.get_ancestors))
	echo "${ancestors[0]}"
}

function Git.get_base_tag()
{
	local ancestors=()

	ancestors=($(Git.get_ancestors))
	for a in "${ancestors[@]}"; do
		Git.check_tag "$a"
		if [ $? -eq 0 ]; then
			echo "$a"
			return
		fi
	done
}

function Git.get_parent_branch()
{
	local ancestors=()

	ancestors=($(Git.get_ancestors))
	for a in "${ancestors[@]}"; do
		Git.check_tag "$a"
		if [ $? -ne 0 ]; then
			echo "$a"
			return
		fi
	done
}

function Git.get_branch_commits()
{
	local parent=$(Git.get_branch_base)
	Git.run log --pretty=format:"%H" ${parent}..HEAD
}

function Git.get_upstream()
{
	local b="$(initdefault "$1" "$(Git.get_current_branch)")"
	git rev-parse --abbrev-ref ${b}@{upstream}
}

function Git.check_tree_dirty()
{
	Git.run_quiet diff-files
}

function Git.check_tag()
{
	local n="$1"
	local tags=$(Git.run tag -l)
	
	grep -qE "^$n$" <<< "$tags"
}

function Git.update_branch_from_remote()
{
	local b="$1"
	local b_old=$(Git.get_current_branch)

	Git.run checkout "$b"
	CLI.die_check $? "check out branch: $b"

	Git.run pull --rebase '%REMOTE%'
	CLI.die_check $? "pull changes from remote: $b"

	Git.run checkout "$b_old"
	CLI.die_check $? "switch back to original branch: $b_old"
}

function Git.fetch_branch_from_remote()
{
	local b="$1"
	local b_old=$(Git.get_current_branch)

	# If the branch already exists locally, delete it.
	Git.run_quiet branch -D "$b"
	Git.run fetch '%REMOTE%' "$b"
	CLI.die_check $? "fetch branch from remote: $b"

	# Now check out the branch so we get a named ref.
	Git.run checkout "$b"
	CLI.die_check $? "check out branch: $b"

	# Now switch back to our original branch.
	Git.run checkout "$b_old"
	CLI.die_check $? "switch back to original branch: $b_old"
}

function Git.update_remote_refs_and_pull()
{
	local status=

	Git.run remote update '%REMOTE%'
	CLI.die_check $? "update remote refs"

	status=$(Git._status_plusplus -uno)
	if [[ ! "$status" =~ 'Your branch is behind' ]]; then
		return 0
	fi

	Git.run pull '%REMOTE%'
	CLI.die_check $? "pull changes from remote"
}

function Git.run()
{
	local gitcmd="$1"
	local i=0
	local argv=
	local dir_arg=
	local wt_arg=
	local qarg=
	local varg=
	local runhow=command

	if [ -n "$F_GIT_DIR" ]; then
		dir_arg="--git-dir=$F_GIT_DIR"
	fi

	if [ -n "$F_GIT_WORKTREE" ]; then
		wt_arg="--work-tree=$F_GIT_WORKTREE"
	fi

	# Many git commands support quiet/verbose flags, but not all of them support
	# both. There are a lot of subcommands, so just enumerate the ones we know
	# and care about so we don't fall over accidentally by passing a bogus
	# option to a subcommand that cannot deal with it. Those options should be
	# top-level ones at this point.
	case "$gitcmd" in
	branch|clone|commit|fetch|pull|push|merge)
		qarg=$(CLI.get_verbosity_opt "dq")
		varg=$(CLI.get_verbosity_opt "dv")
		;;
	checkout|reset)
		qarg=$(CLI.get_verbosity_opt "dq")
		;;
	remote|rebase)
		varg=$(CLI.get_verbosity_opt "dv")
		;;
	quiet)
		qarg="-q"

		gitcmd="$2"
		shift
		;;
	*)
		;;
	esac

	# Second pass to make up for poorly-behaved commands that aren't quiet when
	# given -q.
	if [ $(CLI.get_verbosity) -eq 0 ]; then
		case "$gitcmd" in
		push|rebase)
			runhow=command_noerr
			;;
		*)
			;;
		esac
	fi

	# Look for the magic '%REMOTE%' argument and replace it with our remote.
	# There is no conventional option/argument for specifying the remote across
	# various git subcommands, and it's usually positional.
	shift
	argv=("$@")
	for (( i = 0; i < ${#argv[@]}; i++ )); do
		local arg="${argv[$i]}"
		if [ "$arg" = '%REMOTE%' ]; then
			argv[$i]="$F_GIT_REMOTE"
		fi
	done

	shift
	CLI.$runhow git $dir_arg $wt_arg $gitcmd $varg $qarg "${argv[@]}"
}

function Git.run_timeout()
{
	local remote=
	local proto=
	local to_env=
	local to_arg=
	local v_arg=$(CLI.get_verbosity_opt "dv" 2)

	remote=$(Git.run remote get-url '%REMOTE%')
	proto=$(sed -E 's/(^[a-z]+):\/\/.*/\1/;' <<< "$remote")

	case "$proto" in
	ssh|'')
		GIT_SSH_COMMAND="ssh -o ConnectTimeout=2" Git.run "$@"
		return $?
		;;
	http)
		Git.run "$@"
		return $?
		;;
	*)
		Git.run "$@"
		return $?
		;;
	esac
}

function Git.run_quiet()
{
	Git.run "quiet" "$@"
}
