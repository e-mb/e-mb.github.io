#!/bin/sh

PROGRESS_CURR=0
PROGRESS_TOTAL=130                         

# This file was autowritten by rmlint
# rmlint was executed from: /home/muellerer/Projects/eric-mb.github.io/
# Your command line was: rmlint

RMLINT_BINARY="/usr/bin/rmlint"

# Only use sudo if we're not root yet:
# (See: https://github.com/sahib/rmlint/issues/27://github.com/sahib/rmlint/issues/271)
SUDO_COMMAND="sudo"
if [ "$(id -u)" -eq "0" ]
then
  SUDO_COMMAND=""
fi

USER='muellerer'
GROUP='muellerer'

# Set to true on -n
DO_DRY_RUN=

# Set to true on -p
DO_PARANOID_CHECK=

# Set to true on -r
DO_CLONE_READONLY=

# Set to true on -q
DO_SHOW_PROGRESS=true

# Set to true on -c
DO_DELETE_EMPTY_DIRS=

# Set to true on -k
DO_KEEP_DIR_TIMESTAMPS=

# Set to true on -i
DO_ASK_BEFORE_DELETE=

##################################
# GENERAL LINT HANDLER FUNCTIONS #
##################################

COL_RED='[0;31m'
COL_BLUE='[1;34m'
COL_GREEN='[0;32m'
COL_YELLOW='[0;33m'
COL_RESET='[0m'

