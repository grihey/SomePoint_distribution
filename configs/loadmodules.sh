#!/bin/sh

case "${1}" in
    start)

        # Exit if there's no modules file or there are no
        # valid entries
        [ -r /etc/modules ] &&
            egrep -qv '^($|#)' /etc/modules ||
            exit 0

        echo -n "Loading modules:"

        # Only try to load modules if the user has actually given us
        # some modules to load.
        while read module args; do

            # Ignore comments and blank lines.
            case "$module" in
                ""|"#"*) continue ;;
            esac

            # Attempt to load the module, making
            # sure to pass any arguments provided.
            modprobe -a ${module} ${args} >/dev/null

            # Print the module name if successful,
            # otherwise take note.
            if [ $? -eq 0 ]; then
                echo -n " ${module}"
            else
                failedmod="${failedmod} ${module}"
            fi
        done < /etc/modules

        # Print a message about successfully loaded
        # modules on the correct line.

        # Print a failure message with a list of any
        # modules that may have failed to load.
        if [ -n "${failedmod}" ]; then
            echo "Failed to load modules:${failedmod}"

        fi
        ;;
    *)
        echo "Usage: ${0} {start}"
        exit 1
        ;;
esac
