#!/usr/bin/env perl

# Identify which file is broken when ATA error occured.
#
# USAGE:
# ./check_hdd.pl PATH

use strict;
use warnings;

use Time::HiRes;
use File::Basename;
use Getopt::Std;
use File::Find::Rule;
use Time::Progress;
use Log::Log4perl qw(:easy);

use Data::Dumper;

use constant READ_BLOCK_SIZE   => 64*1024*1024;
use constant DMESG             => 'demsg';
use constant DMESG_ERROR_REGEX => '^\[\d+\.\d+\] ata\d\.\d+: failed command';

sub show_setting
{
    my $path_list = shift;
    my $depth = shift;
    print <<"__TEXT__";
======================================================================
[CHECK SETTING]
  * PATH
@{[ map { "      - $_\n" } @{$path_list} ]}  * DEPTH
      $depth
__TEXT__
}

sub get_last_ata_dmesg
{
    my @dmesg = reverse(split(m|\n|, `dmesg | tail -n 100`));

    foreach my $line (@dmesg) {
    next unless $line =~ m|${\(DMESG_ERROR_REGEX)}|;
    chomp $line;
    return $line;
    }
    return '';
}

sub create_error_monitor {
    my $last_error = get_last_ata_dmesg();
    return {
    check => sub {
        my $message = shift;
        my $new_error = get_last_ata_dmesg();

        if ($new_error ne $last_error) {
        ERROR(sprintf('ERROR: %s (%s)', $message, $new_error));
        $last_error = $new_error;
        return 1;
        } else {
        return 0;
        }
    }
    };
}

sub get_dir_list
{
    my $path_list = shift;
    my $depth = shift;

    my $error_monitor = create_error_monitor();
    my @dir_list;
    foreach my $path (@{$path_list}) {
    my @dir = File::Find::Rule->directory->maxdepth($depth)
        ->extras({ follow => 0 })->in($path);
    $error_monitor->{check}->($path);
    push(@dir_list, @dir);
    }

    my @filtered;
    foreach my $dir_path (@dir_list) {
    push(@filtered, $dir_path)
        if (scalar(grep(m|^$dir_path/|, @dir_list)) == 0);
    }
    return [sort @filtered];
}

sub check_dir
{
    my $dir_path = shift;
    my $error_monitor = create_error_monitor();

    my @file_list = File::Find::Rule->file->extras({ follow => 0 })->in($dir_path);
    $error_monitor->{check}->($dir_path);

    foreach my $file_path (@file_list) {
    my $buf;
    open(FILE, $file_path) or die $!;
    while (read(FILE, $buf, READ_BLOCK_SIZE) != 0) {
        Time::HiRes::sleep(0.1);
        my $is_error = $error_monitor->{check}->($file_path);
        last if $is_error;
    }
    close(FILE);
    }
}

sub exec_check 
{
    my $path_list = shift;
    my $depth = shift;

    my $dir_list = get_dir_list($path_list, $depth);
    my $dir_count = scalar(@{$dir_list});
    my $progress = Time::Progress->new();

    $progress->attr(min => 0, max => scalar(@{$dir_list}));

    local $| = 1;

    foreach my $i (0..($dir_count-1)) {
    my $dir_path = $dir_list->[$i];

    printf "Processing: %-75s\n", $dir_path;
    print $progress->report("%40b $i/$dir_count (%p), eta: %E min\r", $i + 1);

    check_dir($dir_path);
    }
    print $progress->report("%40b $dir_count/$dir_count (%p), eta: %E min\r", $dir_count);
    $progress->stop;
    print "\n";
    print $progress->elapsed_str, "\n";
}

Log::Log4perl->easy_init({
    level   => $ERROR,
    file    => '>>' . (basename($0) =~ m|^([^.]+)|)[0] . '.error',
});

my %opt;
getopts('d:' => \%opt);

my @path = @ARGV;
my $depth = $opt{d} || 1;

show_setting(\@path, $depth);
exec_check(\@path, $depth);

__END__
