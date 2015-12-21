# dns-tools
Tools to integrate with powerdns. 

## foremanapi2pdns.pl

### NAME
foremanapi2pdns.pl - Extract DNS information from foreman and populate PowerDNS

### DESCRIPTION
A perl script to extract using the foreman API, hostname and IP address information, which is used to create domain, host and PTR records using DBI into the PowerDNS MySQL backend.

### CAVEATS
Right now, this does not check for duplicate IP's so multiple A records will be created.

### LICENSE
GPL v2, June 1991

## mikrotik2pdns.pl

### NAME
mikrotik2pdns.pl - Extract dynamic lease information from mikrotik router and populate PowerDNS

### DESCRIPTION
This script uses the mikrotik API to extract dynamic lease information creates a CSV file with hostname, IP information for use with csv2pdns.pl If the CSV file already exists, the lease information is compared and any
records that is in the CSV file, but not in the lease is checked in PDNS MySQL backend, and if found, removed.

### LICENSE
GPL v2, June 1991

## csv2pdns.pl

### NAME
csv2pdns.pl - Extract hostname and IP information from CSV file and populate PowerDNS

### DESCRIPTION
A perl script to extract hostname and IP information from CSV file, which is used to create domain, host and PTR records using DBI into the PowerDNS MySQL backend.

### CAVEATS
Script does not check for duplicate IP's so multiple A records will be created.

### LICENSE
GPL v2, June 1991

