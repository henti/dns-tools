#!/usr/bin/perl

=pod

=head1 NAME

axfr2pdns.pl - Extract DNS information from zone transfer and populate into PowerDNS

=head1 DESCRIPTION

Script will do a zone transfer from DNS server using Net::DNS and then populate PowerDNS MySQL backend using PowerDNS::Backend::MySQL

=head1 LICENSE

GPL v2, June 1991

=cut

use strict;
use warnings;

die 'Usage: axfr2pdns.pl zone' if @ARGV != 1;

use Data::Dumper;
use DBI;
use Net::DNS;
use PowerDNS::Backend::MySQL;

#vars
my $zone =$ARGV[0];

my $params = {   
  db_user                 =>      'pdns',
  db_pass                 =>      'XExHQqwYS2aK',
  db_name                 =>      'pdns',
  db_port                 =>      '3306',
  db_host                 =>      'localhost',
  mysql_print_error       =>      1,
  mysql_warn              =>      1,
  mysql_auto_commit       =>      1,
  mysql_auto_reconnect    =>      1,
  lock_name               =>      'powerdns_backend_mysql',
  lock_timeout            =>      3,
};

my $pdns = PowerDNS::Backend::MySQL->new($params);

# sub routine to get SOA time
sub soa_timestamp{
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $mon++;
  $year = $year + 1900;
  my $soatime = sprintf ("%04d%02d%02d", $year, $mon, $mday, $hour, $min, $sec);
  $soatime.= "00";
  return $soatime;
}

# Sub routine to get all A and CNAME records from the region NS server
sub get_zone_records{
  my %hash;
  my $res  = Net::DNS::Resolver->new;
  my $nameserver = $_[1];
  $res->nameservers($nameserver);
  my @zone = $res->axfr($_[0]);

  foreach my $rr (@zone) {
    my $type = $rr->type;
    my $name = $rr->name;
    chomp($type);
    if ($type eq "A") {
      my $address = $rr->address;
      $hash{$name}->{name} = $name;
      $hash{$name}->{type} = $type;
      $hash{$name}->{address} = $address;
    } elsif ($type eq "CNAME") {
      my $cname = $rr->cname;
      $hash{$name}->{name} = $name;
      $hash{$name}->{type} = $type;
      $hash{$name}->{address} = $cname;
    }
  }
  return %hash;
}

#Subroutine to check if domain exists and if not create with soa and ns records.
sub check_pdns_domain{

  my $domain=$_[0];
  my $MNAME = 'ns1.acme.com.';
  my $RNAME = 'hostmaster.acme.com.';
  my $refresh = 7200;         # Refresh 2 hours
  my $retry   = 1800;         # Retry 30 minutes
  my $expire  = 2592000;      # Expire 30 days
  my $minimum = 14400;        # Minimum 4 hours

  if (! $pdns->domain_exists(\$domain)) {

    unless ($pdns->add_domain(\$domain) ) {
      die "Cannot add domain $domain";
    }
    unless ( $pdns->make_domain_master(\$domain) ){
      print "Could not make domain ($domain) to master \n";
    }

    my $soa_time = "2015120700";
    add_rr($domain, '', 'SOA', "$MNAME $RNAME $soa_time $refresh $retry $expire $minimum");
    add_rr($domain, '', 'NS', 'ns1.acme.com');
    add_rr($domain, '', 'NS', 'ns2.acme.com');
  }
}

sub add_or_update_rr {
  my ($domain, $host, $type, $ns_record) = @_;
  my $fqdn = ($host) ? "$host.$domain" : "$domain";
  my @rr_set = ($fqdn, $type, $ns_record);
  my @rr_record = ($fqdn, $type);
  # This is a lazy way of doing this. I know. The module doesn't give an uption to just overwrite the existing record, unless you know what the rr currently contains. 
  # Only update_or_add_records does not require knowledge of the existing $name , $type , $content data. 
  # Add or update record
  unless ($pdns->update_or_add_records(\@rr_record,\@rr_set, \$domain) ) {
    die "Cannot add RR to $domain";
  }
}

sub add_rr {
  my ($domain, $host, @rr) = @_;
  my $fqdn = ($host) ? "$host.$domain" : "$domain";
  my @rrset = ($fqdn, @rr);
  unless ($pdns->add_record(\@rrset, \$domain) ) {
    die "Cannot add RR to $domain";
  }
}

sub main{


  # this is a hardcode. Sorry. Point to NS server that you want to get zone transfer from. If enough people bitch, I'll add Ns lookup on the zone. 
  my $nsserver = "192.168.0.1";

  # Get the records for the region from the region NS server
  my %host_result=&get_zone_records($zone,$nsserver);

  # make sure we got a resultset.
  if (!%host_result) {
    print "No results found for $zone\n";
    exit;
  }

  # Values are : name = hostname, address=records(ip or cname), type = A/CNAME
  OUTER: while ((my $key,my $value) = each %host_result) {
    # Set all the vars needed
    my $timestamp=time;
    my $hostname=$key;
    my @name=split(/\./,$key);
    my $shortname = shift @name;
    my $domain = join('.', @name);
    my $ns_type=$value->{type};
    my $ns_record=$value->{address};    

    #check domain
    check_pdns_domain($domain);

    # check record type and add
    if ( $ns_type eq "A" || $ns_type eq "CNAME" ){
      my $fqdn = ($shortname) ? "$shortname.$domain" : "$domain";
      my @rr_set = ($fqdn, $ns_type, $ns_record);
      add_or_update_rr($domain, $shortname, $ns_type, $ns_record);
    }
  } 


}

main();
