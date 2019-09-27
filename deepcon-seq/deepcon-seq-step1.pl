#!/usr/bin/perl -w
# Badri Adhikari, 6-7-2019
# Accepts: Multiple-sequence-alignment (.aln) file as input
# Generates: Feature file (.txt) with the following features:
#  -> Psipred - https://www.ncbi.nlm.nih.gov/pubmed/10869041
#  -> Psisolv - https://www.ncbi.nlm.nih.gov/pubmed/10869041
#  -> Shannon entropy sum - features from the .colstat file generated by the alnstat program in MetaPSICOV
#						  - https://www.ncbi.nlm.nih.gov/pubmed/25431331
#  -> ccmpred - https://github.com/soedinglab/CCMpred
#  -> freecontact - https://rostlab.org/owiki/index.php/FreeContact
#  -> pstat_pots - features from the .pairstat file generated by the alnstat program in MetaPSICOV
#				 - https://www.ncbi.nlm.nih.gov/pubmed/25431331

use strict;
use warnings;
use Carp;
use Cwd 'abs_path';
use File::Basename;

####################################################################################################
my $aln    = shift;
my $outdir = shift;

if (not $aln){
	print "Output directory not defined!\n";
	print "Usage: $0 <aln> <output-directory>\n";
	exit(1);
}

if (not $outdir){
	print "Output directory not defined!\n";
	print "Usage: $0 <aln> <output-directory>\n";
	exit(1);
}

####################################################################################################
use constant{
	PSIPRED      => '/tmp/tools/runpsipredandsolv.tcsh',
	ALNSTAT      => '/tmp/tools/metapsicov/metapsicov-2.0.3/bin/alnstats',
	FREECONTACT  => '/usr/bin/freecontact',
	PSICOV       => '/tmp/tools/psicov/psicov',
	CCMPRED      => '/tmp/tools/CCMpred/bin/ccmpred'
};

confess "Oops!! psipred program not found at ".PSIPRED      if not -f PSIPRED;
confess "Oops!! alnstat program not found at ".ALNSTAT      if not -f ALNSTAT;
confess 'Oops!! psicov not found at '.PSICOV                if not -f PSICOV;
confess 'Oops!! ccmpred qq not found!'.CCMPRED              if not -f CCMPRED;
confess 'Oops!! freecontact not found!'.FREECONTACT         if not -f FREECONTACT;

####################################################################################################
print "Started [$0]: ".(localtime)."\n";

my $id = basename($aln, ".aln");
my $rootpath = dirname(abs_path($0));
system_cmd("mkdir -p $outdir") if not -d $outdir;

print "\n";
system_cmd("echo \">$id\" > $outdir/$id.fasta");
system_cmd("head -1 $aln >> $outdir/$id.fasta");

$outdir = abs_path($outdir);
$aln = abs_path($aln);
my $fasta = "$outdir/$id.fasta";
print "Input: $aln\n";
print "L    : ".length(seq_fasta($fasta))."\n";
print "Seq  : ".seq_fasta($fasta)."\n\n";

chdir $outdir or confess $!;

####################################################################################################
print "\n";
print "Predicting secondary structure and solvent accessibility using PSIPRED..\n";
system_cmd("mkdir -p $outdir/psipred");
chdir $outdir."/psipred" or confess $!;
system_cmd("echo \">$id\" > ./$id.fasta");
system_cmd("echo \"".seq_fasta($fasta)."\" >> ./$id.fasta");
if (-s "$id.solv"){
	print "Looks like .solv file is already here.. skipping..\n";
}
else{
	system_cmd(PSIPRED." $fasta");
}
chdir $outdir or confess $!;

####################################################################################################
print "\n\n";
print "Generate alignment stats ..\n";
system_cmd("mkdir -p alnstat");
system_cmd("cp $aln $outdir/alnstat/");
chdir $outdir."/alnstat" or confess $!;
system_cmd(ALNSTAT." $id.aln $id.colstats $id.pairstats");
chdir $outdir or confess $!;

