#! /usr/bin/perl

$ENV{"LC_ALL"} = "POSIX";

use strict;
use utf8; # for \x{nnn} regex
use Sys::MemInfo qw(totalmem freemem totalswap);
use Data::Dumper;

# init server hash
my %server = ();
$server{'rtm.info.mem.top_mem_1_name'} = "Unknown";
$server{'rtm.info.mem.top_mem_1_size'} = "Unknown";
$server{'rtm.info.mem.top_mem_2_name'} = "Unknown";
$server{'rtm.info.mem.top_mem_2_size'} = "Unknown";
$server{'rtm.info.mem.top_mem_3_name'} = "Unknown";
$server{'rtm.info.mem.top_mem_3_size'} = "Unknown";
$server{'rtm.info.mem.top_mem_4_name'} = "Unknown";
$server{'rtm.info.mem.top_mem_4_size'} = "Unknown";
$server{'rtm.info.mem.top_mem_5_name'} = "Unknown";
$server{'rtm.info.mem.top_mem_5_size'} = "Unknown";

my (@netstatTable, $line, $socketInfo, $procInfo, @tempTable, $port, $pid, $procName, $ip, $cmdline, $exe, @status, $statusLine, $uid, @passwd, $passwdLine, %passwdHash);
my $maxListenPort = 50;
my $i = 0;

chomp(@netstatTable = `sockstat -4l | tail -n +2`);

open(FILE, "/etc/passwd");
chomp(@passwd = <FILE>);
close(FILE);

foreach $passwdLine (@passwd) {
    $passwdLine =~ /^([^:]+):[^:+]:(\d+):/;
    $passwdHash{$2} = $1;
}

