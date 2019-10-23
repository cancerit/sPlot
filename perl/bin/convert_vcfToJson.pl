#!/usr/bin/perl

##########LICENCE##########
# Copyright (c) 2014-2019 Genome Research Ltd.
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

use strict;
use warnings;
use JSON;
use Const::Fast qw(const);
use Getopt::Long;
use Pod::Usage;
use File::Spec;
use File::Basename;
use Carp qw(croak);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

use Sanger::CGP::splot;

#Valid analysis types
const my %VALID_ANALYSIS => ('caveman' => 1,
                             'caveman_c' => 1,
                             'pindel' => 1);

const my %VCF_ANALYSIS => ('CaVEMan' => 'caveman_c',
                           'Pindel' => 'pindel');

#Vcf headers
my @HEADERS = ('CHROM', 'POS', 'ID', 'REF', 'ALT', 'QUAL', 'FILTER', 'INFO', 'FORMAT',  'NORMAL', 'TUMOUR');

my %header_idx;
for (my $i = 0; $i < @HEADERS; $i++) {
  $header_idx{$HEADERS[$i]} = $i;
}

const my %BP_COMBINATIONS => ('C->A' => 'C->A|G->T',
                              'G->T' => 'C->A|G->T',
                              'C->G' => 'C->G|G->C',
                              'G->C' => 'C->G|G->C',
                              'C->T' => 'C->T|G->A',
                              'G->A' => 'C->T|G->A',
                              'T->A' => 'T->A|A->T',
                              'A->T' => 'T->A|A->T',
                              'T->C' => 'T->C|A->G',
                              'A->G' => 'T->C|A->G',
                              'T->G' => 'T->G|A->C',
                              'A->C' => 'T->G|A->C');

#List of required mutations. Other mutations are not considered
#in any of the summaries. Can use command line option --effects to over-ride
const my %MUTATION_LIST => ('missense' => 1,
                            'nonsense' => 1,
                            'stop_lost' => 1,
                            'start_lost' => 1,
                            'ess_splice' => 1,
                            'frameshift' => 1,
                            'silent' => 1,
                            'complex_sub' => 1,);

pod2usage(-exitstatus => 0, -verbose => 1) if (scalar(@ARGV) == 0);

my $opts = option_builder();

main($opts);

#
# Find vcf files for each sample and analysis
# Create a json string from each vcf file
#
sub main {
  my ($opts) = @_;

  my $vcf_path = $opts->{'input'};
  my $sample_name = $opts->{'sample'};
  my $analysis = $opts->{'analysis'};

  #print "vcf_path=$vcf_path\n";
  my $json_string = get_json_from_vcf($opts);
  if (defined $opts->{'output'}) {
    write_output($opts->{'output'}, $sample_name,$analysis, $json_string);
  } else {
    print "$json_string";
  }
}

