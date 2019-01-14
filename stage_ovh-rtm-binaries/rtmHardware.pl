#! /usr/bin/perl
$ENV{"LC_ALL"} = "POSIX";
use warnings;
use strict;
use Unix::Uptime; # uptime
use Sys::Info;
use Sys::Info::Constants qw( :device_cpu ); # CPU Info

my %globalSgPaths = ();

my @dmesg_lines = ();

eval {
   my $fnret = getSgPaths();
   if( ok($fnret) )
   {
       %globalSgPaths = %{$fnret->{value}};
   }
};

eval {
    my $fnret = getDmesg();
    if( ok($fnret) )
    {
        @dmesg_lines = @{$fnret->{value}}
    }
};

# init server hash
my %server = ();
$server{'rtm.info.rtm.version'} = "#version#";
$server{'rtm.hostname'} = "Unknown";
$server{'rtm.info.kernel.release'} = "Unknown";
$server{'rtm.info.kernel.version'} = "Unknown";
$server{'rtm.info.release.os'} = "Unknown";
$server{'rtm.info.bios_vendor'} = "Unknown";
$server{'rtm.info.bios_version'} = "Unknown";
$server{'rtm.info.bios_date'} = "Unknown";
$server{'rtm.hw.mb.manufacture'} = "Unknown";
$server{'rtm.hw.mb.name'} = "Unknown";
$server{'rtm.hw.mb.serial'} = "Unknown";
$server{'rtm.hw.cpu.name'} = "Unknown";
$server{'rtm.hw.cpu.number'} = "Unknown";
$server{'rtm.hw.cpu.cache'} = "Unknown";
$server{'rtm.hw.cpu.mhz'} = "Unknown";
$server{'rtm.info.uptime'} = "Unknown";
$server{'rtm.info.check.vm'} = "False";
$server{'rtm.info.check.oops'} = "False";

#uptime
# get uptime
my $uptime = Unix::Uptime->uptime(); # 2345
$server{'rtm.info.uptime'} = $uptime;

# CPU info
my %cpu_info = ( 'cpu_no' => 0 );
my %options;
my $info = Sys::Info->new;
my $cpu  = $info->device( CPU => %options );

$server{'rtm.hw.cpu.number'} = $cpu->count;

$server{'rtm.hw.cpu.name'} = scalar($cpu->identify);

my $frequency = `dmidecode -t processor | grep "Max Speed"`;
$frequency =~ /(\d* [M|G]?Hz$)/;
$frequency=$1;
$server{'rtm.hw.cpu.mhz'} = $frequency;
    
#if ($_ =~ /^cache size/) {
#        s/cache size\s+:\s*//g;
#        $server{'rtm.hw.cpu.cache'} = $_;
#    }
#}

eval {
    my $fnret = completeCpuInfo();
    if( ok($fnret) )
    {
        my %info = %{$fnret->{value}};
        $server{'rtm.hw.cpu.fmax_mhz'} = $info{fmax_mhz} || -1;
        $server{'rtm.hw.cpu.fmin_mhz'} = $info{fmin_mhz} || -1;
        $server{'rtm.hw.cpu.sockets'} = $info{sockets} || -1;
        $server{'rtm.hw.cpu.cores'} = $info{cores} || -1;
        $server{'rtm.hw.cpu.threads'} = $info{threads} || -1;
    }
};

# check for allocation failed or kernel oops
if (`dmesg | grep -i "allocation failed"`) {
    $server{'rtm.info.check.vm'}="True";
}

if (`dmesg | grep -i "Oops"`) {
    $server{'rtm.info.check.oops'}="True";
}

$server{'rtm.hostname'}=`hostname`;
$server{'rtm.info.kernel.release'}=`uname -r`;
$server{'rtm.info.kernel.version'}=`uname -v`;
my $osDetect = `uname -s -r -U`;
if ($? == 0)
{
    $server{'rtm.info.release.os'}=$osDetect;
}