####################################################################################################
print "\n\n";
print "Contact Predictions ..\n";
my $ccmpreddir     = "$outdir/ccmpred";
my $freecontactdir = "$outdir/freecontact";
system_cmd("mkdir -p $ccmpreddir");
system_cmd("mkdir -p $freecontactdir");
if (count_lines($aln) <= 5){
	warn "Too few sequences in the alignment!\n";
}

####################################################################################################
chdir $ccmpreddir or confess $!;
system_cmd("cp $aln ./");
open  JOB, ">$id-ccmpred.sh" or confess "ERROR! Could not open $id-ccmpred.sh $!";
print JOB "#!/bin/bash\n";
print JOB "touch ccmpred.running\n";
print JOB "echo \"running ccmpred ..\"\n";
print JOB CCMPRED." -t 4 $aln $id.ccmpred > ccmpred.log\n";
print JOB "if [ -s \"$id.ccmpred\" ]; then\n";
print JOB "   mv ccmpred.running ccmpred.done\n";
print JOB "   echo \"ccmpred job done.\"\n";
print JOB "   exit\n";
print JOB "fi\n";
print JOB "echo \"ccmpred failed!\"\n";
print JOB "mv ccmpred.running ccmpred.failed\n";
close JOB;
system_cmd("chmod 755 $id-ccmpred.sh");

if (not -f "$ccmpreddir/$id.ccmpred"){
	print "Starting job $id-ccmpred.sh ..\n";
	system "./$id-ccmpred.sh > $id-ccmpred.log";
	sleep 1;
}

####################################################################################################
chdir $freecontactdir or confess $!;
system_cmd("cp $aln ./");
open  JOB, ">$id-freecontact.sh" or confess "ERROR! Could not open $id-freecontact.sh $!";
print JOB "#!/bin/bash\n";
print JOB "touch freecontact.running\n";
print JOB "echo \"running freecontact ..\"\n";
print JOB "export LD_LIBRARY_PATH=/storage/hpc/group/prayog/TOOLS/freecontact-1.0.21/freecontact/lib \n";
print JOB "".FREECONTACT." < $aln > $id.freecontact.rr\n";
print JOB "if [ -s \"$id.freecontact.rr\" ]; then\n";
print JOB "   mv freecontact.running freecontact.done\n";
print JOB "   echo \"freecontact job done.\"\n";
print JOB "   exit\n";
print JOB "fi\n";
print JOB "echo \"freecontact failed!\"\n";
print JOB "mv freecontact.running freecontact.failed\n";
close JOB;
system_cmd("chmod 755 $id-freecontact.sh");

if(not -f "$freecontactdir/$id.freecontact.rr"){
	print "Starting job $id-freecontact.sh ..\n";
	system "./$id-freecontact.sh";
	sleep 1;
}

####################################################################################################
print "\nChecking FreeContact prediction..\n";
if(not -f "$freecontactdir/$id.freecontact.rr"){
	confess "Looks like CCMpred did not finish! $freecontactdir/$id.freecontact.rr is absent!\n";
	system_cmd("touch $freecontactdir/$id.freecontact.rr");
}

####################################################################################################
print "\nChecking CCMpred prediction..\n";
if(not -f "$ccmpreddir/$id.ccmpred"){
	confess "Looks like CCMpred did not finish! $ccmpreddir/$id.ccmpred is absent!\n";
	system_cmd("touch $ccmpreddir/$id.ccmpred");
}

####################################################################################################
print "\n\n";
print "Verify coevolution-based contact predictions ..\n";
if (not -s "$ccmpreddir/$id.ccmpred"){
	warn "Warning! ccmpred/$id.ccmpred file is empty!\n";
}
if (not -s "$freecontactdir/$id.freecontact.rr"){
	warn "Warning! freecontact/$id.freecontact.rr file is empty!\n";
}

