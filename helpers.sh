#!/bin/bash

# This file has multipurpose functions.
# Usage . helpers.sh

# Set exit on error, so shellcheck won't suggest '|| exit 1' everywhere
set -e

# Get actual directory of this bash script
HDIR="$(dirname "${BASH_SOURCE[0]}")"
HDIR="$(realpath "$HDIR")"

# Minimum config for config generation
function Min_config {
    local flags

    # Save flags
    flags="$-"

    # Enable automatic export of global environment variables
    # So config settings are all exported (for e.g. Makefile use)
    set -a

    # Set main source directory for other scripts
    TCDIST_DIR="${HDIR}"

    # Set output dir only if not specified in environment already
    if [ -z "$TCDIST_OUTPUT" ]; then
        if [ -f "${TCDIST_DIR}/.tcdist_output" ]; then
            # Let .tcdist_output file set TCDIST_OUTPUT
            # shellcheck disable=SC1091,SC1090
            . "${TCDIST_DIR}/.tcdist_output"
            if [ -z "$TCDIST_OUTPUT" ]; then
                echo "${TCDIST_DIR}/.tcdist_output was sourced, but it did not set TCDIST_OUTPUT" >&2
                exit 1
            fi
        else
            # Use a dir in main source dir
            TCDIST_OUTPUT="${TCDIST_DIR}/output"
        fi
    fi

    TCDIST_OUTPUT="$(Sanity_check "$TCDIST_OUTPUT" non_existing)"

    if [ "$TCDIST_OUTPUT" == "$TCDIST_DIR" ]; then
        echo "\$TCDIST_OUTPUT can no longer be the same directory as \$TCDIST_DIR, please change your output directory settings" >&2
        exit 2
    fi

    # Restore a flag
    if [[ "$flags" =~ "a" ]]; then
        set -a
    else
        set +a
    fi
}

# Loads build system configurations
# Disable complaints about arguments they are optional here
# shellcheck disable=SC2120
function Load_config {
    local flags

    Min_config

    # Save flags
    flags="$-"

    # Enable automatic export of global environment variables
    # So config settings are all exported (for e.g. Makefile use)
    set -a

    # Load defaults in case .setup_sh_config is missing any settings
    # for example .setup_sh_config could be from older revision
    # disable shellchecking of default_setup_sh_config and warnings about it
    # shellcheck disable=SC1091,SC1090
    . "${TCDIST_DIR}/configs/default_setup_sh_config"

    if [ -f "${TCDIST_OUTPUT}/.setup_sh_config${TCDIST_PRODUCT}" ]; then
        # disable shellchecking of .setup_sh_config${TCDIST_PRODUCT} and warnings about it
        # shellcheck disable=SC1091,SC1090
        . "${TCDIST_OUTPUT}/.setup_sh_config${TCDIST_PRODUCT}"
    else
        if [ -n "${TCDIST_PRODUCT}" ]; then
            echo "${TCDIST_OUTPUT}/.setup_sh_config${TCDIST_PRODUCT} doesn't exist"
            exit 1
        fi
    fi

    TCDIST_SETUP_SH_CONFIG=".setup_sh_config${TCDIST_PRODUCT}"

    # Convert some options to lower case
    TCDIST_ARCH="${TCDIST_ARCH,,}"
    TCDIST_PLATFORM="${TCDIST_PLATFORM,,}"
    TCDIST_HYPERVISOR="${TCDIST_HYPERVISOR,,}"
    TCDIST_SUDOTYPE="${TCDIST_SUDOTYPE,,}"

    # Put admin machine name in it's own variable for convenience
    # shellcheck disable=SC2034 # Don't complain about unused variable, it's exported
    TCDIST_ADMIN="${TCDIST_VMLIST%% *}"

    # Restore a flag
    if [[ "$flags" =~ "a" ]]; then
        set -a
    else
        set +a
    fi

    if [ "$1" != "nocheck" ]; then
        case "$TCDIST_ARCH" in
        x86)
            case "$TCDIST_SUB_ARCH" in
            intel|amd)
                # Options ok
            ;;
            *)
                echo "Invalid TCDIST_SUB_ARCH: $TCDIST_SUB_ARCH" >&2
                exit 1
            ;;
            esac
        ;;
        arm64)
            if [ -n "$TCDIST_SUB_ARCH" ] ; then
                echo "Invalid TCDIST_SUB_ARCH for $TCDIST_PLATFORM, please leave blank." >&2
                exit 1
            fi
        ;;
        *)
            echo "Invalid TCDIST_ARCH: $TCDIST_ARCH" >&2
            exit 1
        ;;
        esac

        case "$TCDIST_PLATFORM" in
        raspi4)
            # Options ok
        ;;
        cm4io)
            # Options ok
        ;;
        ls1012afrwy)
            # Options ok
        ;;
        imx8qxpc0mek)
            # Options ok
        ;;
        upxtreme)
            # Options ok
        ;;
        qemu)
            # Options ok
        ;;
        *)
            echo "Invalid TCDIST_PLATFORM: $TCDIST_PLATFORM" >&2
            exit 1
        ;;
        esac

        case "$TCDIST_HYPERVISOR" in
        xen|kvm)
            # Options ok
        ;;
        *)
            echo "Invalid TCDIST_HYPERVISOR: $TCDIST_HYPERVISOR" >&2
            exit 1
        ;;
        esac

        case "$TCDIST_SUDOTYPE" in
        standard)
            # Disable sudo function if standard sudo is requested
            unset sudo
        ;;
        showonpassword|verbose|confirm)
            # Options ok
        ;;
        *)
            echo "Invalid TCDIST_SUDOTYPE: $TCDIST_SUDOTYPE" >&2
            exit 1
        ;;
        esac
    fi
}