# motherboard
my @dmidecode = `dmidecode 2>/dev/null`;
for (my $i = 0; $i < @dmidecode; $i++){
    # Bios
    if($dmidecode[$i] =~ /^\s*BIOS Information/i) {
        my $biosVendor = $dmidecode[$i+1];
        $biosVendor =~ /Vendor:\s+(.*)/;
        $server{'rtm.info.bios_vendor'} = $1;
        my $biosVersion = $dmidecode[$i+2];
        $biosVersion =~ /Version:\s+(.*)/;
        $server{'rtm.info.bios_version'} = $1;
        my $biosRelease = $dmidecode[$i+3];
        $biosRelease =~ /Release Date:\s+(.*)/;
        $server{'rtm.info.bios_date'} = $1;
    }

    # motherboard
    if($dmidecode[$i] =~ /^\s*Base Board Information/i) {
        my $manufacturer = $dmidecode[$i+1];
        $manufacturer =~ /Manufacturer:\s+(.*)/;
        $server{'rtm.hw.mb.manufacture'} = $1;
        my $mbName = $dmidecode[$i+2];
        $mbName =~ /Product Name:\s+(.*)/;
        $server{'rtm.hw.mb.name'} = $1;
        my $mbSerial = $dmidecode[$i+4];
        $mbSerial =~ /Serial Number:\s+(.*)/;
        $server{'rtm.hw.mb.serial'} = $1;

    }
    # memory
    if($dmidecode[$i] =~ /^\s*Memory Device/i) {
        my $bank = $dmidecode[$i+9];
        $bank =~ /Bank Locator:\s+(.*)/;
        $bank = $1;
        next if !$bank;
        $bank =~ s/\s//g;
        $bank =~ s/[\s\.\/\\_]/-/g;
        my $locator = $dmidecode[$i+8];
        $locator =~ /Locator:\s+(.*)/;
        $locator = $1;
        next if !$locator;
        $locator =~ s/\s//g;
        $locator =~ s![\s./\\_#]!-!g;
        my $size = $dmidecode[$i+5];
        $size =~ /Size:\s+(.*)/;
        $size = $1;
        next if !$size;
        $size =~ s/\s*MB\s*//g;
        chomp($size);
        my $type = $dmidecode[$i+10];
        $type =~ /Type:\s+(.*)/;
        $type = $1;
        next if !$type;
        my $speed = $dmidecode[$i+12];
        $speed =~ /Speed:\s+(.*)/;
        $speed = $1;
        next if !$speed;
        my $manufacturer = $dmidecode[$i+13];
        $manufacturer =~ /Manufacturer:\s+(.*)/;
        $manufacturer = $1;
        next if !$manufacturer;
        if ($bank . $locator ne "") {
            $server{'rtm.hw.mem.bank-'.$bank . '-' . $locator} = $size;
#            $server{'rtm.hw.mem.bank-'.$bank . '-' . $locator}{'size'} = $size;
#            $server{'rtm.hw.mem'}{$bank . "-" . $locator}{'type'} = $type;
#            $server{'rtm.hw.mem'}{$bank . "-" . $locator}{'speed'} = $speed;
#            $server{'rtm.hw.mem'}{$bank . "-" . $locator}{'manufacturer'} = $manufacturer;
        }
    }
}

# get disk
my @disks = split(" ",`sysctl -n kern.disks`);
if ($? == 0) {
    foreach my $disk (@disks) {
        if ($disk =~ /(^\w*)/) {
            my $disk = $1;
            $server{'rtm.info.hdd'}{$disk}{'model'}="Unknown";
            $server{'rtm.info.hdd'}{$disk}{'capacity'}="Unknown";
            $server{'rtm.info.hdd'}{$disk}{'serial'}="Unknown";
            $server{'rtm.info.hdd'}{$disk}{'temperature'}=0;
        }
    }
}

# smart on all disk
foreach my $disk (keys %{$server{'rtm.info.hdd'}}) {
    my $diskSmart = "/dev/".$disk;
    my $before = time();
    my @smartctl =  `smartctl -a $diskSmart 2>/dev/null`;
    my $after = time();

    my $smartTime = $after - $before;
    $server{'rtm.info.hdd'}->{$disk}->{'smart'}->{'time'} = $smartTime;

    my $smart_other_error = 0;
    foreach my $line (@smartctl) {
        if ( $line =~ /^Transport\s*protocol\s*:\s+SAS/ )
        {
            $server{'rtm.info.hdd'}->{$disk}->{link_type} = 'sas';
            next;
        }
        if ($line =~ /^(?:Product|Device Model|Model Number):\s+(.*)$/i or $line =~ /Device:\s+([^\s].+)Version/i )
        {
            $server{'rtm.info.hdd'}{$disk}{'model'}=$1;
            next;
        }
        if ($line =~ /^Serial Number:.(.*)$/i) {
            $server{'rtm.info.hdd'}{$disk}{'serial'}=$1;
            next;
        }
        if ($line =~ /.*Capacity:\s+.*\[(.*)\]/) {
            $server{'rtm.info.hdd'}{$disk}{'capacity'}=$1;
            next;
        }
        if ($line =~ /^Firmware Version:.(.*)$/i) {
            $server{'rtm.info.hdd'}{$disk}{'firmware'}=$1;
            next;
        }
        if ($line =~ /^\s+5 Reallocated_Sector_Ct.*\s+(\d+)$/) {
            $server{'rtm.info.hdd'}{$disk}{'smart'}{'reallocated-sector-count'}=$1;
            next;
        }
        if ($line =~ /^187 Reported_Uncorrect.*\s+(\d+)$/) {
            $server{'rtm.info.hdd'}{$disk}{'smart'}{'reported-uncorrect'}=$1;
            next;
        }
        if ($line =~ /^196 Reallocated_Event_Count.*\s+(\d+)$/) {
            $server{'rtm.info.hdd'}{$disk}{'smart'}{'realocated-event-count'}=$1;
            next;
        }
        if ($line =~ /^197 Current_Pending_Sector.*\s+(\d+)$/) {
            $server{'rtm.info.hdd'}{$disk}{'smart'}{'current-pending-sector'}=$1;
            next;
        }
        if ($line =~ /^198 Offline_Uncorrectable.*\s+(\d+)$/) {
            $server{'rtm.info.hdd'}{$disk}{'smart'}{'offline-uncorrectable'}=$1;
            next;
        }
        if ($line =~ /^199 UDMA_CRC_Error_Count.*\s+(\d+)$/) {
            $server{'rtm.info.hdd'}{$disk}{'smart'}{'udma-crc-error'}=$1;
            next;
        }
        if ($line =~ /^200 Multi_Zone_Error_Rate.*\s+(\d+)$/) {
            $server{'rtm.info.hdd'}{$disk}{'smart'}{'multizone-error-rate'}=$1;
            next;
        }
        if ($line =~ /^209 Offline_Seek_Performnce.*\s+(\d+)$/) {
            $server{'rtm.info.hdd'}{$disk}{'smart'}{'offline-seek-performance'}=$1;
            next;
        }
        if ($line =~ /^\s+9 Power_On_Hours.*\s+(\d+)$/) {
            $server{'rtm.info.hdd'}{$disk}{'smart'}{'power-on-hours'}=$1;
            next;
        }

        if ($line =~ /Error \d+ (occurred )?at /){
            if ($line =~ /^read:.+(\d+)$/) {
                $server{'rtm.info.hdd'}{$disk}{'smart'}{'uncorrected-read-errors'}=$1;
                next;
            }
            if ($line =~ /^write:.+(\d+)$/) {
                $server{'rtm.info.hdd'}{$disk}{'smart'}{'uncorrected-write-errors'}=$1;
                next;
            }
        }
    }

    # get hddtemp
    if ($disk =~ /nvme/) {
        my @hddtemp =  `nvme smart-log $diskSmart 2>/dev/null`;
        foreach my $line (@hddtemp) {
            if ($line =~ /^temperature\s+:\s+([0-9]+)/) {
                $server{'rtm.info.hdd'}{$disk}{'temperature'}=$1;
            }
        }
    } else {
	# get temp using smart 
	# @smartctl =  `smartctl -a $diskSmart 2>/dev/null`;
        foreach my $line (@smartctl) {
            if ($line =~ /Drive Temperature:\s+(\d*)/) {
		$server{'rtm.info.hdd'}{$disk}{'temperature'}=$1; 
	    }	    
	}
    }

    # New way to gather stats
    eval {
        my $linkType = $server{'rtm.info.hdd'}->{$disk}->{link_type};
        my $realDisk = $disk;
	if( $disk !~ /^\/dev\// )
	{
	    $realDisk = "/dev/$disk";
	}
        my $fnret = gatherStats( smartDisk => $realDisk, sgPaths => \%globalSgPaths, linkType => $linkType );
        if(ok($fnret) and $fnret->{value})
        {
            my %smartUpdate = %{$fnret->{value}};
            my %smartInfo = defined $server{'rtm.info.hdd'}->{$disk}->{smart} ? %{$server{'rtm.info.hdd'}->{$disk}->{smart}} : ();
            @smartInfo{keys %smartUpdate} = values %smartUpdate;
            $server{'rtm.info.hdd'}->{$disk}->{smart} = \%smartInfo;
        }
    };

    # Get related dmesg errors
    eval {
        my $fnret = countDmesgErrors(
            diskName => $disk,
            lines => \@dmesg_lines,
        );

        if( ok($fnret) )
        {
            $server{'rtm.info.hdd'}->{$disk}->{'dmesg.io.errors'} = $fnret->{value};
        }
    };

    eval {
        my $fnret = iostatCounters(
            diskName => $disk,
        );

        if( ok($fnret) )
        {
	    defined $fnret->{value}->{'ms/r'} and $server{'rtm.info.hdd'}->{$disk}->{'iostat.read.avg.wait'} = $fnret->{value}->{'r_await'};
	    defined $fnret->{value}->{'ms/w'} and $server{'rtm.info.hdd'}->{$disk}->{'iostat.write.avg.wait'} = $fnret->{value}->{'w_await'};
	    # defined $fnret->{value}->{'rrqm/s'} and $server{'rtm.info.hdd'}->{$disk}->{'iostat.read.merged.per.sec'} = $fnret->{value}->{'rrqm/s'};
	    #defined $fnret->{value}->{'wrqm/s'} and $server{'rtm.info.hdd'}->{$disk}->{'iostat.write.merged.per.sec'} = $fnret->{value}->{'wrqm/s'};
            defined $fnret->{value}->{'r/s'} and $server{'rtm.info.hdd'}->{$disk}->{'iostat.read.per.sec'} = $fnret->{value}->{'r/s'};
            defined $fnret->{value}->{'w/s'} and $server{'rtm.info.hdd'}->{$disk}->{'iostat.write.per.sec'} = $fnret->{value}->{'w/s'};
            defined $fnret->{value}->{'%b'} and $server{'rtm.info.hdd'}->{$disk}->{'iostat.busy'} = $fnret->{value}->{'%idle'};
        }

    };

}

#lspci
my @lspci = `lspci -n 2>/dev/null`;
my %lspci_info = ();
if ($? == 0) {
    foreach (@lspci) {
        if (/^(\S+).+:\s+(.+:.+)\s+\(/i) {
            $lspci_info{$1} = $2;
        }
        elsif (/^(\S+).+:\s+(.+:.+$)/i){
            $lspci_info{$1} = $2;
        }
    }
    foreach (keys %lspci_info) {
        my $tempKey = $_;
        $tempKey =~ s/\:|\.|\_/-/g;
            $server{'rtm.hw.lspci.pci.'.$tempKey}=$lspci_info{$_};
    }
}

sub hash_walk {
    my ($hash, $key_list, $callback) = @_;
    while (my ($key, $value) = each (%$hash)) {
        $key =~ s/^\s+|\s+$//g;
        push @$key_list, $key;
        if (ref($value) eq 'HASH') {
            hash_walk($value,$key_list,$callback)
        } else {
            $callback->($key, $value, $key_list);
        }
        pop @$key_list;
    }
}

sub print_keys_and_value {
    my ($k, $v, $key_list) = @_;
    $v =~ s/^\s+|\s+$//g;
    my $key;
    foreach (@$key_list) {
        if ($key) {
            $key = $key.".".$_;
        } else {
            $key = $key.$_;
        }
    }
    print "{\"metric\":\"$key\",\"timestamp\":".time.",\"value\":\"".$v."\"}\n";
}


sub ok
{
    my $arg = shift;

    if ( ref $arg eq 'HASH' and $arg->{status} eq 100 )
    {
        return 1;
    }

    return 0;
}

sub getSectorSize {
    my %params = @_;
    my $disk = $params{disk};
    my $cmd = "diskinfo -v $disk | tail -n +2 | grep sectorsize";
    my $sectorSize = `$cmd`;
    my $last_status = $? >> 8;
    if( $last_status != 0 )
    {
        return { status => 500, msg => "Error: unable to get sector size for device $disk" };
    }
    
    if( $sectorSize =~ /(\d*)/)
    {
	$sectorSize=$1;
    }
    elsif( $sectorSize !~ /(\d+)/ )
    {
        return { status => 500, msg => "Error: unexpected format for sectorSize; $sectorSize" };
    }
    return { status => 100, value => $sectorSize };
}

sub getSmartOverallHealthStatus
{
    my %params = @_;
    my $smartDisk = $params{smartDisk};
    my @lines = `smartctl -H $smartDisk 2>/dev/null`;
    my $last_status = $? >> 8;
    $last_status = $last_status & 7;
    if( $last_status != 0 )
    {
        return { status => 500, msg => "Error: unable to get overall health for device $smartDisk" };
    }
    foreach my $line (@lines)
    {
        if( $line =~ /SMART\s+Health\s+Status:\s+OK|SMART\s+overall-health\s+self-assessment\s+test\s+result:\s+PASSED/ )
        {
            return { status => 100, value => { status => 'success' } };
        }
    }

    return { status => 100, value => { status => 'failed' } };
}


sub getSmartCommonInfo
{
    my %params = @_;
    my $smartDisk = $params{smartDisk};
    my $health = -1;
    my $loggedErrorCount = -1;

    # overall health as boolean 0 -> KO, 1 -> OK
    my $fnret = getSmartOverallHealthStatus(smartDisk => $smartDisk);
    if(ok($fnret))
    {
        $health = $fnret->{value}->{status} eq 'success' ? 1 : 0;
    }

    # any logged error count
    $fnret = getSmartLoggedError(smartDisk => $smartDisk);
    if( ok($fnret) )
    {
        $loggedErrorCount = $fnret->{value}->{logged_error_count};
    }

    return {
        status => 100,
        value => {
            "global-health" => $health,
            "logged-error-count" => $loggedErrorCount
        }
    };
}

sub gatherStats
{
    my %params = @_;
    my $linkType = $params{linkType};
    my %sgPaths = %{$params{sgPaths} || {} };
    my $smartDisk  = $params{smartDisk}  || return { status => 201, msg => 'Missing argument' };
    my $fnret;
    if( $linkType and $linkType eq 'sas' ) {
        my $sgDisk = $sgPaths{$smartDisk}->{sgDrive};
        if( ! $sgDisk )
        {
            return { status => 500, msg => "Unable to get sg path for $smartDisk" };
        }
        $fnret = getSmartStatsSAS( sgDisk => $sgDisk, smartDisk => $smartDisk );
    }
    else
    {
        $fnret = getSmartStatsATA(smartDisk => $smartDisk);
    }
    return $fnret;

}

sub getSmartStatsATA
{
    my %params = @_;
    my $smartDisk  = $params{smartDisk}  || return { status => 201, msg => 'Missing argument' };
    my $sectorSize = getSectorSize( disk => $smartDisk );
    ok($sectorSize) or return $sectorSize;
    $sectorSize = $sectorSize->{value};

    my $fnret = getSmartStatsAndAttributes(smartDisk => $smartDisk);

    my $smartStats     = $fnret->{value};

    my $bytesWritten   = -1;
    my $bytesRead      = -1;
    my $percentageUsed = -1;
    my $powerOnHours   = -1;
    my $powerCycles    = -1;
    #was undef until here
    my $linkFailures       = -1;
    my $eccCorrectedErrs = -1;
    my $eccUncorrectedErrs = -1;
    my $reallocSectors = -1;
    my $uncorrectedEccPage = -1;
    my $commandTimeout = -1;
    my $offlineUncorrectable = -1;
    my $temperature = -1;
    my $highestTemperature = -1;
    my $lowestTemperature = -1;
    my $pendingSectors = -1;

    ##
    ## Gather bytesWritten information
    ##

    # Expressed in logical sectors : more precise, use it when possible
    if ( my ($gplPage) = grep { $_->{page} eq '0x01' and $_->{offset} eq '0x018' } @{$smartStats->{statistics}} )
    {
        $gplPage->{value} =~ /^\d+\z/ or return { status => 500, msg => 'Unconsistent ATA write counter' };
        $bytesWritten = $gplPage->{value}*$sectorSize;
    }

    # For Samsung SSD, expressed in LBA
    if ( my ($attr) = grep { $_->{name} eq 'Total_LBAs_Written' } @{$smartStats->{attributes}} )
    {
        $attr->{raw_value} =~ /^\d+\z/ or return { status => 500, msg => 'Unconsistent ATA write counter' };
        $attr->{raw_value} *= $sectorSize;
        $attr->{raw_value} >= ($bytesWritten||0) and $bytesWritten = $attr->{raw_value};
    }

    # 32MB blocks, less precise but better than nothing
    # Seems to be expressed in MB and not in MiB as stated, or maybe a firmware bug on some models ?
    if ( my ($attr) = grep { $_->{name} eq 'Host_Writes_32MiB' } @{$smartStats->{attributes}} )
    {
        $attr->{raw_value} =~ /^\d+\z/ or return { status => 500, msg => 'Unconsistent ATA write counter' };
        $attr->{raw_value} *= 32*(2**20);
        $attr->{raw_value} >= ($bytesWritten||0) and $bytesWritten = $attr->{raw_value};
    }

    ##
    ## Gather BytesRead information
    ##
    # Expressed in logical sectors : more precise, use it when possible
    if ( my ($gplPage) = grep { $_->{page} eq '0x01' and $_->{offset} eq '0x028' and $_->{value}  =~ /^\d+\z/ } @{$smartStats->{statistics}} )
    {
        $bytesRead = $gplPage->{value}*$sectorSize;
    }
    elsif ( my ($attr) = grep { ( ( $_->{id} eq 242 ) or ( $_->{name} eq 'Total_LBAs_Read' )) and $_->{raw_value} =~ /^\d+\z/ } @{$smartStats->{attributes}} )
    {
        $attr->{raw_value} *= $sectorSize;
        $attr->{raw_value} >= ($bytesRead||0) and $bytesRead = $attr->{raw_value};
    }
    # 32MB blocks, less precise but better than nothing
    # Seems to be expressed in MB and not in MiB as stated, or maybe a firmware bug on some models ?
    elsif ( my ($smartAttr) = grep { $_->{name} eq 'Host_Reads_32MiB' and $_->{raw_value} =~ /^\d+\z/ } @{$smartStats->{attributes}} )
    {
        $smartAttr->{raw_value} *= 32*(2**20);
        $smartAttr->{raw_value} >= ($bytesRead||0) and $bytesRead = $smartAttr->{raw_value};
    }

    ##
    ## Gather percentageUsed information
    ##

    # From 0 to 255 (Yup, a percentage from 0 to 255, no problem)
    # Note that some SSD have a MWI reported as less than 100 in attribute pages, while statistics page return 0
    if ( my ($gplPage) = grep { $_->{page} eq '0x07' and $_->{offset} eq '0x008' } @{$smartStats->{statistics}} )
    {
        $gplPage->{value} =~ /^\d+\z/ or return { status => 500, msg => 'Unconsistent ATA MWI counter' };
        $percentageUsed = $gplPage->{value};
    }

    # From 0 to 100. Raw value has no meaning AFAIK
    if ( my ($attr) = grep { $_->{name} eq 'Media_Wearout_Indicator' } @{$smartStats->{attributes}} )
    {
        $attr->{value} =~ /^\d+\z/ or return { status => 500, msg => 'Unconsistent ATA MWI counter' };
        $attr->{value} = 100-$attr->{value};
        $attr->{value} >= ($percentageUsed||0) and $percentageUsed = $attr->{value};
    }

    # For Samsung SSD, rated from 0 to 100. For other brands, may not mean the same thing
    # Raw value is Program/Erase cycles. Disk is considered "used" when TLC > 1000 or MLC > 3000
    if ( my ($attr) = grep { $_->{name} eq 'Wear_Leveling_Count' } @{$smartStats->{attributes}} )
    {
        $attr->{value} =~ /^\d+\z/ or return { status => 500, msg => 'Unconsistent ATA MWI counter' };
        $attr->{value} = 100-$attr->{value};
        $attr->{value} >= ($percentageUsed||0) and $percentageUsed = $attr->{value};
    }

    ##
    ## Gather powerOnHours information
    ##

    # For ATA devices, should be nearly always known
    if ( my ($attr) = grep { $_->{name} eq 'Power_On_Hours' } @{$smartStats->{attributes}} )
    {
        $attr->{raw_value} =~ /^\d+\z/ or return { status => 500, msg => 'Unconsistent ATA POH counter' };
        $powerOnHours = $attr->{raw_value};
    }

    ##
    ## Gather powerCycles information
    ##
    # For ATA devices, should be nearly always known
    if ( my ($attr) = grep { ( ($_->{id} eq 12) or ($_->{name} eq 'Power_Cycle_Count') ) and $_->{raw_value} =~ /^\d+\z/ } @{$smartStats->{attributes}} )
    {
        $powerCycles = $attr->{raw_value};
    }

    ##
    ## Gather eccCorrectedErrs information
    ##

    if ( my ($attr) = grep { $_->{id} eq 195 } @{$smartStats->{attributes}} )
    {
        if( $attr->{raw_value} =~ /^\d+\z/ )
        {
            $eccCorrectedErrs = $attr->{raw_value};
        }
        else
        {
            $eccCorrectedErrs = -1;
        }
    }


    # Gather the following attributes, useful to predict failures
    # https://www.backblaze.com/blog/hard-drive-smart-stats/

    ##
    ## Gather eccUncorrectedErrs information (187)
    ##

    # Prefer the statistics section when available
    if ( my ($uncorrectedEccPage) = grep { $_->{page} eq '0x04' and $_->{offset} eq '0x008' } @{$smartStats->{statistics}} )
    {
        if( $uncorrectedEccPage->{value} !~ /^\d+\z/ )
        {
            $eccUncorrectedErrs = -1;
        }
        else
        {
            $eccUncorrectedErrs = $uncorrectedEccPage->{value};
        }
    }
    elsif ( my ($attr) = grep { $_->{id} eq 187 } @{$smartStats->{attributes}} )
    {
        if( $attr->{raw_value} =~ /^\d+\z/ )
        {
            $eccUncorrectedErrs = $attr->{raw_value};
        }
        else
        {
            $eccUncorrectedErrs = -1;
        }
    }

    #
    # Reallocated sectors (5)
    #
    if ( my ($reallocSectorPage) = grep { $_->{page} eq '0x03' and $_->{offset} eq '0x020' } @{$smartStats->{statistics}} )
    {
        if( $reallocSectorPage->{value} =~ /^\d+\z/ )
        {
            $reallocSectors = $reallocSectorPage->{value};
        }
        else
        {
            $reallocSectors = -1;
        }
    }
    elsif ( my ($attr) = grep {
                (($_->{id} eq 5) or $_->{name} =~ /^(Reallocate_NAND_Blk_Cnt|Reallocated_Sector_Ct|Total_Bad_Block_Count)$/)
                    and $_->{raw_value} =~ /^\d+\z/ } @{$smartStats->{attributes}} )
    {
        $reallocSectors = $attr->{raw_value};
    }

    #
    # Current_Pending_Sector_Count (197)
    #

    if ( my ($attr) = grep { $_->{id} eq 197 } @{$smartStats->{attributes}} )
    {
        if( $attr->{raw_value} =~ /^\d+\z/ )
        {
            $pendingSectors = $attr->{raw_value};
        }
        else
        {
            $pendingSectors = -1;
        }
    }


    #
    # Offline_Uncorrectable (198)
    #

    if ( my ($attr) = grep { $_->{id} eq 198 and $_->{raw_value} =~ /^\d+\z/ } @{$smartStats->{attributes}} )
    {
        $offlineUncorrectable = $attr->{raw_value};
    }

    #
    # Command_Timeout (188)
    #
    if ( my ($attr) = grep { $_->{id} eq 188 and $_->{raw_value} =~ /^\d+\z/ } @{$smartStats->{attributes}} )
    {
        $commandTimeout = $attr->{raw_value};
    }

    #
    # Temperature (194)
    #
    if( my ($tempStat) = grep { $_->{page} eq '0x05' and $_->{offset} eq '0x008' and $_->{value} =~ /^\d+\z/ } @{$smartStats->{statistics}} )
    {
        $temperature = $tempStat->{value};
    }
    elsif ( my ($attr) = grep { $_->{id} eq 194 and $_->{raw_value} =~ /^\d+\z/ } @{$smartStats->{attributes}} )
    {
        $temperature = $attr->{raw_value};
    }

    if( my ($tempStat) = grep { $_->{page} eq '0x05' and $_->{offset} eq '0x020' and $_->{value} =~ /^\d+\z/ } @{$smartStats->{statistics}})
    {
        $highestTemperature = $tempStat->{value};
    }

    if( my ($tempStat) = grep { $_->{page} eq '0x05' and $_->{offset} eq '0x028' and $_->{value} =~ /^\d+\z/ } @{$smartStats->{statistics}})
    {
        $lowestTemperature = $tempStat->{value};
    }


    $fnret = getSataPhyErrorCounters(smartDisk => $smartDisk);
    if( ok($fnret) )
    {
        ##
        ## Gather failures information
        ##
        ## SATA Phy Event Counters (GP Log 0x11)
        ## ID      Size     Value  Description
        ## 0x000b  4            0  CRC errors within host-to-device FIS
        if ( my ($attr) = grep { $_->{id} eq '0x000b' and $_->{value} =~ /^\d+\z/ } @{$fnret->{value}})
        {
            $linkFailures = $attr->{value};
        }
    }

    $fnret = getSmartCommonInfo(smartDisk => $smartDisk);
    my %commonInfo = ();
    if( ok($fnret) )
    {
        %commonInfo = %{$fnret->{value}}
    }

    return {
        status => 100,
        value  => {
            "bytes-written"   => $bytesWritten,
            "bytes-read"      => $bytesRead,
            "percentage-used" => $percentageUsed || 0,
            "power-on-hours"   => $powerOnHours,
            "power-cycles" => $powerCycles,
            "reported-corrected" => $eccCorrectedErrs,
            "reported-uncorrect" => $eccUncorrectedErrs,
            "reallocated-sector-count" => $reallocSectors,
            "current-pending-sector" => $pendingSectors,
            "offline-uncorrectable" => $offlineUncorrectable,
            "command-timeout" => $commandTimeout,
            "link-failures" => $linkFailures,
            "temperature" => $temperature,
            "highest-temperature" => $highestTemperature,
            "lowest-temperature" => $lowestTemperature,
            #"logged-error-count" => $loggedErrorCount,
            #"global-health" => $health,
            #rawReport => $rawReport,
            %commonInfo
        },
    };


}

sub getSmartStatsAndAttributes
{
    my %params = @_;
    my $smartDisk = $params{smartDisk};

    my $cmd = "timeout 15 smartctl -l devstat -A ".$smartDisk." 2>/dev/null";
    my @smartctl =  `$cmd`;
    my $status = $? >> 8;
    my $smart_filtered_status = $status & 7;
    if( $smart_filtered_status != 0 )
    {
        return { status => 201, msg => "Unable to gather smart stats correctly. status: $smart_filtered_status" };
    }

    my %result = (attributes => [], statistics => []);
    my %in     = ();

    foreach my $line ( @smartctl )
    {
        $line =~ s/\s+$//g;
        $line eq '' and next;

        if ( !$in{smart} and $line eq '=== START OF READ SMART DATA SECTION ===' )
        {
            $in{smart} = 1;
            next;
        }
        $in{smart} or next;

        # Vendor Specific SMART Attributes with Thresholds:
        # ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
        if ( $line eq 'Vendor Specific SMART Attributes with Thresholds:' or $line =~ /^ID#\sATTRIBUTE_NAME/ )
        {
            $in{statistics} = 0;
            $in{attributes} = 1;
        }
        # Device Statistics (GP Log 0x04)
        # Page Offset Size         Value  Description
        elsif ( $line eq 'Device Statistics (GP Log 0x04)' or $line =~ /^Page\s+Offset\sSize/ )
        {
            $in{attributes} = 0;
            $in{statistics} = 1;
        }
        # 184 End-to-End_Error        0x0033   100   100   090    Pre-fail  Always       -       0
        # 187 Reported_Uncorrect      0x0032   100   100   000    Old_age   Always       -       0
        # 190 Temperature_Case        0x0022   086   081   000    Old_age   Always       -       14 (Min/Max 13/20)
        # 170 Unknown_Attribute       0x0003   100   100   ---    Pre-fail  Always       -       1310720
        elsif (
            $in{attributes} and
            $line =~ /^\s*
                (\d+)\s
                (\S+)\s+
                (0x[0-9a-f]{4})\s+
                (\d{3})\s+
                (\d{3})\s+
                (\d{3}|-{3})\s+
                (\S+)\s+
                (\S+)\s+
                (-|FAILING_NOW|In_the_past)\s+
                (.+)
            $/x
        )
        {
            push(@{$result{attributes}}, {
                id        => $1,
                name      => $2,
                flag      => $3,
                value     => $4,
                worst     => $5,
                thresh    => $6,
                type      => $7,
                updated   => $8,
                when      => $9,
                raw_value => $10,
            });
        }
        #   1  =====  =                =  == General Statistics (rev 2) ==
        # 0x01  =====  =               =  ===  == General Statistics (rev 2) ==
        elsif ( $in{statistics} and $line =~ /^\s*(\d+|0x[\da-f]{2})\s+={5}\s{2}=\s+=\s{2}==(?:=\s{2}==)?\s(.+)\s==$/ )
        {
            # Ok
        }
        #   1  0x008  4               54  Lifetime Power-On Resets
        #   1  0x018  6      48984500672  Logical Sectors Written
        #   7  0x008  1                3~ Percentage Used Endurance Indicator
        #   5  0x028  1               -1  Lowest Temperature
        # 0x04  0x008  4               0  ---  Number of Reported Uncorrectable Errors
        elsif ( $in{statistics} and $line =~ /^\s*(\d+|0x[\da-f]{2})\s+(0x[0-9a-f]{3})\s+(\d+)\s+(-?\d+|-)\s*([CDN-]{3}|~|)\s+(.+)$/ )
        {
            if (length($5) <= 1)
            {
                # Smartctl 6.4
                push(@{$result{statistics}}, {
                    page       => sprintf('0x%02d', $1),
                    offset     => $2,
                    size       => $3,
                    value      => $4,
                    normalized => ($5 eq '~') ? 1 : 0,
                    desc       => $6,
                });
            }
            else
            {
                my @flags = split('', $5);

                push(@{$result{statistics}}, {
                    page                    => $1,
                    offset                  => $2,
                    size                    => $3,
                    value                   => $4,
                    monitored_condition_met => ($flags[0] ne '-') ? 1 : 0,
                    supports_dsn            => ($flags[1] ne '-') ? 1 : 0,
                    normalized              => ($flags[2] ne '-') ? 1 : 0,
                    desc                    => $6,
                });
            }
        }
        # SMART Attributes Data Structure revision number: 1
        elsif ( $line =~ /SMART Attributes Data Structure revision number: \d+$/ )
        {
            # Don't care for now
        }
        elsif ( $line eq 'Device Statistics (GP/SMART Log 0x04) not supported' )
        {
            # Sad, but ok
        }
        #                               |_ ~ normalized value
        #                                |||_ C monitored condition met
        elsif ( $line =~ /^\s+\|+_+\s[CDN~]\s[a-zA-Z\s]+$/ )
        {
            # Device statistics footer (optional)
        }
        else
        {
            return { status => 500, msg => 'Unhandled line in smartctl return' };
        }
    }

    return { status => 100, value => \%result };
}


sub getSmartLoggedError
{
    my %params = @_;

    my $smartDisk = $params{smartDisk};

    my $cmd = "timeout 15 smartctl -l error,256 $smartDisk 2>/dev/null";
    my @smartLines = `$cmd`;
    my $last_status = $? >> 8;
    my $smart_status = $last_status & 7;
    if( $smart_status != 0 )
    {
        $cmd = "timeout 15 smartctl -l error $smartDisk 2>/dev/null";
        @smartLines = `$cmd`;
        $last_status = $? >> 8;
        $smart_status = $last_status & 7;
        if( $smart_status != 0 )
        {
            return { status => 500, msg => 'Unable to get smartctl logged errors' };
        }
    }

    my $smartReport = join( "\n", @smartLines );

    # # SAS
    # smartctl 5.41 2011-06-09 r3365 [x86_64-linux-3.10.23-xxxx-std-ipv6-64-rescue] (local build)
    # Copyright (C) 2002-11 by Bruce Allen, http://smartmontools.sourceforge.net
    #
    #
    # Error counter log:
    #            Errors Corrected by           Total   Correction     Gigabytes    Total
    #                ECC          rereads/    errors   algorithm      processed    uncorrected
    #            fast | delayed   rewrites  corrected  invocations   [10^9 bytes]  errors
    # read:          0   908758         0    908758       1235      23321.010           0
    # write:         0  3411453         0   3411453          4      57956.539           0
    # verify:        0    39612         0     39612       1591      12208.742           0
    #
    # Non-medium error count:        0

    # SATA
    # smartctl -l error /dev/sda
    # smartctl 5.41 2011-06-09 r3365 [x86_64-linux-3.10.14-xxxx-std-ipv6-64] (local build)
    # Copyright (C) 2002-11 by Bruce Allen, http://smartmontools.sourceforge.net
    #
    # === START OF READ SMART DATA SECTION ===
    # SMART Error Log Version: 1
    # ATA Error Count: 1
    #     CR = Command Register [HEX]
    #     FR = Features Register [HEX]
    #     SC = Sector Count Register [HEX]
    #     SN = Sector Number Register [HEX]
    #     CL = Cylinder Low Register [HEX]
    #     CH = Cylinder High Register [HEX]
    #     DH = Device/Head Register [HEX]
    #     DC = Device Command Register [HEX]
    #     ER = Error register [HEX]
    #     ST = Status register [HEX]
    # Powered_Up_Time is measured from power on, and printed as
    # DDd+hh:mm:SS.sss where DD=days, hh=hours, mm=minutes,
    # SS=sec, and sss=millisec. It "wraps" after 49.710 days.
    #
    # Error 1 occurred at disk power-on lifetime: 2438 hours (101 days + 14 hours)
    #   When the command that caused the error occurred, the device was in an unknown state.
    #
    #   After command completion occurred, registers were:
    #   ER ST SC SN CL CH DH
    #   -- -- -- -- -- -- --
    #   04 51 00 00 00 00 00  Error: ABRT
    #
    #   Commands leading to the command that caused the error were:
    #   CR FR SC SN CL CH DH DC   Powered_Up_Time  Command/Feature_Name
    #   -- -- -- -- -- -- -- --  ----------------  --------------------
    #   00 00 00 00 00 00 00 04  30d+09:26:18.794  NOP [Abort queued commands]
    #   b0 d4 00 81 4f c2 00 00  30d+09:26:01.106  SMART EXECUTE OFF-LINE IMMEDIATE
    #   b0 d1 01 01 4f c2 00 00  30d+09:26:01.092  SMART READ ATTRIBUTE THRESHOLDS [OBS-4]
    #   b0 d0 01 00 4f c2 00 00  30d+09:26:01.080  SMART READ DATA
    #   b0 da 00 00 4f c2 00 00  30d+09:26:01.072  SMART RETURN STATUS

    # SATA no error
    # root@rescue:~# smartctl -l error /dev/sda
    # smartctl 5.41 2011-06-09 r3365 [x86_64-linux-3.10.23-xxxx-std-ipv6-64-rescue] (local build)
    # Copyright (C) 2002-11 by Bruce Allen, http://smartmontools.sourceforge.net
    #
    # === START OF READ SMART DATA SECTION ===
    # SMART Error Log Version: 1
    # No Errors Logged

    # NVME
    # Error Information (NVMe Log 0x01, max 64 entries)
    # Num   ErrCount  SQId   CmdId  Status  PELoc          LBA  NSID    VS
    #   0          2     1       -  0x400c      -            0     -     -
    #   1          1     1       -  0x400c      -            0     -     -
    #   1         32     4  0x0203  0xc502  0x000    439549024     1     -
    # ... (17 entries not shown)

    my %details = ();
    if ($smartReport =~ /^ATA Error Count:\s*(\d+)/m)
    {
        # SATA with ata error
        $details{logged_error_count} = $1;
        $details{disk_type}          = 'ata';
    }
    elsif ($smartReport =~ /^No Errors Logged/m)
    {
        # SATA/NVME without logged error
        $details{logged_error_count} = 0;
        $details{disk_type}          = ($smartReport =~ /\(NVMe Log/) ? 'nvme' : 'ata';
    }
    elsif ($smartReport =~ /^Non-medium\s+error\s+count\s*:\s*(\d+)/m)
    {
        # SAS (and probably SCSI)
        $details{logged_error_count} = $1;
        $details{disk_type}          = 'sas';
    }
    elsif ($smartReport =~ /\(NVMe Log/)
    {
        # "No Errors Logged" flag is not present, error have been logged
        my ($filtered) = $smartReport =~ /Num\s+ErrCount\s+SQId\s+CmdId\s+Status\s+PELoc\s+LBA\s+NSID\s+VS\n(.+)$/s;

        # ... (17 entries not shown
        if (defined($filtered) and ($filtered =~ /^(.+)\n\.{3} \(\d+ entries not shown\)(?:\r?\n)*$/s))
        {
            $filtered = $1;
        }
        assert(defined($filtered) and ($filtered ne ''));

        $details{logged_error_count} = 0;
        $details{disk_type}          = 'nvme';
        $details{logged_errors}      = [];

        foreach my $line (split(/[\n\r]+/, $filtered))
        {
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;

            #   0          1     0  0x0000  0x4212  0x028            0   255     -
            my @elems = split(/\s+/, $line);
            @elems == 9 or return {status => 500, msg => 'Failed to parse "smartctl -l" return'};

            push(@{$details{logged_errors}}, {
                id        => $elems[0],
                err_count => $elems[1],
                sq_id     => $elems[2],
                cmd_id    => $elems[3],
                status    => $elems[4],
                pe_loc    => $elems[5],
                lba       => $elems[6],
                nsid      => $elems[7],
                vs        => $elems[8],
            });

            $details{logged_error_count} += 1;
        }

        assert($details{logged_error_count} > 0);
    }
    else
    {
        return { status => 200, msg => 'Unhandled smartct -l error return' };
    }

    return { status => 100, value => \%details, details => $smartReport };
}

sub getSataPhyErrorCounters
{
    my %params = @_;
    my $smartDisk = $params{smartDisk};

    my $cmd = "timeout 15 smartctl -l sataphy $smartDisk 2>/dev/null";
    my @smartLines = `$cmd`;
    my $last_status = $? >> 8;
    my $smart_status = $last_status & 7;
    if( $smart_status != 0 )
    {
        return { status => 500, msg => 'Unable to get smart phy error counters' };
    }
    my $smartReport = join( "\n", @smartLines );

    my @counters = ();
    foreach my $line (split(/[\n\r]+/, $smartReport))
    {
        $line =~ s/\s+$//;
        $line eq '' and next;

        # smartctl 6.5 2016-05-07 r4318 [x86_64-linux-3.14.77-mod-std-ipv6-64-rescue] (local build)
        # Copyright (C) 2002-16, Bruce Allen, Christian Franke, www.smartmontools.org
        # SATA Phy Event Counters (GP Log 0x11)
        # ID      Size     Value  Description

        if (($line =~ /^(smartctl|Copyright|SATA Phy|ID\s+Size)/) and !@counters)
        {
            # Header
        }
        # 0x0001  4            0  Command failed due to ICRC error
        # 0x000d  4            0  Non-CRC errors within host-to-device FIS
        elsif ($line =~ /^(0x[0-9a-f]{4})\s+(\d+)\s+(\d+)\s+(.+)$/)
        {
            push(@counters, {
                id    => $1,
                size  => $2,
                value => $3,
                desc  => $4,
            });
        }
        else
        {
            return { status => 500, msg => 'Unhandled line in smartctl return' };
        }
    }

    return { status => 100, value => \@counters };
}


sub getSgPaths
{
    my $cmd = "lsscsi -tg 2>/dev/null";
    my @lines = `$cmd`;
    my $last_status = $? >> 8;
    if( $last_status != 0 )
    {
        return { status => 500, msg => "Unable to gather sg paths" };
    }

    my %drives;

    foreach my $line ( @lines )
    {
        # lsi phyiscal disk in raid device
        # [4:0:1:0]    disk    sas:0x78659942acbbe8b2          -          /dev/sg1

        # lsi raid device (virtual)
        # [4:1:8:0]    disk                                    /dev/sda   /dev/sg2

        # lsi disk in JBOD mode
        # [4:0:0:0]    disk    sas:0x78659942ace4d5b2          /dev/sda   /dev/sg0

        if ( $line =~ /
            disk\s+
            sas:0x([0-9a-f]+)\s+
            (\/dev\/sd[a-z]+|-)\s+
            (\/dev\/sg\d+|)
            /x)
        {
            ( $2 eq '-' ) and next;
            $drives{$2} = {
                sasAddress  => $1,
                sdDrive     => $2,
                sgDrive     => $3,
            };
        }
    }

    return { status => 100, value => \%drives };
}

# ##################################
# Sg logs subs

sub getSupportedLogPages
{
    my %params = @_;

    my $devPath = $params{devPath};

    my $cmd = "sg_logs -x $devPath 2>/dev/null";
    my @lines = `$cmd`;
    my $status = $? >> 8;
    if( $status )
    {
        return { status => 500, msg => 'unable to get sg logs supported pages' };
    }

    my @pages = ();

    foreach my $i ( 0 .. $#lines )
    {
        my $line = $lines[$i];
        $line    =~ s/^\s+$//;

        # Supported log pages  [0x0]:
        if ( $i == 0 )
        {
            # Page name
        }
        #     0x00        Supported log pages
        #     0x0d        Temperature
        elsif ( $line =~ /^\s{4}(0x[\da-f]{2})\s+(.+)$/ )
        {
            push(@pages, {code => $1, desc => $2});
        }
        else
        {
            return { status => 500, msg => 'Unhandled sg_logs return' };
        }
    }
    return { status => 100, value => \@pages };
}

sub getGenericLogPage
{
    my %params = @_;

    my $devPath     = $params{devPath};
    my $page        = $params{page};
    my $stopOnValue = $params{stopOnValue};

    my $cmd = "sg_logs -x --page $page $devPath";
    my @lines = `$cmd`;
    my $status = $? >> 8;
    if( $status )
    {
        return { status => 500, msg => "Unable to get sg logs requested page" };
    }
    my $category   = '';
    my %details    = ();
    my $headerSeen = 0;

    foreach my $i ( 0 .. $#lines )
    {
        my $line = $lines[$i];
        $line    =~ s/^\s+$//;

        # Read error counter page  [0x3]
        if ( substr($line, 0, 1) ne ' ' and $line =~ /\[0x[0-9a-f]{1,2}\]$/ )
        {
            # Header
            $headerSeen and return { status => 200, msg => 'Can not parse specified log page ('.$page.')' };
            $headerSeen++;
        }
        elsif ( defined($stopOnValue) and ($line =~ $stopOnValue) )
        {
            # Stop on value reached, stop here
            last;
        }
        #   Total times correction algorithm processed = 1418
        #   Percentage used endurance indicator: 2%
        elsif ( $line =~ /^\s{2}([^\s][^=:]+)(?:\s=|:)\s(.+)$/ )
        {
            $details{$1} = $2;
        }
        #   Status parameters:
        elsif ( $line =~ /^\s{2}([^\s][^=:]+):$/ )
        {
            $category = $1;
            $details{$category} ||= {};
        }
        #     Accumulated power on minutes: 939513 [h:m  15658:33]
        elsif ( $category and $line =~ /^\s{4}([^\s][^=:]+)(?:\s=|:)\s(.+)$/ )
        {
            $details{$category}{$1} = $2;
        }
        else
        {
            return { status => 500, msg => 'Unhandled sg_logs return' };
        }
    }

    # Sanity check
    if ( !$headerSeen )
    {
        return { status => 500, msg => 'sg_logs return may have not been properly handled' };
    }

    return { status => 100, value => \%details };
}

sub getBackgroundScanResultsLogPage
{
    my %params = @_;

    my $devPath = $params{devPath};

    my $cmd = "sg_logs -x --page 0x15 $devPath 2>/dev/null";
    my @lines = `$cmd`;
    my $status = $? >> 8;
    if( $status )
    {
        return { status => 500, msg => 'Unable to get background scan page' };
    }

    my $category   = '';
    my %details    = ();
    my $headerSeen = 0;

    foreach my $i ( 0 .. $#lines )
    {
        my $line = $lines[$i];
        $line    =~ s/^\s+$//;

        # Read error counter page  [0x3]
        if ( substr($line, 0, 1) ne ' ' and $line =~ /\[0x[0-9a-f]{1,2}\]$/ )
        {
            # Header
            $headerSeen and return { status => 200, msg => 'Can not parse specified log page (0x15)' };
            $headerSeen++;
        }
        #   Total times correction algorithm processed = 1418
        #   Percentage used endurance indicator: 2%
        elsif ( $line =~ /^\s{2}([^\s][^=:]+)(?:\s=|:)\s(.+)$/ )
        {
            $details{$1} = $2;
        }
        #   Status parameters:
        elsif ( $line =~ /^\s{2}([^\s][^=:]+):$/ )
        {
            $category = $1;
            $details{$category} ||= {};
        }
        #     Accumulated power on minutes: 939513 [h:m  15658:33]
        elsif ( $category and $line =~ /^\s{4}([^\s][^=:]+)(?:\s=|:)\s(.+)$/ )
        {
            $details{$category}{$1} = $2;
        }
        #   Medium scan parameter # 1 [0x1]
        elsif ( $line =~ /^\s{2}Medium scan parameter #\s*(\d+)\s*\[0x[0-9a-f]+\]$/ )
        {
            # Start of scan results, not handled for now
            last;
        }
        else
        {
            return { status => 500, msg => 'Unhandled sg_logs return' };
        }
    }

    # Sanity check
    if ( !$headerSeen )
    {
        return { status => 500, msg => 'sg_logs return may have not been properly handled' };
    }

    if ( $details{'Status parameters'} and my $pohLine = $details{'Status parameters'}{'Accumulated power on minutes'} )
    {
        # 939513 [h:m  15658:33]
        my ($poh) = $pohLine =~ /^\d+\s\[h:m\s+(\d+):(\d+)\]$/;
        $details{'Status parameters'}{'Accumulated power on hours'} = $poh;
    }

    return { status => 100, value => \%details };
}


# end sg_logs subs
# ########################################

sub getDmesg
{
    my @dmesg = `/sbin/dmesg -a | tail -n 15000`;
    my $status = $? >> 8;
    if( $status )
    {
        return { status => 500, msg => 'Unable to get dmesg' };
    }

    my @filtered = ();

    foreach my $line (@dmesg)
    {
        chomp $line;
        if ( $line =~ /(I\/O|critical medium) error/
                or $line =~ /Buffer I\/O error on device/
                or $line =~ /Unhandled (error|sense) code/ )
        {
            push @filtered, $line;
        }
    }

    return { status => 100, value => \@filtered };

}


sub countDmesgErrors
{
    my %params = @_;

    my $diskName = $params{diskName};
    my @lines = @{$params{lines}};

    my $counter = 0;

    foreach my $line (@lines)
    {
        if ( $line =~ /(I\/O|critical medium) error, dev $diskName, sector/
                or $line =~ /Buffer I\/O error on device $diskName,/
                or $line =~ /\[$diskName\]\s+Unhandled (error|sense) code/ )
        {
            $counter++;
        }
    }

    return { status => 100, value => $counter };
}


sub iostatCounters
{

    my %params = @_;
    my $diskName = $params{diskName} || return { status => 500, msg => "Missing diskName" };

    my @lines = `iostat -d -x $diskName`;
    my $status = $? >> 8;
    if( $status )
    {
        return { status => 500, msg => 'Unable to get iostat' };
    }

    my $counterLabelsLine = undef;
    my $countersLine = undef;

    foreach my $line (@lines)
    {
        chomp $line;
        if( $line =~ /^\s*device\s*:(.*)$/i )
        {
            $counterLabelsLine = $1;
            chomp( $counterLabelsLine );
            $counterLabelsLine =~ s/^\s*//;
            $counterLabelsLine =~ s/\s*$//;
        }
        elsif( $line =~ /^\s*$diskName\s(.*)$/ )
        {
            $countersLine = $1;
            chomp( $countersLine );
            $countersLine =~ s/^\s*//;
            $countersLine =~ s/\s*$//;
        }
    }

    if( !defined($counterLabelsLine) or !defined($countersLine) )
    {
        return { status => 500, msg => 'Unable to parse iostat' };
    }

    my @fields = split /\s+/, $counterLabelsLine;
    my @values = split /\s+/, $countersLine;

    if( scalar(@fields) != scalar(@values) )
    {
        return { status => 500, msg => 'Unexpected iostat parsing: '.scalar(@fields).' != '.scalar(@values) };
    }

    my $counters = {};

    for( my $i=0; $i<scalar(@fields); $i++)
    {
        $counters->{$fields[$i]} = $values[$i];
    }

    return { status => 100, value => $counters };

}


sub getSmartStatsSAS
{
    my %params = @_;

    my $device = $params{sgDisk} || return { status => 201, msg => 'Missing argument' };
    my $smartDisk = $params{smartDisk} || return { status => 201, msg => 'Missing argument' };

    my $fnret = getSupportedLogPages(devPath => $device);
    ok($fnret) or return $fnret;

    my @supportedPages = @{$fnret->{value}};
    # Attempt to gather the same subset of information as via smart for sata drives
    my $bytesWritten   = undef;
    my $bytesRead      = -1;
    my $percentageUsed = undef;
    my $powerOnHours   = undef;
    my $linkFailures = -1;
    my $powerCycles = -1;
    my $eccCorrectedErrs = -1;
    my $eccUncorrectedErrs = -1;
    my $reallocSectors = -1;
    my $commandTimeout = -1;
    my $offlineUncorrectable = -1;
    my $temperature = -1;
    my $highestTemperature = -1;
    my $lowestTemperature = -1;
    my $pendingSectors = -1;

    # Write counter
    if ( grep { $_->{code} eq '0x02' } @supportedPages )
    {
        my $fnret = getGenericLogPage(devPath => $device, page => '0x02');

        ok($fnret) or return $fnret;

        $bytesWritten = $fnret->{value}->{'Total bytes processed'};
        $bytesWritten =~ /^\d+\z/ or return { status => 500, msg => 'Unconsistent SCSI write counter' };

        my $eccErrsU = $fnret->{value}->{'Total uncorrected errors'};
        my $eccErrsC = $fnret->{value}->{'Total errors corrected'};

        if( defined($eccErrsU) and $eccErrsU =~ /^\d+\z/ )
        {
            $eccUncorrectedErrs = $eccErrsU;
        }

        if( defined($eccErrsC) and $eccErrsC =~ /^\d+\z/  )
        {
            $eccCorrectedErrs = $eccErrsC;
        }
    }


    # SSD specific page
    if ( grep { $_->{code} eq '0x11' } @supportedPages )
    {
        # Note : STEC drives have additional log pages, but not interpreted by sg_logs as of version 1.24 20140523
        # We only care about MWI here, ignore them for now
        my $fnret = getGenericLogPage(
            devPath     => $device,
            page        => '0x11',
            stopOnValue => qr/^\s{2}Reserved\s\[parameter_code=0x[0-9a-f]{4}\]:$/,
        );
        ok($fnret) or return $fnret;

        $percentageUsed = $fnret->{value}->{'Percentage used endurance indicator'};
        $percentageUsed =~ s/%$//;
        $percentageUsed =~ /^\d+\z/ or return { status => 500, msg => 'Unconsistent SCSI MWI counter' };
    }

    # Power On Hours, hidden in 'Background scan results' page
    if ( grep { $_->{code} eq '0x15' } @supportedPages )
    {
        my $fnret = getBackgroundScanResultsLogPage(devPath => $device);
        ok($fnret) or return $fnret;

        $powerOnHours = $fnret->{value}->{'Status parameters'}->{'Accumulated power on hours'};
        $powerOnHours =~ /^\d+\z/ or return { status => 500, msg => 'Unconsistent SCSI POH counter' };
    }

    # Read counter
    if ( grep { $_->{code} eq '0x03' } @supportedPages )
    {
        my $fnret = getGenericLogPage(devPath => $device, page => '0x03');
        if ( ok($fnret) )
        {
            if( defined( $fnret->{value}->{'Total bytes processed'} ) and $fnret->{value}->{'Total bytes processed'} =~ /^\d+\z/ )
            {
                $bytesRead = $fnret->{value}->{'Total bytes processed'};
            }

            my $eccErrsU = $fnret->{value}->{'Total uncorrected errors'};
            my $eccErrsC = $fnret->{value}->{'Total errors corrected'};

            if( defined($eccErrsU) and $eccErrsU =~ /^\d+\z/ )
            {
                if( $eccUncorrectedErrs == -1 ) {
                    $eccUncorrectedErrs = $eccErrsU;
                }
                else
                {
                    $eccUncorrectedErrs += $eccErrsU;
                }
            }

            if( defined($eccErrsC) and $eccErrsC =~ /^\d+\z/  )
            {
                if( $eccCorrectedErrs == -1 ) {
                    $eccCorrectedErrs = $eccErrsC;
                }
                else
                {
                    $eccCorrectedErrs += $eccErrsC;
                }
            }

        }
    }

    # Power cycle count
    if ( grep { $_->{code} eq '0x0e' } @supportedPages )
    {
        my $fnret = getGenericLogPage(devPath => $device, page => '0x0e');
        if ( ok($fnret) )
        {
            $powerCycles = $fnret->{value}->{'Accumulated start-stop cycles'};
            if( $powerCycles !~ /^\d+\z/ )
            {
                $powerCycles = -1;
            }
        }
    }

    # Link failure errors
    if ( grep { $_->{code} eq '0x06' } @supportedPages )
    {
        my $fnret = getGenericLogPage(devPath => $device, page => '0x06');
        if ( ok($fnret) )
        {
            $linkFailures = $fnret->{value}->{'Non-medium error count'};
            if( $linkFailures !~ /^\d+\z/ )
            {
                $linkFailures = -1;
            }
        }
    }

    # Temperature
    if ( grep { $_->{code} eq '0x0d' } @supportedPages )
    {
        my $fnret = getGenericLogPage(devPath => $device, page => '0x0d');
        if ( ok($fnret) )
        {
            $temperature = $fnret->{value}->{'Current temperature'};
            if( $temperature =~ /^(\d+)\s*C/ )
            {
                $temperature = $1;
            }
            else
            {
                $temperature = -1;
            }
        }
    }

    my %commonInfo = ();
    if( $smartDisk )
    {
        $fnret = getSmartCommonInfo(smartDisk => $smartDisk);
        if( ok($fnret) )
        {
            %commonInfo = %{$fnret->{value}}
        }
    }

    return {
        status => 100,
        value  => {
            "bytes-written"   => $bytesWritten,
            "bytes-read"      => $bytesRead,
            "percentage-used" => $percentageUsed || 0,
            "power-on-hours"   => $powerOnHours,
            "power-cycles" => $powerCycles,
            "reported-corrected" => $eccCorrectedErrs,
            "reported-uncorrect" => $eccUncorrectedErrs,
            "reallocated-sector-count" => $reallocSectors,
            "current-pending-sector" => $pendingSectors,
            "offline-uncorrectable" => $offlineUncorrectable,
            "command-timeout" => $commandTimeout,
            "link-failures" => $linkFailures,
            "temperature" => $temperature,
            "highest-temperature" => $highestTemperature,
            "lowest-temperature" => $lowestTemperature,
            #"logged-error-count" => $loggedErrorCount,
            #"global-health" => $health,
            #rawReport => $rawReport,
            %commonInfo
        },
    };
}

sub completeCpuInfo
{
    # Purpose of this
    my %cpuInfo = ( f_mhz => -1, fmax_mhz => -1, fmin_mhz => -1 );
    my @info = `dmidecode -t processor`;

    my $status = $? >> 8;
    if( $status )
    {
        return { status => 500, msg => "lscpu error: $!" };
    }

    $cpuInfo{architecture} = `uname -p`;
    $cpuInfo{sockets} = `sysctl hw dev.cpu | grep ncpu | sed -e "s/hw.ncpu: //"`;
    $cpuInfo{model} = `sysctl hw dev.cpu | grep hw.model | sed -e "s/hw.model: //"`;

    foreach my $line (@info) {
        chomp $line;
        if ($line =~ /^\s*Core Count[^:]*:[^\d]*(\d+)[^\d]*$/i)
        {
            my $field = $1;
            $field =~ s/^\s*//;
            $field =~ s/\s*$//;

            $cpuInfo{cores} = $field;
        }
        elsif ($line =~ /^\s*Thread Count[^:]*:[^\d]*(\d+)[^\d]*$/i)
        {
            my $field = $1;
            $field =~ s/^\s*//;
            $field =~ s/\s*$//;

            $cpuInfo{threads} = $field;
        }
        elsif ($line =~ /\s*Current Speed\s*MHz[^:]*:[^\d]*(\d+)[^\d]*/i )
        {
            my $field = $1;
            $field =~ s/^\s*//;
            $field =~ s/\s*$//;

            $cpuInfo{f_mhz} = $field;
        }
        elsif ($line =~ /\s*Max\s*speed\s*MHz[^:]*:[^\d]*(\d+)[^\d]*/i )
        {
            my $field = $1;
            $field =~ s/^\s*//;
            $field =~ s/\s*$//;

            $cpuInfo{fmax_mhz} = $field;
        }
        elsif ($line =~ /\s*Cpu\s*min\s*MHz[^:]*:[^\d]*(\d+)[^\d]*/i )
        {
            my $field = $1;
            $field =~ s/^\s*//;
            $field =~ s/\s*$//;

            $cpuInfo{fmin_mhz} = $field;
        }
    }

    if( defined($cpuInfo{sockets}) and defined($cpuInfo{cores}) and defined($cpuInfo{threads}) )
    {
        $cpuInfo{cpu_no} = $cpuInfo{sockets} * $cpuInfo{cores} * $cpuInfo{threads};
    }

    return { status => 100, value => \%cpuInfo };
}



hash_walk(\%server, [], \&print_keys_and_value);
