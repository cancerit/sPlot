#!/bin/bash

set -xe

if [[ -z "${TMPDIR}" ]]; then
  TMPDIR=/tmp
fi

set -u

if [ "$#" -lt "1" ] ; then
  echo "Please provide an installation path such as /opt/CASM"
  exit 1
fi


# get path to this script
SCRIPT_PATH=`dirname $0`;
SCRIPT_PATH=`(cd $SCRIPT_PATH && pwd)`

# get the location to install to
INST_PATH=$1
mkdir -p $1
INST_PATH=`(cd $1 && pwd)`
echo $INST_PATH

# get current directory
INIT_DIR=`pwd`

CPU=`grep -c ^processor /proc/cpuinfo`
if [ $? -eq 0 ]; then
  if [ "$CPU" -gt "6" ]; then
    CPU=6
  fi
else
  CPU=1
fi
echo "Max compilation CPUs set to $CPU"

SETUP_DIR=$INIT_DIR/install_tmp
mkdir -p $SETUP_DIR/distro # don't delete the actual distro directory until the very end
mkdir -p $INST_PATH/bin
cd $SETUP_DIR

# make sure tools installed can see the install loc of libraries
set +u
export LD_LIBRARY_PATH=`echo $INST_PATH/lib:$LD_LIBRARY_PATH | perl -pe 's/:\$//;'`
export PATH=`echo $INST_PATH/bin:$BB_INST/bin:$PATH | perl -pe 's/:\$//;'`
export MANPATH=`echo $INST_PATH/man:$BB_INST/man:$INST_PATH/share/man:$MANPATH | perl -pe 's/:\$//;'`
export PERL5LIB=`echo $INST_PATH/lib/perl5:$PERL5LIB | perl -pe 's/:\$//;'`
set -u

## INSTALL CPANMINUS
set -eux
curl -sSL https://cpanmin.us/ > $SETUP_DIR/cpanm
perl $SETUP_DIR/cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH App::cpanminus
rm -f $SETUP_DIR/cpanm

##### DEPS for sPlot #####
cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH --installdeps Const::Fast
cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH Const::Fast
cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH JSON
cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH Encode
cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH IPC::System::Simple
cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH --installdeps Pod::Usage
cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH Pod::Usage
cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH Storable
cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH Pod::Simple

cd $HOME
rm -rf $SETUP_DIR