print_progress_prefix() {
    if [ -n "$DO_SHOW_PROGRESS" ]; then
        PROGRESS_PERC=0
        if [ $((PROGRESS_TOTAL)) -gt 0 ]; then
            PROGRESS_PERC=$((PROGRESS_CURR * 100 / PROGRESS_TOTAL))
        fi
        printf '%s[%3d%%]%s ' "${COL_BLUE}" "$PROGRESS_PERC" "${COL_RESET}"
        if [ $# -eq "1" ]; then
            PROGRESS_CURR=$((PROGRESS_CURR+$1))
        else
            PROGRESS_CURR=$((PROGRESS_CURR+1))
        fi
    fi
}

handle_emptyfile() {
    print_progress_prefix
    echo "${COL_GREEN}Deleting empty file:${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        rm -f "$1"
    fi
}

handle_emptydir() {
    print_progress_prefix
    echo "${COL_GREEN}Deleting empty directory: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        rmdir "$1"
    fi
}

handle_bad_symlink() {
    print_progress_prefix
    echo "${COL_GREEN} Deleting symlink pointing nowhere: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        rm -f "$1"
    fi
}

handle_unstripped_binary() {
    print_progress_prefix
    echo "${COL_GREEN} Stripping debug symbols of: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        strip -s "$1"
    fi
}

handle_bad_user_id() {
    print_progress_prefix
    echo "${COL_GREEN}chown ${USER}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chown "$USER" "$1"
    fi
}

handle_bad_group_id() {
    print_progress_prefix
    echo "${COL_GREEN}chgrp ${GROUP}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chgrp "$GROUP" "$1"
    fi
}

handle_bad_user_and_group_id() {
    print_progress_prefix
    echo "${COL_GREEN}chown ${USER}:${GROUP}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chown "$USER:$GROUP" "$1"
    fi
}

###############################
# DUPLICATE HANDLER FUNCTIONS #
###############################

check_for_equality() {
    if [ -f "$1" ]; then
        # Use the more lightweight builtin `cmp` for regular files:
        cmp -s "$1" "$2"
        echo $?
    else
        # Fallback to `rmlint --equal` for directories:
        "$RMLINT_BINARY" -p --equal  "$1" "$2"
        echo $?
    fi
}

original_check() {
    if [ ! -e "$2" ]; then
        echo "${COL_RED}^^^^^^ Error: original has disappeared - cancelling.....${COL_RESET}"
        return 1
    fi

    if [ ! -e "$1" ]; then
        echo "${COL_RED}^^^^^^ Error: duplicate has disappeared - cancelling.....${COL_RESET}"
        return 1
    fi

    # Check they are not the exact same file (hardlinks allowed):
    if [ "$1" = "$2" ]; then
        echo "${COL_RED}^^^^^^ Error: original and duplicate point to the *same* path - cancelling.....${COL_RESET}"
        return 1
    fi

    # Do double-check if requested:
    if [ -z "$DO_PARANOID_CHECK" ]; then
        return 0
    else
        if [ "$(check_for_equality "$1" "$2")" -ne "0" ]; then
            echo "${COL_RED}^^^^^^ Error: files no longer identical - cancelling.....${COL_RESET}"
            return 1
        fi
    fi
}

cp_symlink() {
    print_progress_prefix
    echo "${COL_YELLOW}Symlinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            # replace duplicate with symlink
            rm -rf "$1"
            ln -s "$2" "$1"
            # make the symlink's mtime the same as the original
            touch -mr "$2" -h "$1"
        fi
    fi
}

cp_hardlink() {
    if [ -d "$1" ]; then
        # for duplicate dir's, can't hardlink so use symlink
        cp_symlink "$@"
        return $?
    fi
    print_progress_prefix
    echo "${COL_YELLOW}Hardlinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            # replace duplicate with hardlink
            rm -rf "$1"
            ln "$2" "$1"
        fi
    fi
}

cp_reflink() {
    if [ -d "$1" ]; then
        # for duplicate dir's, can't clone so use symlink
        cp_symlink "$@"
        return $?
    fi
    print_progress_prefix
    # reflink $1 to $2's data, preserving $1's  mtime
    echo "${COL_YELLOW}Reflinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            touch -mr "$1" "$0"
            if [ -d "$1" ]; then
                rm -rf "$1"
            fi
            cp --archive --reflink=always "$2" "$1"
            touch -mr "$0" "$1"
        fi
    fi
}

clone() {
    print_progress_prefix
    # clone $1 from $2's data
    # note: no original_check() call because rmlint --dedupe takes care of this
    echo "${COL_YELLOW}Cloning to: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        if [ -n "$DO_CLONE_READONLY" ]; then
            $SUDO_COMMAND $RMLINT_BINARY --dedupe  --dedupe-readonly "$2" "$1"
        else
            $RMLINT_BINARY --dedupe  "$2" "$1"
        fi
    fi
}

skip_hardlink() {
    print_progress_prefix
    echo "${COL_BLUE}Leaving as-is (already hardlinked to original): ${COL_RESET}$1"
}

skip_reflink() {
    print_progress_prefix
    echo "${COL_BLUE}Leaving as-is (already reflinked to original): ${COL_RESET}$1"
}

user_command() {
    print_progress_prefix

    echo "${COL_YELLOW}Executing user command: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        # You can define this function to do what you want:
        echo 'no user command defined.'
    fi
}

remove_cmd() {
    print_progress_prefix
    echo "${COL_YELLOW}Deleting: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            if [ -n "$DO_KEEP_DIR_TIMESTAMPS" ]; then
                touch -r "$(dirname "$1")" "$STAMPFILE"
            fi
            if [ -n "$DO_ASK_BEFORE_DELETE" ]; then
              rm -ri "$1"
            else
              rm -rf "$1"
            fi
            if [ -n "$DO_KEEP_DIR_TIMESTAMPS" ]; then
                # Swap back old directory timestamp:
                touch -r "$STAMPFILE" "$(dirname "$1")"
                rm "$STAMPFILE"
            fi

            if [ -n "$DO_DELETE_EMPTY_DIRS" ]; then
                DIR=$(dirname "$1")
                while [ ! "$(ls -A "$DIR")" ]; do
                    print_progress_prefix 0
                    echo "${COL_GREEN}Deleting resulting empty dir: ${COL_RESET}$DIR"
                    rmdir "$DIR"
                    DIR=$(dirname "$DIR")
                done
            fi
        fi
    fi
}

original_cmd() {
    print_progress_prefix
    echo "${COL_GREEN}Keeping:  ${COL_RESET}$1"
}

##################
# OPTION PARSING #
##################

ask() {
    cat << EOF

This script will delete certain files rmlint found.
It is highly advisable to view the script first!

Rmlint was executed in the following way:

   $ rmlint

Execute this script with -d to disable this informational message.
Type any string to continue; CTRL-C, Enter or CTRL-D to abort immediately
EOF
    read -r eof_check
    if [ -z "$eof_check" ]
    then
        # Count Ctrl-D and Enter as aborted too.
        echo "${COL_RED}Aborted on behalf of the user.${COL_RESET}"
        exit 1;
    fi
}

usage() {
    cat << EOF
usage: $0 OPTIONS

OPTIONS:

  -h   Show this message.
  -d   Do not ask before running.
  -x   Keep rmlint.sh; do not autodelete it.
  -p   Recheck that files are still identical before removing duplicates.
  -r   Allow deduplication of files on read-only btrfs snapshots. (requires sudo)
  -n   Do not perform any modifications, just print what would be done. (implies -d and -x)
  -c   Clean up empty directories while deleting duplicates.
  -q   Do not show progress.
  -k   Keep the timestamp of directories when removing duplicates.
  -i   Ask before deleting each file
EOF
}

DO_REMOVE=
DO_ASK=

while getopts "dhxnrpqcki" OPTION
do
  case $OPTION in
     h)
       usage
       exit 0
       ;;
     d)
       DO_ASK=false
       ;;
     x)
       DO_REMOVE=false
       ;;
     n)
       DO_DRY_RUN=true
       DO_REMOVE=false
       DO_ASK=false
       DO_ASK_BEFORE_DELETE=false
       ;;
     r)
       DO_CLONE_READONLY=true
       ;;
     p)
       DO_PARANOID_CHECK=true
       ;;
     c)
       DO_DELETE_EMPTY_DIRS=true
       ;;
     q)
       DO_SHOW_PROGRESS=
       ;;
     k)
       DO_KEEP_DIR_TIMESTAMPS=true
       STAMPFILE=$(mktemp 'rmlint.XXXXXXXX.stamp')
       ;;
     i)
       DO_ASK_BEFORE_DELETE=true
       ;;
     *)
       usage
       exit 1
  esac
