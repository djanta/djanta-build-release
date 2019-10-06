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

source ${basedir}/common.sh

if [ "$#" -eq 0 ] &&  [ ! -f ".variables" ]; then
  error_exit "Insuffisant command argument"
fi

# Load the project given .variables file if any
if [ -f ".variables" ]; then
  colored --blue "Exporting .variables file ..."
  export_properties .variables
fi

# Load the pom version
#[ -f "pom.xml" ] && version=`./mvnw -o help:evaluate -N -Dexpression=project.version | sed -n '/^[0-9]/p'` || \
#    version="0.0.1-SNAPSHOT" # Set the default pom version to "0.0.1-SNAPSHOT"

#echo "[*] Version: ${version}"

increment() {
  local version=$1
  result=`echo ${version} | awk -F. -v OFS=. 'NF==1{print ++$NF}; NF>1{if(length($NF+1)>length($NF))$(NF-1)++; $NF=sprintf("%0*d", length($NF), ($NF+1)%(10^length($NF))); print}'`
  echo "${result}-SNAPSHOT"
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

release() {

  argv inarg '--arg' ${@:1:$#}
  argv intag '--tag' ${@:1:$#}
  argv insnapshot '--snapshot' ${@:1:$#}
  argv inlabel '--tag-prefix' ${@:1:$#}
  argv inprofile '--profile' ${@:1:$#}

  colored --green "[Release] In label=${inlabel}"

  [[ ! -z "$insnapshot" ]] && snapshot="${insnapshot}" || snapshot=''
  [[ ! -z "$intag" ]] && tag="${intag}" || tag=''
  [[ ! -z "$inlabel" ]] && label="-Dtag=${inlabel}-${tag}" || label=''

  ## Version argument declaration ...
  [[ ! -z "$intag" ]] && tag_argv="-DnewVersion=${intag}" || tag_argv='-DremoveSnapshot'
  [[ ! -z "$inprofile" ]] && profile_argv="-P${inprofile}" || profile_argv=''
  [[ ! -z "$snapshot" ]] && snapshot_argv="-DnewVersion=${snapshot}" \
    || snapshot_argv="-DnewVersion=$(increment ${intag})"

  colored --green "[Release] Tag=${tag}"
  colored --green "[Release] Label=${label}"
  colored --green "[Release] Snapshot=${snapshot}"
  colored --green "[Release] Snapshot Label=${snapshot_argv}"
  colored --green "[Release] Tag Label=${tag_argv}"
  colored --green "[Release] Profile=${profile_argv}"
  colored --green "[Release] Extra Arg=${inarg}"

  # Update the versions, removing the snapshots, then create a new tag for the release, this will
  # start the travis-ci release process.
  ./mvnw -B versions:set scm:checkin "${profile_argv}" "${tag_argv}" -DgenerateBackupPoms=false \
    -Dmessage="prepare release ${tag}" -DpushChanges=false "${inarg}"

  # tag the release
  echo "pushing tag ${tag}"
  ./mvnw "${label}" scm:tag #"${inarg}"

  #FIXME: Temporally fix to manually deploy (Deploy the new release tag)
  ./mvnw -B "${profile_argv}" -DskipTests deploy

  # Update the versions to the next snapshot
  ./mvnw -B versions:set scm:checkin "${profile_argv}" "${snapshot_argv}" -DgenerateBackupPoms=false \
      -Dmessage="[travis skip] updating versions to next development iteration ${snapshot}" "${inarg}"

  #FIXME: Temporally fix to manually deploy (Deploy the new snapshot)
  ./mvnw -B "${profile_argv}" -DskipTests deploy
}

# Incremental versioning
api_version() {
  # extract the release version from the pom file
  version=`./mvnw -o help:evaluate -N -Dexpression=project.version | sed -n '/^[0-9]/p'`
  tag=`echo ${version} | cut -d'-' -f 1`

  # determine the next snapshot version
#  snapshot=$(snapshot ${tag})

  argv inlabel '--label' ${@:1:$#}
  argv inpatch '--patch' ${@:1:$#}
  argv insnapshot '--next-snapshot' ${@:1:$#}
  argv invarg '--varg' ${@:1:$#}
  argv inprofile '--profile' ${@:1:$#}

  [[ ! -z "$insnapshot" ]] && snapshot="$insnapshot" || snapshot=$(increment ${tag})

  echo "release version is: ${tag} and next snapshot is: ${snapshot}"

  # Update the versions, removing the snapshots, then create a new tag for the release, this will
  # start the travis-ci release process.
#  ./mvnw -B versions:set scm:checkin -DremoveSnapshot -DgenerateBackupPoms=false -Dmessage="prepare release ${tag}" \
#    -DpushChanges=false

  # tag the release
#  echo "pushing tag ${tag}"
#  ./mvnw scm:tag

  # Update the versions to the next snapshot
#  ./mvnw -B versions:set scm:checkin -DnewVersion="${snapshot}" -DgenerateBackupPoms=false \
#      -Dmessage="[travis skip] updating versions to next development iteration ${snapshot}"

  release --tag="${tag}" --tag-prefix="${inlabel:-release}" --snapshot="${snapshot}" \
    --profile="${inprofile:-}" --arg="${invarg:-}"
}

#Date based versioning
ts_version() {
  colored --blue "[timestamp] Building version basee release"

  argv fulldate '--full-date' ${@:1:$#}
  argv informat '--format' ${@:1:$#}

  argv inday '--day' ${@:1:$#}
  argv inmonth '--month' ${@:1:$#}
  argv inyear '--year' ${@:1:$#}

  argv inlabel '--label' ${@:1:$#}
  argv seperator '--separator' ${@:1:$#}
  argv inpatch '--patch' ${@:1:$#}
  argv inprofile '--profile' ${@:1:$#}

  argv invarg '--varg' ${@:1:$#}
  exists is_incremental '--continue-snapshot' ${@:1:$#}
  argv innextsnapshot '--next-snapshot' ${@:1:$#}

  [ ! -z "$NEXT_RELEASE" ] && nextrelease="$NEXT_RELEASE" || nextrelease=$(date +'%y.%m.%d')
  [ ! -z "$informat" ] && format="$informat" || format='%y.%m.%d'
  [ ! -z "$fulldate" ] && now=$(date -j -f "${format}" "$fulldate" +"${format}") || now="$nextrelease"
  [ ! -z "$inday" ] && d="$inday" || d="$(date -j -f "${format}" "$now" '+%d')"
  [ ! -z "$inmonth" ] && m="$inmonth" || m="$(date -j -f "${format}" "$now" '+%m')"
  [ ! -z "$inyear" ] && y="$inyear" || y="$(date -j -f "${format}" "$now" '+%y')"

  local sep="${seperator:-.}"
  local ver="${y}${sep}${m}${sep}${d}"

  [ ! -z "$inpatch" ] && tag="${ver}-${inpatch}" || tag="$ver"

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

  [ ! -z "$innextsnapshot" ] && snapshot="${innextsnapshot}" #|| snapshot="${y}${sep}${m}${sep}$(($(date '+%d') + 1))-SNAPSHOT"

#  colored --yellow "Continue snapshot: ${is_incremental}"
#  colored --yellow "[WARN] Exported Next Release: ${NEXT_RELEASE}"
#  colored --yellow "[WARN] Next Release: ${nextrelease}"
#  colored --yellow "[WARN] Next Snapshot: ${snapshot}"
#  colored --green "[timestamp] Generated version: ${tag}"

  release --tag="${tag}" --tag-prefix="${inlabel:-release}" --snapshot="${snapshot:-}" \
    --profile="${inprofile:-}" --arg="${invarg:-}"
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

  Options:
  -h, --help [(timestamp|ts) | (increment|api) ] Display this help message within the given command and exit.
  --timestamp [timestamp | -- ts | ts]: Release the current project based on timestamp format (e.g: $(date +'%y.%m.%d'))
  --increment [increment | --api | api]: Release the current project, by continueing the current version.

  $(usage "${1}")
EOF
  return
}

usage() {
  for i in ${@}; do
    #colored --green "Command arugment: ${i}"
#    case ${i} in
#      --long-help)
#      LONGHELP="1"
#      ;;
#    esac

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
  [ ! -z "$RELEASE_STYLE" ] && XCMD="$RELEASE_STYLE" || XCMD='--help'
fi

case ${XCMD} in
  -h|--help)
    help_message ${@:$INDEX:$#}
    graceful_exit ${?}
    ;;
  timestamp|ts|--timestamp|--ts)
    XCMD="ts_version"
    ;;
  api|--api|--increment|increment)
    XCMD="api_version"
    ;;
esac

if [ -n "${XCMD}" ]; then
  ${XCMD} ${@:$INDEX:$#}
  graceful_exit ${?}
else
  graceful_exit
fi

# Trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT" INT
