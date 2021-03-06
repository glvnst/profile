#!/bin/bash
# trying to make this stuff work with POSIX shell as much as possible

#
# plumbing
#

_ifndef() {
  eval "[ -n \"\$$1\" ]" || export "$1=$2"
}

_import() {
  # shellcheck source=/dev/null
  [ -f "$1" ] && IMPORT=1 . "$1"
}

_isfunc() {
  [ "$(type -t "$1")" = "function" ]
  # here's some posix-compatible hackery i tested, but its ugly.
  # _raw_type="$(type "$1")"
  # _type_first_line="${_raw_type%%[!a-zA-Z0-9_\ ]*}"
  # _type_last_word="${_type_first_line##* }"
  # [ "$_type_last_word" = "function" ]
}

_print() {
  printf '%s\n' "$*"
}

_run() {
  "$@"
}

_printrun() {
  _print "$@"
  _run "$@"
}

warn() {
  printf '%s %s\n' "$(date '+%FT%T')" "$*" >&2
}

die() {
  warn "$* EXITING"
  exit 1
}

#
# shell functions
#

if ! _isfunc tprint; then
  tprint() {
    # Usage: tprint [-p|-n] [-d] spec message [...]
    # spec is one or more dash-separated keywords such as
    # bright-underscore-magenta-bgblue
    # messge is the message to print
    # additional arguments will be concatenated into the message

    # arg parse
    while getopts "dnp" _opt; do
      case "$_opt" in
        'p')
          _output_mode='bash-prompt'
          ;;

        'n')
          _output_mode='no-newline'
          ;;

        'd')
          _tprint_debug='1'
          ;;

        *)
          warn "tprint: Unknown option ${_opt} IGNORING"
      esac
    done
    shift $(( OPTIND - 1 ))
    _spec="$1"; shift
    _message="$*"

    # init
    _term_codes=''

    # spec parse
    _old_IFS="$IFS"
    IFS="-"
    for _keyword_item in \
      'reset:0' \
      'bright:1' \
      'dim:2' \
      'standout:3' \
      'underscore:4' \
      'blink:5' \
      'reverse:6' \
      'black:30' \
      'red:31' \
      'green:32' \
      'yellow:33' \
      'blue:34' \
      'magenta:35' \
      'cyan:36' \
      'white:37' \
      'default:38' \
      'fgblack:30' \
      'fgred:31' \
      'fggreen:32' \
      'fgyellow:33' \
      'fgblue:34' \
      'fgmagenta:35' \
      'fgcyan:36' \
      'fgwhite:37' \
      'fgdefault:38' \
      'bgblack:40' \
      'bgred:41' \
      'bggreen:42' \
      'bgyellow:43' \
      'bgblue:44' \
      'bgmagenta:45' \
      'bgcyan:46' \
      'bgwhite:47' \
      'bgdefault:48' \
    ; do
      _keyword="${_keyword_item%%:*}"
      _code="${_keyword_item##*:}"
      # search the entire spec for this keyword and add it if it exists
      for _substr in $_spec; do
        [ "$_substr" = "$_keyword" ] && _term_codes="${_term_codes}${_code};"
      done
    done
    IFS="$_old_IFS"

    # strip the trailing ; if needed
    _term_codes="${_term_codes%%;}"

    [ -n "$_tprint_debug" ] && printf "term codes: %s\n" "$_term_codes" >&2

    # print
    if [ "$_output_mode" = "bash-prompt" ]; then
      printf '\[\e[%sm\]%s\[\e[0m\]' "$_term_codes" "$_message"
    else
      printf '\e[%sm%s\e[0m' "$_term_codes" "$_message"
      [ "$_output_mode" != "no-newline" ] && printf '\n'
    fi

    # it is critical to unset OPTIND here otherwise things will go Trump
    unset \
      _code \
      _fmt \
      _keyword \
      _keyword_item \
      _message \
      _old_IFS \
      _opt \
      _output_mode \
      _spec \
      _term_codes \
      _tprint_debug \
      OPTIND
  }
fi

if ! _isfunc cdwd; then
  cdwd() {
    # cdwd: cd to the current working directory
    #
    # the wd can be deleted by automation, cdwd gets you back to what remains of it
    # nobody@example.com:/Users/nobody $ mkdir -p one/two/three && cd one/two/three/
    #
    # now to pull the rug out from under our feet...
    # nobody@example.com:/Users/nobody/one/two/three $ (cd ~/one && rm -r two)
    # nobody@example.com:/Users/nobody/one/two/three $ pwd
    # /Users/nobody/one/two/three
    # nobody@example.com:/Users/nobody/one/two/three $ ls ~/one
    # nobody@example.com:/Users/nobody/one/two/three $ cdwd
    # nobody@example.com:/Users/nobody/one $ pwd
    # /Users/nobody/one

    if [ -n "$1" ]; then
      cd -- "$1"   2>/dev/null || cdwd "$(dirname "$1")"
    else
      cd -- "$PWD" 2>/dev/null || cdwd "$(dirname "$PWD")"
    fi
  }
