package Mojo::Headers;
use Mojo::Base -base;

use Mojo::Util 'monkey_patch';

has max_line_size => sub { $ENV{MOJO_MAX_LINE_SIZE} || 8192 };
has max_lines     => sub { $ENV{MOJO_MAX_LINES}     || 100 };

# Common headers
my %NORMALCASE = map { lc($_) => $_ } (
  qw(Accept Accept-Charset Accept-Encoding Accept-Language Accept-Ranges),
  qw(Access-Control-Allow-Origin Allow Authorization Cache-Control Connection),
  qw(Content-Disposition Content-Encoding Content-Language Content-Length),
  qw(Content-Location Content-Range Content-Security-Policy Content-Type),
  qw(Cookie DNT Date ETag Expect Expires Host If-Modified-Since If-None-Match),
  qw(Last-Modified Link Location Origin Proxy-Authenticate),
  qw(Proxy-Authorization Range Sec-WebSocket-Accept Sec-WebSocket-Extensions),
  qw(Sec-WebSocket-Key Sec-WebSocket-Protocol Sec-WebSocket-Version Server),
  qw(Set-Cookie Status Strict-Transport-Security TE Trailer Transfer-Encoding),
  qw(Upgrade User-Agent Vary WWW-Authenticate)
);
for my $header (values %NORMALCASE) {
  my $name = lc $header;
  $name =~ y/-/_/;
  monkey_patch __PACKAGE__, $name, sub { shift->header($header => @_) };
}

sub add {
  my ($self, $name) = (shift, shift);

  # Make sure we have a normal case entry for name
  my $key = lc $name;
  $self->{normalcase}{$key} //= $name unless $NORMALCASE{$key};
  push @{$self->{headers}{$key}}, @_;

  return $self;
}

sub append {
  my ($self, $name, $value) = @_;
  my $old = $self->header($name);
  return $self->header($name => defined $old ? "$old, $value" : $value);
}

sub clone { $_[0]->new->from_hash($_[0]->to_hash(1)) }

sub from_hash {
  my ($self, $hash) = @_;

  # Empty hash deletes all headers
  delete $self->{headers} if keys %{$hash} == 0;

  # Merge
  for my $header (keys %$hash) {
    my $value = $hash->{$header};
    $self->add($header => ref $value eq 'ARRAY' ? @$value : $value);
  }

  return $self;
}

sub header {
  my ($self, $name) = (shift, shift);

  # Replace
  return $self->remove($name)->add($name, @_) if @_;

  return undef unless my $headers = $self->{headers}{lc $name};
  return join ', ', @$headers;
}

