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

# this is a catch all to ensure all modules do compile

use strict;
use Data::Dumper;
use Test::More;
use List::Util qw(first);
use Try::Tiny qw(try catch);
use autodie qw(:all);
use File::Find;

use FindBin qw($Bin);
my $script_path = "$Bin/../bin";

my $perl = $^X;

my @scripts;
find({ wanted => \&build_path_set, no_chdir => 1 }, $script_path);

for(@scripts) {
  my $script = $_;
  my $message = "Compilation check: $script";
  my $command = "$perl -c $script";
print "$command\n";
  my ($pid, $process);
  try {
    $pid = open $process, $command.' 2>&1 |';
    while(<$process>){};
    close $process;
    pass($message);
  }
  catch {
    fail($message);
  };
}

done_testing();

sub build_path_set {
  push @scripts, $_ if($_ =~ m/\.pl$/);
}
