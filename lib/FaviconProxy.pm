package FaviconProxy;

use CHI;
use AnyEvent::HTTP ();
use HTML::Parser;
use Plack::Util::Accessor qw{cache};

use parent 'Plack::Component';

sub prepare_app {
  my $self = shift;
  $self->{cache} = CHI->new(driver => "Memory", global => 1)
    unless defined $self->{cache};
}

sub call {
  my ($self, $env) = @_;
  my ($domain) = grep {$_} split "/", $env->{PATH_INFO};

  if (!$domain) {
    return [404, ["Content-Type", "text/plain"], ["not found"]];
  }

  my $info = $self->{cache}->get($domain);
  my ($image, @headers) = @$info;

  if ($image) {
    return [200, \@headers, $image];
  }

  return sub {
    my $respond = shift;
    AnyEvent::HTTP::http_get "http://$domain/favicon.ico", sub {
      my ($body, $headers) = @_;
      if ($headers->{Status} == 200) {
        my @headers = map {$_, $headers->{$_}} grep {/a-z/} keys %$headers;
        $self->{cache}->set($domain, [$body, @headers]);
        $respond->([200, \@headers, [$body]]);
      }
      else {
        AnyEvent::HTTP::http_get "http://$domain/", sub {
          my ($body, $headers) = @_;
          if ($headers->{Status} == 200 and $headers->{"content-type"} =~ /^x?html/) {
            my $url;
            my $parser = HTML::Parser->new(
              api_version => 3,
              start_h => [ sub {
                if (lc $_[0] eq "link" and defined $_[1]->{href}) {
                  $url = $attr->{href};
                }
              }, "tagname, attr" ],
            );
            $parser->parse($body);
            $parser->eof;

            if ($url) {
              AnyEvent::HTTP::http_get $url, sub {
                my ($body, $headers) = @_;
                if ($headers->{Status} == 200) {
                  my @headers = map {$_, $headers->{$_}} grep {/a-z/} keys %$headers;
                  $self->{cache}->set($domain, [$body, @headers]);
                  $respond->([200, \@headers, [$body]]);
                }
                else {
                  $respond->([404, ["Content-Type", "text/plain"], ["not found"]]);
                }
              };
            }
          }
          else {
            $respond->([404, ["Content-Type", "text/plain"], ["not found"]]);
          }
        };
      }
    };
  };
}

1;