done

if [ -z $DO_REMOVE ]
then
    echo "#${COL_YELLOW} ///${COL_RESET}This script will be deleted after it runs${COL_YELLOW}///${COL_RESET}"
fi

if [ -z $DO_ASK ]
then
  usage
  ask
fi

if [ -n "$DO_DRY_RUN" ]
then
    echo "#${COL_YELLOW} ////////////////////////////////////////////////////////////${COL_RESET}"
    echo "#${COL_YELLOW} /// ${COL_RESET} This is only a dry run; nothing will be modified! ${COL_YELLOW}///${COL_RESET}"
    echo "#${COL_YELLOW} ////////////////////////////////////////////////////////////${COL_RESET}"
fi

######### START OF AUTOGENERATED OUTPUT #########


original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/10-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/10-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/10-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/12-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/12-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/12-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/3-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/3-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/3-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/4-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/4-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/4-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/5-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/5-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/5-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/7-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/7-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/7-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/8-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/8-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/8-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/9-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/9-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/9-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/al-folio-preview-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/al-folio-preview-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/al-folio-preview-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/code-screenshot-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/code-screenshot-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/code-screenshot-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/distill-screenshot-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/distill-screenshot-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/distill-screenshot-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/math-screenshot-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/math-screenshot-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/math-screenshot-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/photos-screenshot-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/photos-screenshot-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/photos-screenshot-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/projects-screenshot-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/projects-screenshot-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/projects-screenshot-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/CONTRIBUTING.md' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/CONTRIBUTING.md' '/home/muellerer/Projects/eric-mb.github.io/CONTRIBUTING.md' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/publications-screenshot-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/publications-screenshot-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/publications-screenshot-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/Dockerfile' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/Dockerfile' '/home/muellerer/Projects/eric-mb.github.io/Dockerfile' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/LICENSE' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/LICENSE' '/home/muellerer/Projects/eric-mb.github.io/LICENSE' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/bibliography/2018-12-22-distill.bib' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/bibliography/2018-12-22-distill.bib' '/home/muellerer/Projects/eric-mb.github.io/assets/bibliography/2018-12-22-distill.bib' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/12.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/12.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/12.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/7.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/7.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/7.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/8.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/8.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/8.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/pagespeed.svg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/pagespeed.svg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/pagespeed.svg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/common.js' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/common.js' '/home/muellerer/Projects/eric-mb.github.io/assets/js/common.js' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/publication_preview/wave-mechanics.gif' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/publication_preview/wave-mechanics.gif' '/home/muellerer/Projects/eric-mb.github.io/assets/img/publication_preview/wave-mechanics.gif' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/copy_code.js' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/copy_code.js' '/home/muellerer/Projects/eric-mb.github.io/assets/js/copy_code.js' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/dark_mode.js' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/dark_mode.js' '/home/muellerer/Projects/eric-mb.github.io/assets/js/dark_mode.js' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/distillpub/overrides.js' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/distillpub/overrides.js' '/home/muellerer/Projects/eric-mb.github.io/assets/js/distillpub/overrides.js' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/masonry.js' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/masonry.js' '/home/muellerer/Projects/eric-mb.github.io/assets/js/masonry.js' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/theme.js' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/theme.js' '/home/muellerer/Projects/eric-mb.github.io/assets/js/theme.js' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/zoom.js' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/zoom.js' '/home/muellerer/Projects/eric-mb.github.io/assets/js/zoom.js' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/pdf/example_pdf.pdf' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/pdf/example_pdf.pdf' '/home/muellerer/Projects/eric-mb.github.io/assets/pdf/example_pdf.pdf' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/docker-compose.yml' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/docker-compose.yml' '/home/muellerer/Projects/eric-mb.github.io/docker-compose.yml' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/docker-local.yml' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/docker-local.yml' '/home/muellerer/Projects/eric-mb.github.io/docker-local.yml' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/1-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/1-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/1-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/11-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/11-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/11-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/6-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/6-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/6-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/2-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/2-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/2-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/README.md' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/README.md' '/home/muellerer/Projects/eric-mb.github.io/README.md' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/10.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/10.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/10.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/1.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/1.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/1.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/4.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/4.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/4.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/5.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/5.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/5.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/3.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/3.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/3.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/9.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/9.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/9.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/11.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/11.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/11.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/6.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/6.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/6.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/2.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/2.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/2.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/prof_pic-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/prof_pic-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/prof_pic-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/publication_preview/brownian-motion.gif' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/publication_preview/brownian-motion.gif' '/home/muellerer/Projects/eric-mb.github.io/assets/img/publication_preview/brownian-motion.gif' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/profile-800.webp' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/profile-1400.webp' '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/profile-800.webp' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/math-screenshot.png' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/math-screenshot.png' '/home/muellerer/Projects/eric-mb.github.io/assets/img/math-screenshot.png' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/code-screenshot.png' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/code-screenshot.png' '/home/muellerer/Projects/eric-mb.github.io/assets/img/code-screenshot.png' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/distillpub/template.v2.js' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/distillpub/template.v2.js' '/home/muellerer/Projects/eric-mb.github.io/assets/js/distillpub/template.v2.js' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/distill-screenshot.png' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/distill-screenshot.png' '/home/muellerer/Projects/eric-mb.github.io/assets/img/distill-screenshot.png' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/photos-screenshot.png' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/photos-screenshot.png' '/home/muellerer/Projects/eric-mb.github.io/assets/img/photos-screenshot.png' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/distillpub/template.v2.js.map' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/distillpub/template.v2.js.map' '/home/muellerer/Projects/eric-mb.github.io/assets/js/distillpub/template.v2.js.map' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/publications-screenshot.png' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/publications-screenshot.png' '/home/muellerer/Projects/eric-mb.github.io/assets/img/publications-screenshot.png' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/projects-screenshot.png' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/projects-screenshot.png' '/home/muellerer/Projects/eric-mb.github.io/assets/img/projects-screenshot.png' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/al-folio-preview.png' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/al-folio-preview.png' '/home/muellerer/Projects/eric-mb.github.io/assets/img/al-folio-preview.png' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/profile.png' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/profile.png' '/home/muellerer/Projects/eric-mb.github.io/assets/img/profile.png' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/distillpub/transforms.v2.js' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/distillpub/transforms.v2.js' '/home/muellerer/Projects/eric-mb.github.io/assets/js/distillpub/transforms.v2.js' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/js/distillpub/transforms.v2.js.map' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/js/distillpub/transforms.v2.js.map' '/home/muellerer/Projects/eric-mb.github.io/assets/js/distillpub/transforms.v2.js.map' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/img/prof_pic.jpg' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/img/prof_pic.jpg' '/home/muellerer/Projects/eric-mb.github.io/assets/img/prof_pic.jpg' # duplicate

original_cmd  '/home/muellerer/Projects/eric-mb.github.io/assets/plotly/demo.html' # original
remove_cmd    '/home/muellerer/Projects/eric-mb.github.io/_site/assets/plotly/demo.html' '/home/muellerer/Projects/eric-mb.github.io/assets/plotly/demo.html' # duplicate
                                               
                                               
                                               
######### END OF AUTOGENERATED OUTPUT #########
                                               
if [ $PROGRESS_CURR -le $PROGRESS_TOTAL ]; then
    print_progress_prefix                      
    echo "${COL_BLUE}Done!${COL_RESET}"      
fi                                             
                                               
if [ -z $DO_REMOVE ] && [ -z $DO_DRY_RUN ]     
then                                           
  echo "Deleting script " "$0"             
  rm -f '/home/muellerer/Projects/eric-mb.github.io/rmlint.sh';                                     
fi                                             
