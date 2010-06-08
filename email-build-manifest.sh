#! /bin/bash

usage() {
  echo "Usage: $0 <repository> <distribution> <emails>"
  exit 1
}

[ $# != 3 ] && usage

REPOSITORY=$1
DISTRIBUTION=$2
EMAILS=$3

pkgtools=$(dirname $0)
. $pkgtools/release-constants.sh

HOST=mephisto
SNAPSHOT=`date -d "-1day" "+%Y-%m-%d"`

tmp_base=/tmp/manifest-$REPOSITORY-$DISTRIBUTION-`date -Iminutes`
/bin/rm -f ${tmp_base}*
diffCommand="$pkgtools/apt-chroot-utils/compare-sources.py $HOST,$REPOSITORY,$DISTRIBUTION/snapshots/$SNAPSHOT $HOST,$REPOSITORY,$DISTRIBUTION $tmp_base"

python $diffCommand

[ -f ${tmp_base}*.txt ] || touch ${tmp_base}.txt
[ -f ${tmp_base}*.csv ] || touch ${tmp_base}.csv

attachments="-a ${tmp_base}*.txt -a ${tmp_base}*.csv"
mutt -F $MUTT_CONF_FILE $attachments -s "[Build manifest] $REPOSITORY/$DISTRIBUTION" $EMAILS <<EOF
Effective `date`.

Attached are the diff files for this build, generated by running the
following command:

  $diffCommand

--ReleaseMaster ($USER@`hostname`)
EOF

#/bin/rm -f ${tmp_base}*
