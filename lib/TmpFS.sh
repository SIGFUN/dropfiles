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
F_TMPFS_MOUNT=

# MARK: Meta
function TmpFS.available()
{
	return 0
}

# MARK: Public
function TmpFS.init()
{
	local p="$1"
	F_TMPFS_MOUNT="$p"
}

function TmpFS.check_mounted()
{
	local fs=

	# Check whether there is a filesystem already mounted at the mount path, and
	# if there is, check whether it's a tmpfs filesystem.
	fs=$(mount | grep " $F_TMPFS_MOUNT " | sed -E 's/.*\(([a-zA-Z]+), .*/\1/;')
	case "$fs" in
	tmpfs)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

function TmpFS.mount()
{
	local mnt_flags="nobrowse,noexec,nosuid"
	CLI.command sudo mount_tmpfs -o "$mnt_flags" "$F_TMPFS_MOUNT"
}

function TmpFS.unmount()
{
	local v_arg=$(CLI.get_verbosity_opt "dv")
	CLI.command sudo umount $v_arg -f "$F_TMPFS_MOUNT"
}