# Function to quickly check most important settings in current config
function Conf {
    printf "TCDIST_OUTPUT=%s\n" "$TCDIST_OUTPUT"
    printf "TCDIST_ARCH=%s\n" "$TCDIST_ARCH"
    if [ "$TCDIST_ARCH" == "x86" ]; then
        printf "TCDIST_SUB_ARCH=%s\n" "$TCDIST_SUB_ARCH"
    fi
    printf "TCDIST_PLATFORM=%s\n" "$TCDIST_PLATFORM"
}

# Get path to sudo binary (or empty if not available, but don't fail here)
SUDOCMD="$(command -v sudo || true)"

# sudo function will show the command about to be run if password is prompted for
# if TCDIST_SUDOTYPE=verbose then all commands will be shown
# if TCDIST_SUDOTYPE=confirm then all commands will be confirmed regardless of password prompting
# if left in the confirm prompt for a long time, then sudo might ask password again after confirmation, but it is what it is
# sudo function meant to replace sudo command, so it is not capitalized like other functions
function sudo {
    local prompt
    local inp

    prompt="$(printf "About to sudo: \"%s\"" "$*")"

    # Check if sudo is going to ask password or not
    if "${SUDOCMD:?}" -n true 2> /dev/null; then
        case "$TCDIST_SUDOTYPE" in
        confirm)
            # Ask for confirmation if confirm mode enabled
            inp="x"
            while [ "$inp" == "x" ]; do
                printf "%s\nConfirm (Y/n): " "$prompt" > /dev/tty
                read -r inp < /dev/tty
                case "$inp" in
                ""|y|Y)
                    inp="Y"
                ;;
                n|N)
                    return 1
                ;;
                *)
                    echo "Invalid input" > /dev/tty
                    inp="x"
                ;;
                esac
            done
        ;;
        verbose)
            # Show the command in verbose mode
            printf "sudo: \"%s\"\n" "$*"
        ;;
        esac

        "${SUDOCMD:?}" "$@"
    else
        # If sudo is going to ask password show the command about to be run anyway
        printf "%s\n" "$prompt" > /dev/tty
        "${SUDOCMD:?}" "$@"
    fi
}

function Xenconfig {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} with xen configuration" >&2
    cp -f  "${TCDIST_DIR}"/configs/default_setup_sh_config_xen "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function Kvmconfig {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} with kvm configuration" >&2
    # Change TCDIST_HYPERVISOR option to kvm
    cp -f  "${TCDIST_DIR}"/configs/default_setup_sh_config_kvm "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function X86config {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} for x86 qemu" >&2
    cp -f  "${TCDIST_DIR}"/configs/default_setup_sh_config_x86 "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function X86config_upxtreme {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} for x86 upXtreme" >&2
    cp -f  "${TCDIST_DIR}"/configs/default_setup_sh_config_x86_upxtreme "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function Arm64config {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} for arm64" >&2
    cp -f  "${TCDIST_DIR}"/configs/default_setup_sh_config_arm64 "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function Arm64config_cm4io {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} for arm64 cm4io" >&2
    cp -f  "${TCDIST_DIR}"/configs/default_setup_sh_config_arm64_cm4io "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function Arm64config_ls1012a {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} for arm64 ls1012afrwy" >&2
    mkdir -p "${TCDIST_OUTPUT:?}"
    cp -f  "${TCDIST_DIR}"/configs/default_setup_sh_config_arm64_ls1012afrwy "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}

