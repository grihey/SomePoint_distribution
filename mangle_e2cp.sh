#!/bin/bash
# removes e.g. the "_x86_qemu" from the filenames when copying into image

file="$1"
dir="$2"

fext="${file##*.}"

if [ -n "$fext" ]; then 
    fext=".${fext}"
fi

fout="$(basename "$file")"
fout="${fout%.*}"
fout="${fout%%_${TCDIST_ARCH}_${TCDIST_PLATFORM}}"

e2cp ${E2CPFLAGS} "$file" "$dir/${fout}${fext}"
