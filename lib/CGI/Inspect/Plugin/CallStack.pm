package CGI::Inspect::Plugin::CallStack;

use strict;
use base 'CGI::Inspect::Plugin';
use Devel::StackTrace::WithLexicals;
use Data::Dumper;
use CGI qw( escapeHTML );

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(@_);
  $self->{trace} = Devel::StackTrace::WithLexicals->new();
  return $self;
}

sub print_trace {
  my $self = shift;
  my $output = "<div class=dialog id=stacktrace title='Stacktrace'><ul>";
  my $trace = $self->{trace};
  $trace->reset_pointer;
  my $frame_index = 0;
  my $frame; 
  while($frame = $trace->next_frame) {
    last if $frame->package() !~ /^(Continuity|Coro|CGI::Inspect)/
      || $frame->subroutine() eq 'CGI::Inspect::inspect';
    $frame_index++;
  }
  while($frame) {
    my $next_frame = $trace->next_frame;
    my $subname = $next_frame ? $next_frame->subroutine : '[GLOBAL]';
    $output .= "<li>$subname"
      . " (" . $frame->filename . ":" . $frame->line . ")"
    ;
    $output .= $self->print_lexicals($frame->lexicals, $frame_index);
    $output .= "</li>";
    $frame = $next_frame;
    $frame_index++;
  }
  $output .= "</ul></div>";
  return $output;
}

sub get_field_name {
  return time() . rand();
}

sub print_lexicals {
  my ($self, $lexicals, $frame_index) = @_;
  my $output = '<ul>';
  local $Data::Dumper::Terse = 1;

  foreach my $var (sort keys %$lexicals) {
    my $val = Dumper(${ $lexicals->{$var} });
    $val = escapeHTML($val);
    my $out;
    my $edit_link = $self->request->callback_link(
      Edit => sub {
        my $save_button = $self->request->callback_submit(
          Save => sub {
            my $val = $self->param('blah');
            ${ $lexicals->{$var} } = eval($val);
          }
        );
        $self->{output} = qq{
          <div class=dialog id=stacktrace title='Stacktrace'>
            $var = <textarea name=blah style="width: 100%; height: 80%">$val</textarea><br>
            $save_button
          </div>
        };
      }
    );
    $out ||= "<li><pre>$var = $val</pre>$edit_link</li>";
    #$out ||= "<li><pre>$var = $val</pre></li>";
    $output .= "<li>$out</li>";
  }

  $output .= "</ul>";
  return $output;
}


sub process {
  my ($self) = @_;
  if($self->{output}) {
    my $output = $self->{output};
    $self->{output} = undef;
    return $output;
  }
  return $self->print_trace;
}

1;

