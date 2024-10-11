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

# MARK: Globals
G_DICTIONARY_BUCKETS_CNT=19
G_DICTIONARY_KEYS_0=()
G_DICTIONARY_KEYS_1=()
G_DICTIONARY_KEYS_2=()
G_DICTIONARY_KEYS_3=()
G_DICTIONARY_KEYS_4=()
G_DICTIONARY_KEYS_5=()
G_DICTIONARY_KEYS_6=()
G_DICTIONARY_KEYS_7=()
G_DICTIONARY_KEYS_8=()
G_DICTIONARY_KEYS_9=()
G_DICTIONARY_KEYS_10=()
G_DICTIONARY_KEYS_11=()
G_DICTIONARY_KEYS_12=()
G_DICTIONARY_KEYS_13=()
G_DICTIONARY_KEYS_14=()
G_DICTIONARY_KEYS_15=()
G_DICTIONARY_KEYS_16=()
G_DICTIONARY_KEYS_17=()
G_DICTIONARY_KEYS_18=()

G_DICTIONARY_VALS_0=()
G_DICTIONARY_VALS_1=()
G_DICTIONARY_VALS_2=()
G_DICTIONARY_VALS_3=()
G_DICTIONARY_VALS_4=()
G_DICTIONARY_VALS_5=()
G_DICTIONARY_VALS_6=()
G_DICTIONARY_VALS_7=()
G_DICTIONARY_VALS_8=()
G_DICTIONARY_VALS_9=()
G_DICTIONARY_VALS_10=()
G_DICTIONARY_VALS_11=()
G_DICTIONARY_VALS_12=()
G_DICTIONARY_VALS_13=()
G_DICTIONARY_VALS_14=()
G_DICTIONARY_VALS_15=()
G_DICTIONARY_VALS_16=()
G_DICTIONARY_VALS_17=()
G_DICTIONARY_VALS_18=()

G_DICTIONARY_CNT_0=0
G_DICTIONARY_CNT_1=0
G_DICTIONARY_CNT_2=0
G_DICTIONARY_CNT_3=0
G_DICTIONARY_CNT_4=0
G_DICTIONARY_CNT_5=0
G_DICTIONARY_CNT_6=0
G_DICTIONARY_CNT_7=0
G_DICTIONARY_CNT_8=0
G_DICTIONARY_CNT_9=0
G_DICTIONARY_CNT_10=0
G_DICTIONARY_CNT_11=0
G_DICTIONARY_CNT_12=0
G_DICTIONARY_CNT_13=0
G_DICTIONARY_CNT_14=0
G_DICTIONARY_CNT_15=0
G_DICTIONARY_CNT_16=0
G_DICTIONARY_CNT_17=0
G_DICTIONARY_CNT_18=0

# MARK: Internal
function Dictionary._compute_bucket()
{
	local k="$1"
	local bucket=

	bucket=$(cksum <<< "$k" | cut -f 1 -d ' ')
	bucket=$(( bucket % ${G_DICTIONARY_BUCKETS_CNT} ))

	echo "$bucket"
}

# MARK: Meta
function Dictionary.available()
{
	return 0
}

# MARK: Public
function Dictionary.init()
{
	for i in $(seq 0 $G_DICTIONARY_BUCKETS_CNT); do
		eval "G_DICTIONARY_KEYS_${mah_bucket}=()"
		eval "G_DICTIONARY_VALS_${mah_bucket}=()"
		eval "G_DICTIONARY_CNT_${mah_bucket}=0"
	done
}

function Dictionary.insert()
{
	local k="$1"
	local v="$2"
	local mah_bucket=$(Dictionary._compute_bucket "$k")

	Dictionary.remove "$k"
	eval "G_DICTIONARY_KEYS_${mah_bucket}+=(\"$k\")"
	eval "G_DICTIONARY_VALS_${mah_bucket}+=(\"$v\")"
	eval "(( G_DICTIONARY_CNT_${mah_bucket} += 1 ))"
}

function Dictionary.lookup()
{
	local k="$1"
	local mah_bucket=$(Dictionary._compute_bucket "$k")
	local i=0
	local cnt=$(eval "echo \$G_DICTIONARY_CNT_${mah_bucket}")

	for (( i = 0; i < $cnt; i++ )); do
		local ki=$(eval "echo \${G_DICTIONARY_KEYS_$mah_bucket[$i]}")
		local vi=$(eval "echo \${G_DICTIONARY_VALS_$mah_bucket[$i]}")

		if [ "$ki" = "$k" ]; then
			echo "$vi"
			return
		fi
	done
}

function Dictionary.remove()
{
	local k="$1"
	local mah_bucket=$(Dictionary._compute_bucket "$k")
	local i=0
	local cnt=$(eval "echo \$G_DICTIONARY_CNT_${mah_bucket}")

	for (( i = 0; i < $cnt; i++ )); do
		local ki=$(eval "echo \${G_DICTIONARY_KEYS_$mah_bucket[$i]}")
		local vi=$(eval "echo \${G_DICTIONARY_VALS_$mah_bucket[$i]}")

		if [ "$ki" = "$k" ]; then
			eval "unset \${G_DICTIONARY_KEYS_$mah_bucket[$i]}"
			eval "unset \${G_DICTIONARY_VALS_$mah_bucket[$i]}"
			eval "(( G_DICTIONARY_CNT_${mah_bucket} -= 1 ))"
			return
		fi
	done
}

function Dictionary.dump()
{
	local i=0

	for (( i = 0; i < $G_DICTIONARY_BUCKETS_CNT; i++ )); do
		local j=0
		local cnt=$(eval "echo \$G_DICTIONARY_CNT_${i}")

		echo "bucket[$i] = {" >&2

		for (( j = 0; j < $cnt; j++ )); do
			local ki=$(eval "echo \${G_DICTIONARY_KEYS_$i[$j]}")
			local vi=$(eval "echo \${G_DICTIONARY_VALS_$i[$j]}")

			echo "  $ki => $vi" >&2
		done

		echo "}" >&2
	done
}
