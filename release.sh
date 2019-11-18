#!/usr/bin/env bash

#
# Copyright 2019 DJANTA, LLC (https://www.djanta.io)
#
# Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed toMap in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

argv0=$(echo "$0" | sed -e 's,\\,/,g')
basedir=$(dirname "$(readlink "$0" || echo "$argv0")")

case "$(uname -s)" in
  Linux) basedir=$(dirname "$(readlink -f "$0" || echo "$argv0")");;
  *CYGWIN*) basedir=`cygpath -w "$basedir"`;;
esac

# shellcheck disable=SC1090
source "${basedir}"/common.sh

if [[ "$#" -eq 0 ]] &&  [[ ! -f ".variables" ]]; then
  error_exit "Insuffisant command argument"
fi

# Load the pom version
#[ -f "pom.xml" ] && version=`./mvnw -o help:evaluate -N -Dexpression=project.version | sed -n '/^[0-9]/p'` || \
#    version="0.0.1-SNAPSHOT" # Set the default pom version to "0.0.1-SNAPSHOT"

#echo "[*] Version: ${version}"

# shellcheck disable=SC2006
increment() {
  local version=$1
  result=`echo "${version}" | awk -F. -v OFS=. 'NF==1{print ++$NF}; NF>1{if(length($NF+1)>length($NF))$(NF-1)++; $NF=sprintf("%0*d", length($NF), ($NF+1)%(10^length($NF))); print}'`
  echo "${result}-SNAPSHOT"
}

safe_checkout() {
  # We need to be on a branch for release:perform to be able to create commits, and we want that branch to be master.
  # But we also want to make sure that we build and release exactly the tagged version, so we verify that the remote
  # master is where our tag is.
  branch="${1:-master}"
  git checkout -B "${branch}"
  git fetch origin "${branch}":origin/"${branch}"
  commit_local="$(git show --pretty='format:%H' "${branch}")"
  commit_remote="$(git show --pretty='format:%H' origin/"${branch}")"
  if [[ "$commit_local" != "$commit_remote" ]]; then
    echo "${branch} on remote 'origin' has commits since the version under release, aborting"
    exit 1
  fi
}

update_release__() {
  if [[ -f .variables ]]; then
    colored --blue "Updating next release version in (.variables) file ..."
    sed -i "s/NEXT_RELEASE=${1}/NEXT_RELEASE=${2}/g" .variables
  fi
}

###
# Deploy the given profiles
# shellcheck disable=SC2116
##
__mvn_deploy__() {
  IFS=';' # hyphen (;) is set as delimiter
  read -ra ADDR <<< "${MVN_PROFILES:-}" # str is read into an array as tokens separated by IFS
  for i in "${ADDR[@]}"; do # access each element of array
    ./mvnw [ -n "${MVN_BASHMODE}" ] && $(echo "${MVN_BASHMODE}") [ -n "${MVN_DEBUG}" ] && $(echo "${MVN_DEBUG}") \
      [ -n "${MVN_VARG}" ] && $(echo "${MVN_VARG}") \
      --no-snapshot-updates -P"$i" -DskipTests=true deploy
  done
  IFS=' ' # reset to default value after usage
}

#pom_version() {
#  if [[ -f "pom.xl" ]]; then
#    version=`./mvnw -o help:evaluate -N -Dexpression=project.version | sed -n '/^[0-9]/p'`
#    return version
#  else
#    #return "0.0.1-SNAPSHOT" # default version hand crafted
#    return ""
#  fi;
#}

