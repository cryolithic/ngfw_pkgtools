#! /bin/bash +x

# Use the current distro to pull main, but use upstream from stage/testing+$1/testing+$1/alpha
# (not everyone has upstream in his target distro)
# --Seb

SOURCES=/etc/apt/sources.list

# for our own build-deps
echo deb http://mephisto/public/$1 $2 main premium upstream internal >> ${SOURCES}

# also search in nightly
[ $2 != nightly ] && echo deb http://mephisto/public/$1 nightly main premium upstream internal >> ${SOURCES}

#echo deb http://mephisto/public/sarge testing upstream >> ${SOURCES}
#echo deb http://mephisto/public/sarge alpha upstream >> ${SOURCES}

apt-get -q update

umount -f /proc

exit 0