#
# Parse vcf header for vcfProcessLog lines.
# Only support pindel and caveman_c (not caveman)
#
sub get_analysis_from_vcf {
  my ($vcf) = @_;
  my $z = new IO::Uncompress::Gunzip $vcf, MultiStream=>1 or die "gunzip failed: $GunzipError\n";

  my $analysis;
  while (my $line = <$z>) {
    chomp $line;
    next unless ($line =~ /^##vcfProcessLog/);
    my ($input_source) = $line =~ /^##vcfProcessLog.*InputVCFSource=<(\w+)>.*/;
    if ($input_source) {
      if (exists $VCF_ANALYSIS{$input_source}) {
        $analysis = $VCF_ANALYSIS{$input_source};
        last;
      }
    }
  }
  close $z;
  return $analysis;
}

#
# Parse the vcf file and convert to a json string
#
sub get_json_from_vcf {
  my ($opts) = @_;

  my $vcf_path = $opts->{'input'};
  my $sample_name = $opts->{'sample'};
  my $analysis = $opts->{'analysis'};

  if (defined $vcf_path && -e $vcf_path) {
    my $variant_data = parse_vcf($opts, $vcf_path);
    my $sample_json = convert_to_json_by_analysis($variant_data, $sample_name, $analysis);
    return $sample_json;
  } else {
    croak "Unable to find vcf file $vcf_path";
  }
}

#
# Write json string to file in output directory
#
sub write_output {
  my ($json_file, $sample_name, $analysis, $sample_json) = @_;

  my ($filename, $out_dir, $suffix) = fileparse($json_file);

  #Create output directory
  mkdir $out_dir;

  #Write json file
  open my $fh_out, "> $json_file" or die "Unable to open $json_file";
  print $fh_out "$sample_json\n";
  close $fh_out;
}

#
# Parse the vcf file
#
sub parse_vcf {
  my ($opts, $source) = @_;

  my $variant_data;
  my $z = new IO::Uncompress::Gunzip $source, MultiStream=>1 or die "gunzip failed: $GunzipError\n";

  while (my $line = <$z>) {
    chomp $line;
    next if ($line =~ /^#/);
    my @cols = split ' ', $line;

    my $variant_info;

    $variant_info->{'FILTER'} = $cols[$header_idx{'FILTER'}];
    #skip anything that where FILTER != PASS
    next unless ($cols[$header_idx{'FILTER'}] eq 'PASS');

    my $info_data = $cols[$header_idx{'INFO'}];
    my $gene_seen;
    ($gene_seen, $variant_info) = info_fields($info_data, $variant_info);

    #Do not store any data unless we find a gene (VD)
    next unless ($gene_seen);

    #No skipping required if want all effects, else skip anything not in
    #the mutation list
    unless ($opts->{'all_effects'}) {
      #Skip anything not in the requested mutation list
      next unless (exists $opts->{'mutation_list'}{$variant_info->{'EFFECT'}} &&
                   $opts->{'mutation_list'}{$variant_info->{'EFFECT'}});
    }

    my $format_data = $cols[$header_idx{'FORMAT'}];
    my $tumour_data = $cols[$header_idx{'TUMOUR'}];

    $variant_info = format_fields($format_data, $tumour_data, $variant_info);
    $variant_info->{'REF'} = $cols[$header_idx{'REF'}];
    $variant_info->{'ALT'} = $cols[$header_idx{'ALT'}];
    push @{$variant_data}, $variant_info;
  }
  close $z;
  return $variant_data;
}

#
# Convert vcf data into json
#
sub convert_to_json_by_analysis {
  my ($variant_data, $sample_name, $analysis) = @_;
  my $sample_mutations;

  my %mutation_counts;
  my %bp_change_counts;

  foreach my $variant (@{$variant_data}) {
    my $gene = $variant->{'GENE'};
    my $effect = $variant->{'EFFECT'};
    my $sample = $variant->{'SAMPLE'};
    my $filter = $variant->{'FILTER'};
    my $ref = $variant->{'REF'};
    my $alt = $variant->{'ALT'};

    #These are not available in pindel files
    my $total_read_depth =  $variant->{'DP'} if (defined $variant->{'DP'});
    my $tum_read_depth =  $variant->{'DP-TUM'} if (defined $variant->{'DP-TUM'});
    my $vaf_tum =  $variant->{'PM-TUM'} if (defined $variant->{'PM-TUM'});

    #Must be PASS
    next unless $filter eq 'PASS';

    #mutation consequence
    $mutation_counts{$effect}++;

    #base-pair changes counts (skip pindel)
    unless ($analysis eq 'pindel') {
      $bp_change_counts{$BP_COMBINATIONS{"${ref}->${alt}"}}++;
    }

    #Gene mutation data
    my $gene_data;
    %{$gene_data} = ('effect' => $effect,
                     'dp' => $total_read_depth,
                     'dp-tum' => $tum_read_depth,
                     'pm-tum' => $vaf_tum);

    push @{$sample_mutations->{'gene'}{$gene}}, $gene_data;
  }

  $sample_mutations->{'version'} = Sanger::CGP::splot->VERSION;

  $sample_mutations->{'sample'} = $sample_name;
  $sample_mutations->{'analysis'} = $analysis;
  $sample_mutations->{'mutation_counts'} = \%mutation_counts;
  $sample_mutations->{'bp_change_counts'} = \%bp_change_counts;

  my $sample_json = encode_json $sample_mutations;
  return $sample_json;
}

#
# Parse vcf INFO fields
#
sub info_fields {
  my ($info_row, $json_info) = @_;

  my @info_data;

  foreach my $e (split ';', $info_row){
    push @info_data, [split '=', $e];
  }

  #Check if we have a gene present
  my $vdseen = 0;
  foreach my $d (@info_data) {
    if($d->[0] eq 'VD'){
      $vdseen = 1;
      my @anno_data = split('\|',$d->[1]);
      if (defined $anno_data[0]) {
        $json_info->{'GENE'} = $anno_data[0];
      }
    }

    if($vdseen == 1){
      foreach my $d (@info_data){
        if($d->[0] eq 'VC'){
          $json_info->{'EFFECT'} = $d->[1];
        }
        if($d->[0] eq 'DP'){
          $json_info->{'DP'} = $d->[1];
        }
      }
    }
  }

  return ($vdseen, $json_info);
}

#
# Parse vcf FORMAT fields
#
sub format_fields {
  my ($format_data, $tumour_data, $json_info) = @_;

  my @format_headers = split ':', $format_data;
  my @tumour = split ':', $tumour_data;

  for (my $i = 0; $i < @format_headers; $i++) {
    if ($format_headers[$i] eq 'PM') {
      $json_info->{'PM-TUM'} = $tumour[$i];
    }
    if ($format_headers[$i] eq 'FAZ' ||
        $format_headers[$i] eq 'FCZ' ||
        $format_headers[$i] eq 'FGZ' ||
        $format_headers[$i] eq 'FTZ' ||
        $format_headers[$i] eq 'RAZ' ||
        $format_headers[$i] eq 'RCZ' ||
        $format_headers[$i] eq 'RGZ' ||
        $format_headers[$i] eq 'RTZ') {
      $json_info->{'DP-TUM'} += $tumour[$i];
    }
  }
  return $json_info;
}

sub option_builder {
  my ($factory) = @_;
  my %opts = ();
  my @analyses;
  my @mutation_effects;

  my $result = &GetOptions (
                            'h|help' => \$opts{'h'},
                            'v|version' => \$opts{'v'},
                            'a|analysis=s' => \$opts{'analysis'},
                            'i|input=s' => \$opts{'input'},
                            'o|output=s' => \$opts{'output'},
                            's|sample=s' => \$opts{'sample'},
                            'e|effects=s' => \@mutation_effects,
                            'ae|all_effects' => \$opts{'all_effects'},
                            'debug' => \$opts{'debug'},
                           );

  if ($opts{'v'}) {
    print "Version: $VERSION\n";
    exit 0;
  }

  pod2usage(0) unless ($result);
  pod2usage(0) if ($opts{'h'});

  if (@mutation_effects) {
    my @effects = split(/,/,join(',',@mutation_effects));
    foreach my $effect (split(/,/,join(',',@mutation_effects))) {
      $opts{'mutation_list'}{$effect} = 1;
    }
  } elsif (!$opts{'all_effects'}) {
    #default list if not requesting all mutations
    $opts{'mutation_list'} = \%MUTATION_LIST;
  }

  validateInput(\%opts);
  return \%opts;
}

sub validateInput {
  my $opts = shift;

  #Need sample and input

  unless (defined $opts->{'sample'} && defined $opts->{'input'}) {
    pod2usage('Please specify sample, analysis and input vcf file');
  }

  unless (-e $opts->{'input'}) {
    pod2usage('Input file ' . $opts->{'input'} . ' does not exist');
  }

  #Get analysis from vcf header
  my $vcf_header_analysis = get_analysis_from_vcf($opts->{'input'});

  #Check the analysis found in the vcf header is the same as that on the
  #command line
  if (defined $opts->{'analysis'}) {
    if (defined $vcf_header_analysis &&
        ($opts->{'analysis'} ne $vcf_header_analysis)) {
      croak('Command line analysis ' . $opts->{'analysis'} . " is not the same as that found in the vcf header $vcf_header_analysis");
    }
  } else {
    #If no analysis given on the command line, set to vcf header value
    $opts->{'analysis'} = $vcf_header_analysis;
  }

  unless ($opts->{'analysis'} && exists $VALID_ANALYSIS{$opts->{'analysis'}}) {
    pod2usage('Analysis can be either caveman, caveman_c or pindel');
  }

  #Have effects or all_effects, not both
  if (defined $opts->{'mutation_list'} && defined $opts->{'all_effects'}) {
    pod2usage('Please specify either a subset of mutation effects using a comma separated list or all_effects but not both');
  }
}

__END__

=head1 NAME

convert_vcfToJson.pl - Parses pindel and caveman annotated vcf files and creates a json string of summary information. This can be written to stdout or a file. If no analysis is given, this is parsed from the vcf header, although this is only possible for pindel and caveman_c files. To process analyses not run in canpipe, you need to specify the analysis on the command line. The json is used as input for the sequencing and somatic variation plots (splot).

=head1 SYNOPSIS

convert_vcfToJson.pl [-h] [-v] [-s] <SAMPLE_NAME> [-a] <ANALYSIS> [-i] </PATH/TO/VCF_FILE> [-o] </PATH/TO/OUTPUT/DIRECTORY>

 General Options:

    --help              (-h)    Brief documentation

    --version           (-v)    Print version and exit

    --analysis          (-a)   Analysis (caveman_c, caveman, pindel)

    --sample            (-s)   Sample name

    --input             (-i)   Annotated gzipped vcf file

    --output            (-o)   Output json name

    --effects           (-e)   Mutational consequences. Default to missense,nonsense,stop_lost,start_lost,ess_splice,frameshift,silent,complex_sub

    --all_effects       (-ae)  Use all mutational consequences (boolean). Default false

 Examples:

    convert_vcfToJson.pl -s PD12345 -i /my/path/to/sample.vcf -o /my/path/to/output/file.json

=cut
