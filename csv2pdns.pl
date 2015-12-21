#!/usr/bin/perl

=pod 

=head1 NAME

csv2pdns.pl - Extract hostname and IP information from CSV file and populate PowerDNS

=head1 DESCRIPTION

A perl script to extract hostname and IP information from CSV file, which is used to create domain, host and PTR records using DBI into the PowerDNS MySQL backend.

=head1 CAVEATS

Script does not check for duplicate IP's so multiple A records will be created.

=head1 LICENSE

GPL v2, June 1991

=cut

use strict;
use warnings;

die 'Usage: csv2pdns.pl filename' if @ARGV != 1;

use Data::Dumper;
use DBI;

#vars
my $db_host= "localhost";
my $db_port= "3306";
my $db_name = "pdns";
my $db_user = "pdns";
my $db_pass = "password";
my @blacklist = ("acme.com","domain.com");
my $filename =$ARGV[0];

sub soa_timestamp{
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $mon++;
  $year = $year + 1900;
  my $soatime = sprintf ("%04d%02d%02d", $year, $mon, $mday, $hour, $min, $sec);
  $soatime.= "00";
  return $soatime;
}

sub get_file{
  my %hash;
  open my $fh, '<', $_[0] or die "Cannot open: $_[0] $!";
  while (my $line = <$fh>) {
    chomp $line;
    my @array = split(/,/, $line);
    my ($key, $ip) = @array;
    my $fqdn = $key;
    $hash{$key}->{name} = $fqdn;
    $hash{$key}->{ip} = $ip;
  }
  close $fh;

  return %hash;
}

# Open DB connection
my $dbh = DBI->connect("DBI:mysql:database=$db_name;host=$db_host",$db_user,$db_pass,{'RaiseError' => 1});

sub create_domain{
  my $domain = $_[0];
  my $soa_time = $_[1];
  my $timestamp = $_[2];
  # Insert domain into domain table;
  print "Inserting domain record : $domain\n";
  my $query="INSERT INTO `domains` VALUES('','$domain',NULL,NULL,'MASTER',NULL,NULL)";
  my $sth = $dbh->prepare($query);
  $sth->execute();
  my $domain_id=$sth->{mysql_insertid};
  # insert domain into zone table
  print "Inserting zone record : $domain\n";
  $query="INSERT INTO `zones` VALUES('',$domain_id,1,NULL,0)";
  $sth = $dbh->prepare($query);
  $sth->execute();
  # insert SOA ito new domain
  $query="INSERT INTO `records` VALUES('',$domain_id,'$domain','SOA','ns1.acme.com hostmaster.acme.com $soa_time 28800 7200 604800 86400',86400,0,$timestamp,'',1)";
  $sth = $dbh->prepare($query);
  $sth->execute();
  # insert NS record for DC for new domain
  $query="INSERT INTO `records` VALUES('',$domain_id,'$domain','NS','ns1.acme.com',86400,0,$timestamp,'',1)";
  $sth = $dbh->prepare($query);
  $sth->execute();
  # insert NS record for INT for new domain
  $query="INSERT INTO `records` VALUES('',$domain_id,'$domain','NS','ns2.acme.com',86400,0,$timestamp,'',1)";
  $sth = $dbh->prepare($query);
  $sth->execute();
  return $domain_id;
}

my %host_result=&get_file($filename);
#print Dumper(\%host_result);

