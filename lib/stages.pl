use strict;
use warnings;

# Format rules for the deep review stages. An angle lists hypotheses, a
# verifier answers each one, and merge keeps what is worth writing up.
#   stages.pl hypotheses <file>
#   stages.pl verification <hypotheses> <verification>
#   stages.pl merge <angle> <hypotheses> <verification>
#   stages.pl present <hypotheses>
#   stages.pl ceiling <verified findings> <review>
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

my %RANK = (blocking => 0, medium => 1, low => 2, nit => 3);

# id => {severity, state} for each finding in the merged verified file.
sub known_findings {
    my (%known, $id);
    for my $line (split /\n/, $_[0]) {
        if ($line =~ m{\A### ([a-z-]+/H[0-9]+)\z}) { $id = $1; $known{$id} = {}; }
        next unless defined $id;
        $known{$id}{severity} = $1 if $line =~ /\ASeverity: (\w+)\z/;
        $known{$id}{state} = $1 if $line =~ /\AVerified: (yes|open)\z/;
    }
    return \%known;
}

# Where a finding ends: a blank line, the next named section of the comment or
# the verdict.
my $SECTION_START = qr/\A\s*(?:\*\*(?:Overview|Strengths|Findings|Security|Test coverage|For AI authors|Since last review)|VERDICT:)/;

# The findings of a review as [tag, text]; wrapped lines belong to the item
# they continue. A finding starts with its severity tag, after an optional list
# marker ("1.", "1)", "-", "*", "+") and bold. A second severity tag on the
# line, or one anywhere else, is not understood, so the whole review is refused
# (undef) instead of skipped.
sub review_items {
    my (@items, $open);
    for my $line (split /\n/, $_[0]) {
        if ($line =~ /\A\s*(?:(?:\d+[.)]|[-*+])\s+)?(?:\*\*)?\s*\[(blocking|medium|low|nit|open)\](.*)\z/i) {
            return undef if $2 =~ /\[(?:blocking|medium|low|nit)\]/i;
            push @items, [lc $1, $line];
            $open = 1;
        } elsif ($line =~ /\[(?:blocking|medium|low|nit)\]/i) {
            return undef;
        } elsif ($line !~ /\S/ || $line =~ $SECTION_START) {
            $open = 0;
        } elsif ($open) {
            $items[-1][1] .= " $line";
        }
    }
    return \@items;
}

# An item cites the findings it comes from in an HTML comment. It may be
# [open] whatever it cites; any other tag needs a cited, confirmed finding
# at least that serious, so an unverified finding is never promoted.
sub item_allowed {
    my ($tag, $text, $known) = @_;
    my ($cited) = $text =~ /<!--\s*src:\s*([^>]*?)\s*-->/;
    return 0 unless defined $cited;
    my @ids = split /\s*,\s*/, $cited;
    return 0 if !@ids || grep { !exists $known->{$_} } @ids;
    return 1 if $tag eq 'open';
    return scalar grep { $known->{$_}{state} eq 'yes' && $RANK{$known->{$_}{severity}} <= $RANK{$tag} } @ids;
}

sub within_ceiling {
    my ($findings, $review) = (slurp($_[0]), slurp($_[1]));
    return 0 unless defined $findings && defined $review;
    my $known = known_findings($findings);
    my $items = review_items($review);
    return $items && !grep { !item_allowed(@$_, $known) } @$items;
}

my ($mode, @args) = @ARGV;
$mode //= '';
my $ok;
if ($mode eq 'hypotheses' && @args == 1) {
    $ok = hypotheses($args[0]);
} elsif ($mode eq 'verification' && @args == 2) {
    my $hypotheses = hypotheses($args[0]);
    $ok = $hypotheses && verification($hypotheses, $args[1]);
} elsif ($mode eq 'present' && @args == 1) {
    my $hypotheses = hypotheses($args[0]);
    $ok = $hypotheses && @$hypotheses;
} elsif ($mode eq 'ceiling' && @args == 2) {
    $ok = within_ceiling(@args);
} elsif ($mode eq 'merge' && @args == 3 && $args[0] =~ /\A[a-z][a-z-]{0,23}\z/) {
    my $hypotheses = hypotheses($args[1]);
    my $verdicts = $hypotheses && (@$hypotheses ? verification($hypotheses, $args[2]) : []);
    print merge($args[0], $hypotheses, $verdicts) if $verdicts;
    $ok = $verdicts;
}
exit($ok ? 0 : 1);
