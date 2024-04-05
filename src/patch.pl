#!/usr/bin/perl
use strict;
use warnings;
use File::Copy;

my $pwd = `pwd`;
if ($pwd =~ m/\/src$/) {
    print "Please run this script from the root directory of the project\n";
    exit 1;
}
chomp $pwd;

my $dockerfile = "$pwd/Dockerfile";
my $dockerfile_template = "$pwd/Dockerfile.template";
my $postgresql_conf = "$pwd/src/postgresql.conf";
my $pg_hba_conf = "$pwd/src/pg_hba.conf";
my $server_start = "$pwd/src/server-start.sh";
my $entrypoint = "$pwd/src/entrypoint.sh";

# read postgresql.conf
open my $fh, '<', $postgresql_conf or die "Could not open file $postgresql_conf: $!";
my $postgresql_conf_content = do { local $/; <$fh> };
close $fh;

# Open the Dockerfile for writing
open my $fw, '>', $dockerfile or die "Could not open file $dockerfile: $!";

# Read the template file
open my $fr, '<', $dockerfile_template or die "Could not open file $dockerfile_template: $!";

for my $line (<$fr>) {
    if ($line =~ m/src\/postgresql\.conf/) {
        print $fw "# /etc/postgresql/postgresql.conf content\n";
        print $fw "COPY --chown=postgres:postgres <<-EOF /etc/postgresql/postgresql.conf\n";
        write_data_to_dockerfile($postgresql_conf, $fw);
        print $fw "EOF\n\n";
    }
    elsif ($line =~ m/src\/pg_hba\.conf/) {
        print $fw "# /etc/postgresql/pg_hba.conf content\n";
        print $fw "COPY --chown=postgres:postgres <<-EODOCKER /etc/postgresql/pg_hba.conf\n";
        write_data_to_dockerfile($pg_hba_conf, $fw);
        print $fw "EODOCKER\n\n";
    }
    elsif ($line =~ m/src\/server-start/) {
        print $fw "# /usr/local/bin/server-start.sh content\n";
        print $fw "COPY --chown=postgres:postgres <<-EODOCKER /usr/local/bin/server-start\n";
        write_data_to_dockerfile($server_start, $fw);
        print $fw "EODOCKER\n\n";
    }
    elsif ($line =~ m/src\/entrypoint\.sh/) {
        print $fw "# /usr/local/bin/entrypoint.sh content\n";
        print $fw "COPY --chown=postgres:postgres <<-EODOCKER /entrypoint.sh\n";
        write_data_to_dockerfile($entrypoint, $fw);
        print $fw "EODOCKER\n\n";
    }
    else {
        print $fw $line;
    }
}
close $fr;
close $fw;

sub write_data_to_dockerfile {
    my ($src, $fw) = @_;
    my $scaped_line = "";

    open my $fr, '<', $src or die "Could not open file $src: $!";
    for my $line (<$fr>) {
        $line =~ s/\\/\\\\/g;
        $line =~ s/\$/\\\$/g;
        print $fw "\t$line";
    }
    close $fr;
}