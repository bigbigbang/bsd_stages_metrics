#! /usr/bin/perl
$ENV{"LC_ALL"} = "POSIX";
use strict;
use utf8; # for \x{nnn} regex
use warnings;
use Unix::Uptime;
use Sys::MemInfo qw(totalmem freemem totalswap);
use IPC::Open3;

# init server hash
my %server = ();

systemInfo();
hash_walk(\%server, [], \&print_keys_and_value);

sub systemInfo
{
    $server{'rtm.info.rtm.version'} = "1.0.12";
   
    my $fnret = processes();
    if (ok($fnret))
    {
        $server{"os.load.processesactive"} = $fnret->{value}->{active};
        $server{"os.load.processesup"} = $fnret->{value}->{up};
    }
    else
    {
        print "Error with processes \n";
    }
    $fnret = _getTopProcess();
    if (ok($fnret))
    {
       # values in server hash
    }
    else
    {
        print "Error with getTopProcess \n";
    }
    $fnret = _getPortsAndInfos();
    if (ok($fnret))
    {
       # values in server hash
    }
    else
    {
        print "Error with getPortsAndInfos \n";
    }
    $fnret = uptime();
    if (ok($fnret))
    {
        $server{"rtm.info.uptime"} = $fnret->{value};
    }
    else
    {
        print "Error with uptime \n";
    }

    # hostname
    $fnret = execute('hostname');
    if (ok($fnret) and defined($fnret->{value}[0]))
    {
        $server{"rtm.hostname"}=$fnret->{value}[0];
    }
    else
    {
        $server{"rtm.hostname"}="Unknow";
    } 
}

# get processes running/count
sub processes
{
    my $fnret = execute('pgrep "noderig|beamium" -o sid | sort -n | uniq');
    if ( $fnret->{status} != 100 )
    {
        print $fnret->{msg}." \n";
        return { status => 500, msg => "ps error: ".$fnret->{msg}." \n" };
    }
    else
    {
        my $rtm_sids = $fnret->{value};
        $fnret = execute('ps -A -o sid,state,command');
        if( $fnret->{status} != 100 )
        {
            print "ps error: ".$fnret->{msg}."\n";
            return { status => 500, msg => "ps error: ".$fnret->{msg}." \n" };
        }
        else
        {
            my $active = 0;
            my $total = 0;
            my $ids = $fnret->{value};
            
            foreach my $line (@{$ids})
            {
                next if $line !~ /(\d+)\s+(\S+)/;
                my $sid = $1;
                my $state = $2;
                if (grep $sid == $_, @{$rtm_sids})
                {
                    next;
                }
                ++$total;
                ++$active if $state =~ /^R/;
            }
            return {status=>100, value => {up => $total, active=>$active}};
        }
    }
}

# top process
sub _getTopProcess
{
    my $fnret = execute('top -o cpu -n 5 | tail -n 7 | head -n 6');
    if ( $fnret->{status} != 100 )
    {
        print "top error: ".$fnret->{msg}." \n";
        return { status => 500, msg => "top error: ".$fnret->{msg}."\n" };
    }
    else
    {
        for (my $i=1; $i <= 5; $i++)
        {
            $server{"rtm.info.mem.top_mem_".$i."_name"} = "Unknown";
            $server{"rtm.info.mem.top_mem_".$i."_size"} = "Unknown";
        }
        my $i=0;
        my @name;

	my @tempTable;
	my $sizeIndex;
	my $commandIndex;
        foreach my $line (@{$fnret->{value}})
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
        return {status=>100};
    }
}