fi

if ! _isfunc chop; then
   chop() {
      # this is a shell function instead of an alias so that $COLUMNS is
      # evaluated at runtime, so a changing window width is supported
      expand | cut -c "1-${COLUMNS}"
   }
fi

if ! _isfunc readcert; then
  readcert() {
    if [ -n "$*" ]; then
      _action="_printrun"
    else
      warn "need a path to a cert to read/dump"
      _action="_print"
    fi

    $_action openssl x509 -text -issuer -subject -dates -hash -fingerprint -in "$@"

    unset _action
  }
fi

if ! _isfunc dumpcert; then
  dumpcert() {
    readcert "$@"
  }
fi

if ! _isfunc fmt_duration; then
  fmt_duration() {
    # documentation repeated here for copy/paste into other scripts
    # takes a number of seconds and prints it in years, hours, minutes, seconds
    #
    # for example:
    #   fmt_duration 35000000
    # yields:
    #   1 year, 39 days, 20 hours, 13 minutes, 20 seconds
    #
    # Note: by default 1 year is treated as 365.25 days to account for leap years
    #
    # You may optionally specify the labeled increments to use when formatting
    # the duration. Use "singular/plural:seconds" for each increment. For example
    # if you only want duration specified in days and hours use the increments
    # day/days:86400 hour/hours:3600.
    #
    # The complete example call:
    #   fmt_duration 1216567 day/days:86400 hour/hours:3600
    # yields:
    #   14 days, 1 hour
    #
    # This function makes heavy use of POSIX shell Parameter Expansion for
    # string manipulations, see:
    # https://pubs.opengroup.org/onlinepubs/009695399/utilities/xcu_chap02.html

    _seconds=${1:-0}; shift
    _labeled_increments=${*:-'year/years:31557600' \
                            'day/days:86400' \
                            'hour/hours:3600' \
                            'minute/minutes:60' \
                            'second/seconds:1'}
    _result=""

    for _increment in $_labeled_increments; do
      _labels="${_increment%%:*}"
      _increment="${_increment##*:}"

      _singular_label="${_labels%%/*}"
      _plural_label="${_labels##*/}"

      if [ "$_seconds" -ge "$_increment" ]; then
        _quantity=$((_seconds / _increment))
        if [ "$_quantity" -eq 1 ]; then
          _label="$_singular_label"
        else
          _label="$_plural_label"
        fi
        _seconds=$(( _seconds - (_quantity * _increment) ))
        _result="${_result}, ${_quantity} ${_label}"
      fi
    done

    if [ -z "$_result" ]; then
      _result="0 ${_plural_label}"
    fi

    printf '%s\n' "${_result#*, }"

    unset _increment _label _labeled_increments _labels _plural_label \
      _quantity _result _seconds _singular_label
  }
fi

if ! _isfunc source_find; then
  source_find() {
    _search_dir="$1"; shift
    if [ -z "$_search_dir" ]; then
      warn 'source_find: requires a search directory argument cannot continue'
      return 1
    fi
    if [ -z "$*" ]; then
      warn "source_find: requires find arguments (for example: -name '*.py')" \
        "cannot continue"
      return 1
    fi

    # temp redirecting outputs so i can grep-out some stderr output
    # via https://unix.stackexchange.com/a/3540
    { find "$_search_dir" \
      -not \
      '(' '(' \
        -name 'node_modules' \
        -or -name '.DS_Store' \
        -or -name 'vendor' \
        -or -name '.git' \
        -or -name '.npm' \
        -or -name 'venv' \
        -or -name 'site-packages' \
        -or -name '.idea' \
        -or -name 'restore' \
      ')' -prune ')' \
      -type f \
      "$@" \
      -print \
      2>&1 1>&3 \
      | grep -vF 'Operation not permitted'; \
    } 3>&1
  }
fi

if ! _isfunc dockerfilegrep; then
  dockerfilegrep() {
    if [ -z "$*" ]; then
      warn "grep arguments required. cannot continue"
      return 1
    fi
    source_find "." \
      -name 'Dockerfile' \
    | tr '\n' '\0' \
    | xargs -0 grep "$@"
  }
fi

if ! _isfunc composefilegrep; then
  composefilegrep() {
    if [ -z "$*" ]; then
      warn "grep arguments required. cannot continue"
      return 1
    fi
    source_find "." \
      '(' \
        -name 'docker-compose.yml' \
        -or -name 'docker-compose.*.yml' \
      ')' \
    | tr '\n' '\0' \
    | xargs -0 grep "$@"
  }
fi

if ! _isfunc pygrep; then
  pygrep() {
    if [ -z "$*" ]; then
      warn "grep arguments required. cannot continue"
      return 1
    fi
    source_find '.' \
      -name '*.py' \
    | tr '\n' '\0' \
    | xargs -0 grep "$@"
  }
