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

# MARK: Internal
function Module._get_verbosity()
{
	check_available CLI
	if [ $? -eq 0 ]; then
		CLI.get_verbosity
		return
	fi

	echo "0"
}

function Module.log()
{
	local fmt="$1"
	local vlvl=$(Module._get_verbosity)

	shift 1
	if [ $vlvl -lt 1 ]; then
		return
	fi

	printf "$fmt\n" "$@" >&2
}

function Module.config()
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
		Module.log '%s' "$name"
	else
		Module.log '%-*s: %s' $width "$name" "$@"
	fi
}

function Module.find_resource()
{
	local rez="$1"
	# We first search in our local dotfiles so that we find the correct resource
	# whether we're run from the $HOME deployment or from within the normal
	# repository in a development scsenario. Then we look for the .employer
	# symlink in the parent directory of the dotfiles directory, which will find
	# the employer repository for the development scenario. Finally, we look in
	# the .employer symlink inside the dotfiles directory, which covers the
	# $HOME scenario for the employer dotfiles (which share the work tree
	# directory).
	local roots=(
		"$dotfiles"
		"$dotfiles/../.employer"
		"$dotfiles/.employer"
	)

	for r in "${roots[@]}"; do
		local p="$r/$rez"

		if [ -e "$p" ]; then
			echo "$p"
			return
		fi
	done
}

function Module.load_lazy()
{
	local n="$1"
	local rez=

	rez=$(Module.find_resource "lib/$n.sh")
	if [ -z "$rez" ]; then
		echo "no module with name: $n" >&2
		return 1
	fi

	source "$rez"
	if [ $? -ne 0 ]; then
		echo "failed to load module: $p" >&2
		return 1
	fi
}
