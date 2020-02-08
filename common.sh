#
# Copyright 2019-2020 DJANTA, LLC (https://www.djanta.io)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed toMap in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

PROGNAME=${0##*/}
datestamp=$(date +%Y%m%d%H%M%S)
DEV_MODE=0

argv0=$(echo "$0" | sed -e 's,\\,/,g')
basedir=$(dirname "$(readlink "$0" || echo "$argv0")")

case "$(uname -s)" in
  Linux) basedir=$(dirname "$(readlink -f "$0" || echo "$argv0")");;
  *CYGWIN*) basedir=`cygpath -w "$basedir"`;;
esac

ERROR_BOLD="\e[1;31m"
ERROR_NORMAL="\e[0;31m"
DEBUG_BOLD="\e[1;35m"
DEBUG_NORMAL="\e[0;35m"
RESET="\e[00m"

RED="\033[31;01m"
CYAN="\033[36;01m"
YELLOW="\033[33;01m"
NORMAL="\033[00m"

if [[ -n "$COLORS" ]] && [[ ! "$COLORS" =~ ^(always|yes|true|1)$ ]]; then
  unset ERROR_BOLD
  unset ERROR_NORMAL
  unset DEBUG_BOLD
  unset DEBUG_NORMAL
  unset RESET

  unset RED="\\e[0;31m"
  unset CYAN="\\e[0;36m"
  unset YELLOW="\\e[0;33m"
  unset NORMAL="\\e[0;0m"
fi

colored() {
  while [ "$1" ]; do
    case "$1" in
      -normal|--normal)     color="$NORMAL" ;;
      -black|--black)       color="\033[30;01m" ;;
      -red|--red)           color="$RED" ;;
      -green|--green)       color="\033[32;01m" ;;
      -yellow|--yellow)     color="$YELLOW" ;;
      -blue|--blue)         color="\033[34;01m" ;;
      -magenta|--magenta)   color="\033[35;01m" ;;
      -cyan|--cyan)         color="$CYAN" ;;
      -white|--white)       color="\033[37;01m" ;;
      -n)             one_line=1;   shift ; continue ;;
      *)              echo -n "$1"; shift ; continue ;;
    esac
    shift
      echo -en "$color"
      echo -en "$1"
      echo -en "\033[00m"
      shift
  done
  if [ ! $one_line ]; then
    echo
  fi
}

clean_up() { # Perform pre-exit housekeeping
  return
}

error_exit() {
  echo -e "${PROGNAME}: ${1:-"Unknown Error"}" >&2
  clean_up
  exit ${2:-1}
}

graceful_exit() {
  clean_up
  exit
}

signal_exit() { # Handle trapped signals
  case $1 in
    INT)
      error_exit "Program interrupted by user" ;;
    TERM)
      echo -e "\n$PROGNAME: Program terminated" >&2
      graceful_exit ;;
    *)
      error_exit "$PROGNAME: Terminating on unknown signal" ;;
  esac
}

die() {
    ret=${1}
    shift
    printf "${CYAN}${@}${NORMAL}\n" 1>&2
    exit ${ret}
}

##
# Extract the given parameter from the command line argument and assigne to the local given variable
# e.g: argv support '--support' ${@:1:$#}
##
#argv() {
#  arg_name="${1}"
#  for i in ${@:1:$#}; do
#    PARAM=`echo $i | awk -F= '{print $1}'`
#    VALUE=`echo $i | awk -F= '{print $2}'`
#    case ${PARAM} in
#    "$arg_name" )
#      echo ${VALUE}
#      #eval "$1=\"${VALUE}\""  # Assign new value.
#      break
#    ;;
#    esac
#  done
#}

# shellcheck disable=SC2006
normalize() {
  local version=$1
  result=`echo "${version}" | awk -F. -v OFS=. 'NF==1{print ++$NF}; NF>1{if(length($NF+1)>length($NF))$(NF-1)++; $NF=sprintf("%0*d", length($NF), ($NF+1)%(10^length($NF))); print}'`
  echo "${result}"
}

#value(){
# shellcheck disable=SC2006
argv() {
  arg_name="${2}"
  for i in "${@:3:$#}"; do
    PARAM=`echo "$i" | awk -F= '{print $1}'`
    VALUE=`echo "$i" | awk -F= '{print $2}'`
    case ${PARAM} in
    "$arg_name")
      #value_=${i}
      eval "$1=\"${VALUE}\""  # Assign new value.
    ;;
    esac
  done
}

