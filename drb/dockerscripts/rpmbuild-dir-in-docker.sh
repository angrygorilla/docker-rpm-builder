#!/bin/bash
# $1 is calling user uid, $2 is calling user gid, $3 is whether to spawn bash on fail.
# $4 is an ascii armored, base64 nowrap encoded, non-password-protected private GPG key if signing was requested.
set -ex
CALLING_UID=$1
CALLING_GID=$2
RPMS_DIR=$(rpm --eval %{_rpmdir})
SRPMS_DIR=$(rpm --eval %{_srcrpmdir})
SOURCE_DIR=$(rpm --eval %{_sourcedir})

function finish {
  chown -R ${CALLING_UID}:${CALLING_GID} ${RPMS_DIR} || /bin/true
}
trap finish EXIT

echo "starting $0"
SPEC=$(ls ${SOURCE_DIR}/*.spec | head -n 1)
/dockerscripts/rpm-setup-deps.sh
#rpmbuild complains if it can't find a proper user for uid/gid
groupadd -g $2 mygroup || /bin/true
useradd -g $2 -u $1 myuser || /bin/true

if [ -n "$4" ]
then
    echo "Running with RPM signing"
    echo "$4" | base64 -d | gpg --import
    [[ $(gpg --list-secret-keys) =~ uid(.*) ]]
    KEYNAME="${BASH_REMATCH[1]}"
    [ -n "${KEYNAME}" ] || { echo "could not find key for signing purpose"; exit 1; }
    echo -e "%_gpg_name ${KEYNAME}\n%_signature gpg" > ${HOME}/.rpmmacros
    echo -e "\n" | setsid rpmbuild -bb --sign $SPEC ||  { [ "bashonfail" == "$3" ] && { echo "Build failed, spawning a shell" ; /bin/bash ; exit 1; } || /bin/false ; }
else
    echo "Running without RPM signing"
    rpmbuild -bb $SPEC || { [ "bashonfail" == "$3" ] && { echo "Build failed, spawning a shell" ; /bin/bash ; exit 1; } || /bin/false ; }
fi
echo "Done"