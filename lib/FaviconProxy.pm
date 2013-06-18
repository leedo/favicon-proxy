package FaviconProxy;

use CHI;
use AnyEvent::HTTP ();
use HTML::Parser;
use Plack::Util::Accessor qw{cache};
use Plack::Request;
use URI;

use parent 'Plack::Component';

sub prepare_app {
  my $self = shift;
  $self->{cache} = CHI->new(driver => "Memory", global => 1)
    unless defined $self->{cache};
}

sub not_found {
  my $status = $_[1] or 404;
  return [$status, ["Content-Type", "text/plain"], ["not found"]];
}

sub call {
  my ($self, $env) = @_;
  my $req = Plack::Request->new($env);
  my $url = $req->parameters->{url};

  if (!$url) {
    return $self->not_found(410);
  }

  my $domain = URI->new($url)->host;

  if (!$domain) {
    return $self->not_found;
  }

  my $info = $self->{cache}->get($domain);

  if ($info) {
    my ($image, @headers) = @$info;
    return [200, \@headers, [$image]];
  }

  return sub {
    my $respond = shift;
    AnyEvent::HTTP::http_get "http://$domain/favicon.ico", sub {
      my ($body, $headers) = @_;
      if ($headers->{Status} == 200) {
        my @headers = map {$_, $headers->{$_}} grep {/^[a-z]/} keys %$headers;
        $self->{cache}->set($domain, [$body, @headers]);
        $respond->([200, \@headers, [$body]]);
      }
      else {
        AnyEvent::HTTP::http_get $url, sub {
          my ($body, $headers) = @_;
          if ($headers->{Status} == 200 and $headers->{"content-type"} =~ m{/x?html$}) {
            my $url;
            my $parser = HTML::Parser->new(
              api_version => 3,
              start_h => [ sub {
                if ($_[0] eq "link" and $_[1]->{rel} eq "shortcut icon") {
                  $url = $_[1]->{href};
                  $_[2]->eof;
                }
              }, "tagname, attr, self" ],
            );
            $parser->parse($body);
            $parser->eof;

            if ($url) {
              AnyEvent::HTTP::http_get $url, sub {
                my ($body, $headers) = @_;
                if ($headers->{Status} == 200) {
                  my @headers = map {$_, $headers->{$_}} grep {/^[a-z]/} keys %$headers;
                  $self->{cache}->set($domain, [$body, @headers]);
                  $respond->([200, \@headers, [$body]]);
                }
                else {
                  $respond->($self->not_found);
                }
              };
            }
          }
          else {
            $respond->($self->not_found);
          }
        };
      }
    };
  };
}

1;