sub is_finished { (shift->{state} // '') eq 'finished' }

sub is_limit_exceeded { !!shift->{limit} }

sub leftovers { delete shift->{buffer} }

sub names {
  my $self = shift;
  return [map { $NORMALCASE{$_} || $self->{normalcase}{$_} || $_ }
      keys %{$self->{headers}}];
}

sub parse {
  my $self = shift;

  $self->{state} = 'headers';
  $self->{buffer} .= shift // '';
  my $headers = $self->{cache} ||= [];
  my $size    = $self->max_line_size;
  my $lines   = $self->max_lines;
  while ($self->{buffer} =~ s/^(.*?)\x0d?\x0a//) {
    my $line = $1;

    # Check line size limit
    if ($+[0] > $size || @$headers >= $lines) {
      @$self{qw(state limit)} = ('finished', 1);
      return $self;
    }

    # New header
    if ($line =~ /^(\S[^:]*)\s*:\s*(.*)$/) { push @$headers, [$1, $2] }

    # Multiline
    elsif ($line =~ s/^\s+// && @$headers) { $headers->[-1][1] .= " $line" }

    # Empty line
    else {
      $self->add(@$_) for @$headers;
      @$self{qw(state cache)} = ('finished', []);
      return $self;
    }
  }

  # Check line size limit
  @$self{qw(state limit)} = ('finished', 1) if length $self->{buffer} > $size;

  return $self;
}

sub referrer { shift->header(Referer => @_) }

sub remove {
  my ($self, $name) = @_;
  delete $self->{headers}{lc $name};
  return $self;
}

sub to_hash {
  my ($self, $multi) = @_;
  return {map { $_ => $multi ? $self->{headers}{lc $_} : $self->header($_) }
      @{$self->names}};
}

sub to_string {
  my $self = shift;

  # Make sure multiline values are formatted correctly
  my @headers;
  for my $name (@{$self->names}) {
    push @headers, "$name: $_" for @{$self->{headers}{lc $name}};
  }

  return join "\x0d\x0a", @headers;
}

1;

=encoding utf8

=head1 NAME

Mojo::Headers - Headers

=head1 SYNOPSIS

  use Mojo::Headers;

  # Parse
  my $headers = Mojo::Headers->new;
  $headers->parse("Content-Length: 42\x0d\x0a");
  $headers->parse("Content-Type: text/html\x0d\x0a\x0d\x0a");
  say $headers->content_length;
  say $headers->content_type;

  # Build
  my $headers = Mojo::Headers->new;
  $headers->content_length(42);
  $headers->content_type('text/plain');
  say $headers->to_string;

=head1 DESCRIPTION

L<Mojo::Headers> is a container for HTTP headers based on
L<RFC 7230|http://tools.ietf.org/html/rfc7230> and
L<RFC 7231|http://tools.ietf.org/html/rfc7231>.

=head1 ATTRIBUTES

L<Mojo::Headers> implements the following attributes.

=head2 max_line_size

  my $size = $headers->max_line_size;
  $headers = $headers->max_line_size(1024);

Maximum header line size in bytes, defaults to the value of the
C<MOJO_MAX_LINE_SIZE> environment variable or C<8192> (8KB).

=head2 max_lines

  my $num  = $headers->max_lines;
  $headers = $headers->max_lines(200);

Maximum number of header lines, defaults to the value of the C<MOJO_MAX_LINES>
environment variable or C<100>.

=head1 METHODS

L<Mojo::Headers> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 accept

  my $accept = $headers->accept;
  $headers   = $headers->accept('application/json');

Shortcut for the C<Accept> header.

=head2 accept_charset

  my $charset = $headers->accept_charset;
  $headers    = $headers->accept_charset('UTF-8');

Shortcut for the C<Accept-Charset> header.

=head2 accept_encoding

  my $encoding = $headers->accept_encoding;
  $headers     = $headers->accept_encoding('gzip');

Shortcut for the C<Accept-Encoding> header.

=head2 accept_language

  my $language = $headers->accept_language;
  $headers     = $headers->accept_language('de, en');

Shortcut for the C<Accept-Language> header.

=head2 accept_ranges

  my $ranges = $headers->accept_ranges;
  $headers   = $headers->accept_ranges('bytes');

Shortcut for the C<Accept-Ranges> header.

=head2 access_control_allow_origin

  my $origin = $headers->access_control_allow_origin;
  $headers   = $headers->access_control_allow_origin('*');

Shortcut for the C<Access-Control-Allow-Origin> header from
L<Cross-Origin Resource Sharing|http://www.w3.org/TR/cors/>.

=head2 add

  $headers = $headers->add(Foo => 'one value');
  $headers = $headers->add(Foo => 'first value', 'second value');

Add one or more header values with one or more lines.

  # "Vary: Accept"
  # "Vary: Accept-Encoding"
  $headers->vary('Accept')->add(Vary => 'Accept-Encoding')->to_string;

=head2 allow

  my $allow = $headers->allow;
  $headers  = $headers->allow('GET, POST');

Shortcut for the C<Allow> header.

=head2 append

  $headers = $headers->append(Vary => 'Accept-Encoding');

Append value to header and flatten it if necessary.

  # "Vary: Accept"
  $headers->append(Vary => 'Accept')->to_string;

  # "Vary: Accept, Accept-Encoding"
  $headers->vary('Accept')->append(Vary => 'Accept-Encoding')->to_string;

=head2 authorization

  my $authorization = $headers->authorization;
  $headers          = $headers->authorization('Basic Zm9vOmJhcg==');

Shortcut for the C<Authorization> header.

=head2 cache_control

  my $cache_control = $headers->cache_control;
  $headers          = $headers->cache_control('max-age=1, no-cache');

Shortcut for the C<Cache-Control> header.

=head2 clone

  my $clone = $headers->clone;

Clone headers.

=head2 connection

  my $connection = $headers->connection;
  $headers       = $headers->connection('close');

Shortcut for the C<Connection> header.

=head2 content_disposition

  my $disposition = $headers->content_disposition;
  $headers        = $headers->content_disposition('foo');

Shortcut for the C<Content-Disposition> header.

=head2 content_encoding

  my $encoding = $headers->content_encoding;
  $headers     = $headers->content_encoding('gzip');

Shortcut for the C<Content-Encoding> header.

=head2 content_language

  my $language = $headers->content_language;
  $headers     = $headers->content_language('en');

Shortcut for the C<Content-Language> header.

=head2 content_length

  my $len  = $headers->content_length;
  $headers = $headers->content_length(4000);

Shortcut for the C<Content-Length> header.

=head2 content_location

  my $location = $headers->content_location;
  $headers     = $headers->content_location('http://127.0.0.1/foo');

Shortcut for the C<Content-Location> header.

=head2 content_range

  my $range = $headers->content_range;
  $headers  = $headers->content_range('bytes 2-8/100');

Shortcut for the C<Content-Range> header.

=head2 content_security_policy

  my $policy = $headers->content_security_policy;
  $headers   = $headers->content_security_policy('default-src https:');

Shortcut for the C<Content-Security-Policy> header from
L<Content Security Policy 1.0|http://www.w3.org/TR/CSP/>.

=head2 content_type

  my $type = $headers->content_type;
  $headers = $headers->content_type('text/plain');

Shortcut for the C<Content-Type> header.

=head2 cookie

  my $cookie = $headers->cookie;
  $headers   = $headers->cookie('f=b');

Shortcut for the C<Cookie> header from
L<RFC 6265|http://tools.ietf.org/html/rfc6265>.

=head2 date

  my $date = $headers->date;
  $headers = $headers->date('Sun, 17 Aug 2008 16:27:35 GMT');

Shortcut for the C<Date> header.

=head2 dnt

  my $dnt  = $headers->dnt;
  $headers = $headers->dnt(1);

Shortcut for the C<DNT> (Do Not Track) header, which has no specification yet,
but is very commonly used.

=head2 etag

  my $etag = $headers->etag;
  $headers = $headers->etag('"abc321"');

Shortcut for the C<ETag> header.

=head2 expect

  my $expect = $headers->expect;
  $headers   = $headers->expect('100-continue');

Shortcut for the C<Expect> header.

=head2 expires

  my $expires = $headers->expires;
  $headers    = $headers->expires('Thu, 01 Dec 1994 16:00:00 GMT');

Shortcut for the C<Expires> header.

=head2 from_hash

  $headers = $headers->from_hash({'Cookie' => 'a=b'});
  $headers = $headers->from_hash({'Cookie' => ['a=b', 'c=d']});
  $headers = $headers->from_hash({});

Parse headers from a hash reference, an empty hash removes all headers.

=head2 header

  my $value = $headers->header('Foo');
  $headers  = $headers->header(Foo => 'one value');
  $headers  = $headers->header(Foo => 'first value', 'second value');

Get or replace the current header values.

=head2 host

  my $host = $headers->host;
  $headers = $headers->host('127.0.0.1');

Shortcut for the C<Host> header.

=head2 if_modified_since

  my $date = $headers->if_modified_since;
  $headers = $headers->if_modified_since('Sun, 17 Aug 2008 16:27:35 GMT');

Shortcut for the C<If-Modified-Since> header.

=head2 if_none_match

  my $etag = $headers->if_none_match;
  $headers = $headers->if_none_match('"abc321"');

Shortcut for the C<If-None-Match> header.

=head2 is_finished

  my $bool = $headers->is_finished;

Check if header parser is finished.

=head2 is_limit_exceeded

  my $bool = $headers->is_limit_exceeded;

Check if headers have exceeded L</"max_line_size"> or L</"max_lines">.

=head2 last_modified

  my $date = $headers->last_modified;
  $headers = $headers->last_modified('Sun, 17 Aug 2008 16:27:35 GMT');

Shortcut for the C<Last-Modified> header.

=head2 leftovers

  my $bytes = $headers->leftovers;

Get and remove leftover data from header parser.

=head2 link

  my $link = $headers->link;
  $headers = $headers->link('<http://127.0.0.1/foo/3>; rel="next"');

Shortcut for the C<Link> header from
L<RFC 5988|http://tools.ietf.org/html/rfc5988>.

=head2 location

  my $location = $headers->location;
  $headers     = $headers->location('http://127.0.0.1/foo');

Shortcut for the C<Location> header.

=head2 names

  my $names = $headers->names;

Return a list of all currently defined headers.

  # Names of all headers
  say for @{$headers->names};

=head2 origin

  my $origin = $headers->origin;
  $headers   = $headers->origin('http://example.com');

Shortcut for the C<Origin> header from
L<RFC 6454|http://tools.ietf.org/html/rfc6454>.

=head2 parse

  $headers = $headers->parse("Content-Type: text/plain\x0d\x0a\x0d\x0a");

Parse formatted headers.

=head2 proxy_authenticate

  my $authenticate = $headers->proxy_authenticate;
  $headers         = $headers->proxy_authenticate('Basic "realm"');

Shortcut for the C<Proxy-Authenticate> header.

=head2 proxy_authorization

  my $authorization = $headers->proxy_authorization;
  $headers          = $headers->proxy_authorization('Basic Zm9vOmJhcg==');

Shortcut for the C<Proxy-Authorization> header.

=head2 range

  my $range = $headers->range;
  $headers  = $headers->range('bytes=2-8');

Shortcut for the C<Range> header.

=head2 referrer

  my $referrer = $headers->referrer;
  $headers     = $headers->referrer('http://example.com');

Shortcut for the C<Referer> header, there was a typo in
L<RFC 2068|http://tools.ietf.org/html/rfc2068> which resulted in C<Referer>
becoming an official header.

=head2 remove

  $headers = $headers->remove('Foo');

Remove a header.

=head2 sec_websocket_accept

  my $accept = $headers->sec_websocket_accept;
  $headers   = $headers->sec_websocket_accept('s3pPLMBiTxaQ9kYGzzhZRbK+xOo=');

Shortcut for the C<Sec-WebSocket-Accept> header from
L<RFC 6455|http://tools.ietf.org/html/rfc6455>.

=head2 sec_websocket_extensions

  my $extensions = $headers->sec_websocket_extensions;
  $headers       = $headers->sec_websocket_extensions('foo');

Shortcut for the C<Sec-WebSocket-Extensions> header from
L<RFC 6455|http://tools.ietf.org/html/rfc6455>.

=head2 sec_websocket_key

  my $key  = $headers->sec_websocket_key;
  $headers = $headers->sec_websocket_key('dGhlIHNhbXBsZSBub25jZQ==');

Shortcut for the C<Sec-WebSocket-Key> header from
L<RFC 6455|http://tools.ietf.org/html/rfc6455>.

=head2 sec_websocket_protocol

  my $proto = $headers->sec_websocket_protocol;
  $headers  = $headers->sec_websocket_protocol('sample');

Shortcut for the C<Sec-WebSocket-Protocol> header from
L<RFC 6455|http://tools.ietf.org/html/rfc6455>.

=head2 sec_websocket_version

  my $version = $headers->sec_websocket_version;
  $headers    = $headers->sec_websocket_version(13);

Shortcut for the C<Sec-WebSocket-Version> header from
L<RFC 6455|http://tools.ietf.org/html/rfc6455>.

=head2 server

  my $server = $headers->server;
  $headers   = $headers->server('Mojo');

Shortcut for the C<Server> header.

=head2 set_cookie

  my $cookie = $headers->set_cookie;
  $headers   = $headers->set_cookie('f=b; path=/');

Shortcut for the C<Set-Cookie> header from
L<RFC 6265|http://tools.ietf.org/html/rfc6265>.

=head2 status

  my $status = $headers->status;
  $headers   = $headers->status('200 OK');

Shortcut for the C<Status> header from
L<RFC 3875|http://tools.ietf.org/html/rfc3875>.

=head2 strict_transport_security

  my $policy = $headers->strict_transport_security;
  $headers   = $headers->strict_transport_security('max-age=31536000');

Shortcut for the C<Strict-Transport-Security> header from
L<RFC 6797|http://tools.ietf.org/html/rfc6797>.

=head2 te

  my $te   = $headers->te;
  $headers = $headers->te('chunked');

Shortcut for the C<TE> header.

=head2 to_hash

  my $single = $headers->to_hash;
  my $multi  = $headers->to_hash(1);

Turn headers into hash reference, array references to represent multiple
headers with the same name are disabled by default.

  say $headers->to_hash->{DNT};

=head2 to_string

  my $str = $headers->to_string;

Turn headers into a string, suitable for HTTP messages.

=head2 trailer

  my $trailer = $headers->trailer;
  $headers    = $headers->trailer('X-Foo');

Shortcut for the C<Trailer> header.

=head2 transfer_encoding

  my $encoding = $headers->transfer_encoding;
  $headers     = $headers->transfer_encoding('chunked');

Shortcut for the C<Transfer-Encoding> header.

=head2 upgrade

  my $upgrade = $headers->upgrade;
  $headers    = $headers->upgrade('websocket');

Shortcut for the C<Upgrade> header.

=head2 user_agent

  my $agent = $headers->user_agent;
  $headers  = $headers->user_agent('Mojo/1.0');

Shortcut for the C<User-Agent> header.

=head2 vary

  my $vary = $headers->vary;
  $headers = $headers->vary('*');

Shortcut for the C<Vary> header.

=head2 www_authenticate

  my $authenticate = $headers->www_authenticate;
  $headers         = $headers->www_authenticate('Basic realm="realm"');

Shortcut for the C<WWW-Authenticate> header.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
