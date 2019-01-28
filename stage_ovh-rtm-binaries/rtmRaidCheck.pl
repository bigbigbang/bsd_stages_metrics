#!/usr/local/bin/perl

$ENV{"LC_ALL"} = "POSIX";

#
# Shows information about RAID arrays such as disks capacity, models, overal array status.
#

use strict;
use IO::Select;

chomp(my @sysctl = `\/sbin\/sysctl dev 2>\/dev\/null`);


# timestamp init :
my $timestamp = time;
# gmirror/gstripe:
chomp(my @gmirror = `gmirror status -s 2>\/dev\/null`);
chomp(my @gstripe = `gstripe status -s 2>\/dev\/null`);
if($#gmirror != -1 or $#gstripe != -1){
  my %raid;

  # gmirror/gstripe enabled
  foreach(@gmirror, @gstripe){
    # mirror/home  DEGRADED  da0s1f (65%)
    next unless $_ =~  m/^\s*(mirror|stripe)\/(\S+)\s+(\S+)\s+(\S+?)\s(?:\((\d+)%\))?\s*/;
    $raid{$1}{$2}{state} = $3;
    my %tmp = (name=>$4);
    $tmp{syncpercent} = $5 if $5;
    push @{$raid{$1}{$2}{disks}}, \%tmp;
  }

  foreach my $type (keys %raid){
    foreach my $vol (keys %{$raid{$type}}){
      my @data;
      if($type eq 'mirror'){
        chomp(@data = `gmirror list $vol 2>\/dev\/null`); 
        print "{\"metric\":\"rtm.hw.scsiraid.unit.$vol.vol0.type\",\"timestamp\":$timestamp,\"value\":\"mirror\"}\n";
      }elsif($type eq 'stripe'){
        chomp(@data = `gstripe list $vol 2>\/dev\/null`); 
        print "{\"metric\":\"rtm.hw.scsiraid.unit.$vol.vol0.type\",\"timestamp\":$timestamp,\"value\":\"stripe\"}\n";
      }

      # volume info:
      foreach(@data){
        last if /Consumers/i;

	#print "hHW_SCSIRAID_UNIT_$type\_vol-$vol\_capacity|$1 $2\n"
	print "{\"metric\":\"rtm.hw.scsiraid.unit.$vol.vol0.capacity\",\"timestamp\":$timestamp,\"value\":\"$1 $2\"}\n"
          if /Mediasize:\s+\d+\s+\((\d+)(\w+)\)$/i;


	  #print "hHW_SCSIRAID_UNIT_$type\_vol-$vol\_phys|$1\n"
        print "{\"metric\":\"rtm.hw.scsiraid.unit.$vol.vol0.phys\",\"timestamp\":$timestamp,\"value\":\"$1\"}\n"
	  if /Components:\s+(\d+)$/i;

        if(/State:\s+(\w+)$/){
          my $st = $1;
          $st eq 'COMPLETE' and $st = 'OK';
          print "{\"metric\":\"rtm.hw.scsiraid.unit.$vol.vol0.status\",\"timestamp\":$timestamp,\"value\":\"$st\"}\n";

        }

	#print "hHW_SCSIRAID_UNIT_$type\_vol-$vol\_flags|$1\n"
        print "{\"metric\":\"rtm.hw.scsiraid.unit.$vol.vol0.flags\",\"timestamp\":$timestamp,\"value\":\"$1\"}\n"
  	  if /Flags:\s*(\w+)$/;
      }

      # disk info:
      my ($ldn, $ldi); # lastDiskName and lastDiskId
      my $consumers = 0;

      foreach(@data){
        # skip volume info:
        $consumers = 1 if /Consumers/i;
        next unless $consumers;


        ($ldi, $ldn) = ($1-1, $2)
          if /^(\d+)\.\s*Name:\s*(\S+)$/;
        
	  #print "hHW_SCSIRAID_PORT_$type\_vol-$vol\_phy$ldi\_capacity|$1 $2\n"
	print "{\"metric\":\"rtm.hw.scsiraid.port.$vol.vol0.$ldn.capacity\",\"timestamp\":$timestamp, \"value\":\"$1 $2\"}\n"
          if /Mediasize:\s+\d+\s+\((\d+)(\w+)\)$/i;

	  # print "hHW_SCSIRAID_PORT_$type\_vol-$vol\_phy$ldi\_status|$1\n"
	print "{\"metric\":\"rtm.hw.scsiraid.port.$vol.vol0.$ldn.status\",\"timestamp\":$timestamp,\"value\":\"$1\"}\n"
          if /State:\s*(\w+)$/;
        
	  #print "hHW_SCSIRAID_PORT_$type\_vol-$vol\_phy$ldi\_flags|$1\n"
	print "{\"metric\":\"rtm.hw.scsiraid.port.$vol.vol0.$ldn.flags\",\"timestamp\":$timestamp,\"value\":\"$1\"}\n"
          if /Flags:\s*(\S+)$/;

        print "{\"metric\":\"rtm.hw.scsiraid.port.$vol.vol0.$ldn.syncprogress\",\"timestamp':$timestamp,\"value\":\"$1\"}\n" 
          if /Synchronized:\s*(\d+)%/;
      }

    }
  }
}

## need to add 3ware and LSI 

sub normalize {
  my $bytes = shift || return 0;
  my @units = qw/KB MB GB TB PB/;
  my $i = -1;

  # if we get bytes/MB/TB and still want to normalize:
  if($bytes =~ /^(\d+)\s*([a-zA-Z]+)\s*$/){
    $bytes = $1;
    my $unit = $2;
    foreach(@units){
      $i++;
      last if uc($unit) eq $_;
    }
  }
  return -1 if $bytes > 1024 and $i >= $#units; # error

  while($bytes > 1024){
    $i++;
    $bytes = int($bytes/1024);
  }
  return $bytes." $units[$i]";
}


