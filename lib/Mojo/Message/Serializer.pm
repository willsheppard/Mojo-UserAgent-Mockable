use 5.014;

package Mojo::Message::Serializer;
use MooseX::Singleton;
use MooseX::AttributeShortcuts;

has _serializer => ( is => 'lazy', isa => 'Data::Serializer::Raw', builder => sub { Data::Serializer::Raw->new(); } );

# ABSTRACT

# VERSION

=head1 SYNOPSIS

    use Mojo::Message::Serializer;
    use File::Slurp;

    my $ua = Mojo::UserAgent->new;

    my $tx = $ua->get('http://example.com');

    my $json = Mojo::Message::Serializer->serialize($tx->req);

    write_file('/path/to/file.json', $json);

    # Later...

    my $json = read_file('/path/to/file.json');
    my $reconstituted_request = Mojo::Message::Serializer->deserialize($json);

=method serialize

Serialize or freeze an instance of L<Mojo::Message>.  Takes a single argument, the message to be 
serialized.

=method deserialize

Deserialize or thaw a previously serialized instance of L<Mojo::Message>.  Takes a single argument, 
the data to be thawed.

=method store

Serialize an instance of L<Mojo::Message> and write it to the given file or file handle.  Takes a 
single argument, the file or handle to write to. Note that if a handle is passed, it will _not_ 
be closed after writing.

=method retrieve

Read from the specified file or file handle and deserialize an instance of L<Mojo::Message> from 
the data read.  If a file handle is passed, data will be read until an EOF is received.

=cut

1;