# shellcheck disable=SC2154
release__() {

  argv inarg '--arg' "${@:1:$#}"
  argv intag '--tag' "${@:1:$#}"
  argv insnapshot '--snapshot' "${@:1:$#}"
  argv inlabel '--tag-prefix' "${@:1:$#}"
  argv inprofile '--profile' "${@:1:$#}"

  colored --green "[Release] In label=${inlabel}"

  [[ ! -z "$insnapshot" ]] && snapshot="${insnapshot}" || snapshot=''
  [[ ! -z "$intag" ]] && tag="${intag}" || tag=''
  [[ ! -z "$inlabel" ]] && fullversion="${inlabel}-${tag}" || fullversion=''
  [[ ! -z "$fullversion" ]] && label="-Dtag=${fullversion}" || label=''

  ## Version argument declaration ...
  [[ ! -z "$intag" ]] && tag_argv="-DnewVersion=${intag}" || tag_argv='-DremoveSnapshot'
  [[ ! -z "$snapshot" ]] && snapshot_argv="-DnewVersion=${snapshot}" || snapshot_argv="-DnewVersion=$(increment "${intag}")"

  colored --green "[Release] Tag=${tag}"
  colored --green "[Release] Label=${label}"
  colored --green "[Release] Snapshot=${snapshot}"
  colored --green "[Release] Snapshot Label=${snapshot_argv}"
  colored --green "[Release] Tag Label=${tag_argv}"

  # shellcheck disable=SC2154
  colored --green "[Release] Extra Arg=${inarg}"
  colored --green "[Release] Full version: ${fullversion}"

  [[ ! -z $(is_tag_exists "${fullversion}") ]] && error_exit "Following tag: ${fullversion}, has already existed."

  # Update the versions, removing the snapshots, then create a new tag for the release,
  # this will start the travis-ci release process.
  ./mvnw -B -X versions:set scm:checkin "${tag_argv}" -DgenerateBackupPoms=false \
    -Dmessage="prepare release ${tag}" -DpushChanges=false

  # tag the release
  echo "pushing tag ${tag}"
  ./mvnw -B -X "${label}" -Dmvn.tag.prefix="${inlabel}-" scm:tag

  #Temporally fix to manually deploy (Deploy the new release tag)
  __mvn_deploy__ "${inprofile}" "${inarg}" # Deploy after version tag is created

  # Update the versions to the next snapshot
  ./mvnw -B -X versions:set scm:checkin "${snapshot_argv}" -DgenerateBackupPoms=false \
    -Dmessage="[travis skip] updating versions to next development iteration ${snapshot}"

  #Temporally fix to manually deploy (Deploy the new snapshot)
  __mvn_deploy__ "${inprofile}" "${inarg}" # Deploy after snapshot version is created
}

# Incremental versioning
# shellcheck disable=SC2006
# shellcheck disable=SC2154
# shellcheck disable=SC2236
api_version() {
  if [[ ! -z "$NEXT_RELEASE" ]]; then
    tag="$NEXT_RELEASE"
  else
    # extract the release version from the pom file
    version=`./mvnw -o help:evaluate -N -Dexpression=project.version | sed -n '/^[0-9]/p'`
    tag=`echo "${version}" | cut -d'-' -f 1`
  fi

  # determine the next snapshot version
#  snapshot=$(snapshot ${tag})

  argv inlabel '--label' "${@:1:$#}"
  argv inpatch '--patch' "${@:1:$#}"
  argv insnapshot '--next-snapshot' "${@:1:$#}"
  argv invarg '--varg' "${@:1:$#}"
  argv inprofile '--profile' "${@:1:$#}"

  [[ ! -z "$insnapshot" ]] && snapshot="$insnapshot" || snapshot=$(increment "${tag}")

  release__ --tag="${tag}" --tag-prefix="${inlabel:-release}" --snapshot="${snapshot}" --arg="${invarg:-}"
}

#Date based versioning
# shellcheck disable=SC2154
ts_version() {
  colored --blue "[timestamp] Building version basee release"

  argv fulldate '--full-date' "${@:1:$#}"
  argv informat '--format' "${@:1:$#}"

  argv inday '--day' "${@:1:$#}"
  argv inmonth '--month' "${@:1:$#}"
  argv inyear '--year' "${@:1:$#}"

  argv inlabel '--label' "${@:1:$#}"
  argv seperator '--separator' "${@:1:$#}"
  argv inpatch '--patch' "${@:1:$#}"
  argv inprofile '--profile' "${@:1:$#}"

  argv invarg '--varg' "${@:1:$#}"
  exists is_incremental '--continue-snapshot' "${@:1:$#}"
  argv innextsnapshot '--next-snapshot' "${@:1:$#}"

  [[ ! -z "$NEXT_RELEASE" ]] && nextrelease="$NEXT_RELEASE" || nextrelease=$(date +'%y.%m.%d')
  [[ ! -z "$informat" ]] && format="$informat" || format='%y.%m.%d'
  [[ ! -z "$fulldate" ]] && now=$(date -j -f "${format}" "$fulldate" +"${format}") || now="$nextrelease"
  [[ ! -z "$inday" ]] && d="$inday" || d="$(date -j -f "${format}" "$now" '+%d')"
  [[ ! -z "$inmonth" ]] && m="$inmonth" || m="$(date -j -f "${format}" "$now" '+%m')"
  [[ ! -z "$inyear" ]] && y="$inyear" || y="$(date -j -f "${format}" "$now" '+%y')"

  local sep="${seperator:-.}"
  local ver="${y}${sep}${m}${sep}${d}"

  [[ ! -z "$inpatch" ]] && tag="${ver}-${inpatch}" || tag="$ver"

  ##
  # IF '--continue-snapshot' was passed need to increment the snapshot version from the existing pom file
  ##
#  if [ -z "$innextsnapshot" ] || ([ is_incremental ] && [ -f "pom.xml" ] && [ -f "mvnw" ]); then
#    pversion=`./mvnw -o help:evaluate -N -Dexpression=project.version | sed -n '/^[0-9]/p'`
#    snapshot=$(increment ${pversion})
#
#    colored --white "[INFO] POM Version: ${pversion}"
#    colored --white "[INFO] Next snapshot: ${snapshot}"
#  else
#    [ ! -z "$innextsnapshot" ] && snapshot="${innextsnapshot}" \
#        || snapshot="${y}${sep}${m}${sep}$(($(date '+%d') + 1))-SNAPSHOT"
#  fi

  # shellcheck disable=SC2154
  [[ ! -z "${innextsnapshot}" ]] && snapshot="${innextsnapshot}" #|| snapshot="${y}${sep}${m}${sep}$(($(date '+%d') + 1))-SNAPSHOT"

  release__ --tag="${tag}" --tag-prefix="${inlabel:-release}" --snapshot="${snapshot:-}" --arg="${invarg:-}"
}