foreach $line (@netstatTable) {
	$line =~ s/\s+/|/g;
        @tempTable = split(/\|/, $line);
        $socketInfo = $tempTable[5];
        $procInfo = $tempTable[2].'/'.$tempTable[1];

        $socketInfo =~ /:(\d+)$/;
        $port = $1;
        $socketInfo =~ /(.+):\d+$/;
        $ip = $1;
        $ip =~ s/\./-/g;
        $ip =~ s/[^0-9\-]//g;
        if ($ip eq "") {$ip = 0;}
        @tempTable = split(/\//, $procInfo);
        $pid = $tempTable[0];
	my $cmdline = `ps -waux $pid | tail -n +2`;

        my @cmdLine = split ' ', $cmdline;
        $cmdline = @cmdLine[10];

        my $username = @cmdLine[0];

        $procName = $tempTable[1];
        my $exe = $cmdline;

        $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.pid'} = $pid;
        $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.procname'} = $procName;
        $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.cmdline'} = $cmdline;
        $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.exe'} = $exe;
        $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.username'} = $username;
        $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.uid'} = $uid;
        $i++;
        last if $i >= $maxListenPort;
}

# top process
my @top;
my @output = `top -o cpu -n 5 | tail -n 7 | head -n 6`;
$i=1;
my $sizeIndex;
my $commandIndex;
# map with result from first line

foreach $line (@output)
{
    $line =~ s/\s+/|/g;
    @tempTable = split(/\|/, $line);
    if($line =~ /\|PID\|USERNAME\|THR\|PRI/)
    {
	# first line is head like :|PID|USERNAME|THR|PRI|NICE|SIZE|RES|STATE|TIME|WCPU|COMMAND| 
	if($tempTable[6] eq 'SIZE')
	{
	    $sizeIndex=6;
	}
	if($tempTable[11] eq 'COMMAND')
	{
	    $commandIndex=11;
	}
	if($tempTable[12] eq 'COMMAND')
	{
	    $commandIndex=12;
	}
        next;	
    }
    
    my $size=$tempTable[$sizeIndex];
    $size =~ s/K//;
    my $name = $tempTable[$commandIndex];
    $server{'rtm.info.mem.top_mem_'.$i.'_size'}=$size;
    $server{'rtm.info.mem.top_mem_'.$i.'_name'}=$name;
    $i++;
}

# get process runnig/count
chomp(my @rtm_sids = `pgrep "noderig|beamium" -o sid | sort -n | uniq`);
my @ps_output = `ps -A -o sid,state,command`;
my $active = 0;
my $total = 0;
my $rtm_procs = 0;
foreach my $line (@ps_output) {
    next if $line !~ /(\d+)\s+(\S+)/;
    my $sid = $1;
    my $state = $2;
    if (grep $sid == $_, @rtm_sids) {
        ++$rtm_procs;
        next;
    }
    ++$total;
    ++$active if $state =~ /^R/;
}
print "{\"metric\":\"os.load.processesactive\",\"timestamp\":".time.",\"value\":".$active."}\n";
print "{\"metric\":\"os.load.processesup\",\"timestamp\":".time.",\"value\":".$total."}\n";

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


sub loadAvg
{

    my $load = `sysctl vm.loadavg`;
    my $oneMinLoad = "-1";
    my $fiveMinLoad = "-1";
    my $tenMinLoad = "-1";
    if( $load =~ /(\d+.\d+?)\s(\d+.\d+?)\s(\d+.\d+?)\s/g )
    {
        $oneMinLoad = $1;
        $fiveMinLoad = $2;
        $tenMinLoad = $3;
    }

    return {
        status => 100,
        value => {
            oneMinLoad => $oneMinLoad,
            fiveMinLoad => $fiveMinLoad,
            tenMinLoad => $tenMinLoad
        }
    }

}


sub memUsage
{

    my $memory = `grep memory /var/run/dmesg.boot`;
    $memory =~ /real memory\s*=\s*\d*\s\((.*)\)/;
    my $total = $1;
    $memory =~ /avail memory\s*=\s*\d*\s\((.*)\)/;
    my $available = $1;

    return {
        status => 100,
        value => {
            total => $total,
            available => $available
        }
    };
}

sub cpuRealTimeInfo
{
    # Purpose of this is to get actual frequency
    my $frequency = `dmidecode -t processor | grep "Current Speed"`;
    $frequency =~ /(\d* [M|G]?Hz$)/;
    $frequency = $1;

    return {
        status => 100,
        value => $frequency,
    };
}

sub getPartitionUsage
{

    my %partition = ();

    my @slash = `df -h /`;
    my @home = `df -h /home`;

    my %usage = ( home => -1, slash => -1);

    foreach my $df (['home', \@home], ['slash', \@slash])
    {
        my $name = $df->[0];
        my @lines = @{$df->[1]};

        if( scalar(@lines) < 2 )
        {
            next;
        }

        my $head = $lines[0];
        $head =~ s/Mounted on/MountedOn/ig;

        my $tail = $lines[$#lines];
        my @heads = split( /\s+/, $head );
        my @tails = split( /\s+/, $tail );

        foreach my $index (0 .. $#heads)
        {
            my $field = $heads[$index];
            if( $field =~ /Capacity/i )
            {
                $usage{$name} = $tails[$index];
                $usage{$name} =~ s/[^\d]//g;
            }
        }
    }

    return {
        status => 100,
        value => \%usage,
    };
}


sub systemInfo {

    my $fnret = loadAvg();
    if( ok($fnret) )
    {
        $server{"os.load.average.1min"} = $fnret->{value}->{oneMinLoad};
        $server{"os.load.average.5min"} = $fnret->{value}->{fiveMinLoad};
        $server{"os.load.average.10min"} = $fnret->{value}->{tenMinLoad};
    }

    $fnret = memUsage();

    if( ok($fnret) )
    {
        $server{"os.mem.total"} = $fnret->{value}->{total};
        $server{"os.mem.available"} = $fnret->{value}->{available};
    }

    $fnret = cpuRealTimeInfo();
    if( ok($fnret) )
    {
        $server{"os.cpu.f_mhz"} = $fnret->{value};
    }

    $fnret = getPartitionUsage();
    if( ok($fnret) )
    {
        $server{"os.disk.home.usage"} = $fnret->{value}->{home};
        $server{"os.disk.slash.usage"} = $fnret->{value}->{slash};
    }
}

eval {
    systemInfo();
};

hash_walk(\%server, [], \&print_keys_and_value)

