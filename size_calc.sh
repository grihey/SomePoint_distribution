#!/bin/bash
# Calculates how much room files need

function File_size {
    local fsize

    fsize=$(stat --printf "%s" "$1")

    if [ "$fsize" -eq 0 ]; then
        # zero size files still take one cluster in this calculation
        printf "%d\n" "$cluster"
    else
        # Round up to cluster multiple
        fsize=$(( ((fsize + cluster - 1) / cluster) * cluster ))
        printf "%d\n" "$fsize"
    fi
}

# Cluster size
cluster=4096

# Additional free space multiplier (percent, 100 would mean no extra space)
mult=125

# Total size accumulator
size=0

while [ -n "$1" ]; do
    size=$((size + $(File_size "$1") ))
    shift
done

# Multiply by margin (no floats here)
size=$(((size * mult) / 100))

meg=$((1024 * 1024))
# Round up to multiple of megabytes
size=$(( (size + meg - 1) / meg ))

printf "%dM\n" "$size"