help_message () {
  #$(usage "${@:1:$#}")
  cat <<-EOF
  $PROGNAME
  This script will be use to tag your maven project with two type versioning style.
  #./release timestamp [--format=.., --full-date=..[[--year.., --month=.., --day=..]], --patch]

  Global:

    --label The given expect label used to tag the released version (release|tag|rc), etc...
    --next-snapshot Define this option (no matter the value) to indicate the ongoing snapshot version
    --patch Use this option to define the current patching version stage
    --setting-file This option is globaly used to define the target maven settings file
    --bash-mode This option can globaly use to define maven internal (-B) option
    --debug global option used activate maven (X) option
    --profile this option define your maven profile. ex: sonatype,other. If you wish to run your profile separaly, please use a comma (;) separator ex: sonatype,other;!sonatype,github

  Options:

  -h, --help [(timestamp|ts) | (increment|api) ] Display this help message within the given command and exit.
  --timestamp [timestamp | -- ts | ts]: Release the current project based on timestamp format (e.g: $(date +'%y.%m.%d'))
  --increment [increment | --api | api]: Release the current project, by continueing the current version.

  $(usage "${1}")
EOF
  return
}

usage() {
  for i in "${@}"; do
    case ${i} in
      ts|timestamp)
cat <<-EOF
Timestamp base version release:

  $PROGNAME ${i} [--format=.., --full-date=..[[--year.., --month=.., --day=..]], --patch]
  --format Define the given date format. Otherwise, the default value is set to: %y.%m.%d
  --full-date Define the manual or initial date value. The default value will be set to: $(date +'%y.%m.%d')
  --day Manually override the given version date
  --month Manually override the given version year

EOF
        ;;
      api|increment)
cat <<-EOF
//FIXME: NYI
EOF
     ;;
    esac
  done
}

if [[ $1 =~ ^((--)?((timestamp|ts)|(api|increment)|(help)))$ ]]; then
  XCMD="${1}"
  INDEX=2
else
  INDEX=1
  [[ ! -z "${RELEASE_STYLE}" ]] && XCMD="$RELEASE_STYLE" || XCMD='--help'
fi

if [[ "${XCMD}" != "--help" ]] && [[ "${XCMD}" != "-h" ]]; then
  exists indebug '--debug' "${@:$INDEX:$#}"
  argv insettingfile '--setting-file' "${@:$INDEX:$#}"
  exists inbashmodel '--bash-mode' "${@:$INDEX:$#}"
  argv inprofile '--profile' "${@:$INDEX:$#}"
  argv invarg '--varg' "${@:$INDEX:$#}"

  [[ "${inbashmodel}" ]] && $(export "MVN_BASHMODE"="-B") || colored --yellow "[Option] Maven bash mode Off"
  [[ "${indebug}" ]] && $(export "MVN_DEBUG"="-X") || colored --red "[Option] Maven debug Off"
  [[ -n "${insettingfile}" ]] && $(export "MVN_SETTINGS"="${insettingfile}") || colored --yellow "[Option] Maven settings Off"
  [[ -n "${inprofile}" ]] && $(export "MVN_PROFILES"="${inprofile}") || colored --yellow "[Option] Maven profiles Off"
  [[ -n "${invarg}" ]] && $(export "MVN_VARG"="${invarg}")

  # Load the project given .variables file if any
  if [[ -f ".variables" ]]; then
    colored --blue "Exporting .variables file ..."
    export_properties .variables
  fi
fi

case ${XCMD} in
  -h|--help)
    help_message "${@:$INDEX:$#}"
    graceful_exit ${?}
    ;;
  timestamp|ts|--timestamp|--ts)
    XCMD="ts_version"
    ;;
  api|--api|--increment|increment)
    XCMD="api_version"
    ;;
esac

if [[ -n "${XCMD}" ]]; then
  ${XCMD} "${@:$INDEX:$#}"
  graceful_exit ${?}
else
  graceful_exit
fi

# Trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT" INT
