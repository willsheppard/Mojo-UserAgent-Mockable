use 5.014;
use Test::Most;

my $class;
BEGIN {
    $class = 'Mojo::Message::Serializer';
    use_ok($class);
}

my $obj = new_ok($class);
