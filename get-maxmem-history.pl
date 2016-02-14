#!/usr/bin/perl
use strict;
use warnings;

my $atop_cache_cmd = '/tmp/atop_cache.cmd';
my $atop_cache_mem = '/tmp/atop_cache.mem';
my $atop_cache_memcmd = '/tmp/atop_cache.memcmd';
my $interval_re = qr|^ATOP.*(\d{4}/\d\d/\d\d)\s+(\d\d:\d\d:\d\d)|;
my $atop_cmd_re = qr|^(\d+)\s+\S+\s+\S+\s+\d+%\s+(.*)$|;
my $atop_mem_re = qr|^PRM\s+\S+\s+(\d+)\s+(\d{4}/\d\d/\d\d)\s+(\d\d:\d\d:\d\d)\s+\d+\s+(\d+)\s+\((\S+)\)\s+\S+\s+\d+\s+\d+\s+(\d+)|;

system(qq(for i in /var/log/atop/atop.log.*; do atop -r \$i -mc >> $atop_cache_cmd; done)) if not -f $atop_cache_cmd;
system(qq(for i in /var/log/atop/atop.log.*; do atop -r \$i -PPRM >> $atop_cache_mem; done)) if not -f $atop_cache_mem;
my ($fh_cmd, $fh_mem, $fh_memcmd);

if (not -f $atop_cache_memcmd) {
  open($fh_cmd, '<', $atop_cache_cmd) or die;
  open($fh_mem, '<', $atop_cache_mem) or die;
  open($fh_memcmd, '>', $atop_cache_memcmd) or die;
  
  # ATOP - localhost123    2015/06/04  06:25:05    ---------    174d7h0m30s elapsed
  # 27401     - R   6% /usr/bin/perl /var/www/ololo.pl
  my $interval_date;
  my $interval_time;
  my %interval_data;
  while (my $line = <$fh_cmd>) {
    if ($line =~ /$interval_re/) { 
      if (scalar keys %interval_data) {
          merge_interval(\%interval_data, $interval_date, $interval_time);
          undef %interval_data;
      }
      ($interval_date, $interval_time) = ($1, $2);
      next;
    }
    my ($pid, $cmd) = ($line =~ /$atop_cmd_re/);
    $interval_data{$pid} = $cmd if $pid and $cmd;
  }
}

if (-f $atop_cache_memcmd and scalar @ARGV) {
  my $filter = $ARGV[0];
  my ($avgmem, $maxmem, $c) = (0, 0, 0);
  open(my $fh, '-|', qq(grep -E '$filter' $atop_cache_memcmd | awk '{ print \$2 }')) or die;
  while (<$fh>) { ++$c; $avgmem += $_; $maxmem = $_ if $_ > $maxmem; };
  if ($c > 0) {
    ($avgmem, $maxmem) = ($avgmem / 1024.0 / $c, $maxmem / 1024.0);
    printf "%s: avg: %d MB, max: %d MB\n", $filter, $avgmem, $maxmem;
  } else {
    print "not found\n";
  }
}


sub merge_interval {
  # PID, name (between brackets), state, page size for this machine (in bytes), virtual memory size (Kbytes), resident memory size (Kbytes)
  # PRM localhost123 1433647507 2015/06/07 06:25:07 15318031 543 (ololo.pl) S 4096 217984 32296 8 217984 32296 18431 0 10276 101164 136 0 543 y
  my ($data, $date, $time) = @_;
  my $found_interval = 0;
  while (my $line = <$fh_mem>) {
    my ($epoch, $interval_date, $interval_time, $pid, $name, $rss) = ($line =~ /$atop_mem_re/);
    map { next if not $_ } ($epoch, $interval_date, $interval_time, $pid, $name, $rss);
    if ($interval_date eq $date and $interval_time eq $time) {
      printf($fh_memcmd "%d %d %s\n", $epoch, $rss, $data->{$pid}) if $data->{$pid};
      $found_interval = 1;
    }
    elsif ($found_interval) {
      return;
    }
  }
}
