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
F_BYTES_BYTES=
F_BYTES_LEN=
F_BYTES_CURSOR=0

# MARK: Internal
function Bytes._read()
{
	local n="$1"
	local left=$(( F_BYTES_LEN - F_BYTES_CURSOR ))

	# If we're going to read past the end of the bytes, truncate the read such
	# that the next read will return an EOF.
	if [ $n -gt $left ]; then
		n=$left
	fi

	if [ $F_BYTES_CURSOR -eq $F_BYTES_LEN ]; then
		echo "EOF"
		return
	fi

	Bytes.map "$F_BYTES_CURSOR" "$n"
}

function Bytes._interpret_integer()
{
	local v="$1"
	local l="$2"
	local f="$3"
	local order="$4"

	case "$l" in
	1|2|4|8)
		;;
	*)
		CLI.die "unsupported integer length: $l"
		;;
	esac

	# The shell is always big endian. xxd's -e option doesn't work for plain hex
	# dumps (i.e. the -p option), so we have to torture the output ourselves.
	if [ "$order" = "little" ]; then
		local v_swapped=

		v_swapped=$(echo "$v" | xxd -r -p | xxd -e -g$l)
		v_swapped=${v_swapped#*: }
		v_swapped=$(grep -oE '^[0-9a-f]+' <<< "$v_swapped")

		CLI.debug "swapped integer: original = $v, swapped = $v_swapped"
		v=$v_swapped
	fi

	case "$f" in
	d|u|o|x)
		;;
	*)
		CLI.die "unsupported integer format: $f"
		;;
	esac

	printf "%$f" "0x$v"
}

# MARK: Meta
function Bytes.to_raw_unsafe()
{
	local s="$1"
	echo "$s" | xxd -r -p -g0
}

function Bytes.measure()
{
	local d_len="$1"
	local s="$2"

	Bytes.to_raw_unsafe "$s" | shasum -a "$d_len" | grep -oE '^[0-9a-f]+'
}

# MARK: Public
function Bytes.init_with_file()
{
	local f="$1"

	# bash strings cannot represent null bytes, so we internally normalize to
	# xxd's plain representation.
	F_BYTES_BYTES=$(cat "$f" | xxd -g0 -p | tr -d $'\n')
	F_BYTES_LEN=${#F_BYTES_BYTES}
	F_BYTES_LEN=$(( F_BYTES_LEN / 2 ))
	F_BYTES_CURSOR=0

	Module.config 0 "bytes"
	Module.config 1 "file" "$f"
	Module.config 1 "length" "$F_BYTES_LEN"
}

function Bytes.map()
{
	local o="$1"
	local l="$2"
	local b_available=
	local b_requested=

	if [ $o -gt $F_BYTES_LEN ]; then
		CLI.die "out of bounds mapping: offset = $o, expected <= $F_BYTES_LEN"
	fi

	# If the caller gives -1 for the length, then just map from the given offset
	# to the end.
	if [ $l -eq -1 ]; then
		l=$(( F_BYTES_LEN - o ))
	fi

	b_available=$F_BYTES_LEN
	b_requested=$(( o + l ))
	if [ $b_requested -gt $b_available ]; then
		CLI.die "out of bounds mapping: " \
				"actual = $b_requested, expected <= $b_available," \
				"offset = $o, length = $l"
	fi

	CLI.debug "mapping: offset = $o, length = $l"
	echo "$F_BYTES_BYTES" | xxd -r -p | xxd -g0 -p -s $o -l$l | tr -d $'\n'
}

function Bytes.read()
{
	local n="$1"

	CLI.debug "reading: cursor = $F_BYTES_CURSOR, nbytes = $n"
	Bytes._read "$n"
}

function Bytes.check_read()
{
	local s="$1"
	local what="$2"
	local l_expect="$3"
	local l_actual=${#s}

	l_actual=$(( l_actual / 2 ))
	if [ $l_actual -ne $l_expect ]; then
		CLI.die "failed to read $what: actual = $l_actual, expected = $l_expect"
	fi

	Bytes.seek "current" "$l_actual"
}

function Bytes.check_read_bytes()
{
	local s="$1"
	local what="$2"
	local l_expect=0
	local l_actual=${#s}

	l_actual=$(( l_actual / 2 ))
	if [ $l_actual -le $l_expect ]; then
		CLI.die "failed to read $what: actual = $l_actual, expected > $l_expect"
	fi

	Bytes.seek "current" "$l_actual"
}

function Bytes.check_read_integer()
{
	local s="$1"
	local what="$2"
	local l_read="$3"
	local l_expect=0
	local l_actual=${#s}

	if [ $l_actual -le $l_expect ]; then
		CLI.die "failed to read $what: actual = $l_actual, expected > $l_expect"
	fi

	CLI.debug "read integer: $what = $s"
	Bytes.seek "current" "$l_read"
}

function Bytes.getpos()
{
	echo "$F_BYTES_CURSOR"
}

function Bytes.seek()
{
	local whence="$1"
	local o="$2"
	local base=
	local left=

	case "$whence" in
	current)
		base=$F_BYTES_CURSOR
		left=$(( F_BYTES_LEN - F_BYTES_CURSOR ))
		;;
	set)
		base=0
		left=$F_BYTES_LEN
		;;
	end)
		base=$F_BYTES_LEN
		left=0
		;;
	esac

	if [ $o -gt $left ]; then
		CLI.die "illegal seek: whence = $whence, off = $o, left = $left"
	fi

	CLI.debug "seeking cursor: " \
			"whence = $whence, base = $base, off = $o, old = $F_BYTES_CURSOR"
	F_BYTES_CURSOR=$(( base + o ))
}

function Bytes.read_integer()
{
	local l="$1"
	local f="$2"
	local end="$3"
	local v=

	v=$(Bytes.read "$l" "string")
	Bytes._interpret_integer "$v" "$l" "$f" "$end"
}

function Bytes.get_integer()
{
	local o="$1"
	local l="$2"
	local f="$3"
	local end="$4"

	v=$(Bytes.map "$o" "$l")
	CLI.die_ifz "$v" "failed to read integer at offset: $o"

	Bytes._interpret_integer "$v" "$l" "$f" "$end"
}
