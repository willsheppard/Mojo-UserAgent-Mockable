use 5.014;

package Mojo::Message::Serializer;

use Carp;
use File::Slurp qw/slurp/;
use MooseX::Singleton;
use MooseX::AttributeShortcuts;
use Safe::Isa (qw/$_isa/);
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

Serialize an instance of L<Mojo::Message> and write it to the given file or file handle.  Takes two
arguments:

=for :list
= $message
Instance of L<Mojo::Message> to serialize
= $file 
File or handle to write serialized object to.
 
=method retrieve

Read from the specified file or file handle and deserialize an instance of L<Mojo::Message> from 
the data read.  If a file handle is passed, data will be read until an EOF is received.

=cut

sub serialize {
    my ($self, $message) = @_;

    if (!$message->$_isa('Mojo::Message')) {
        croak q{Only instances of Mojo::Message may be serialized using this class};
    }

    return $self->_serializer->serialize($message);
}

sub deserialize { 
    my ($self, $data) = @_;

    my $obj = $self->_serializer->deserialize($data);
    if (!$obj->$_isa('Mojo::Message')) {
        croak q{Only instances of Mojo::Message may be deserialized using this class};
    }

    return $obj;
}

sub store {
    my ($self, $message, $file) = @_;

    my $serialized = $self->serialize($message);
    write_file($file, $message);
}

sub retrieve {
    my ($self, $file) = @_;

    my $contents = slurp($file);
    return $self->deserialize($contents);
}
1;
