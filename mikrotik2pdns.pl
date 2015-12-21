#!/usr/bin/perl

use warnings;
use strict;

=pod 

=head1 NAME

mikrotik2pdns.pl - Extract dynamic lease information from mikrotik router and populate PowerDNS

=head1 DESCRIPTION

This script uses the mikrotik API to extract dynamic lease information creates a CSV file with hostname, IP information for use with csv2pdns.pl
If the CSV file already exists, the lease information is compared and any records that is in the CSV file, but not in the lease is checked in PDNS 
MySQL backend, and if found, removed. 

=head1 LICENSE

GPL v2, June 1991

=cut 

use MikroTik::API;
use Data::Dumper;
use Text::CSV;
use DBI;

#vars
my $db_host= "localhost";
my $db_port= "3306";
my $db_name = "pdns";
my $db_user = "pdns";
my $db_pass = "password";
my $domain = "internal.acme.com";

my $csv_file="/etc/powerdns/scripts/mikrotik.csv";

# Log into mikrotik. 
my $api = MikroTik::API->new({
  host => '192.168.0.1',
  username => 'username',
  password => 'password',
  use_ssl => 1,
  debug => 0,
});

sub check_file{
  # sub to check the CSV file exists, and if not, create it.
  if(!-e $_[0]){
    return 0;
  } elsif (-z $_[0]){
    return 0;
  } else {
    return 1;
  }
}

sub create_file{
  #sub to create a newfile using data from mikrotik. 
  my @rows;
  # get hash from mikrotik
  my %lease=$api->get_by_key('/ip/dhcp-server/lease/print', 'active-address' );
  my $csv = Text::CSV->new ( { binary => 1 } ) or die "Cannot use CSV: ".Text::CSV->error_diag ();
  while ((my $key,my $value) = each %lease) {
    my $address=$value->{'active-address'};
    if ( ! $value->{'host-name'} eq "" ){
      my $hostname=$value->{'host-name'};
      my $row->[0] = "$hostname.$domain";
      $row->[1] = $address;
      push @rows, $row;
    }
    $csv->eol ("\r\n");

    open my $fh, ">:encoding(utf8)", $csv_file or die "$csv_file: $!";
    $csv->print ($fh, $_) for @rows;
    close $fh or die "$csv_file: $!";
    
  }  
}

sub remove_dns{
  # sub to check which records have been removed from the Mikotik and then remove them from DNS before updating the file.
  #print "Checking CSV file against Mikrotik leases to find removed records\n";
  my $csv = Text::CSV->new ( { binary => 1 } ) or die "Cannot use CSV: ".Text::CSV->error_diag ();
  open my $fh, "<:encoding(utf8)", "$csv_file" or die "$csv_file: $!";
  my %lease = $api->get_by_key('/ip/dhcp-server/lease/print', 'active-address' );
  while ( my $row=$csv->getline( $fh ) ) {
    my $csv_hostname = $row->[0];
    my $csv_address = $row->[1];
    my $match = 0;
    while ((my $key,my $value) = each %lease) {
      my $address=$value->{'active-address'};
      my $hostname=$value->{'host-name'};
      if ( $csv_address eq $address ){
        $match = 1;
      }
    }
    if ( ! $match) {
      #print "No match found for $csv_address. Checking DNS\n";
      # find A record and remove if need be
      my $dbh = DBI->connect("DBI:mysql:database=$db_name;host=$db_host",$db_user,$db_pass,{'RaiseError' => 1});
      my $query="SELECT * from records where content='$csv_address'";
      my $sth = $dbh->prepare($query);
      $sth->execute();      
      my $db_rows = $sth->rows;
      if ($db_rows > 0) {
        #print "Found record, deleting\n";
        # delete record
        my $query="delete from records where content='$csv_address'";
        #print "$query\n";
        my $sth = $dbh->prepare($query);
        $sth->execute();
      }
      # find PTR and remove if need be
      $query="SELECT * from records where content='$csv_hostname'";
      $sth = $dbh->prepare($query);
      $sth->execute();
      $db_rows = $sth->rows;
      if ($db_rows > 0) {
        #print "Found record, deleting\n";
        # delete record
        my $query="delete from records where content='$csv_hostname'";
        #print "$query\n";
        my $sth = $dbh->prepare($query);
        $sth->execute();
      }
    }
  }
}

sub main{

  my $boolean = check_file($csv_file);
  if ( $boolean ) {
    #print "CSV file contains data. parse file.\n";
    remove_dns();
    create_file();
  } else {
    #print "CSV file contains no data. Create new file.\n";
    create_file();
  }
}

main();

$api->logout();
