#!/usr/bin/env bash
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

set -euo pipefail
set -x

argv0=$(echo "$0" | sed -e 's,\\,/,g')
basedir=$(dirname "$(readlink "$0" || echo "$argv0")")

case "$(uname -s)" in
  Linux) basedir=$(dirname "$(readlink -f "$0" || echo "$argv0")");;
  *CYGWIN*) basedir=`cygpath -w "$basedir"`;;
esac

# Load current shared labrary ...
# shellcheck disable=SC1090
source "${basedir}"/common.sh

#Line 7 specifies that your tag names will include a 'v' before the number. Remove the 'v' if desired.
#Lines 18 must point to a valid file path
#Line 22 expects to find text like "= v1.3.6", and will replace the number with the one you specified as an argument. Modify sed command as necessary/desired

# current Git branch
branch=$(git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,')

# v1.0.0, v1.5.2, etc.
versionLabel=v$1

# establish branch and tag name variables
devBranch=develop
masterBranch=master
releaseBranch=release-$versionLabel

# create the release branch from the -develop branch
git checkout -b $releaseBranch $devBranch

# file in which to update version number
versionFile="version.txt"

# find version number assignment ("= v1.5.5" for example)
# and replace it with newly specified version number
sed -i.backup -E "s/\= v[0-9.]+/\= $versionLabel/" $versionFile $versionFile

# remove backup file created by sed command
rm $versionFile.backup

# commit version number increment
git commit -am "Incrementing version number to $versionLabel"

# merge release branch with the new version number into master
git checkout $masterBranch
git merge --no-ff $releaseBranch

# create tag for new version from -master
git tag $versionLabel

# merge release branch with the new version number back into develop
git checkout $devBranch
git merge --no-ff $releaseBranch

# remove release branch
git branch -d $releaseBranch