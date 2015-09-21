use 5.014;
use Test::Most;
use Test::Moose;

my $class;
BEGIN {
    $class = 'Mojo::Message::Serializer';
    use_ok($class);
}

my $obj = new_ok($class);

for my $method (qw/serialize deserialize store retrieve/) {
    can_ok($obj, $method);
}

$obj->{'foo'} = 'bar';
my $o2 = $class->new();

is $o2->{'foo'}, $obj->{'foo'}, q{Object is a singleton};

done_testing;