function Arm64config_imx8qxpc0mek {
    echo "Creating ${TCDIST_SETUP_SH_CONFIG} for arm64 imx8qxpc0mek" >&2
    cp -f  "${TCDIST_DIR}"/configs/default_setup_sh_config_arm64_imx8qxpc0mek "${TCDIST_OUTPUT:?}/${TCDIST_SETUP_SH_CONFIG}"
}


# Returns 0 if function exists, 1 if not
function Fn_exists {
    if [ "$(LC_ALL=C type -t "$1")" == "function" ]; then
        return 0
    else
        echo "$1: Unknown function" >&2
        return 1
    fi
}

# Calculates actual number of bytes from strings like '4G' and '23M' plain numbers are sectors (512 bytes)
function Actual_value {
    local lch

    lch="${1: -1}"
    case "$lch" in
    G)
        echo "$((${1:0:-1}*1024*1024*1024))"
    ;;
    M)
        echo "$((${1:0:-1}*1024*1024))"
    ;;
    0|1|2|3|4|5|6|7|8|9)
        echo "$((${1}*512))"
    ;;
    *)
        echo "0"
    ;;
    esac
}

# Trims off whitespace from start and end of a string
function Trim {
    local str

    str="$*"

    # remove whitespace from start
    str="${str#"${str%%[![:space:]]*}"}"

    # remove whitespace from end
    str="${str%"${str##*[![:space:]]}"}"

    printf '%s' "$str"
}

# Slightly safer recursive deletion
# If second parameter is 'sudo' root user is used to remove files
function Safer_rmrf {
    local rmd

    # Sanity check the path, just in case
    rmd="$(Sanity_check "$1" ne)"
    if [  "$2" == "sudo" ]; then
        # Check that we actually have something to delete before using sudo
        if [ -e "${rmd:?}" ]; then
            sudo rm -rf "${rmd:?}"
        fi
    else
        rm -rf "${rmd:?}"
    fi
}

# Remove files and directories listed in .gitignores
# Disable complaints about arguments they are optional here
# shellcheck disable=SC2120
function Remove_ignores {
    local entry

    if [ -f .gitignore ]; then
        while IFS= read -r entry; do
            entry="$(Trim "$entry")"
            if [ -n "$entry" ] && [ "${entry:0:1}" != "#" ]; then
                Safer_rmrf "$entry" "$1"
            fi
        done < .gitignore
    fi
}

# Check proper number of parameters given
# First parameter is the number of parameters expected the rest are the parameters
# Negative number of parameters turns off empty parameter checking
function Check_params {
    local checkempty=1
    local i=0
    local expected
    local param

    expected="${1:?}"

    shift

    if [ "$expected" -lt 0 ]; then
        # check only the number of parameters, empty parameters allowed
        expected=$((-expected))
        checkempty=0
    fi

    if [ "$#" -lt "$expected" ]; then
        echo "${FUNCNAME[1]}: Invalid number of parameters (expected $expected got $#)" >&2
        exit 1
    fi

    if [ "$checkempty" == 1 ]; then
        for param in "$@"; do
            if [ "$i" -eq "$expected" ]; then
                # Only check up to expected number of parameters, extra parameters may be empty
                break
            fi
            if [ -z "$param" ]; then
                echo "${FUNCNAME[1]}: Empty parameters not allowed" >&2
                exit 1
            fi
            i=$((i + 1))
        done
    fi
}

function Check_sha {
    echo "Check_sha"
    # $1 is sha
    # $2 is file
    Check_params 2 "$@"
    echo "${1} *${2}" | shasum -a 256 --check -s --strict
    ok="$?"
    echo "val: <$ok>"
    if [ "$ok" == "0" ]; then
        echo 1 > shaok
    fi
    echo "Check_sha done"
}

function Download {
    Check_params 3 "$@"

    Download_artifactory_binary "$1" "$2" "$3" 0
}

function Download_artifactory_binary {
    local download_url
    local destdir
    local filename
    local tmpoutput
    local extra_options
    local from_artifactory

    echo "Download_artifactory_binary"

    Check_params 3 "$@"
    download_url="$1"
    destdir="$2"
    filename="$3"
    tmpoutput="${destdir}/${filename}"
    from_artifactory="${4}"

    if [ -n "${TCDIST_DL_CACHE_DIR}" ]; then
        tmpoutput="${TCDIST_DL_CACHE_DIR}/${filename}"
        mkdir -p "${TCDIST_DL_CACHE_DIR}"
    fi

    if [ ! -f "${TCDIST_DL_CACHE_DIR}/${filename}" ] || [ -z "${TCDIST_DL_CACHE_DIR}" ] ; then
        if [ "${from_artifactory}" != "0" ]; then
            extra_options="-k -H X-JFrog-Art-Api:${TCDIST_ARTIFACTORY_API_KEY:?}"
        fi
        # extra_options contains options separated with spaces, so it is purposefully unquoted
        # shellcheck disable=SC2086
        curl ${extra_options} -L "${download_url}" -o "${tmpoutput}"
    fi

    if [ -n "${TCDIST_DL_CACHE_DIR}" ]; then
        cp "${TCDIST_DL_CACHE_DIR}/${filename}" "${destdir}/${filename}"
    fi

    echo "Download_artifactory_binary done"
}

# Sanity_check function will return the clean path or exit with an error
# if second argument is given, path does not need to exist
# usage example: CLEANPATH="$(Sanity_check <path to check> [non_existing])"
#   on error an error message is printed to stderr and CLEANPATH is empty and return value is nonzero
#   on success CLEANPATH is the cleaned up path to <path to check> and return value is zero
function Sanity_check {
    local tpath

    set +e

    if [ -z "$2" ]; then
        tpath="$(realpath -e "$1" 2>/dev/null)"
    else
        tpath="$(realpath -m "$1" 2>/dev/null)"
    fi

    # Explicitly allowed paths
    case "$tpath" in
    /usr/src/*) # For docker environment this needs to be allowed
        echo "$tpath"
        exit 0
    ;;
    *)
        # Do nothing
    ;;
    esac

    # Denied paths
    case "$tpath" in
    /bin*|/boot*|/dev*|/etc*|/lib*|/opt*|/proc*|/run*|/sbin*|/snap*|/sys*|/usr*|/var*|/home)
        echo "Will not touch host special directories" >&2
        exit 6
        ;;
    /)
        echo "Will not touch host root directory" >&2
        exit 2
        ;;
    "")
        echo "Path does not exist" >&2
        exit 4
        ;;
    "$HOME")
        echo "Will not touch user home directory" >&2
        exit 5
        ;;
    *)  # Path allowed
        echo "$tpath"
        exit 0
        ;;
    esac
}

# Checks if we are running in docker or not from script dir
function In_docker {
    if [ "$HDIR" == "/usr/src" ]; then
        return 0;
    fi
    return 1
}

# Checks scripts with shellcheck and bashate
function Shellcheck_bashate {
    local sc
    local bh
    set +e

    shellcheck "$@"
    sc=$?
    # Ignore "E006 Line too long" errors
    bashate -i E006 "$@"
    bh=$?

    if [ "$sc" -eq 0 ] && [ "$bh" -eq 0 ]; then
        echo "Nothing to complain" >&2
    else
        echo "Problems found" >&2
    fi

    return $((sc+bh))
}

# Fetches all branches from remote repo and makes them track remote branches
function Fetch_all {
    local dir
    local outp
    local remote

    dir="$1"

    # If directory not given, use original current directory
    if [ -z "$dir" ]; then
        dir="$OPWD"
        if [ -z "$dir" ]; then
            # If OPWD is not set, something is wrong
            echo "OPWD is not set, did you run fetch_all via setup.sh?" >&2
            return 1
        fi
    fi

    pushd "$dir" > /dev/null

    outp="$(git branch -r | grep -v '\->')"
    while read -r remote; do
        # Try to create matching branch
        if ! git branch --track "${remote#origin/}" "$remote" 2> /dev/null; then
            # If failed, assume branch exists, so make sure it tracks branch from origin
            git branch --set-upstream-to="$remote" "${remote#origin/}"
        fi
    done <<< "$outp"

    # Fetch all branches
    git fetch --all

    popd > /dev/null
}

# Just run make (with currently loaded configuration)
function Make {
    make -C "$OPWD" "$@"
}

# Finds first argument in the following list of arguments
# Can be used e.g. to get index of an element in an array
function Index_of {
    local i=0
    local j
    local elm

    elm="$1"
    shift

    for j in "$@"; do
        if [ "$elm" == "$j" ]; then
            echo "$i"
            return 0
        fi
        i=$((i+1))
    done
}

# Escapes given parameters to a string
function Escape {
    local a

    printf "%q" "$1"
    shift

    for a in "$@"; do
        printf " %q" "$a"
    done

    printf "\n"
}

# Runs a command in bash or opens a shell (With configuration loaded in environment)
function Bash {
    cd "$OPWD"
    if [ $# -gt 0 ]; then
        bash -c "$(Escape "$@")"
    else
        bash --init-file <(echo ". \"$HOME/.bashrc\";echo TCDIST shell")
    fi
}