# get port and associated infos
sub _getPortsAndInfos
{
    my $maxListenPort = 50;
    my $fnret = execute('sockstat -4l | tail -n +2');
    if ( $fnret->{status} != 100 )
    {
        print $fnret->{msg}."\n";
        return { status => 500, msg => "sockstat error: ".$fnret->{msg}."\n" };
    }
    else
    {
        my $netstatTable = $fnret->{value};
        if (open(my $fh, '<', '/etc/passwd'))
        {
            my @passwd;
            chomp(@passwd = <$fh>);
            close($fh);
            my %passwdHash;
            foreach my $passwdLine (@passwd)
            {
            	$passwdLine =~ /^([^:]+):[^:+]:(\d+):/;
    		if ((defined($1)) and (defined($2)))
		{
			$passwdHash{$2} = $1;
		}
	    }
            my $i = 0;
            foreach my $line (@{$netstatTable})
            {
            	$line =~ s/\s+/|/g;
                my @tempTable = split(/\|/, $line);
                my $socketInfo = $tempTable[5];
                my $procInfo = $tempTable[2].'/'.$tempTable[1];

                $socketInfo =~ /:(\d+)$/;
                my $port = $1;
                $socketInfo =~ /(.+):\d+$/;
                my $ip = $1;
                $ip =~ s/\./-/g;
                $ip =~ s/[^0-9\-]//g;
                if ($ip eq "") {$ip = 0;}
                @tempTable = split(/\//, $procInfo);
                my $pid = $tempTable[0];
                my $cmdline = `ps -waux $pid | tail -n +2`;
                            
                my @cmdLine = split ' ', $cmdline;
                $cmdline = $cmdLine[10];
                     
                my $username = $cmdLine[0];
                            
                my $procName = $tempTable[1];
                my $exe = $cmdline;

                $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.pid'} = $pid;
                $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.procname'} = $procName;
                $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.cmdline'} = $cmdline;
                $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.exe'} = $exe;
                $server{'rtm.info.tcp.listen.ip-' . $ip . '.port-' . $port . '.username'} = $username;
                $i++;
                last if $i >= $maxListenPort;
	    }
            return {status=>100};
        }
        else
        {
            print "Could not open /etc/passwd";
            return {status=>500};
        }
    }
}

#uptime
sub uptime
{
	my $uptime = Unix::Uptime->uptime(); # 2345 
        if ($uptime)
	{
		return {status=>100, value => $uptime};
	}
	else
        {
            print "Error with uptime";
            return {status=>500};
        }

}

sub print_keys_and_value {
    my ($k, $v, $key_list) = @_;
    $v =~ s/^\s+|\s+$//g;
    my $key;
    foreach (@$key_list)
    {
        if ($key)
        {
            $key = $key.".".$_;
        }
        else
        {
            $key = $key || "";
            $key = $key.$_;
        }
    }
    if (defined($key))
    {
        print "{\"metric\":\"$key\",\"timestamp\":".time.",\"value\":\"".$v."\"}\n";
    }
}

sub hash_walk {
    my ($hash, $key_list, $callback) = @_;
    while (my ($key, $value) = each (%$hash))
    {
        $key =~ s/^\s+|\s+$//g;
        push @$key_list, $key;
        if (ref($value) eq 'HASH')
        {
            hash_walk($value,$key_list,$callback)
        }
        else
        {
            $callback->($key, $value, $key_list);
        }
        pop @$key_list;
    }
}

sub ok
{
    my $arg = shift;
    if ( ref $arg eq 'HASH' and $arg->{status} eq 100 )
    {
        return 1;
    }
    elsif (ref $arg eq 'HASH' and $arg->{status} eq 500 and defined($arg->{msg}))
    {
        print $arg->{msg};
    }
    return 0;
}

sub execute
{
    my ($bin, @args) = @_;
    defined($bin) or return { status => 201, msg => 'No binary specified (execute)' };

    #print("Executing : ".$bin." ".join(" ", @args".\n"));
    my ($in, $out);
    my $pid = IPC::Open3::open3($in, $out, $out, $bin, @args);
    $pid or return { status => 500, msg => 'Failed to fork : '.$! };

    local $/;

    my $stdout = <$out>;
    my $ret    = waitpid($pid, 0);
    my $status = ($? >> 8);

    close($in);
    close($out);
    my @stdout = split(/\n/, $stdout);
    if ($ret != $pid)
    {
        return { status => 500, msg => 'Invalid fork return (waitpid)', value => $stdout };
    }
    elsif ($status != 0 and $bin ne '/bin/ps')
    {
        return { status => 500, msg => 'Binary '.$bin.' exited on a non-zero status ('.$status.')', value => $stdout };
    }
    else
    {
        # Ok
    }
    return { status => 100, value => \@stdout };
}