# check for results. 
if (!%host_result) { 
  print "No results found\n"; 
  exit;
} 
OUTER: while ((my $key,my $value) = each %host_result) { 
  # split FQDN into hostname and domain.
  my $timestamp=time;
  my $ipaddress=$value->{ip};
  chop($ipaddress);
  my @name=split(/\./,$value->{name});
  my $shortname = shift @name;
  my $domain = join('.', @name); 
  # create PTR components
  my @ptr = split(/\./,$ipaddress);
  my $ptr_ip = pop @ptr;
  my $inaddr = join('.',reverse @ptr);
  $inaddr .= ".in-addr.arpa";
  # check if domain needs to be added. 
  for my $ext_domain ( @blacklist ){
    if ($domain eq $ext_domain){
      #print "Skipping $server\n";
      last OUTER;
    }
  }
  # Check if domain exists in the DB
  my $query="select * from domains where name='$domain'";
  my $sth1 = $dbh->prepare($query);
  $sth1->execute();
  my $rows1 = $sth1->rows;
  if ($rows1 == 1) {
    # If it does, check for existing record with $value-{name} or add new one.
    while (my $ref = $sth1->fetchrow_hashref()) {
      my $domain_id = $ref->{'id'};
      $query="select * from records where name='$value->{name}'";
      my $sth2 = $dbh->prepare($query);
      $sth2->execute();
      my $rows2 = $sth2->rows;
      if ($rows2 > 0) {
        $query="select * from records where name='$value->{name}' AND content='$ipaddress' AND ordername='$shortname'";
        $sth2 = $dbh->prepare($query);
        $sth2->execute();
        $rows2 = $sth2->rows;
        if ($rows2 == 0){
          print "Updating record : $value->{name}\n";
          $query="UPDATE `records` set name='$value->{name}',content='$ipaddress',change_date=$timestamp,ordername='$shortname' where name='$value->{name}'";
        }
      } else {
        print "Inserting record : $value->{name}\n";
        $query="INSERT INTO `records` VALUES('',$domain_id,'$value->{name}','A','$ipaddress',86400,0,$timestamp,'$shortname',1)";
      }
      $sth2 = $dbh->prepare($query);
      $sth2->execute();
    }
  } else {
    # Otherwise Create domain and zone table with default records. 
    my $soa_time = soa_timestamp();
    my $domain_id = create_domain($domain,$soa_time,$timestamp);
    # insert record into new domain
    print "Inserting record : $value->{name}\n";
    $query="INSERT INTO `records` VALUES('',$domain_id,'$value->{name}','A','$ipaddress',86400,0,$timestamp,'$shortname',1)";
    my $sth3 = $dbh->prepare($query);
    $sth3->execute();
  }
  # Check if inaddr domain exists in the DB
  $query="select * from domains where name='$inaddr'";
  $sth1 = $dbh->prepare($query);
  $sth1->execute();
  $rows1 = $sth1->rows;
  if ($rows1 == 1) {
    # If it does, check for existing record or add new one.
    while (my $ref = $sth1->fetchrow_hashref()) {
      my $domain_id = $ref->{'id'};
      $query="select * from records where type='PTR' and content='$value->{name}'";
      my $sth2 = $dbh->prepare($query);
      $sth2->execute();
      my $rows2 = $sth2->rows;
      if ($rows2 > 0) {
        $query="select * from records where name='$ptr_ip.$inaddr' AND content='$value->{name}'";
        $sth2 = $dbh->prepare($query);
        $sth2->execute();
        $rows2 = $sth2->rows;
        if ($rows2 == 0){
          print "Updating PTR record : $value->{name}\n";
          $query="UPDATE `records` set content='$value->{name}',name='$ptr_ip.$inaddr',change_date=$timestamp where content='$value->{name}'";
        }
      } else {
        print "Inserting PTR record : $value->{name}\n";
        $query="INSERT INTO `records` VALUES('',$domain_id,'$ptr_ip.$inaddr','PTR','$value->{name}',86400,0,$timestamp,'',1)";
      }
      $sth2 = $dbh->prepare($query);
      $sth2->execute();
    }
  } else {
    # Otherwise Create domain and zone table with default records. 
    print "Create PTR $inaddr\n";
    my $soa_time = soa_timestamp();
    my $domain_id = create_domain($inaddr,$soa_time,$timestamp);
    # insert PTR record into new domain
    print "Inserting PTR record : $value->{name}\n";
    $query="INSERT INTO `records` VALUES('',$domain_id,'$ptr_ip.$inaddr','PTR','$value->{name}',86400,0,$timestamp,'',1)";
    my $sth3 = $dbh->prepare($query);
    $sth3->execute();
  }
}

# Close DB connection
$dbh->disconnect();
