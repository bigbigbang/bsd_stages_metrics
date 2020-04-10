#!/usr/local/bin/perl
$ENV{"LC_ALL"} = "POSIX";
use warnings;
use strict;
use Filesys::Df;

# get fileSystem and mount point

my %fs;
my @cmd = `mount`;
my $fs;
my $fsMount;

foreach my $line (@cmd)
{
    if ($line =~ /(.+)\son\s(\/\w*)\s\(/)
    {
	$fs = $1;
	$fsMount = $2;
	# get stats for each 
	my $ref = df("$fsMount");  # Default output is 1K blocks
	if(defined($ref))
	{
	    my $btotal=$ref->{blocks};
	    my $bused = $ref->{used};
 	    my $pused= $ref->{per};
	    my $itotal=0;
	    my $iused=0;
   	    if(exists($ref->{files}))
	    {
		$itotal = $ref->{files};
		$iused = $ref->{fused};
   	    }
	    # example:
	    # printf "ovh.monitoring.celery.active.workers{host=$host} $s -1\n";
	    #1547736587616283// os.disk.fs{host=smb-gra1-2.ovh.net, disk=homez/home}{mount=/homez/home} 46.815948280069215
	    #1547736587616283// os.disk.fs{host=smb-gra1-2.ovh.net, disk=homez/home@2018-10-12_13:08:03}{mount=/homez/snap/install} 46.815948280069215
	    print("os.disk.fs{disk=$fs,mount=$fsMount} ".time." $pused\n");
	    print("os.disk.fs.used{disk=$fs,mount=$fsMount} ".time." $bused\n");
	    print("os.disk.fs.total{disk=$fs,mount=$fsMount} ".time." $btotal\n");
	    print("os.disk.fs.inodes.total{disk=$fs,mount=$fsMount} ".time." $itotal\n");
	    print("os.disk.fs.inodes.used{disk=$fs,mount=$fsMount} ".time." $iused\n");
	}

    }
    
}