####################################################################################################
print "\n";
print "Generating feature file..\n";

my $fasta_fname       = $fasta;
my $ss_sa_fname       = "$outdir/ss_sa/$id.ss_sa";
my $colstat_fname     = "$outdir/alnstat/$id.colstats";
my $pairstat_fname    = "$outdir/alnstat/$id.pairstats";
my $freecontact_fname = "$outdir/freecontact/$id.freecontact.rr";
my $ccmpred_fname     = "$outdir/ccmpred/$id.ccmpred";
my $psipred_fname     = "$outdir/psipred/$id.ss2";
my $psisolv_fname     = "$outdir/psipred/$id.solv";

####################################################################################################
open FASTA, "<" . $fasta_fname or die "Couldn't open fasta file ".$fasta_fname."\n";
my @lines = <FASTA>;
chomp(@lines);
close FASTA;

shift @lines;
my $seq = join('', @lines);
$seq =~ s/ //g;
my @seq = split(//, $seq);

my $seq_len = length($seq);

####################################################################################################
open SS_SA, "<" . $ss_sa_fname or die "Couldn't open ss_sa file\n";
my @ss_sa=<SS_SA>;
chomp @ss_sa;
my @ss = split(//, $ss_sa[2]);
my @sa = split(//, $ss_sa[3]);
close SS_SA;

my $beta_count = 0; my $alpha_count = 0;
foreach my $ss_t (@ss) {
  if($ss_t eq 'E') {
    $beta_count++;
  }
  if($ss_t eq 'H') {
    $alpha_count++;
  }
}

my $exposed_count = 0;
foreach my $sa_t (@sa) {
  if($sa_t eq 'b') {
    $exposed_count++;
  }
}

####################################################################################################
my @psipredss;
open INPUT, $psipred_fname or confess $!;
while(<INPUT>){
	$_ =~ s/^\s+//;
	next if $_ !~ m/^[0-9]/;
	my @columns = split(/\s+/, $_);
	$psipredss[$columns[0]][0] = $columns[3];
	$psipredss[$columns[0]][1] = $columns[4];
	$psipredss[$columns[0]][2] = $columns[5];
}
close INPUT;

####################################################################################################
my @psisolv;
open INPUT, $psisolv_fname or confess $!;
while(<INPUT>){
	$_ =~ s/^\s+//;
	next if $_ !~ m/^[0-9]/;
	my @columns = split(/\s+/, $_);
	$psisolv[$columns[0]] = $columns[2];
}
close INPUT;

####################################################################################################
# Initialize coevolutionary features to zero
my %con_ccmpre = %{all_zero_2D_features(0)};
my %con_frecon = %{all_zero_2D_features(1)};
my %con_psicov = %{all_zero_2D_features(1)};
my %pstat_pots = %{all_zero_2D_features(1)};
my %pstat_mimt = %{all_zero_2D_features(1)};
my %pstat_mip  = %{all_zero_2D_features(1)};
my $colstatrow = "1 1";
my @colstat    = split /\s+/, $colstatrow;

# Obtain co-evolution features
if (-f $ccmpred_fname){
	%con_ccmpre = %{ccmpred2hash($ccmpred_fname)};
	%con_frecon = %{freecontact2hash($freecontact_fname)};
	%pstat_pots = %{pairstat2hash($pairstat_fname, "potsum")};
	%pstat_mimt = %{pairstat2hash($pairstat_fname, "mimat")};
	%pstat_mip  = %{pairstat2hash($pairstat_fname, "mip")};
	$colstatrow = colstatfeatures($colstat_fname);
	@colstat    = split /\s+/, $colstatrow;
}
else{
	print STDERR 'Coevolutionary features absent for '. $ccmpred_fname;
}

####################################################################################################
open OUT, ">$outdir/$id.input.features" or confess "ERROR! Could not open $id.input.features $!";

print OUT "# Sequence\n";
print OUT "$seq\n";

print OUT "# Psipred\n";
for(my $i = 0; $i < 3; $i++){
	for(my $j = 1; $j <= $seq_len; $j++) {
		printf OUT " %.3f", $psipredss[$j][$i];
	}
	print OUT "\n";
}

####################################################################################################
print OUT "# Psisolv\n";
for(my $i = 1; $i <= $seq_len; $i++) {
	printf OUT " %.3f", $psisolv[$i];
}
print OUT "\n";

####################################################################################################
print OUT "# Shannon entropy sum\n";
my @entropy = colstat_entropy($colstat_fname);
for(my $i = 21; $i <= 21; $i++){
	for(my $j = 0; $j < $seq_len; $j++) {
		printf OUT " %.3f", $entropy[$i][$j];
	}
	print OUT "\n";
}

####################################################################################################
print OUT "# ccmpred\n";
for(my $i = 0; $i < $seq_len; $i++){
	for(my $j = 0; $j < $seq_len; $j++){
		my $xx = $con_ccmpre{$i." ".$j};
		$xx = 0 if not defined $xx;
		printf OUT " %.4f", $xx;
	}
}
print OUT "\n";

####################################################################################################
print OUT "# freecontact\n";
for(my $i = 1; $i <= $seq_len; $i++){
	for(my $j = 1; $j <= $seq_len; $j++){
		my $xx = $con_frecon{$i." ".$j};
		$xx = 0 if not defined $xx;
		$xx = 0 if $xx < 0;
		printf OUT " %.4f", $xx;
	}
}
print OUT "\n";

####################################################################################################
print OUT "# pstat_pots\n";
for(my $i = 1; $i <= $seq_len; $i++){
	for(my $j = 1; $j <= $seq_len; $j++){
		my $xx = $pstat_pots{$i." ".$j};
		$xx = 0 if not defined $xx;
		printf  OUT " %.4f", (1 + exp(-$xx)) ** -1;
	}
}
print OUT "\n";

close OUT;

print "Strip leading spaces from feature files..\n";
system_cmd("sed -i 's/^ *//g' $outdir/$id.input.features");

####################################################################################################
sub ccmpred2hash{
	my $file_ccmpred = shift;
	die "ERROR! file_ccmpred not defined!" if !$file_ccmpred;
	my %conf = ();
	open CCM, $file_ccmpred or die $!." $file_ccmpred";
	my $i = 0;
	while(<CCM>){
		$_ =~ s/^\s+//;
		my @C = split /\s+/, $_;
		for(my $j = 0; $j <= $#C; $j++){
			$conf{$i." ".$j} = $C[$j];
			$conf{$j." ".$i} = $C[$j];
		}
		$conf{$i." ".$i} = 1;
		$i++;
	}
	close CCM;
	return \%conf;
}

####################################################################################################
sub freecontact2hash{
	my $file_fc = shift;
	die "ERROR! file_freecontact not defined!" if !$file_fc;
	my %conf = ();
	open FC, $file_fc or die $!." $file_fc";
	while(<FC>){
		$_ =~ s/\r//g;
		$_ =~ s/^\s+//;
		next unless $_ =~ /^[0-9]/;
		my @C = split /\s+/, $_;
		$conf{$C[0]." ".$C[2]} = $C[5];
		$conf{$C[2]." ".$C[0]} = $C[5];
		$conf{$C[0]." ".$C[0]} = 1;
		$conf{$C[2]." ".$C[2]} = 1;
	}
	close FC;
	return \%conf;
}

####################################################################################################
sub pairstat2hash{
	my $file_pairstat = shift;
	my $option = shift;
	die "ERROR! file_freecontact not defined!" if !$file_pairstat;
	my %pairs = ();
	open PS, $file_pairstat or die $!." $file_pairstat";
	while(<PS>){
		$_ =~ s/\r//g;
		$_ =~ s/^\s+//;
		next unless $_ =~ /^[0-9]/;
		my @C = split /\s+/, $_;
		my $value = 0;
		$value = $C[2] if $option eq "potsum"; # mean contact potential
		$value = $C[3] if $option eq "mimat";  # mutual information
		$value = $C[4] if $option eq "mip";    # normalized mutual information
		$pairs{$C[0]." ".$C[1]} = $value;
		$pairs{$C[1]." ".$C[0]} = $value;
	}
	close PS;
	return \%pairs;
}

####################################################################################################
sub colstatfeatures{
	my $file_colstat = shift;
	my $option = shift;
	die "ERROR! file_freecontact not defined!" if !$file_colstat;
	open CS, $file_colstat or die $!." $file_colstat";
	my @lines = <CS>;
	close CS;
	chomp @lines;
	my $seqlen      = $lines[0];
	my $alignlen    = $lines[1];
	my $effalignlen = $lines[2];
	if(not defined $seqlen){
		return "0 0";
	}
	$alignlen = 0 if not defined $alignlen;
	$effalignlen = 0 if not defined $effalignlen;
	if($seqlen ne length($seq)){
		print STDERR "ERROR! Fasta file reports seqlen is ".length($seq)." but colstat feature file reports ".$seqlen." [fasta: $fasta_fname]\n";
	}
	return ($alignlen)." ".($effalignlen);
}

####################################################################################################
sub colstat_entropy{
	my $file_colstat = shift;
	my $option = shift;
	die "ERROR! file_freecontact not defined!" if !$file_colstat;
	open CS, $file_colstat or die $!." $file_colstat";
	my @lines = <CS>;
	close CS;
	my @aaentropy;
	for (my $l = 4; $l < $seq_len + 4; $l++){
		my @aacomp = split /\s+/, $lines[$l];
		for (my $i = 0; $i <= $#aacomp; $i++){
			$aaentropy[$i][$l - 4] = $aacomp[$i];
			if ($aacomp[$i] eq ""){
				print STDERR "space in aacomp.. something is wrong.. $l $i";
				exit 1;
			}
		}
	}
	return @aaentropy;
}

####################################################################################################
sub all_zero_2D_features{
	my $start_at = shift;
	my $start = 0;
	my $end = $seq_len;
	$start = 1 if $start_at == 0;
	$end   = $end + 1 if $start_at == 0;
	my %feat = ();
	for(my $i = $start; $i < $end; $i++){
		for(my $j = $start; $j < $end; $j++){
			$feat{$i." ".$j} = 0
		}
	}
	return \%feat;
}


####################################################################################################
sub system_cmd{
	my $command = shift;
	my $log = shift;
	confess "EXECUTE [$command]?\n" if (length($command) < 5  and $command =~ m/^rm/);
	if(defined $log){
		system("$command &> $log");
	}
	else{
		print "[[Executing: $command]]\n";
		system($command);
	}
	if($? != 0){
		my $exit_code  = $? >> 8;
		confess "ERROR!! Could not execute [$command]! \nError message: [$!]";
	}
}

####################################################################################################
sub count_lines{
	my $file = shift;
	my $lines = 0;
	return 0 if not -f $file;
	open FILE, $file or confess "ERROR! Could not open $file! $!";
	while (<FILE>){
		chomp $_;
		$_ =~ tr/\r//d; # chomp does not remove \r
		next if not defined $_;
		next if length($_) < 1;
		$lines ++;
	}
	close FILE;
	return $lines;
}

####################################################################################################
sub seq_fasta{
	my $file_fasta = shift;
	confess "ERROR! Fasta file $file_fasta does not exist!" if not -f $file_fasta;
	my $seq = "";
	open FASTA, $file_fasta or confess $!;
	while (<FASTA>){
		next if (substr($_,0,1) eq ">");
		chomp $_;
		$_ =~ tr/\r//d; # chomp does not remove \r
		$seq .= $_;
	}
	close FASTA;
	return $seq;
}