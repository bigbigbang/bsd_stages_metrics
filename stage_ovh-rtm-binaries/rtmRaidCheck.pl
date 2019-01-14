#! /usr/local/bin/perl

$ENV{"LC_ALL"} = "POSIX";

#
# Shows information about RAID arrays such as disks capacity, models, overal array status.
#


use strict;
use IO::Select;

chomp(my @sysctl = `\/sbin\/sysctl dev 2>\/dev\/null`);

# TODO: Soft RAID with:
#   - gvinum and raid-5
#
# TODO: Mylex RAID support (no tools found. Only megarc/amrstat but not working for all cards)

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
    next unless $_ =~  m/^\s*(mirror|stripe)\/(\S+)\s+(\S+)\s+(.*?)(?:\s+\((\d+)%\))?\s*$/;
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
        print "hHW_SCSIRAID_UNIT_$type\_vol-$vol\_type|MIRROR\n";
        print "{'metric':'rtm.hw.scsiraid.unit.$vol.vol0.type','timestamp':$timestamp,'value':mirror}\n";
      }elsif($type eq 'stripe'){
        chomp(@data = `gstripe list $vol 2>\/dev\/null`); 
        print "hHW_SCSIRAID_UNIT_$type\_vol-$vol\_type|STRIPE\n";
        print "{'metric':'rtm.hw.scsiraid.unit.$vol.vol0.type','timestamp':$timestamp,'value':'stripe'}\n";
      }

      # volume info:
      foreach(@data){
        last if /Consumers/i;

	#print "hHW_SCSIRAID_UNIT_$type\_vol-$vol\_capacity|$1 $2\n"
	print "{'metric':'rtm.hw.scsiraid.unit.$vol.vol0.capacity','timestamp':$timestamp,'value':'$1 $2}\n"
          if /Mediasize:\s+\d+\s+\((\d+)(\w+)\)$/i;


	  #print "hHW_SCSIRAID_UNIT_$type\_vol-$vol\_phys|$1\n"
        print "{'metric':'rtm.hw.scsiraid.unit.$vol.vol0.phys','timestamp':$timestamp,'value':'$1'}\n"
	  if /Components:\s+(\d+)$/i;

        if(/State:\s+(\w+)$/){
          my $st = $1;
          $st eq 'COMPLETE' and $st = 'OK';
          print "hHW_SCSIRAID_UNIT_$type\_vol-$vol\_status|$st\n";
          print "{'metric':'rtm.hw.scsiraid.unit.$vol.vol0.status','timestamp':$timestamp,'value':'$st'}\n";

        }

	#print "hHW_SCSIRAID_UNIT_$type\_vol-$vol\_flags|$1\n"
        print "{'metric':'rtm.hw.scsiraid.unit.$vol.vol0.flags','timestamp':$timestamp,'value':'$1'}\n"
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
	print "{'metric':'rtm.hw.scsiraid.port.$vol.vol0.phy$ldi.capacity','timestamp':$timestamp, 'value':'$1 $2'}\n"
          if /Mediasize:\s+\d+\s+\((\d+)(\w+)\)$/i;

	  # print "hHW_SCSIRAID_PORT_$type\_vol-$vol\_phy$ldi\_status|$1\n"
	print "{'metric':'rtm.hw.scsiraid.port.$vol.vol0.phy$ldi.status','timestamp':$timestamp,'value':'$1'}\n"
          if /State:\s*(\w+)$/;
        
	  #print "hHW_SCSIRAID_PORT_$type\_vol-$vol\_phy$ldi\_flags|$1\n"
	print "{'metric':'rtm.hw.scsiraid.port.$vol.vol0.phy$ldi.flags','timestamp':$timestamp,'value':'$1'}\n"
          if /Flags:\s*(\S+)$/;

        print "hHW_SCSIRAID_PORT_$type\_vol-$vol\_phy$ldi\_syncprogress|$1\n"
          if /Synchronized:\s*(\d+)%/;
      }

    }
  }
}


