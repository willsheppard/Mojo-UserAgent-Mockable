use 5.014;
use File::Temp;
use Test::Most;
use Test::JSON;
use Mojo::JSON;
use Mojo::Message::Serializer;
use Mojo::Message::Request;
use Mojo::Message::Response;
use Mojo::UserAgent;
use Mojolicious::Quick;

my $serializer = Mojo::Message::Serializer->new;

my $req    = Mojo::Message::Request->new;
my $cookie = 'foo=bar';
$req->parse("PUT /upload HTTP/1.1\x0d\x0aCookie: $cookie; sessionID=OU812\x0d\x0a");
$req->parse("Content-Length: 0\x0d\x0a\x0d\x0a");

my $expected_body = $req->to_string;
my $serialized = $serializer->serialize($req);
my $slush = Mojo::JSON::decode_json($serialized);
is $slush->{'class'}, 'Mojo::Message::Request', 'class correct';
is $slush->{'body'}, $expected_body, 'Body correct';  

$req = undef;

my $r2 = $serializer->deserialize($serialized);
is $r2->method,  'PUT',     'right method';
is $r2->version, '1.1',     'right version';
is $r2->url,     '/upload', 'right URL';
is $r2->cookie('foo')->value, 'bar', 'cookie matches';
is $r2->cookie('sessionID')->value, 'OU812', 'cookie matches';

done_testing;