fi

if ! _isfunc shgrep; then
  shgrep() {
    if [ -z "$*" ]; then
      warn "grep arguments required. cannot continue"
      return 1
    fi
    source_find '.' \
      -name '*.sh' \
    | tr '\n' '\0' \
    | xargs -0 grep "$@"
  }
fi

#
# prompts and window titles
#

# Setup the shell window updates
if ! _isfunc pre_prompt; then
  pre_prompt() {
    _LAST_RUNTIME=$((SECONDS - _PRE_EXEC_SECONDS))

    # Update terminal window title
    printf '\e]0;%s\a' "${USER}@${HOSTNAME}:${PWD}"

    # If a command took more than ten seconds, report the time
    [ "$_LAST_RUNTIME" -gt 5 ] \
      && tprint dim-yellow-standout "# completed in $(fmt_duration $_LAST_RUNTIME)"

    # Enable the pre_exec command
    _PRE_EXEC_ENABLE=1
  }
fi

if ! _isfunc pre_exec; then
  pre_exec() {
    # If we aren't "enabled", then we short-circuit
    [ -n "$_PRE_EXEC_ENABLE" ] || return

    # Update terminal window title
    _last_command="$(history 1)"
    _last_command="${_last_command##*:}"
    _last_command="${_last_command%%$'\n'*}"
    printf '\e]0;%s\a' "${USER}@${HOSTNAME}:${PWD} # ${_last_command}"

    # Disable the pre_exec function until the next prompt
    # We do this because the debug trap gets caled before
    # the command and after it
    _PRE_EXEC_ENABLE=""
    _PRE_EXEC_SECONDS=$SECONDS
   }
fi

main() {
  #
  # environment
  #

  # special portable non-fancy handling for important values
  export PATH="$HOME/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin:/usr/libexec"
  [ -n "$USER" ] || USER="$(id -un)"
  [ -n "$HOSTNAME" ] || HOSTNAME="$(hostname)"

  # make our selections but still allow the imported files below to have control
  unset \
    EDITOR \
    HISTFILE \
    HISTFILESIZE \
    LESSHISTFILE \
    LESSHISTSIZE \
    PAGER \
    PROMPT_COMMAND \
    PS1 \
    PS2

  _import ~/.bash_local
  _import ~/.profile_local

  _ifndef EDITOR "nano"
  _ifndef FTP_PASSIVE_MODE "1"
  _ifndef HISTFILESIZE "0"
  _ifndef HISTTIMEFORMAT '%FT%T : '
  _ifndef LESSHISTFILE "/dev/null"
  _ifndef LESSHISTSIZE "0"
  _ifndef PAGER "less"
  _ifndef PS1 "$(
    tprint -p dim-underscore '#'
    tprint -p standout-yellow " \$? "
    if [ "$(id -u)" = "0" ]; then
      tprint -p red "\u"
    else
      tprint -p standout-green "\u"
    fi
    tprint -p dim '@'
    tprint -p cyan "\${HOSTNAME}"
    tprint -p dim ':'
    tprint -p standout-white "\${PWD}"
    printf ' '
    tprint -p bright-red '>'
  ) "
  _ifndef PS2 "\e[33m " # just color the ps2 text, better for copy-paste

  # os-specific config
  case "$OSTYPE" in
    darwin*)
      [ -n "$NOCOLOR" ] || export CLICOLOR=1
      export SHELL_SESSION_HISTORY=0
      stty erase '^H'

      ;;

    linux*)
      true
      ;;

    *)
      true
      ;;
  esac

  _ifndef LANG "en_US.UTF-8"
  _ifndef LC_ALL "en_US.UTF-8"
  _ifndef TZ "Europe/Brussels"

  [ -n "$COLUMNS" ] && export COLUMNS

  #
  # shell vars
  #

  # make terminal window size changes work better
  shopt -s checkwinsize 2>/dev/null || warn "warn shopt cmd failed"

  # enable Control-D to terminate the shell
  unset ignoreeof

  #
  # aliases
  #

  if [ "${PAGER##*/}" = "less" ] ; then
    alias more="less -RiM"
    alias less="less -RiM"
  fi

  alias \
    "..=cd .." \
    "...=cd ../.." \
    "....=cd ../../.." \
    ".....=cd ../../../.." \
    "dl=cd ~/Downloads/" \
    "dt=cd ~/Desktop/" \
    "gits=git status" \
    "lg=ll | grep -i" \
    "ll=ls -l -a " \
    "ls=ls -F -r -t -h" \
    "newer=find . -newerct" \
    "unixdate=date '+%s'" \
    "unixtime=unixdate" \
    "sl=ls" \

  _PRE_EXEC_SECONDS=$SECONDS
  _PRE_EXEC_ENABLE=""
  PROMPT_COMMAND="pre_prompt"
  trap pre_exec DEBUG

  unset main
}

[ -n "$IMPORT" ] || main "$@"