# shellcheck disable=SC2006
exists() {
  arg_name="${2}"
  for i in "${@:3:$#}"; do
    PARAM=`echo "$i" | awk -F= '{print $1}'`
    VALUE=`echo "$i" | awk -F= '{print $2}'`
    case ${PARAM} in
    "$arg_name")
      eval "$1=true"  # Assign new value.
    ;;
    esac
  done
}

export_properties() {
  if [ "$#" -eq 0 ]; then
    error_exit "Insuffisant function argument. At least the target proprerties file must be specified."
  elif [ ! -f "${1}" ]; then
   error_exit "The given file: (${1}0 must be an existing file."
  fi

  # read file line by line and populate the array. Field separator is "="
  while IFS='=' read -r k v; do
    export "$k"="$v"
  done < ${1}
}

####
# Check whether the given command has existed
###
command_exists () {
  command -v "$1" >/dev/null 2>&1;
}

##
# Return the given or the origin git remote url
##
# shellcheck disable=SC2120
# shellcheck disable=SC2046
# shellcheck disable=SC2005
get_git_url() {
  #git config --get remote.${1:-origin}.url
  #git ls-remote --get-url [REMOTE]
  echo $(git remote get-url "${1:-origin}")
}

git_current_branch() {
  echo $(git branch | grep \* | cut -d ' ' -f2)
}

##
# Check whether if the given tag exist from the current .git directory
# shellcheck disable=SC2046
# shellcheck disable=SC2005
##
is_tag_exists() {
  if [ "$#" -eq 0 ]; then
    error_exit "Insuffisant command argument. At least the expected git tag name is expected."
  else
    url=$(get_git_url)
    echo $(git ls-remote --heads --tags "${url}" | grep -E "refs/(heads|tags)/${1}")
  fi
}

# We need to be on a branch for release:perform to be able to create commits, and we want that branch to be master.
# But we also want to make sure that we build and release exactly the tagged version, so we verify that the remote
# master is where our tag is.
safe_checkout() {
  local branch="${1:-master}"
  git checkout -B "${branch}"
  git fetch origin "${branch}":origin/"${branch}"
  commit_local="$(git show --pretty='format:%H' "${branch}")"
  commit_remote="$(git show --pretty='format:%H' origin/"${branch}")"
  if [[ "$commit_local" != "$commit_remote" ]]; then
    echo "${branch} on remote 'origin' has commits since the version under release, aborting"
    exit 1
  fi
}

is_master_branch() {
  if [[ $(git branch | grep \* | cut -d ' ' -f2) = master ]]; then
    #echo "[Publishing] branch is master"
    return 0
  else
    #echo "[Not Publishing] branch is not master"
    return 1
  fi
}

print_project_version() {
  ./mvnw help:evaluate -N -Dexpression=project.version|sed -n '/^[0-9]/p'
}

is_release_commit() {
  project_version="$(print_project_version)"
  if [[ "$project_version" =~ ^[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+$ ]]; then
    echo "Build started by release commit $project_version. Will synchronize to maven central."
    return 0
  else
    return 1
  fi
}

javadoc_to_gh_pages() {
  version="$(print_project_version)"
  rm -rf javadoc-builddir
  builddir="javadoc-builddir/$version"

  # Collect javadoc for all modules
  # shellcheck disable=SC2044
  for jar in $(find . -name "*${version}-javadoc.jar"); do
    # shellcheck disable=SC2001
    module="$(echo "$jar" | sed "s~.*/\(.*\)-${version}-javadoc.jar~\1~")"
    this_builddir="$builddir/$module"
    if [[ -d "$this_builddir" ]]; then
        # Skip modules we've already processed.
        # We may find multiple instances of the same javadoc jar because of, for instance,
        # integration tests copying jars around.
        continue
    fi
    mkdir -p "$this_builddir"
    unzip "$jar" -d "$this_builddir"
    # Build a simple module-level index
    echo "<li><a href=\"${module}/index.html\">${module}</a></li>" >> "${builddir}/index.html"
  done

  # Update gh-pages
  git fetch origin gh-pages:gh-pages
  git checkout gh-pages
  rm -rf "$version"
  mv "javadoc-builddir/$version" ./
  rm -rf "javadoc-builddir"

  # Update simple version-level index
  if ! grep "$version" index.html 2>/dev/null; then
    echo "<li><a href=\"${version}/index.html\">${version}</a></li>" >> index.html
  fi

  # Ensure links are ordered by versions, latest on top
  sort -rV index.html > index.html.sorted
  mv index.html.sorted index.html

  git add "$version"
  git add index.html
  git commit -m "Automatically updated javadocs for $version"
  git push origin gh-pages
}