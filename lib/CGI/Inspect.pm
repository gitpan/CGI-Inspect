package CGI::Inspect;

=head1 NAME

CGI::Inspect - Inspect and debug CGI apps with an in-browser UI

=head1 SYNOPSIS

  use CGI;
  use CGI::Inspect;

  print "Content-type: text/html\n\n";
  for my $i (1..10) {
    print "$i cookies for me to eat...<br>";
    inspect() if $i == 5;
  }

=head1 DESCRIPTION

This class is a drop-in web based inspector for plain CGI (or CGI-based)
applications. Include the library, and then call inspect(). In your server
error logs you'll see something like "Please connect to localhost:8080". When
you do, you'll be greeted with an inspection UI which includes a stack trace,
REPL, and other goodies.

=head1 REQUIREMENTS

To work it's magic this modules needs Continuity, Padwalker, and Data::Alias.
Some plugins have additional dependencies which are not pulled in when
installing from CPAN.

=cut

use strict;
use Continuity;
use Continuity::RequestCallbacks;
use base 'Exporter';
our @EXPORT = qw( inspect );

our $VERSION = '0.3';

=head1 EXPORTED SUBS

=head2 inspect()

This starts the Continuity server and inspector on the configured port
(defaulting to 8080).

=cut

sub inspect {
  print STDERR "Starting inspector...\n";
  require IO::Handle;
  STDERR->autoflush(1);
  STDOUT->autoflush(1);
  print "<script>window.open('http://localhost:8080/','cgi-inspect');</script>\n";
  my $self = CGI::Inspect->new(@_);
  $self->start_inspecting;
  print "<script>window.close('cgi-inspect');</script>\n";
}

$SIG{__DIE__} = \&inspect;

=head1 METHODS

These methods are all internal. All you have to do is call inspect().

=head2 CGI::Inspect->new()

Create a new monitor object.

=cut

sub new {
  my ($class, %params) = @_;
  my $self = {
    port => 8080,
    plugins => [qw(
      BasicLook Exit REPL CallStack
    )],
    # REPL CallStack Exit Counter FileEdit
    plugin_objects => [],
    html_headers => [],
    %params
  };
  bless $self, $class;
  return $self;
}

=head2 $self->start_inspecting

Load plugins and start inspecting!

=cut

sub start_inspecting {
  my ($self) = @_;
  $self->load_plugins;
  $self->start_server;
}
  
  # use Devel::StackTrace::WithLexicals;
  # my $trace = Devel::StackTrace::WithLexicals->new(
    # ignore_package => [qw( Devel::StackTrace CGI::Inspect )]
  # );
  # $self->trace( $trace );

=head2 $self->start_server

Initialize the Continuity server, and begin the run loop.

=cut

sub start_server {
  my ($self) = @_;
  my $docroot = $INC{'CGI/Inspect.pm'};
  $docroot =~ s/Inspect.pm/Inspect\/htdocs/;
  #print STDERR "docroot: $docroot\n";
  my $server = Continuity->new(
    port => $self->{port},
    docroot => $docroot,
    callback => sub { $self->main(@_) },
    #debug_callback => sub { STDERR->print("@_\n") },
  );
  $server->loop;
  print STDERR "Done inspecting!\n";
}

=head2 $self->display

Display the current page, based on $self->{content}

=cut

sub display {
  my ($self, $content) = @_;
  my $id = $self->request->session_id;
  my $html_headers = join '', @{ $self->{html_headers} };
  if($self->request->param('no_html_wrapper')) {
    $self->request->print($content);
  } else {
    $self->request->print(qq|
      <html>
        <head>
          <title>CGI::Inspect</title>
          $html_headers
        </head>
        <body class=smoothness>
          <form method=POST action="/">
            <input type=hidden name=sid value="$id">
            $content
          </form>
        </body>
      </html>
    |);
  }
}

=head2 $self->request

Returns the current request obj

=cut

sub request {
  my ($self) = @_;
  return $self->{request};
}

=head2 $self->load_plugins

Load all of our plugins.

=cut

sub load_plugins {
  my ($self) = @_;
  my $base = "CGI::Inspect::Plugin::";
  foreach my $plugin (@{ $self->{plugins} }) {
    my $plugin_pkg = $base . $plugin;
    eval "use $plugin_pkg";
    my $plugin_instance = $plugin_pkg->new( manager => $self );
    push @{ $self->{plugin_objects} }, $plugin_instance;
    $self->{plugins_by_name}->{$plugin_pkg} = $plugin_instance;
  }
}

=head2 $self->main

This is executed as the entrypoint for inspector sessions.

=cut

sub main {
  my ($self, $request) = @_;
  $self->{request} = $request; # For plugins to use
  $self->{do_exit} = 0;
  do {
    my $content = '';
    if($request->param('plugin')) {
      $content .= $self->{plugins_by_name}->{$request->param('plugin')}->process();
    } else {
      foreach my $plugin (@{$self->{plugin_objects}}) {
        $content .= $plugin->process();
      }
    }
    $self->display($content);
    $request->next->execute_callbacks
      unless $self->{do_exit};
  } until($self->{do_exit});
  $request->print("<script>window.close();</script>");
  Coro::Event::unloop();
  $request->print("Exiting...");
  $request->print("<script>window.close();</script>");
  $request->end_request;
}

=head1 SEE ALSO

L<Carp::REPL>

=head1 AUTHOR

  Brock Wilcox <awwaiid@thelackthereof.org> - http://thelackthereof.org/

=head1 COPYRIGHT

  Copyright (c) 2008-2009 Brock Wilcox <awwaiid@thelackthereof.org>. All rights
  reserved.  This program is free software; you can redistribute it and/or
  modify it under the same terms as Perl itself.

=cut

1;

