#!/bin/bash

##########LICENCE##########
# Copyright (c) 2019 Genome Research Ltd.
#
# Author: Cancer Genome Project cgpit@sanger.ac.uk
#
# This file is part of splot.
#
# splot is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation; either version 3 of the License, or (at your option) any
# later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
##########LICENCE##########

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

SETUP_DIR=$INIT_DIR/install_tmp
mkdir -p $INST_PATH/bin $SETUP_DIR
cd $SETUP_DIR

# make sure tools installed can see the install loc of libraries
set +u
export LD_LIBRARY_PATH=`echo $INST_PATH/lib:$LD_LIBRARY_PATH | perl -pe 's/:\$//;'`
export PATH=`echo $INST_PATH/bin:$BB_INST/bin:$PATH | perl -pe 's/:\$//;'`
export MANPATH=`echo $INST_PATH/man:$BB_INST/man:$INST_PATH/share/man:$MANPATH | perl -pe 's/:\$//;'`
export PERL5LIB=`echo $INST_PATH/lib/perl5:$PERL5LIB | perl -pe 's/:\$//;'`
set -u

# if cpanm is not installed
if [ -z $(which cpanm) ]; then
  echo "Can't find cpanm, trying to install.."
  ## INSTALL CPANMINUS
  set -eux
  curl -sSL https://cpanmin.us/ > $SETUP_DIR/cpanm
  perl $SETUP_DIR/cpanm --no-wget --no-interactive --notest --mirror http://cpan.metacpan.org -l $INST_PATH App::cpanminus
  rm -f $SETUP_DIR/cpanm
fi
CPANM=`which cpanm`

# Install sPlot
$CPANM --no-wget --no-interactive --mirror http://cpan.metacpan.org --notest -l $INST_PATH --installdeps $SCRIPT_PATH/perl/
$CPANM --no-wget --no-interactive --mirror http://cpan.metacpan.org -l $INST_PATH $SCRIPT_PATH/perl/

cd $HOME
rm -rf $SETUP_DIR
