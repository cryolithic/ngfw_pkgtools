#! /bin/bash

# set -x

# usage...
if [ ! $# -eq 3 ] ; then 
  echo "Usage: $0 distribution VERSION=[version] REPOSITORY=[repository]" && exit 1
fi

if svn list > /dev/null 2>&1 ; then
  VCS="svn"
else
  VCS="git"
fi

DCH=$(mktemp /tmp/dch-XXXXX)

rm -f debian/changelog.dch
DEBEMAIL="${DEBEMAIL:-buildbot@untangle.com}"
DEBFULLNAME="${DEBFULLNAME:-Untangle Buildbot}"

# CL args
distribution=${1}
version=${2/VERSION=}
versionGiven=$version
repository=${3/REPOSITORY=}

[ -z "${repository}" ] && repository=`$0/getPlatform.sh`

osdist=unknown
case $repository in
  sarge|etch|lenny|sid) osdist=debian ;;
  feisty|gutsy|intrepid|hardy) osdist=ubuntu ;;
esac

previousVersion=`dpkg-parsechangelog 2> /dev/null | awk '/Version: / { print $2 }'`
previousUpstreamVersion=`dpkg-parsechangelog 2> /dev/null | awk '/Version: / { gsub(/-.*/, "", $2) ; print $2 }'`

if [ -z "$version" ] ; then
  # not exactly kosher, but I'll contend that incVersion.sh is only
  # called from the Makefile :>
  versionFile=`dirname $0`/resources/VERSION

  # get some values from VCS: branch, last changed revision, timestamp
  # for the current directory
  case $VCS in
    svn)
      VCS_INFO="svn info --recursive"
      VCS_STATUS="svn status"
      url=`$VCS_INFO . | awk '/^URL:/{print $2}'` #FIXME
      case $url in
	*branch/*) branch=`echo $url | perl -pe 's|.*/branch/(.*?)/.*|\1| ; s/-//g'` ;;
	*) branch=main ;;
      esac
      revision=`$VCS_INFO . | awk '/Last Changed Rev: / { print $4 }' | sort -n | tail -1`
      [ -z "$revision" ] && revision=100000
      timestamp=`$VCS_INFO . | awk '/Last Changed Date:/ { gsub(/-/, "", $4) ; gsub(/:/, "", $5) ; print $4 "T" $5 }' | sort -n | tail -1`

      # this is how we figure out if we're up-to-date or not
      hasLocalChanges=`$VCS_STATUS | grep -v -E '^([X?!]|Fetching external item into|Performing status on external item at|$)'`
      ;;
    git)
      # new-style source package are not directly under version
      # control, but their parent dir is
      [[ $(pwd) == */ngfw_upstream/* ]] && d=.. || d=.
      revision=$(git log -n 1 --format="%h" -- $d)
      # convert commit date to something to an ISO timestamp like
      # "2016-09-13T23:46:56-0700"
      timestamp="$(git log -n 1 --date=iso-strict-local --format='%cd' -- $d)"
      # ... and then to "20160913T234656", accounting for weird
      # timezone format&separator
      timestamp=$(echo $timestamp | perl -pe 's/[-+][\d:]+$// ; s/[-:]//g')
      hasLocalChanges=$(git diff-index --name-only HEAD -- .)
      ;;
  esac

  # this is the base version; it will be tweaked a bit if need be:
  # - append a local modification marker is we're not up to date
  # - prepend the upstream version if UNTANGLE-KEEP-UPSTREAM-VERSION exists
  baseVersion=$(cat $versionFile).${timestamp}.${revision}

  if [ -f UNTANGLE-KEEP-UPSTREAM-VERSION ] ; then
    baseVersion=${previousUpstreamVersion}+${baseVersion}
  elif [ -f UNTANGLE-FORCE-UPSTREAM-VERSION ] ; then
    # if we find UNTANGLE-FORCE-UPSTREAM-VERSION, do nothing as it
    # means we want to build an upstream package without modifying it
    # at all.
    baseVersion=${previousVersion}
  fi

  if [ -z "$hasLocalChanges" ] ; then
    version=$baseVersion
  else
    echo -e "The changes were:\n$hasLocalChanges"
    version=${baseVersion}+localdiff`date +"%Y%m%dT%H%M%S"`
  fi

  if [ ! -f UNTANGLE-FORCE-UPSTREAM-VERSION ] ; then  # FIXME: ugly, but will do for now
    version=${version}-1
  fi
else # force version
  if [ -f UNTANGLE-KEEP-UPSTREAM-VERSION ] ; then
    previousUpstreamVersion=`dpkg-parsechangelog | awk '/Version: / { gsub(/-.*/, "", $2) ; print $2 }'`
    version=${previousUpstreamVersion}+${version}
  fi
  case "$version" in
    *-*) ;; # the user did supply a Debian revision
    *)   version=${version}-1 ;;
  esac
fi

version=${version}${repository}

dchargs="--preserve -v ${version} -D ${distribution}"
## dch is called outside the chroot...
#if [ "$osdist" = ubuntu ]; then
#    dchargs="$dchargs --distributor Untangle"
#fi

/bin/cp -f /usr/bin/dch $DCH
chmod 755 $DCH
sed -i -e '/garbage/d' $DCH
echo "Setting version to \"${version}\", distribution to \"$distribution\""
DEBEMAIL="$DEBEMAIL" DEBFULLNAME="$DEBFULLNAME" $DCH $dchargs "auto build" 2> /dev/null
# check changelog back in if version was forced; FIXME: disabled for now
#[ -n "$versionGiven" ] && [ ! -f UNTANGLE-KEEP-UPSTREAM-VERSION ] && $SVN commit debian/changelog -m "Forcing version to $version"
rm -f $DCH
echo " done."
