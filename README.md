# dns-tools
Tools to integrate with powerdns. 

## foremanapi2pdns.pl

NAME
       foremanapi2pdns.pl - Extract DNS information from foreman and populate PowerDNS

DESCRIPTION
       A perl script to extract using the foreman API, hostname and IP address information, which is used to create domain, host and PTR records using DBI into the PowerDNS MySQL backend.

CAVEATS
       Right now, this does not check for duplicate IP's so multiple A records will be created.

LICENSE
       GPL v2, June 1991

