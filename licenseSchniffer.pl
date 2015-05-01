#! /usr/bin/perl -w
#
#    Perl LicenseSniffer for multiple License Servers
#    Copyright (C) 2014  Maximilian Thumfart
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
use strict;
use POSIX qw(strftime);
use DBI();
my $content;
my $server;
my %products;
my $product;
my $currentProduct;
my %borrowed;

my $date = strftime "%d.%m.%Y %H:%M", localtime;

# Connect to the database.
# Adapt this to your environment.
my $dbh = DBI->connect("DBI:mysql:
	database=licensesniffer;
	host=localhost",
	"licensesniffer",
	"password",
    {'RaiseError' => 1});

use LWP::Simple;
sub print_help ();
sub print_usage ();

$ENV{'PATH'}='';
$ENV{'BASH_ENV'}='';
$ENV{'ENV'}='';

$server = $ARGV[0];

# Scan a Zoo license server
if ($ARGV[1] eq "Z")
{
	{
        local $/ = undef;
        $content = get("http://$server/status");
        if (!$content) {print "Unable to connect to $server\n";exit};
	}

	while ($content =~ /<tr><td>\d*<\/td><td>([a-zA-Z0-9_\- \.\(\)]*)<\/td><td>[a-zA-Z0-9_\- \.\(\)]*<\/td><td>[a-zA-Z0-9_\- \.\(\)]*<\/td><td>(Available|In Use|Checked Out)<\/td><td>([a-zA-Z0-9_\- \.]*)<\/td><td>([a-zA-Z0-9_\- \.]*)<\/td><\/tr>/g)
	{
		print "$1;$4;$3\n" if (length $4 > 0);
		if ($2 eq "Available")
		{
			push(@{$products{$1}}, 0);
		}
		else
		{
			push(@{$products{$1}}, 1);
			push(@{$borrowed{$1}}, 1) if ($2 eq "Checked Out");
		}
	}
}

# Scan a Flexnet Server
if ($ARGV[1] eq "F")
{
	open(CMD,"/bin/lmutil lmstat -a -c 27000\@$server |");
	while ( <CMD> )
	{
		if ($_ =~ /Total of/)
		{
			$_ =~ /Users of (.*):\s*\(Total of (\d*) license.* issued;\s*Total of (\d*) license.* in use\)/;
            
			for (my $i = 0; $i < $2; $i++)
            {
                push(@{$products{$1}}, 1) if ($i < $3);
                push(@{$products{$1}}, 0) if ($i >= $3);
            }
			
			$currentProduct = $1;
		}

		if (length $currentProduct && $_ =~/[ ]*(.*) (.*) .* \(v/)
		{
			print "$currentProduct;$1;$2\n";
			push(@{$borrowed{$currentProduct}}, 1) if ($_ =~/linger/);
		}
	}
	
	close CMD;
}

# Scan a RLM License Server
if ($ARGV[1] eq "R")
{
	my $CMD = qx(/bin/rlmutil rlmstat -a -c 5053\@$server);

	while ($CMD =~ m/\t(.*)\n.*count: (\d*), # reservations: (\d*), inuse: (\d*), exp/g)
	{
        for (my $j = 0; $j < $2; $j++)
        {
            push(@{$products{$1}}, 1) if ($j < $4);
            push(@{$products{$1}}, 0) if ($j >= $4);
        }
        push(@{$borrowed{$1}}, $3);
	}

	while ($CMD =~ m/\t(.*): (.*)@(.*) \d*\/\d* at/g)
	{
        print "$1;$2;$3\n";
	}
}

# Prepare and Commit to DB
for $product (keys %products)
{
    my $ava = eval join '+', @{$products{$product}};
    my $tot = scalar(@{$products{$product}});
    my $brw = 0;
    if (exists $borrowed{$product})
	{
        $brw = eval join '+', @{$borrowed{$product}};
    }

    $dbh->do("CREATE TABLE IF NOT EXISTS `licensesniffer`.`$product` ("
            . "`DATE` DATETIME NOT NULL,"
            . "`INUSE` INT NULL,"
            . "`TOTAL` INT NULL,"
            . "`BORROWED` INT NULL,"
            . "`SERVER` TEXT NULL,"
            . "PRIMARY KEY (`DATE`));");
			
    $dbh->do("INSERT INTO `licensesniffer`.`$product` (`DATE`,`INUSE`,`TOTAL`,`SERVER`,`BORROWED`) VALUES (NOW(),'$ava','$tot','$server','$brw')");
}
