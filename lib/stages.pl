use strict;
use warnings;

# Format rules for the deep review stages. An angle lists hypotheses, a
# verifier answers each one, and merge keeps what is worth writing up.
#   stages.pl hypotheses <file>
#   stages.pl verification <hypotheses> <verification>
#   stages.pl merge <angle> <hypotheses> <verification>
# Exit status 0 means valid; invalid input prints nothing.

my $PATH_LINE = '`[^`\s]+:[0-9]+(?:-[0-9]+)?`';
my $TEXT = qr/\S.*/;
my %RULES = (
    Severity       => qr/blocking|medium|low|nit/,
    Class          => qr/bug|security|data-integrity|contract|simplification|tests/,
    Claim          => $TEXT,
    Files          => qr/$PATH_LINE(?:, $PATH_LINE)*/,
    'Failure path' => $TEXT,
    Answer         => qr/yes|no|unknown/,
    Evidence       => $TEXT,
);
my @HYPOTHESIS_FIELDS = ('Severity', 'Class', 'Claim', 'Files', 'Failure path');
my @VERIFICATION_FIELDS = ('Answer', 'Evidence');
my $MAX_HYPOTHESES = 6;

sub slurp {
    open(my $in, '<', $_[0]) or return undef;
    local $/;
    my $text = <$in>;
    close $in;
    return $text;
}

# The value of "Name: value" when it obeys the rule for Name, else undef.
sub field_value {
    my ($line, $name) = @_;
    return undef unless $line =~ /\A\Q$name\E: (.*)\z/;
    my $value = $1;
    return $value =~ /\A$RULES{$name}\z/ ? $value : undef;
}

# Returns [[id, {field => value}], ...] or undef when any line is out of place.
sub parse_blocks {
    my ($text, $fields) = @_;
    my (@blocks, $next);
    for my $line (split /\n/, $text) {
        $line =~ s/\s+\z//;
        next if $line eq '';
        if ($line =~ /\A### (H[1-9][0-9]*)\z/) {
            return undef if defined $next && $next < @$fields;
            push @blocks, [$1, {}];
            $next = 0;
            next;
        }
        return undef unless defined $next && $next < @$fields;
        my $value = field_value($line, $fields->[$next]);
        return undef unless defined $value;
        $blocks[-1][1]{$fields->[$next++]} = $value;
    }
    return undef if @blocks && $next < @$fields;
    return \@blocks;
}

sub no_hypotheses { return $_[0] =~ /\A\s*NO HYPOTHESES\s*\z/ }

# Hypotheses are numbered H1..Hn in order, at most $MAX_HYPOTHESES of them.
sub hypotheses {
    my $text = slurp($_[0]);
    return undef unless defined $text;
    return [] if no_hypotheses($text);
    my $blocks = parse_blocks($text, \@HYPOTHESIS_FIELDS);
    return undef unless $blocks && @$blocks && @$blocks <= $MAX_HYPOTHESES;
    for my $i (0 .. $#$blocks) {
        return undef unless $blocks->[$i][0] eq 'H' . ($i + 1);
    }
    return $blocks;
}

# One answer per hypothesis, same ids in the same order, each one citing code
# (an unknown cites where it looked).
sub verification {
    my ($hypotheses, $path) = @_;
    my $text = slurp($path);
    return undef unless defined $text && @$hypotheses;
    my $blocks = parse_blocks($text, \@VERIFICATION_FIELDS);
    return undef unless $blocks && @$blocks == @$hypotheses;
    for my $i (0 .. $#$blocks) {
        my $fields = $blocks->[$i][1];
        return undef unless $blocks->[$i][0] eq $hypotheses->[$i][0];
        return undef unless $fields->{Evidence} =~ /$PATH_LINE/;
    }
    return $blocks;
}

# Confirmed findings stay; an unknown stays only when it could be serious.
sub verified_state {
    my ($hypothesis, $verdict) = @_;
    return 'yes' if $verdict->{Answer} eq 'yes';
    return 'open' if $verdict->{Answer} eq 'unknown' && $hypothesis->{Severity} =~ /\A(?:blocking|medium)\z/;
    return '';
}

sub merge {
    my ($angle, $hypotheses, $verdicts) = @_;
    my $out = '';
    for my $i (0 .. $#$hypotheses) {
        my ($id, $fields) = @{$hypotheses->[$i]};
        my $verdict = $verdicts->[$i][1];
        my $state = verified_state($fields, $verdict);
        next unless $state;
        $out .= "### $angle/$id\n";
        $out .= "$_: $fields->{$_}\n" for @HYPOTHESIS_FIELDS;
        $out .= "Verified: $state\nEvidence: $verdict->{Evidence}\n\n";
    }
    return $out;
}

my ($mode, @args) = @ARGV;
$mode //= '';
my $ok;
if ($mode eq 'hypotheses' && @args == 1) {
    $ok = hypotheses($args[0]);
} elsif ($mode eq 'verification' && @args == 2) {
    my $hypotheses = hypotheses($args[0]);
    $ok = $hypotheses && verification($hypotheses, $args[1]);
} elsif ($mode eq 'merge' && @args == 3 && $args[0] =~ /\A[a-z][a-z-]{0,23}\z/) {
    my $hypotheses = hypotheses($args[1]);
    my $verdicts = $hypotheses && (@$hypotheses ? verification($hypotheses, $args[2]) : []);
    print merge($args[0], $hypotheses, $verdicts) if $verdicts;
    $ok = $verdicts;
}
exit($ok ? 0 : 1);