# 3ware (all)
if (map {$_ =~ /3ware/i} @sysctl) {
  my (%units, @controlers, %models);

  chomp(my @twCliInfo = `\/usr\/local\/sbin\/tw_cli info 2>\/dev\/null`);

  # parse tw_cli basis view:
  foreach my $line (@twCliInfo) {
    if ($line =~ m/Controller (\d+):/)  { push @controlers, $1;}
    if ($line =~ /^c(\d+)\s+(\S+)\s+/)  { push @controlers, $1; $models{$1} = $2;}
  }


  foreach my $controler (@controlers) {
    chomp(@twCliInfo = `\/usr\/local\/sbin\/tw_cli info c$controler 2>\/dev\/null`);

    # parse tw_cli detailed info:
    foreach my $line (@twCliInfo) {
      if ( $line =~ m/Unit\s(\d):\s+(RAID\s+\d+|[^\s]+)\s([^\s]+)\s([^\s]+)[^:]+:\s(.+)/) {
        print "hHW_SCSIRAID_UNIT_c$controler\_u$1_capacity|$3 $4\n";
        print "hHW_SCSIRAID_UNIT_c$controler\_u$1_type|$2\n";
        print "hHW_SCSIRAID_UNIT_c$controler\_u$1_status|$5\n";
      }
      if ( $line =~ m/Port\s(\d+):\s([^\s]+)\s([^\s]+)\s([^\s]+)\s([^\s]+)\s([^\s]+)[^:]+:\s([^\(]+)\(unit\s(\d+)/) {
        print "hHW_SCSIRAID_PORT_c$controler\_u$8_phy$1_capacity|$5 $6\n";
        print "hHW_SCSIRAID_PORT_c$controler\_u$8_phy$1_model|$2 $3\n";
        print "hHW_SCSIRAID_PORT_c$controler\_u$8_phy$1_status|$7\n";
        if (! exists $units{$controler}{$8}) {$units{$controler}{$8} = 0;}
        $units{$controler}{$8} = $units{$controler}{$8} + 1;
      }

      # 3ware models: 7xxx, 8xxx, 9xxx, 95xx:
      # Units:
      # ONLY FreeBSD: 
      # Unit  UnitType  Status         %RCmpl  %V/I/M  Stripe  Size(GB)  Cache  AVrfy
      if (  $line =~ /^u(\d+)\s+(RAID\-\d+)\s+(\S+)\s+\S+\s+\S+\s+(\S+)\s+(\S+).*/ )
      {
        print "hHW_SCSIRAID_UNIT_c$controler\_u$1_capacity|$5 GB\n";
        print "hHW_SCSIRAID_UNIT_c$controler\_u$1_type|$2\n";
        print "hHW_SCSIRAID_UNIT_c$controler\_u$1_status|$3\n";
      }
      # Ports:
      if ( $line =~ /^p(\d+)\s+(\S+)\s+u(\S+)\s+(\S+\s\S+)\s+(\d+)\s+(\S+)\s*$/ )
      {

        print "hHW_SCSIRAID_PORT_c$controler\_u$3_phy$1_capacity|$4\n";
        print "hHW_SCSIRAID_PORT_c$controler\_u$3_phy$1_serial|$6\n";
        print "hHW_SCSIRAID_PORT_c$controler\_u$3_phy$1_status|$2\n";

        if (! exists $units{$controler}{$3}) {$units{$controler}{$3} = 0;}
        $units{$controler}{$3} += 1 if $2 ne "NOT-PRESENT";

        my $p = $1;
        my $u = $3;
        chomp(my $model = `\/usr\/local\/sbin\/tw_cli info c$controler p$p model 2>\/dev\/null`);
        print "hHW_SCSIRAID_PORT_c$controler\_u$u\_phy$p\_model|$1\n"
          if $model =~ /Model\s+=\s+(.*)$/;

      }
    }
    foreach (keys %{$units{$controler}}) {print "hHW_SCSIRAID_UNIT_c$controler\_u$_\_phys|".($units{$controler}{$_})."\n";}
    print "hHW_SCSIRAID_CONTROLLER_c$controler\_model|$models{$controler}\n" if defined $models{$controler};
  }
} elsif (map {$_ =~ /LSILogic/i} @sysctl) {
  # LSILOGIC MPT adapter:

  my (%units, $count);
  chomp(my @dmesg = `dmesg | grep "mpt"`);
  chomp(my @camcontrolDevlist = `\/sbin\/camcontrol devlist`);

  # check UNIT number:
  $count = 0;
  while(my $a = grep {$_ =~ /^mpt$count: (\d+) Active Volume/i} @dmesg) {
    $units{$count}{volumeCount} = $a;
    $count++;
  }

  # foreach unit (mpt0, mpt1, ...)
  foreach my $u (keys %units){

    foreach(@dmesg){
      /^mpt$u:\s*(\d+).*Drive Members/i and $units{$u}{driveCount} = $1;
      /^mpt$u: Capabilities: \( (.*?) \)$/i and $units{$u}{capabilities} = $1;
    }

    # foreach volume: (vol0, vol1, ...)
    for(my $volume=0; $volume<$units{$u}{volumeCount}; $volume++){
      my @revDmesg = reverse @dmesg;
      my ($lastVolStatus, $lastSyncPercent, $lastFlags);

      foreach(@revDmesg) {
        # print capacity of the volume using bus/target/lun from dmesg,
        # from the line with unix device (ad0) at bus .. target .. lun ..
        # WARNING: we assume that unix device numeration is same as scsi volume numeration
        # example:
        # daX is on scsi volume X
        # TODO improve this
        if(/.*$volume at mpt$u bus (\d+) target (\d+) lun (\d+)/){
          chomp(my $c = `\/sbin\/camcontrol readcap $1:$2:$3 -q`);
          if($c =~ /^(\d+),\s*(\d+)$/){
            print "hHW_SCSIRAID_UNIT_mpt$u\_vol-id$volume\_capacity|".(normalize($1*$2))."\n";
          }
        }


        next unless /mpt$u:vol$volume/;

        # status:
        if(/: Status \( (.*?) \)$/ and not $lastFlags){ $lastFlags = uc $1; }

        # state:
        if(/: RAID-\d+ - (.*)$/i){ $lastVolStatus = uc $1;}

        # sync percentage:
        if(/: (\d+) of (\d+) blocks remaining/i){ $lastSyncPercent = int($1/$2 * 100); }

        # we search backwards only till this line:
        last if /Volume Status Changed/;
      }

      print "hHW_SCSIRAID_UNIT_mpt$u\_vol-id$volume\_flags|$lastFlags\n";
      print "hHW_SCSIRAID_UNIT_mpt$u\_vol-id$volume\_status|$lastVolStatus\n";
      print "hHW_SCSIRAID_UNIT_mpt$u\_vol-id$volume\_type|$units{$u}{capabilities}\n";
      print "hHW_SCSIRAID_UNIT_mpt$u\_vol-id$volume\_phys|".$units{$u}{driveCount}."\n";
      print "hHW_SCSIRAID_UNIT_mpt$u\_vol-id$volume\_syncprogress|$lastSyncPercent\n"
        if $lastFlags =~ /syncing/i;

      # foreach drive in volume
      for(my $d=0; $d<$units{$u}{driveCount}; $d++){
        my $lastStatus = ''; 
        my $lastFlags = '';

        foreach(@revDmesg) {
          next unless /^\(mpt$u:vol$volume:$d\):/;

          if(/\(mpt$u:vol$volume:$d\): Status \( (.*) \)$/ and not $lastFlags){
            $lastFlags = uc $1;
          } elsif(/\(mpt$u:vol$volume:$d\): Physical.* Pass-thru \(mpt$u:(\d+):(\d+):(\d+)\)\s*$/){
            my ($bus, $target, $lun) = ($1, $2, $3);
            foreach(@camcontrolDevlist){
              /<(.*?)>\s+at scbus$bus target $target lun $lun/
                and print "hHW_SCSIRAID_PORT_mpt$u\_vol-id$volume\_phy$d\_model|$1\n"
                and last;
            };
            chomp(my $c = `\/sbin\/camcontrol readcap $bus:$target:$lun -q`);
            print "hHW_SCSIRAID_PORT_mpt$u\_vol-id$volume\_phy$d\_capacity|".(normalize($1*$2))."\n"
              if ($c =~ /^(\d+),\s*(\d+)$/);
            # none
          } elsif(/\(mpt$u:vol$volume:$d\): Volume Status Changed.*$/){
            # none
          } elsif(/\(mpt$u:vol$volume:$d\): (.*)$/ and not $lastStatus){
            $lastStatus = uc $1;
          }

          # we search backwards only till this line:
          last if /Physical Disk Status Changed/;
        }
        $lastFlags = 'NONE' if $lastFlags eq 'ENABLED' or $lastFlags eq '';

        print "hHW_SCSIRAID_PORT_mpt$u\_vol-id$volume\_phy$d\_status|$lastStatus\n";
        print "hHW_SCSIRAID_PORT_mpt$u\_vol-id$volume\_phy$d\_flags|$lastFlags\n";
      }
    }
  }
  
}

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

