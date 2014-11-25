# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl MARC-File-AlephSequential.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 2;
BEGIN { use_ok('MARC::File::AlephSequential') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.


my $records = MARC::File::AlephSequential->in("t/record.with.subfield9.seq");
my $rec = $records->next();

use File::Slurp;
my $expected = read_file('t/record.with.subfield9.formatted');

ok( $rec->as_formatted() eq $expected);
